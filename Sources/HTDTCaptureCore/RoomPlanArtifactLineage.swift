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
    /// Optional bounded CapturedRoom content summary carried into the
    /// canonical captured-room-metadata.json lineage document.
    public let metadataSummary: CapturedRoomContentSummary?

    public init(
        data: Data,
        descriptor: RoomPlanProcessedEvidenceDescriptor,
        metadataSummary: CapturedRoomContentSummary? = nil
    ) {
        self.data = data
        self.descriptor = descriptor
        self.metadataSummary = metadataSummary
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
    public static let metadataPath = CapturedRoomMetadataPackage.path

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
        capturedRoomVersion: String? = nil,
        metadataSummary: CapturedRoomContentSummary? = nil
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
                descriptor: descriptor,
                metadataSummary: metadataSummary
            )
        )
    }
}

public enum CapturedRoomMetadataPackageBuilder {
    /// Builds the canonical lineage payload deterministically from the
    /// already-validated RoomPlan descriptors. The encoded bytes are
    /// sorted-key JSON and are verified to decode back to the same
    /// document before they can reach the store.
    public static func build(
        captureRevisionID: CaptureRevisionID,
        raw: RoomPlanRawEvidenceDescriptor,
        processed: RoomPlanProcessedEvidenceDescriptor?,
        summary: CapturedRoomContentSummary? = nil
    ) throws -> CapturedRoomMetadataPackage {
        let document = try CapturedRoomMetadataDocument(
            captureRevisionID: captureRevisionID,
            raw: raw,
            processed: processed,
            summary: summary
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)

        guard
            let decoded = try? JSONDecoder().decode(
                CapturedRoomMetadataDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw CapturedRoomMetadataError.encodedDocumentMismatch
        }

        return CapturedRoomMetadataPackage(
            document: document,
            data: data
        )
    }
}
