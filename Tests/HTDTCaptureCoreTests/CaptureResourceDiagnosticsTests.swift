import Foundation
import Testing
@testable import HTDTCaptureCore

@Test
func workingSetQualityIncludesTrackingAndResourceEvents() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let store = try CaptureWorkingSetStore(
        rootDirectory: root
    )
    await store.recordTrackingEvent(
        TrackingQualityEvent(
            sessionTimestampSeconds: 2,
            state: .limited,
            reason: "insufficient_features"
        )
    )
    await store.recordTrackingEvent(
        TrackingQualityEvent(
            sessionTimestampSeconds: 1,
            state: .normal
        )
    )
    await store.recordResourceEvent(
        CaptureResourceEvent(
            kind: .memoryPressure,
            severity: .warning,
            detail: "fixture warning"
        )
    )

    let report = await store.evaluateQuality(
        requirements: CaptureQualityRequirements(
            rulesetVersion: "0.0.0-test",
            requireCompletedRoomPlan: false,
            minimumActiveMeshAnchors: 0,
            minimumEvidenceFrames: 0
        )
    )

    #expect(
        report.trackingEvents.map(\.sessionTimestampSeconds)
            == [1, 2]
    )
    #expect(report.resourceEvents.count == 1)
    #expect(
        report.diagnostics.contains {
            $0.code == "tracking_limited_observed"
                && $0.severity == .warning
        }
    )
    #expect(report.readyForHTDTIngestion)
}

@Test
func resourceErrorBlocksQualityReadiness() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let store = try CaptureWorkingSetStore(
        rootDirectory: root
    )
    await store.recordResourceEvent(
        CaptureResourceEvent(
            kind: .storagePressure,
            severity: .error,
            detail: "fixture critical storage"
        )
    )

    let report = await store.evaluateQuality(
        requirements: CaptureQualityRequirements(
            rulesetVersion: "0.0.0-test",
            requireCompletedRoomPlan: false,
            minimumActiveMeshAnchors: 0,
            minimumEvidenceFrames: 0
        )
    )

    #expect(!report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains {
            $0.code == "resource_error"
                && $0.severity == .error
        }
    )
}
