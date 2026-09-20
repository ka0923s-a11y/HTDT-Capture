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

public enum RoomPlanRawSerializationStatus:
    String,
    Codable,
    Sendable,
    Equatable
{
    case persisted
    case unavailable
}

public struct RoomPlanProcessedEvidenceDescriptor: Codable, Sendable, Equatable {
    public var captureSessionID: CaptureSessionID
    public var coordinateSpaceID: CoordinateSpaceID
    public var relativePath: String
    public var byteCount: Int
    public var sha256: EvidenceSHA256
    public var sourceRawSHA256: EvidenceSHA256?
    public var sourceRawSerializationStatus:
        RoomPlanRawSerializationStatus
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
        sourceRawSerializationStatus = .persisted
        self.serializationFormat = serializationFormat
        self.capturedRoomVersion = capturedRoomVersion
        self.runtime = runtime
    }

    public init(
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        relativePath: String,
        byteCount: Int,
        sha256: EvidenceSHA256,
        sourceRawSerializationStatus:
            RoomPlanRawSerializationStatus,
        serializationFormat: String = "apple_codable_json",
        capturedRoomVersion: String? = nil,
        runtime: CaptureRuntimeProvenance
    ) {
        precondition(
            sourceRawSerializationStatus == .unavailable
        )
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        sourceRawSHA256 = nil
        self.sourceRawSerializationStatus =
            sourceRawSerializationStatus
        self.serializationFormat = serializationFormat
        self.capturedRoomVersion = capturedRoomVersion
        self.runtime = runtime
    }
}
