import Foundation

public enum EvidenceDigestError: Error, Sendable, Equatable {
    case invalidSHA256(String)
}

public struct EvidenceSHA256: Codable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) throws {
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        guard value.count == 64,
              value.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw EvidenceDigestError.invalidSHA256(value)
        }
        self.value = value
    }

    public var description: String { value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected 64 lowercase hexadecimal SHA-256 characters"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct CaptureRuntimeProvenance: Codable, Sendable, Equatable {
    public var osVersion: String
    public var osBuild: String?
    public var appVersion: String
    public var appBuild: String

    public init(
        osVersion: String,
        osBuild: String? = nil,
        appVersion: String,
        appBuild: String
    ) {
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.appVersion = appVersion
        self.appBuild = appBuild
    }

    private enum CodingKeys: String, CodingKey {
        case osVersion = "os_version"
        case osBuild = "os_build"
        case appVersion = "app_version"
        case appBuild = "app_build"
    }
}

public struct RoomPlanRawEvidenceDescriptor: Codable, Sendable, Equatable {
    public var captureSessionID: CaptureSessionID
    public var coordinateSpaceID: CoordinateSpaceID
    public var relativePath: String
    public var byteCount: Int
    public var sha256: EvidenceSHA256
    public var serializationFormat: String
    public var runtime: CaptureRuntimeProvenance

    public init(
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        relativePath: String,
        byteCount: Int,
        sha256: EvidenceSHA256,
        serializationFormat: String = "apple_codable_json",
        runtime: CaptureRuntimeProvenance
    ) {
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.serializationFormat = serializationFormat
        self.runtime = runtime
    }
}

public struct RoomPlanProcessedEvidenceDescriptor: Codable, Sendable, Equatable {
    public var captureSessionID: CaptureSessionID
    public var coordinateSpaceID: CoordinateSpaceID
    public var relativePath: String
    public var byteCount: Int
    public var sha256: EvidenceSHA256
    public var sourceRawSHA256: EvidenceSHA256
    public var serializationFormat: String
    public var capturedRoomVersion: String?
    public var runtime: CaptureRuntimeProvenance

    public init(
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        relativePath: String,
        byteCount: Int,
        sha256: EvidenceSHA256,
        sourceRawSHA256: EvidenceSHA256,
        serializationFormat: String = "apple_codable_json",
        capturedRoomVersion: String? = nil,
        runtime: CaptureRuntimeProvenance
    ) {
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.sourceRawSHA256 = sourceRawSHA256
        self.serializationFormat = serializationFormat
        self.capturedRoomVersion = capturedRoomVersion
        self.runtime = runtime
    }
}

public enum CapturedRoomMetadataError: Error, Sendable, Equatable {
    case negativeCount
    case nonFiniteDimension
    case nonCanonicalArtifactPath
    case processedLineageMismatch
    case encodedDocumentMismatch
}

/// Optional bounded summary of the postprocessed CapturedRoom contents.
/// Populated only from real CapturedRoom metadata by the producer; the
/// store never derives these values from opaque payload bytes.
public struct CapturedRoomDimensionsSummary:
    Codable,
    Sendable,
    Equatable
{
    public let xMeters: Double
    public let yMeters: Double
    public let zMeters: Double

    public init(
        xMeters: Double,
        yMeters: Double,
        zMeters: Double
    ) throws {
        guard
            xMeters.isFinite, yMeters.isFinite, zMeters.isFinite,
            xMeters >= 0, yMeters >= 0, zMeters >= 0
        else {
            throw CapturedRoomMetadataError.nonFiniteDimension
        }
        self.xMeters = xMeters
        self.yMeters = yMeters
        self.zMeters = zMeters
    }

    private enum CodingKeys: String, CodingKey {
        case xMeters = "x_m"
        case yMeters = "y_m"
        case zMeters = "z_m"
    }
}

public struct CapturedRoomContentSummary: Codable, Sendable, Equatable {
    public var surfaceCount: Int?
    public var objectCount: Int?
    public var dimensionsMeters: CapturedRoomDimensionsSummary?

    public init(
        surfaceCount: Int? = nil,
        objectCount: Int? = nil,
        dimensionsMeters: CapturedRoomDimensionsSummary? = nil
    ) throws {
        for count in [surfaceCount, objectCount] {
            if let count, count < 0 {
                throw CapturedRoomMetadataError.negativeCount
            }
        }
        self.surfaceCount = surfaceCount
        self.objectCount = objectCount
        self.dimensionsMeters = dimensionsMeters
    }

    private enum CodingKeys: String, CodingKey {
        case surfaceCount = "surface_count"
        case objectCount = "object_count"
        case dimensionsMeters = "dimensions_m"
    }
}

/// Canonical RoomPlan lineage document persisted at
/// `roomplan/captured-room-metadata.json`. It binds the raw and processed
/// RoomPlan artifacts to the exact capture-session/coordinate authority
/// and runtime provenance that the in-memory descriptors carried while
/// the working set was live (issue #152).
public struct CapturedRoomMetadataDocument: Codable, Sendable, Equatable {
    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    public let rawPayloadPath: String
    public let rawSHA256: EvidenceSHA256
    public let rawByteCount: Int
    public let rawSerializationFormat: String
    public let processedPayloadPath: String?
    public let processedSHA256: EvidenceSHA256?
    public let processedByteCount: Int?
    public let processedSerializationFormat: String?
    public let capturedRoomVersion: String?
    public let runtime: CaptureRuntimeProvenance
    public let summary: CapturedRoomContentSummary?

    public init(
        captureRevisionID: CaptureRevisionID,
        raw: RoomPlanRawEvidenceDescriptor,
        processed: RoomPlanProcessedEvidenceDescriptor?,
        summary: CapturedRoomContentSummary? = nil
    ) throws {
        guard raw.relativePath
                == RoomPlanEvidenceArtifactBuilder.rawPath
        else {
            throw CapturedRoomMetadataError.nonCanonicalArtifactPath
        }
        if let processed {
            guard
                processed.relativePath
                    == RoomPlanEvidenceArtifactBuilder.processedPath
            else {
                throw CapturedRoomMetadataError
                    .nonCanonicalArtifactPath
            }
            guard
                processed.sourceRawSHA256 == raw.sha256,
                processed.captureSessionID == raw.captureSessionID,
                processed.coordinateSpaceID == raw.coordinateSpaceID
            else {
                throw CapturedRoomMetadataError
                    .processedLineageMismatch
            }
        }

        self.schema = "htdt.captured-room-metadata"
        self.schemaVersion = "1.0.0"
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = raw.captureSessionID
        self.coordinateSpaceID = raw.coordinateSpaceID
        self.rawPayloadPath = raw.relativePath
        self.rawSHA256 = raw.sha256
        self.rawByteCount = raw.byteCount
        self.rawSerializationFormat = raw.serializationFormat
        self.processedPayloadPath = processed?.relativePath
        self.processedSHA256 = processed?.sha256
        self.processedByteCount = processed?.byteCount
        self.processedSerializationFormat =
            processed?.serializationFormat
        self.capturedRoomVersion = processed?.capturedRoomVersion
        self.runtime = processed?.runtime ?? raw.runtime
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case rawPayloadPath = "raw_payload_path"
        case rawSHA256 = "raw_sha256"
        case rawByteCount = "raw_byte_count"
        case rawSerializationFormat = "raw_serialization_format"
        case processedPayloadPath = "processed_payload_path"
        case processedSHA256 = "processed_sha256"
        case processedByteCount = "processed_byte_count"
        case processedSerializationFormat =
            "processed_serialization_format"
        case capturedRoomVersion = "captured_room_version"
        case runtime
        case summary
    }
}

/// A fully-encoded metadata payload ready for canonical persistence.
public struct CapturedRoomMetadataPackage: Sendable, Equatable {
    public static let path =
        "roomplan/captured-room-metadata.json"

    public let document: CapturedRoomMetadataDocument
    public let data: Data

    public init(
        document: CapturedRoomMetadataDocument,
        data: Data
    ) {
        self.document = document
        self.data = data
    }
}
