import Foundation

public enum BundlePayloadLimits {
    /// Dedicated bound for manifest.json. Far below maxFileBytes so an
    /// oversized manifest is rejected before its bytes are materialized.
    /// Archive validation should enforce the same bound.
    public static let maxManifestBytes: Int64 = 16 * 1024 * 1024
}

public struct BinaryPayloadSummary: Sendable, Equatable {
    public var width: Int?
    public var height: Int?
    public var pixelFormatFourCC: UInt32?
    public var vertexCount: Int?
    public var faceCount: Int?

    public init(
        width: Int? = nil,
        height: Int? = nil,
        pixelFormatFourCC: UInt32? = nil,
        vertexCount: Int? = nil,
        faceCount: Int? = nil
    ) {
        self.width = width
        self.height = height
        self.pixelFormatFourCC = pixelFormatFourCC
        self.vertexCount = vertexCount
        self.faceCount = faceCount
    }
}

public struct BundlePayloadCrossCheck: Sendable {
    var meshAnchorIndex: StrictJSONValue?
    var frameDescriptors: [(path: String, document: StrictJSONValue)] = []
    var meshGeometry: [String: (vertices: Int, faces: Int)] = [:]
    var pixelGeometry: [String: BinaryPayloadSummary] = [:]
    var depthGeometry: [String: BinaryPayloadSummary] = [:]
    var confidenceGeometry: [String: BinaryPayloadSummary] = [:]

    public init() {}

    mutating func recordJSON(path: String, value: StrictJSONValue) {
        if path == "mesh/anchors.json" {
            meshAnchorIndex = value
        }
        if CaptureBundleSchemaRegistry.schemaName(forPath: path) == "frame" {
            frameDescriptors.append((path: path, document: value))
        }
    }

    mutating func recordBinary(
        path: String,
        mediaType: String,
        summary: BinaryPayloadSummary
    ) {
        switch mediaType {
        case CanonicalPayloadValidator.meshMediaType:
            meshGeometry[path] = (
                vertices: summary.vertexCount ?? 0,
                faces: summary.faceCount ?? 0
            )
        case CanonicalPayloadValidator.pixelMediaType:
            pixelGeometry[path] = summary
        case CanonicalPayloadValidator.depthMediaType:
            depthGeometry[path] = summary
        case CanonicalPayloadValidator.confidenceMediaType:
            confidenceGeometry[path] = summary
        default:
            break
        }
    }

    public func finish(
        declaredByPath: [String: BundleFileEntry]
    ) throws {
        if let index = meshAnchorIndex {
            try checkMeshAnchorIndex(index, declaredByPath: declaredByPath)
        }
        for descriptor in frameDescriptors {
            try checkFrameDescriptor(
                descriptor.document,
                descriptorPath: descriptor.path,
                declaredByPath: declaredByPath
            )
        }
    }

    private func checkMeshAnchorIndex(
        _ index: StrictJSONValue,
        declaredByPath: [String: BundleFileEntry]
    ) throws {
        let reportPath = "mesh/anchors.json"
        guard let anchors = index.member("anchors")?.elements else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: reportPath,
                detail: "anchors array missing"
            )
        }
        for (position, anchor) in anchors.enumerated() {
            let anchorPath = "$.anchors[\(position)]"
            guard let geometryPath = anchor.member("geometry_path")?
                .stringValue,
                let declaredSHA = anchor.member("geometry_sha256")?
                .stringValue,
                let vertexCount = anchor.member("vertex_count")?.intValue,
                let faceCount = anchor.member("face_count")?.intValue
            else {
                throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                    path: reportPath,
                    detail: "\(anchorPath) incomplete"
                )
            }
            guard let entry = declaredByPath[geometryPath] else {
                throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                    path: reportPath,
                    detail: "\(anchorPath).geometry_path \(geometryPath) is not declared"
                )
            }
            guard entry.mediaType
                == CanonicalPayloadValidator.meshMediaType
            else {
                throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                    path: reportPath,
                    detail: "\(anchorPath).geometry_path \(geometryPath) is not a mesh payload"
                )
            }
            guard entry.sha256.description == declaredSHA else {
                throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                    path: reportPath,
                    detail: "\(anchorPath).geometry_sha256 does not match manifest"
                )
            }
            guard let decoded = meshGeometry[geometryPath],
                  decoded.vertices == vertexCount,
                  decoded.faces == faceCount
            else {
                throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                    path: reportPath,
                    detail: "\(anchorPath) geometry counts do not match decoded payload"
                )
            }
        }
    }

    private func checkFrameDescriptor(
        _ descriptor: StrictJSONValue,
        descriptorPath: String,
        declaredByPath: [String: BundleFileEntry]
    ) throws {
        guard let pixelPath = descriptor.member("pixel_relative_path")?
            .stringValue,
            let pixelByteCount = descriptor.member("pixel_byte_count")?
            .intValue,
            let pixelSHA = descriptor.member("pixel_sha256")?.stringValue,
            let imageWidth = descriptor.member("image_width")?.intValue,
            let imageHeight = descriptor.member("image_height")?.intValue,
            let pixelFormatFourCC = descriptor
            .member("pixel_format_fourcc")?.intValue
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "descriptor incomplete"
            )
        }
        guard let pixelEntry = declaredByPath[pixelPath] else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "pixel_relative_path \(pixelPath) is not declared"
            )
        }
        guard pixelEntry.mediaType
            == CanonicalPayloadValidator.pixelMediaType,
            Int64(pixelByteCount) == pixelEntry.bytes,
            pixelEntry.sha256.description == pixelSHA
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "pixel linkage does not match manifest"
            )
        }
        guard let decoded = pixelGeometry[pixelPath],
              decoded.width == imageWidth,
              decoded.height == imageHeight,
              decoded.pixelFormatFourCC
              == UInt32(exactly: pixelFormatFourCC)
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "pixel payload dimensions or format do not match descriptor"
            )
        }
        guard let depthStatus = descriptor.member("depth_status")?
            .stringValue
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "depth_status missing"
            )
        }
        let depthMember = descriptor.member("depth")
        guard let depthValue = depthMember, !depthValue.isNull else {
            guard depthStatus == "not_requested"
                || depthStatus == "unavailable"
            else {
                throw BundleDirectoryValidationError
                    .payloadCrossCheckFailed(
                        path: descriptorPath,
                        detail: "depth_status \(depthStatus) without depth payload"
                    )
            }
            return
        }
        let depth = depthValue
        let expectedStatus: String
        switch depth.member("kind")?.stringValue {
        case "scene_depth":
            expectedStatus = "captured_scene_depth"
        case "smoothed_scene_depth":
            expectedStatus = "captured_smoothed_scene_depth"
        default:
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "depth.kind missing"
            )
        }
        guard depthStatus == expectedStatus else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "depth_status \(depthStatus) does not match depth.kind"
            )
        }
        guard let depthPath = depth.member("depth_relative_path")?
            .stringValue,
            let depthByteCount = depth.member("depth_byte_count")?
            .intValue,
            let depthSHA = depth.member("depth_sha256")?.stringValue
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "depth linkage incomplete"
            )
        }
        guard let depthEntry = declaredByPath[depthPath] else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "depth_relative_path \(depthPath) is not declared"
            )
        }
        guard depthEntry.mediaType
            == CanonicalPayloadValidator.depthMediaType,
            Int64(depthByteCount) == depthEntry.bytes,
            depthEntry.sha256.description == depthSHA
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "depth linkage does not match manifest"
            )
        }
        guard let depthSummary = depthGeometry[depthPath],
              let depthWidth = depthSummary.width,
              let depthHeight = depthSummary.height
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "depth payload was not structurally decoded"
            )
        }
        let confidencePath = depth.member("confidence_relative_path")?
            .stringValue
        let confidenceByteCount = depth.member("confidence_byte_count")?
            .intValue
        let confidenceSHA = depth.member("confidence_sha256")?.stringValue
        if confidencePath == nil, confidenceByteCount == nil,
           confidenceSHA == nil
        {
            return
        }
        guard let confidencePath,
              let confidenceByteCount,
              let confidenceSHA
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "confidence linkage partially missing"
            )
        }
        guard let confidenceEntry = declaredByPath[confidencePath] else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "confidence_relative_path \(confidencePath) is not declared"
            )
        }
        guard confidenceEntry.mediaType
            == CanonicalPayloadValidator.confidenceMediaType,
            Int64(confidenceByteCount) == confidenceEntry.bytes,
            confidenceEntry.sha256.description == confidenceSHA
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "confidence linkage does not match manifest"
            )
        }
        guard let confidenceSummary = confidenceGeometry[confidencePath],
              confidenceSummary.width == depthWidth,
              confidenceSummary.height == depthHeight
        else {
            throw BundleDirectoryValidationError.payloadCrossCheckFailed(
                path: descriptorPath,
                detail: "confidence payload dimensions do not match depth"
            )
        }
    }
}

public enum CanonicalPayloadValidator {
    public static let meshMediaType = "application/vnd.htdt.meshbin"
    public static let pixelMediaType = "application/vnd.htdt.pixelbin"
    public static let depthMediaType = "application/vnd.htdt.depthbin"
    public static let confidenceMediaType =
        "application/vnd.htdt.confidencebin"

    /// Validates a schema-owned JSON payload (#188 canonical bytes, #135
    /// schema) and returns its parsed value. Returns nil when the path is
    /// not owned by a published schema.
    public static func validateSchemaOwnedJSON(
        path: String,
        data: Data
    ) throws -> StrictJSONValue? {
        guard let schemaName = CaptureBundleSchemaRegistry.schemaName(
            forPath: path
        ) else {
            return nil
        }
        let value: StrictJSONValue
        do {
            value = try StrictJSON.parse(data)
        } catch {
            throw BundleDirectoryValidationError.payloadNotCanonicalJSON(
                path: path,
                detail: "\(error)"
            )
        }
        let canonical: Data
        do {
            canonical = try CanonicalJSONProfile.canonicalBytes(of: value)
        } catch {
            throw BundleDirectoryValidationError.payloadNotCanonicalJSON(
                path: path,
                detail: "\(error)"
            )
        }
        guard canonical == data else {
            throw BundleDirectoryValidationError.payloadNotCanonicalJSON(
                path: path,
                detail: "bytes are not canonical JSON"
            )
        }
        let schema: CompiledJSONSchema
        do {
            schema = try CaptureBundleSchemaRegistry.compiledSchema(
                named: schemaName
            )
        } catch {
            throw BundleDirectoryValidationError.schemaValidationFailed(
                path: path,
                detail: "\(error)"
            )
        }
        if let violation = JSONSchemaValidator.validate(
            value,
            schema: schema
        ) {
            throw BundleDirectoryValidationError.schemaValidationFailed(
                path: path,
                detail: "\(violation.path): \(violation.detail)"
            )
        }
        return value
    }

    /// True when the declared media type is a canonical binary format
    /// that must be structurally decoded during validation.
    public static func isCanonicalBinaryMediaType(
        _ mediaType: String
    ) -> Bool {
        mediaType == meshMediaType
            || mediaType == pixelMediaType
            || mediaType == depthMediaType
            || mediaType == confidenceMediaType
    }

    /// Decodes and structurally validates a canonical binary payload
    /// (#142). Returns nil when the media type is not a canonical binary
    /// format.
    public static func validateBinaryPayload(
        path: String,
        mediaType: String,
        data: Data
    ) throws -> BinaryPayloadSummary? {
        switch mediaType {
        case meshMediaType:
            let geometry: MeshGeometryPayload
            do {
                geometry = try MeshBinaryCodec.decode(data)
            } catch {
                throw BundleDirectoryValidationError.binaryPayloadInvalid(
                    path: path,
                    detail: "\(error)"
                )
            }
            return BinaryPayloadSummary(
                vertexCount: geometry.vertices.count,
                faceCount: geometry.faceCount
            )
        case pixelMediaType:
            let buffer: PackedPixelBuffer
            do {
                buffer = try PixelBufferBinaryCodec.decode(data)
            } catch {
                throw BundleDirectoryValidationError.binaryPayloadInvalid(
                    path: path,
                    detail: "\(error)"
                )
            }
            return BinaryPayloadSummary(
                width: buffer.width,
                height: buffer.height,
                pixelFormatFourCC: buffer.pixelFormatFourCC
            )
        case depthMediaType:
            let depth: DepthMapPayload
            do {
                depth = try DepthBinaryCodec.decode(data)
            } catch {
                throw BundleDirectoryValidationError.binaryPayloadInvalid(
                    path: path,
                    detail: "\(error)"
                )
            }
            return BinaryPayloadSummary(
                width: depth.width,
                height: depth.height
            )
        case confidenceMediaType:
            let confidence: ConfidenceMapPayload
            do {
                confidence = try ConfidenceBinaryCodec.decode(data)
            } catch {
                throw BundleDirectoryValidationError.binaryPayloadInvalid(
                    path: path,
                    detail: "\(error)"
                )
            }
            return BinaryPayloadSummary(
                width: confidence.width,
                height: confidence.height
            )
        default:
            return nil
        }
    }

    /// Full per-file validation for a declared payload: schema/canonical
    /// JSON checks and structural binary checks, recording linkage facts
    /// into `crossCheck` for the finishing pass.
    public static func validateDeclaredPayload(
        path: String,
        mediaType: String,
        data: Data,
        crossCheck: inout BundlePayloadCrossCheck
    ) throws {
        if let value = try validateSchemaOwnedJSON(
            path: path,
            data: data
        ) {
            crossCheck.recordJSON(path: path, value: value)
        }
        if let summary = try validateBinaryPayload(
            path: path,
            mediaType: mediaType,
            data: data
        ) {
            crossCheck.recordBinary(
                path: path,
                mediaType: mediaType,
                summary: summary
            )
        }
    }
}
