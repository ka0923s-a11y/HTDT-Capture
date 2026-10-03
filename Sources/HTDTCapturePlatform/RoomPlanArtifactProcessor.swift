import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(RoomPlan)
import RoomPlan

/// RoomPlan completion post-processing for the End transaction (legacy bolph71656-ai/HTDT-Capture#208).
///
/// `CapturedRoomData` and `CapturedRoom` are Sendable value types, so
/// the JSON materialization, SHA-256 hashing and descriptor/lineage
/// construction below are pure CPU work on owned bytes. These methods
/// are deliberately `nonisolated` + `async`: the host's MainActor End
/// task suspends while the encode/hash sections run on the cooperative
/// executor instead of blocking the UI/capture actor at the exact point
/// where lifecycle and resource callbacks still matter.
///
/// No RoomPlan view/session object crosses the boundary — only the
/// Sendable result data — and the completion path is serialized by the
/// host's `roomPlanCompletionInFlight` guard, so off-actor work cannot
/// queue unboundedly (legacy bolph71656-ai/HTDT-Capture#147 backpressure contract). Canonical bytes and
/// lineage are identical to the previous synchronous MainActor output.
@available(iOS 17.0, *)
public enum RoomPlanArtifactProcessor {
    /// Encodes the raw `CapturedRoomData` payload and builds its
    /// evidence descriptor (byte count + SHA-256) off the calling actor.
    public static func encodeRaw(
        _ data: CapturedRoomData,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        runtime: CaptureRuntimeProvenance
    ) async throws -> RoomPlanRawArtifactPayload {
        let encoded = try RoomPlanArtifactEncoder.encodeRaw(data)
        return RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: encoded,
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            runtime: runtime
        )
    }

    /// Runs `RoomBuilder` post-processing, encodes the processed
    /// `CapturedRoom`, and builds the processed descriptor + lineage
    /// off the calling actor. The `RoomBuilder` instance is created and
    /// consumed inside this nonisolated task and is never sent across
    /// actors.
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
