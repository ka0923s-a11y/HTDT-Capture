import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(RoomPlan)
import RoomPlan

@available(iOS 17.0, *)
@MainActor
public enum RoomPlanArtifactProcessor {
    public static func encodeRaw(
        _ data: CapturedRoomData,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        runtime: CaptureRuntimeProvenance
    ) throws -> RoomPlanRawArtifactPayload {
        let encoded = try RoomPlanArtifactEncoder.encodeRaw(data)
        return RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: encoded,
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            runtime: runtime
        )
    }

    public static func deriveProcessedWithoutRaw(
        from data: CapturedRoomData,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        runtime: CaptureRuntimeProvenance,
        capturedRoomVersion: String? = nil
    ) async throws -> RoomPlanProcessedArtifactPayload {
        let roomBuilder = RoomBuilder(options: [])
        let capturedRoom = try await roomBuilder.capturedRoom(from: data)
        let encoded = try RoomPlanArtifactEncoder.encodeProcessed(
            capturedRoom
        )
        return RoomPlanEvidenceArtifactBuilder
            .buildProcessedWithoutRaw(
                data: encoded,
                captureSessionID: captureSessionID,
                coordinateSpaceID: coordinateSpaceID,
                runtime: runtime,
                capturedRoomVersion: capturedRoomVersion
            )
    }

    public static func deriveProcessed(
        from data: CapturedRoomData,
        rawArtifact: RoomPlanRawArtifactPayload,
        capturedRoomVersion: String? = nil
    ) async throws -> RoomPlanArtifactLineage {
        let roomBuilder = RoomBuilder(options: [])
        let capturedRoom = try await roomBuilder.capturedRoom(from: data)
        let encoded = try RoomPlanArtifactEncoder.encodeProcessed(
            capturedRoom
        )
        return RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: encoded,
            to: rawArtifact,
            capturedRoomVersion: capturedRoomVersion
        )
    }
}
#endif
