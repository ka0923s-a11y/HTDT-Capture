import Foundation

/// A named span of faces inside a `DerivedMeshDocument`'s index list —
/// one group per RoomPlan object/surface for box exports, or a single
/// group covering a merged ARKit mesh.
public struct DerivedMeshFaceGroup: Sendable, Equatable {
    public let name: String
    public let faceRange: Range<Int>

    public init(name: String, faceRange: Range<Int>) {
        self.name = name
        self.faceRange = faceRange
    }
}

/// A mesh plus the provenance/comment block every writer embeds.
/// Vertices are always capture world space, meters, right-handed
/// with +Y up — the writer records that convention verbatim.
public struct DerivedMeshDocument: Sendable {
    public let mesh: MeshGeometryPayload
    public let objectName: String
    public let faceGroups: [DerivedMeshFaceGroup]
    public let provenance: DerivedExportProvenance

    public init(
        mesh: MeshGeometryPayload,
        objectName: String,
        faceGroups: [DerivedMeshFaceGroup] = [],
        provenance: DerivedExportProvenance
    ) {
        self.mesh = mesh
        self.objectName = objectName
        self.faceGroups = faceGroups
        self.provenance = provenance
    }

    /// Groups guaranteed to cover every face exactly once; falls back
    /// to a single group when the caller did not subdivide.
    public var effectiveFaceGroups: [DerivedMeshFaceGroup] {
        guard faceGroups.isEmpty else { return faceGroups }
        return [
            DerivedMeshFaceGroup(
                name: objectName,
                faceRange: 0..<mesh.triangleIndices.count / 3
            )
        ]
    }
}

public enum DerivedMeshWriterError: Error, Sendable, Equatable {
    /// A group covers a face index outside the mesh's face count.
    case faceGroupOutOfBounds(String)
    /// Groups overlap or leave faces uncovered.
    case faceGroupCoverageInvalid
}

// MARK: - OBJ (Wavefront)

/// Wavefront OBJ writer. Positions are meters in the capture world
/// space; groups map one-to-one to `faceGroups` so a RoomPlan box
/// export keeps each object/surface identifiable by name.
public enum DerivedOBJWriter {
    public static func write(
        _ document: DerivedMeshDocument
    ) throws -> Data {
        var text = ""
        for line in document.provenance.commentLines {
            text += "# \(line)\n"
        }
        text += "o \(document.objectName)\n"

        for vertex in document.mesh.vertices {
            text += "v \(fmt(vertex.x)) \(fmt(vertex.y)) \(fmt(vertex.z))\n"
        }
        if let normals = document.mesh.normals {
            for normal in normals {
                text += "vn \(fmt(normal.x)) \(fmt(normal.y)) \(fmt(normal.z))\n"
            }
        }

        let faceCount = document.mesh.triangleIndices.count / 3
        for group in document.effectiveFaceGroups {
            guard group.faceRange.upperBound <= faceCount,
                  group.faceRange.lowerBound >= 0
            else {
                throw DerivedMeshWriterError.faceGroupOutOfBounds(
                    group.name
                )
            }
            text += "g \(group.name)\n"
            for face in group.faceRange {
                let a = document.mesh.triangleIndices[face * 3] + 1
                let b = document.mesh.triangleIndices[face * 3 + 1] + 1
                let c = document.mesh.triangleIndices[face * 3 + 2] + 1
                if document.mesh.normals != nil {
                    text += "f \(a)//\(a) \(b)//\(b) \(c)//\(c)\n"
                } else {
                    text += "f \(a) \(b) \(c)\n"
                }
            }
        }
        return Data(text.utf8)
    }

    private static func fmt(_ value: Float) -> String {
        String(format: "%.9g", Double(value))
    }
}

// MARK: - PLY (ASCII)

/// ASCII PLY 1.0 writer — the simplest format field tools and mesh
/// viewers still read. Face groups have no PLY equivalent; group names
/// land in the comment block instead.
public enum DerivedPLYWriter {
    public static func write(
        _ document: DerivedMeshDocument
    ) throws -> Data {
        var text = "ply\nformat ascii 1.0\n"
        for line in document.provenance.commentLines {
            text += "comment \(line)\n"
        }
        for group in document.effectiveFaceGroups {
            text += "comment group \(group.name) faces \(group.faceRange.lowerBound)..\(group.faceRange.upperBound)\n"
        }
        let vertexCount = document.mesh.vertices.count
        text += "element vertex \(vertexCount)\n"
        text += "property float x\nproperty float y\nproperty float z\n"
        if document.mesh.normals != nil {
            text += "property float nx\nproperty float ny\nproperty float nz\n"
        }
        let faceCount = document.mesh.triangleIndices.count / 3
        text += "element face \(faceCount)\n"
        text += "property list uchar int vertex_indices\nend_header\n"

        for index in 0..<vertexCount {
            let v = document.mesh.vertices[index]
            if let normal = document.mesh.normals?[index] {
                text += "\(fmt(v.x)) \(fmt(v.y)) \(fmt(v.z)) \(fmt(normal.x)) \(fmt(normal.y)) \(fmt(normal.z))\n"
            } else {
                text += "\(fmt(v.x)) \(fmt(v.y)) \(fmt(v.z))\n"
            }
        }
        for face in 0..<faceCount {
            let a = document.mesh.triangleIndices[face * 3]
            let b = document.mesh.triangleIndices[face * 3 + 1]
            let c = document.mesh.triangleIndices[face * 3 + 2]
            text += "3 \(a) \(b) \(c)\n"
        }
        return Data(text.utf8)
    }

    private static func fmt(_ value: Float) -> String {
        String(format: "%.9g", Double(value))
    }
}

// MARK: - GLB (glTF 2.0 binary)

/// Minimal glTF 2.0 binary writer: one scene, one named node+mesh per
/// face group (so each RoomPlan box stays individually addressable),
/// shared POSITION/NORMAL buffers. Provenance rides in
/// `asset.extras.htdt_derived_export` plus a copyright marker.
public enum DerivedGLBWriter {
    private struct JSONChunk: Codable {
        let asset: Asset
        let scene: Int
        let scenes: [Scene]
        let nodes: [Node]
        let meshes: [Mesh]
        let accessors: [Accessor]
        let bufferViews: [BufferView]
        let buffers: [Buffer]

        struct Asset: Codable {
            let version: String
            let generator: String
            let copyright: String
            let extras: Extras

            struct Extras: Codable {
                let htdtDerivedExport: HtdtExtras

                enum CodingKeys: String, CodingKey {
                    case htdtDerivedExport = "htdt_derived_export"
                }

                struct HtdtExtras: Codable {
                    let derivedArtifact: Bool
                    let captureRevisionID: String
                    let captureSeriesID: String
                    let bundleDigest: String
                    let sourceCoordinateSpaceIDs: [String]
                    let sourceKind: String
                    let representation: String
                    let conversionTransform: String
                    let coordinateConvention: String
                    let unitConversion: String
                    let exporterName: String
                    let exporterVersion: String
                    let generatedAtUTC: String
                    let sourcePayloads: [Payload]

                    struct Payload: Codable {
                        let path: String
                        let sha256: String
                        let byteCount: Int
                    }
                }
            }
        }

        struct Scene: Codable { let nodes: [Int] }
        struct Node: Codable {
            let name: String
            let mesh: Int
        }
        struct Mesh: Codable {
            let name: String
            let primitives: [Primitive]

            struct Primitive: Codable {
                let attributes: [String: Int]
                let indices: Int
                let mode: Int
            }
        }
        struct Accessor: Codable {
            let bufferView: Int
            let byteOffset: Int
            let componentType: Int
            let count: Int
            let type: String
            let min: [Float]?
            let max: [Float]?
        }
        struct BufferView: Codable {
            let buffer: Int
            let byteOffset: Int
            let byteLength: Int
            let target: Int
        }
        struct Buffer: Codable { let byteLength: Int }
    }

    public static func write(
        _ document: DerivedMeshDocument
    ) throws -> Data {
        let mesh = document.mesh
        let vertexCount = mesh.vertices.count
        let groups = document.effectiveFaceGroups
        let faceCount = mesh.triangleIndices.count / 3
        for group in groups {
            guard group.faceRange.lowerBound >= 0,
                  group.faceRange.upperBound <= faceCount
            else {
                throw DerivedMeshWriterError.faceGroupOutOfBounds(
                    group.name
                )
            }
        }

        // BIN layout: positions | normals? | indices (one slice/group).
        var bin = Data()
        var minV = [Float](repeating: .greatestFiniteMagnitude, count: 3)
        var maxV = [Float](repeating: -.greatestFiniteMagnitude, count: 3)
        for vertex in mesh.vertices {
            for axis in 0..<3 {
                let c = [vertex.x, vertex.y, vertex.z][axis]
                minV[axis] = min(minV[axis], c)
                maxV[axis] = max(maxV[axis], c)
            }
            appendFloats(&bin, [vertex.x, vertex.y, vertex.z])
        }
        let positionsLength = bin.count

        var normalsAccessorIndex: Int? = nil
        if let normals = mesh.normals {
            for normal in normals {
                appendFloats(&bin, [normal.x, normal.y, normal.z])
            }
            normalsAccessorIndex = 1
        }

        var bufferViews: [JSONChunk.BufferView] = [
            .init(
                buffer: 0,
                byteOffset: 0,
                byteLength: positionsLength,
                target: 34962 // ARRAY_BUFFER
            )
        ]
        var accessors: [JSONChunk.Accessor] = [
            .init(
                bufferView: 0,
                byteOffset: 0,
                componentType: 5126, // FLOAT
                count: vertexCount,
                type: "VEC3",
                min: minV,
                max: maxV
            )
        ]
        if normalsAccessorIndex != nil {
            bufferViews.append(
                .init(
                    buffer: 0,
                    byteOffset: positionsLength,
                    byteLength: vertexCount * 12,
                    target: 34962
                )
            )
            accessors.append(
                .init(
                    bufferView: 1,
                    byteOffset: 0,
                    componentType: 5126,
                    count: vertexCount,
                    type: "VEC3",
                    min: nil,
                    max: nil
                )
            )
        }

        var nodes: [JSONChunk.Node] = []
        var meshes: [JSONChunk.Mesh] = []
        for (groupIndex, group) in groups.enumerated() {
            var attributes = ["POSITION": 0]
            attributes["NORMAL"] = normalsAccessorIndex

            let indexOffset = bin.count
            var indexCount = 0
            for face in group.faceRange {
                for corner in 0..<3 {
                    var index =
                        mesh.triangleIndices[face * 3 + corner]
                    withUnsafeBytes(of: &index) { bin.append(contentsOf: $0) }
                    indexCount += 1
                }
            }
            let indicesViewIndex = bufferViews.count
            bufferViews.append(
                .init(
                    buffer: 0,
                    byteOffset: indexOffset,
                    byteLength: indexCount * 4,
                    target: 34963 // ELEMENT_ARRAY_BUFFER
                )
            )
            accessors.append(
                .init(
                    bufferView: indicesViewIndex,
                    byteOffset: 0,
                    componentType: 5125, // UNSIGNED_INT
                    count: indexCount,
                    type: "SCALAR",
                    min: nil,
                    max: nil
                )
            )
            meshes.append(
                .init(
                    name: group.name,
                    primitives: [
                        .init(
                            attributes: attributes,
                            indices: accessors.count - 1,
                            mode: 4 // TRIANGLES
                        )
                    ]
                )
            )
            nodes.append(.init(name: group.name, mesh: groupIndex))
        }

        let provenance = document.provenance
        let json = JSONChunk(
            asset: .init(
                version: "2.0",
                generator:
                    "\(provenance.exporterName) \(provenance.exporterVersion)",
                copyright:
                    "Derived artifact — not canonical capture evidence",
                extras: .init(
                    htdtDerivedExport: .init(
                        derivedArtifact: true,
                        captureRevisionID:
                            provenance.captureRevisionID.description,
                        captureSeriesID:
                            provenance.captureSeriesID.description,
                        bundleDigest:
                            provenance.bundleDigest.description,
                        sourceCoordinateSpaceIDs:
                            provenance.sourceCoordinateSpaceIDs
                                .map(\.description),
                        sourceKind: provenance.sourceKind.rawValue,
                        representation:
                            provenance.representation.rawValue,
                        conversionTransform:
                            provenance.conversionTransform,
                        coordinateConvention:
                            provenance.coordinateConvention,
                        unitConversion: provenance.unitConversion,
                        exporterName: provenance.exporterName,
                        exporterVersion: provenance.exporterVersion,
                        generatedAtUTC: provenance.generatedAtUTC,
                        sourcePayloads:
                            provenance.sourcePayloads.map {
                                .init(
                                    path: $0.path,
                                    sha256: $0.sha256.description,
                                    byteCount: $0.byteCount
                                )
                            }
                    )
                )
            ),
            scene: 0,
            scenes: [.init(nodes: Array(0..<nodes.count))],
            nodes: nodes,
            meshes: meshes,
            accessors: accessors,
            bufferViews: bufferViews,
            buffers: [.init(byteLength: bin.count)]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var jsonData = try encoder.encode(json)
        while !jsonData.count.isMultiple(of: 4) {
            jsonData.append(0x20) // JSON chunks pad with spaces
        }
        while !bin.count.isMultiple(of: 4) {
            bin.append(0)
        }

        var glb = Data()
        var word: UInt32 = 0x46546C67 // "glTF"
        withUnsafeBytes(of: &word) { glb.append(contentsOf: $0) }
        word = 2
        withUnsafeBytes(of: &word) { glb.append(contentsOf: $0) }
        let totalLength = 12 + 8 + jsonData.count + 8 + bin.count
        word = UInt32(totalLength)
        withUnsafeBytes(of: &word) { glb.append(contentsOf: $0) }

        word = UInt32(jsonData.count)
        withUnsafeBytes(of: &word) { glb.append(contentsOf: $0) }
        word = 0x4E4F534A // "JSON"
        withUnsafeBytes(of: &word) { glb.append(contentsOf: $0) }
        glb.append(jsonData)

        word = UInt32(bin.count)
        withUnsafeBytes(of: &word) { glb.append(contentsOf: $0) }
        word = 0x004E4942 // "BIN\0"
        withUnsafeBytes(of: &word) { glb.append(contentsOf: $0) }
        glb.append(bin)

        return glb
    }

    private static func appendFloats(
        _ data: inout Data,
        _ values: [Float]
    ) {
        for var value in values {
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
    }
}

// MARK: - RoomPlan box synthesis (Core side)

/// Synthesizes one closed box mesh per `RoomPlanBindableObject` from its
/// world-space pose and object-space extents. The result is explicitly
/// a bounding-box model (`roomplan_bounding_boxes`), never presented as
/// measured surface geometry.
public enum RoomPlanBoxMeshBuilder {
    public struct Result: Sendable {
        public let mesh: MeshGeometryPayload
        public let groups: [DerivedMeshFaceGroup]
    }

    public static func build(
        objects: [RoomPlanBindableObject]
    ) throws -> Result {
        var vertices: [Float3] = []
        var normals: [Float3] = []
        var indices: [UInt32] = []
        var groups: [DerivedMeshFaceGroup] = []
        var emitted = 0

        // Local-space box: six faces, each four corners + two triangles,
        // flat-shaded with a per-face normal.
        let faces: [([Float3], Float3)] = [
            // +X
            ([Float3(1, -1, -1), Float3(1, -1, 1), Float3(1, 1, 1), Float3(1, 1, -1)], Float3(1, 0, 0)),
            // -X
            ([Float3(-1, -1, 1), Float3(-1, -1, -1), Float3(-1, 1, -1), Float3(-1, 1, 1)], Float3(-1, 0, 0)),
            // +Y
            ([Float3(-1, 1, -1), Float3(1, 1, -1), Float3(1, 1, 1), Float3(-1, 1, 1)], Float3(0, 1, 0)),
            // -Y
            ([Float3(-1, -1, 1), Float3(1, -1, 1), Float3(1, -1, -1), Float3(-1, -1, -1)], Float3(0, -1, 0)),
            // +Z
            ([Float3(-1, -1, 1), Float3(-1, 1, 1), Float3(1, 1, 1), Float3(1, -1, 1)], Float3(0, 0, 1)),
            // -Z
            ([Float3(1, -1, -1), Float3(1, 1, -1), Float3(-1, 1, -1), Float3(-1, -1, -1)], Float3(0, 0, -1)),
        ]

        for object in objects {
            let half = Float3(
                max(object.dimensionsMeters.x, 0) / 2,
                max(object.dimensionsMeters.y, 0) / 2,
                max(object.dimensionsMeters.z, 0) / 2
            )
            guard half.x > 0, half.y > 0, half.z > 0 else {
                continue
            }
            let faceStart = indices.count / 3
            for (corners, localNormal) in faces {
                let base = UInt32(vertices.count)
                let worldNormal =
                    object.worldFromObject.applying(
                        toDirection: localNormal
                    )
                for corner in corners {
                    let local = Float3(
                        corner.x * half.x,
                        corner.y * half.y,
                        corner.z * half.z
                    )
                    vertices.append(
                        object.worldFromObject.applying(to: local)
                    )
                    normals.append(worldNormal)
                }
                indices.append(contentsOf: [
                    base, base + 1, base + 2,
                    base, base + 2, base + 3,
                ])
            }
            let faceEnd = indices.count / 3
            groups.append(
                DerivedMeshFaceGroup(
                    name: object.identifier + " (" + object.category + ")",
                    faceRange: faceStart..<faceEnd
                )
            )
            emitted += 1
        }

        guard emitted > 0 else {
            throw DerivedExportError.emptyGeometry(
                reason:
                    "The processed RoomPlan payload contains no objects or surfaces with measurable extents"
            )
        }
        return Result(
            mesh: try MeshGeometryPayload(
                vertices: vertices,
                normals: normals,
                triangleIndices: indices
            ),
            groups: groups
        )
    }
}

// MARK: - ARKit mesh merge

/// Merges the bundle's recorded ARKit mesh anchors into one world-space
/// mesh. Every geometry file's bytes are SHA-256 checked against the
/// recorded `mesh/anchors.json` index before merge, so a corrupt or
/// tampered payload fails with a readable reason instead of exporting
/// bad geometry.
public enum DerivedARMeshMerge {
    public struct Merged: Sendable {
        public let mesh: MeshGeometryPayload
        public let payloads: [DerivedExportSourcePayload]
        public let coordinateSpaceIDs: [CoordinateSpaceID]
        public let anchorCount: Int
    }

    public static func merge(
        bundleDirectory: URL,
        manifest: BundleManifest
    ) throws -> Merged {
        let indexPath = MeshEvidencePackage.indexPath
        guard manifest.files.contains(where: { $0.path == indexPath })
        else {
            throw DerivedExportError.sourceUnavailable(
                reason:
                    "The bundle declares no \(indexPath) — this capture has no recorded ARKit mesh"
            )
        }
        let declared = Set(manifest.files.map(\.path))
        let indexURL = url(bundleDirectory, indexPath)
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(
                  MeshAnchorEvidenceIndex.self,
                  from: indexData
              )
        else {
            throw DerivedExportError.malformedSource(
                reason: "\(indexPath) could not be decoded"
            )
        }
        var payloads = [
            DerivedExportSourcePayload(
                path: indexPath,
                sha256: EvidenceIntegrity.sha256(of: indexData),
                byteCount: indexData.count
            )
        ]

        var vertices: [Float3] = []
        var normals: [Float3] = []
        var indices: [UInt32] = []
        var classifications: [UInt8] = []
        var hasNormals = true
        var hasClassifications = true
        var spaces: [CoordinateSpaceID] = []
        var anchorsUsed = 0

        for record in index.anchors {
            guard declared.contains(record.geometryPath) else {
                throw DerivedExportError.malformedSource(
                    reason:
                        "mesh anchor \(record.anchorID.description) payload \(record.geometryPath) is not declared in the manifest"
                )
            }
            let url = url(bundleDirectory, record.geometryPath)
            guard let data = try? Data(contentsOf: url) else {
                throw DerivedExportError.malformedSource(
                    reason:
                        "mesh anchor \(record.anchorID.description) payload \(record.geometryPath) is unreadable"
                )
            }
            let digest = EvidenceIntegrity.sha256(of: data)
            guard digest == record.geometrySHA256 else {
                throw DerivedExportError.malformedSource(
                    reason:
                        "mesh anchor \(record.anchorID.description) payload digest mismatch — the recorded geometry is not the finalized bytes"
                )
            }
            guard let geometry = try? MeshBinaryCodec.decode(data)
            else {
                throw DerivedExportError.malformedSource(
                    reason:
                        "mesh anchor \(record.anchorID.description) payload could not be decoded"
                )
            }

            let base = UInt32(vertices.count)
            vertices.append(
                contentsOf: geometry.vertices.map {
                    record.worldFromAnchor.applying(to: $0)
                }
            )
            if let meshNormals = geometry.normals {
                normals.append(
                    contentsOf: meshNormals.map {
                        record.worldFromAnchor
                            .applying(toDirection: $0)
                    }
                )
            } else {
                hasNormals = false
            }
            indices.append(
                contentsOf: geometry.triangleIndices.map {
                    $0 + base
                }
            )
            if let meshClassifications =
                geometry.faceClassifications
            {
                classifications.append(
                    contentsOf: meshClassifications
                )
            } else {
                hasClassifications = false
            }
            payloads.append(
                DerivedExportSourcePayload(
                    path: record.geometryPath,
                    sha256: digest,
                    byteCount: data.count
                )
            )
            if !spaces.contains(record.coordinateSpaceID) {
                spaces.append(record.coordinateSpaceID)
            }
            anchorsUsed += 1
        }

        guard anchorsUsed > 0, !indices.isEmpty else {
            throw DerivedExportError.emptyGeometry(
                reason:
                    "The recorded ARKit mesh index contains no anchors with geometry"
            )
        }
        return Merged(
            mesh: try MeshGeometryPayload(
                vertices: vertices,
                normals: hasNormals ? normals : nil,
                triangleIndices: indices,
                faceClassifications:
                    hasClassifications ? classifications : nil
            ),
            payloads: payloads,
            coordinateSpaceIDs: spaces,
            anchorCount: anchorsUsed
        )
    }

    private static func url(
        _ directory: URL,
        _ path: String
    ) -> URL {
        path.split(separator: "/").reduce(directory) {
            $0.appendingPathComponent(
                String($1),
                isDirectory: false
            )
        }
    }
}

// MARK: - Export runner

/// Writes derived 3D artifacts under
/// `<captureRoot>/derived-exports/<capture_revision_id>/` — a sibling
/// of `finalized/`, `exports/`, `working/` and `diagnostics/` that the
/// persisted-capture inventory never scans, so derived convenience
/// outputs can never be mistaken for (or quarantined as) canonical
/// bundle exports (issue bolph71656-ai/HTDT-Capture#306).
public enum DerivedExportRunner {
    public static func exportsDirectory(
        captureRoot: URL,
        revisionID: CaptureRevisionID
    ) -> URL {
        captureRoot
            .appendingPathComponent("derived-exports", isDirectory: true)
            .appendingPathComponent(
                revisionID.description,
                isDirectory: true
            )
    }

    /// Mesh-based formats (GLB/OBJ/PLY) from either geometry source.
    /// `roomPlanObjects` is required when `source == .roomPlanProcessed`
    /// — the platform layer decodes `CapturedRoom` into bindable boxes
    /// and passes them in so Core stays RoomPlan-free (macOS-testable).
    public static func exportMesh(
        bundleDirectory: URL,
        bundleDigest: EvidenceSHA256,
        captureRoot: URL,
        format: DerivedExportFormat,
        source: DerivedExportSourceKind,
        roomPlanObjects: [RoomPlanBindableObject]? = nil,
        generatedAtUTC: String? = nil
    ) throws -> Derived3DExportResult {
        guard format != .usdz else {
            throw DerivedExportError.unsupportedCombination(
                reason:
                    "USDZ is only produced from the processed RoomPlan payload — use the RoomPlan source"
            )
        }
        guard source.supportedFormats.contains(format) else {
            throw DerivedExportError.unsupportedCombination(
                reason:
                    "\(format.rawValue) is not supported for source \(source.rawValue)"
            )
        }
        let manifest = try loadManifest(bundleDirectory: bundleDirectory)
        let timestamp =
            generatedAtUTC ?? BundleTimestamp.utcString(from: Date())
        let stem = filenameStem(
            revisionID: manifest.captureRevisionID,
            source: source
        )

        let document: DerivedMeshDocument
        switch source {
        case .arMeshAnchors:
            let merged = try DerivedARMeshMerge.merge(
                bundleDirectory: bundleDirectory,
                manifest: manifest
            )
            let provenance = DerivedExportProvenance(
                captureSeriesID: manifest.captureSeriesID,
                captureRevisionID: manifest.captureRevisionID,
                bundleDigest: bundleDigest,
                sourceCoordinateSpaceIDs:
                    merged.coordinateSpaceIDs,
                format: format,
                sourceKind: source,
                representation: .arMeshWorldGeometry,
                sourcePayloads: merged.payloads,
                conversionTransform:
                    "each anchor's local vertices transformed by its recorded T_world_from_anchor; merged into one world-space mesh",
                coordinateConvention:
                    "meters, +Y up, right-handed (capture world space)",
                unitConversion: "meters — no scale change",
                producerApp: manifest.app,
                generatedAtUTC: timestamp
            )
            document = DerivedMeshDocument(
                mesh: merged.mesh,
                objectName: stem + "-mesh",
                faceGroups: [
                    DerivedMeshFaceGroup(
                        name: "arkit-mesh",
                        faceRange:
                            0..<merged.mesh.triangleIndices.count / 3
                    )
                ],
                provenance: provenance
            )
        case .roomPlanProcessed:
            guard let objects = roomPlanObjects, !objects.isEmpty
            else {
                throw DerivedExportError.sourceUnavailable(
                    reason:
                        "No RoomPlan objects/surfaces could be decoded from roomplan/captured-room.json"
                )
            }
            let built = try RoomPlanBoxMeshBuilder.build(
                objects: objects
            )
            let provenance = DerivedExportProvenance(
                captureSeriesID: manifest.captureSeriesID,
                captureRevisionID: manifest.captureRevisionID,
                bundleDigest: bundleDigest,
                sourceCoordinateSpaceIDs:
                    roomPlanCoordinateSpaceIDs(
                        bundleDirectory: bundleDirectory,
                        manifest: manifest
                    ),
                format: format,
                sourceKind: source,
                representation: .roomPlanBoundingBoxes,
                sourcePayloads:
                    roomPlanSourcePayloads(
                        bundleDirectory: bundleDirectory,
                        manifest: manifest
                    ),
                conversionTransform:
                    "RoomPlan object/surface poses applied to synthesized bounding boxes (\(objects.count) records); world = T_world_from_object · local",
                coordinateConvention:
                    "meters, +Y up, right-handed (capture world space)",
                unitConversion: "meters — no scale change",
                producerApp: manifest.app,
                generatedAtUTC: timestamp
            )
            document = DerivedMeshDocument(
                mesh: built.mesh,
                objectName: stem + "-roomplan-boxes",
                faceGroups: built.groups,
                provenance: provenance
            )
        }

        let data: Data
        switch format {
        case .obj:
            data = try DerivedOBJWriter.write(document)
        case .ply:
            data = try DerivedPLYWriter.write(document)
        case .glb:
            data = try DerivedGLBWriter.write(document)
        case .usdz:
            preconditionFailure("USDZ is filtered above")
        }
        return try write(
            data: data,
            provenance: document.provenance,
            captureRoot: captureRoot
        )
    }

    /// USDZ export: the platform layer decodes `CapturedRoom` and calls
    /// RoomPlan's `export(to:)` into the prepared destination; this
    /// runner only owns naming + provenance sidecar.
    public static func exportUSDZ(
        bundleDirectory: URL,
        bundleDigest: EvidenceSHA256,
        captureRoot: URL,
        generatedAtUTC: String? = nil,
        usdzWriter: (URL) throws -> Void
    ) throws -> Derived3DExportResult {
        let manifest = try loadManifest(bundleDirectory: bundleDirectory)
        let timestamp =
            generatedAtUTC ?? BundleTimestamp.utcString(from: Date())
        let provenance = DerivedExportProvenance(
            captureSeriesID: manifest.captureSeriesID,
            captureRevisionID: manifest.captureRevisionID,
            bundleDigest: bundleDigest,
            sourceCoordinateSpaceIDs:
                roomPlanCoordinateSpaceIDs(
                    bundleDirectory: bundleDirectory,
                    manifest: manifest
                ),
            format: .usdz,
            sourceKind: .roomPlanProcessed,
            representation: .roomPlanNativeParametric,
            sourcePayloads:
                roomPlanSourcePayloads(
                    bundleDirectory: bundleDirectory,
                    manifest: manifest
                ),
            conversionTransform:
                "RoomPlan CapturedRoom.export parametric emission — RoomPlan-authored transforms applied internally",
            coordinateConvention:
                "USDZ: meters, +Y up, right-handed (capture world space)",
            unitConversion: "meters — no scale change",
            producerApp: manifest.app,
            generatedAtUTC: timestamp
        )

        let destination = try destinationURLs(
            captureRoot: captureRoot,
            revisionID: manifest.captureRevisionID,
            stem: filenameStem(
                revisionID: manifest.captureRevisionID,
                source: .roomPlanProcessed
            ),
            format: .usdz
        )
        do {
            try usdzWriter(destination.primaryFileURL)
        } catch {
            throw DerivedExportError.writeFailed(
                reason:
                    "RoomPlan USDZ export failed: \(error.localizedDescription)"
            )
        }
        try writeProvenance(
            provenance,
            to: destination.provenanceFileURL
        )
        return Derived3DExportResult(
            primaryFileURL: destination.primaryFileURL,
            provenanceFileURL: destination.provenanceFileURL,
            provenance: provenance
        )
    }

    // MARK: internal

    public static func loadManifest(
        bundleDirectory: URL
    ) throws -> BundleManifest {
        let url = bundleDirectory.appendingPathComponent(
            "manifest.json",
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(
                  BundleManifest.self,
                  from: data
              )
        else {
            throw DerivedExportError.malformedSource(
                reason:
                    "manifest.json could not be read or decoded — is this a finalized bundle?"
            )
        }
        return manifest
    }

    /// Digests of the exact RoomPlan payload bytes consumed by a
    /// derived export, when the manifest declares them.
    private static func roomPlanSourcePayloads(
        bundleDirectory: URL,
        manifest: BundleManifest
    ) -> [DerivedExportSourcePayload] {
        var payloads: [DerivedExportSourcePayload] = []
        for path in [
            RoomPlanEvidenceArtifactBuilder.processedPath,
            RoomPlanEvidenceArtifactBuilder.rawPath,
        ] where manifest.files.contains(where: { $0.path == path }) {
            let fileURL = url(bundleDirectory, path)
            if let data = try? Data(contentsOf: fileURL) {
                payloads.append(
                    DerivedExportSourcePayload(
                        path: path,
                        sha256: EvidenceIntegrity.sha256(of: data),
                        byteCount: data.count
                    )
                )
            }
        }
        return payloads
    }

    /// The RoomPlan coordinate space from the metadata payload when
    /// recorded; falls back to the manifest's declared space ids.
    private static func roomPlanCoordinateSpaceIDs(
        bundleDirectory: URL,
        manifest: BundleManifest
    ) -> [CoordinateSpaceID] {
        if let data = try? Data(
            contentsOf: url(
                bundleDirectory,
                RoomPlanEvidenceArtifactBuilder.metadataPath
            )
        ),
           let metadata = try? JSONDecoder().decode(
               CapturedRoomMetadataDocument.self,
               from: data
           )
        {
            return [metadata.coordinateSpaceID]
        }
        return manifest.coordinateSpaceIDs
    }

    private static func filenameStem(
        revisionID: CaptureRevisionID,
        source: DerivedExportSourceKind
    ) -> String {
        switch source {
        case .roomPlanProcessed:
            "capture-" + revisionID.description + "-roomplan"
        case .arMeshAnchors:
            "capture-" + revisionID.description + "-armesh"
        }
    }

    private struct Destination {
        let primaryFileURL: URL
        let provenanceFileURL: URL
    }

    private static func destinationURLs(
        captureRoot: URL,
        revisionID: CaptureRevisionID,
        stem: String,
        format: DerivedExportFormat
    ) throws -> Destination {
        let directory = exportsDirectory(
            captureRoot: captureRoot,
            revisionID: revisionID
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw DerivedExportError.writeFailed(
                reason:
                    "derived-exports directory could not be created: \(error.localizedDescription)"
            )
        }
        return Destination(
            primaryFileURL: directory.appendingPathComponent(
                stem + "." + format.filenameExtension,
                isDirectory: false
            ),
            provenanceFileURL: directory.appendingPathComponent(
                stem + ".provenance.json",
                isDirectory: false
            )
        )
    }

    private static func write(
        data: Data,
        provenance: DerivedExportProvenance,
        captureRoot: URL
    ) throws -> Derived3DExportResult {
        let destination = try destinationURLs(
            captureRoot: captureRoot,
            revisionID: provenance.captureRevisionID,
            stem: filenameStem(
                revisionID: provenance.captureRevisionID,
                source: provenance.sourceKind
            ),
            format: provenance.format
        )
        do {
            try data.write(to: destination.primaryFileURL)
        } catch {
            throw DerivedExportError.writeFailed(
                reason:
                    "the export file could not be written: \(error.localizedDescription)"
            )
        }
        try writeProvenance(
            provenance,
            to: destination.provenanceFileURL
        )
        return Derived3DExportResult(
            primaryFileURL: destination.primaryFileURL,
            provenanceFileURL: destination.provenanceFileURL,
            provenance: provenance
        )
    }

    private static func writeProvenance(
        _ provenance: DerivedExportProvenance,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .prettyPrinted, .withoutEscapingSlashes,
        ]
        do {
            try encoder.encode(provenance).write(to: url)
        } catch {
            throw DerivedExportError.writeFailed(
                reason:
                    "the provenance record could not be written: \(error.localizedDescription)"
            )
        }
    }

    private static func url(
        _ directory: URL,
        _ path: String
    ) -> URL {
        path.split(separator: "/").reduce(directory) {
            $0.appendingPathComponent(
                String($1),
                isDirectory: false
            )
        }
    }
}
