import Foundation

public struct RoomPlanRawArtifactPayload: Sendable, Equatable {
    public let data: Data
    public let descriptor: RoomPlanRawEvidenceDescriptor

    public init(
        data: Data,
        descriptor: RoomPlanRawEvidenceDescriptor
    ) {
        self.data = data
        self.descriptor = descriptor
    }
}

public struct RoomPlanProcessedArtifactPayload: Sendable, Equatable {
    public let data: Data
    public let descriptor: RoomPlanProcessedEvidenceDescriptor

    public init(
        data: Data,
        descriptor: RoomPlanProcessedEvidenceDescriptor
    ) {
        self.data = data
        self.descriptor = descriptor
    }
}

public struct RoomPlanArtifactLineage: Sendable, Equatable {
    public let raw: RoomPlanRawArtifactPayload
    public let processed: RoomPlanProcessedArtifactPayload?

    public init(
        raw: RoomPlanRawArtifactPayload,
        processed: RoomPlanProcessedArtifactPayload? = nil
    ) {
        self.raw = raw
        self.processed = processed
    }
}

public enum RoomPlanEvidenceArtifactBuilder {
    public static let rawPath = "roomplan/captured-room-data.json"
    public static let processedPath = "roomplan/captured-room.json"

    public static func buildRaw(
        data: Data,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        runtime: CaptureRuntimeProvenance
    ) -> RoomPlanRawArtifactPayload {
        let descriptor = RoomPlanRawEvidenceDescriptor(
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            relativePath: rawPath,
            byteCount: data.count,
            sha256: EvidenceIntegrity.sha256(of: data),
            runtime: runtime
        )
        return RoomPlanRawArtifactPayload(
            data: data,
            descriptor: descriptor
        )
    }

    public static func attachProcessed(
        data: Data,
        to raw: RoomPlanRawArtifactPayload,
        capturedRoomVersion: String? = nil
    ) -> RoomPlanArtifactLineage {
        let descriptor = RoomPlanProcessedEvidenceDescriptor(
            captureSessionID: raw.descriptor.captureSessionID,
            coordinateSpaceID: raw.descriptor.coordinateSpaceID,
            relativePath: processedPath,
            byteCount: data.count,
            sha256: EvidenceIntegrity.sha256(of: data),
            sourceRawSHA256: raw.descriptor.sha256,
            capturedRoomVersion: capturedRoomVersion,
            runtime: raw.descriptor.runtime
        )
        return RoomPlanArtifactLineage(
            raw: raw,
            processed: RoomPlanProcessedArtifactPayload(
                data: data,
                descriptor: descriptor
            )
        )
    }
}
