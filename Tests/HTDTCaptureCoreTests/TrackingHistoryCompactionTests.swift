import Foundation
import Testing
@testable import HTDTCaptureCore

/// Issue bolph71656-ai/HTDT-Capture#148: live tracking observations compact into a bounded canonical
/// history so a scan-long limited interval survives a recovered End frame.
@Test
func repeatedSameStateSamplesCompactIntoOneInterval() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let store = try CaptureWorkingSetStore(rootDirectory: root)

    // ~5 s of normal tracking sampled every 250 ms.
    for step in 0..<20 {
        await store.recordTrackingEvent(
            TrackingQualityEvent(
                sessionTimestampSeconds: Double(step) * 0.25,
                state: .normal
            )
        )
    }
    // A limited interval that recovers before End.
    for step in 20..<28 {
        await store.recordTrackingEvent(
            TrackingQualityEvent(
                sessionTimestampSeconds: Double(step) * 0.25,
                state: .limited,
                reason: "insufficient_features"
            )
        )
    }
    // Recovered normal tracking through the End frame.
    for step in 28..<40 {
        await store.recordTrackingEvent(
            TrackingQualityEvent(
                sessionTimestampSeconds: Double(step) * 0.25,
                state: .normal
            )
        )
    }

    let report = await store.evaluateQuality(
        requirements: CaptureQualityRequirements(
            rulesetVersion: "0.0.0-test",
            requireCompletedRoomPlan: false,
            minimumActiveMeshAnchors: 0,
            minimumEvidenceFrames: 0
        )
    )

    // Three compacted intervals -> first/last event each: bounded output
    // that still exposes the limited interval and the recovered End state.
    #expect(report.trackingEvents.count == 6)
    #expect(report.trackingEvents.first?.state == .normal)
    #expect(report.trackingEvents.last?.state == .normal)
    #expect(
        report.trackingEvents.contains {
            $0.state == .limited
                && $0.reason == "insufficient_features"
        }
    )
    #expect(
        report.diagnostics.contains {
            $0.code == "tracking_limited_observed"
                && $0.severity == .warning
        }
    )
    #expect(report.readyForHTDTIngestion)
}

@Test
func duplicateAndOutOfOrderSamplesStayCompacted() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let store = try CaptureWorkingSetStore(rootDirectory: root)

    await store.recordTrackingEvent(
        TrackingQualityEvent(
            sessionTimestampSeconds: 2,
            state: .limited,
            reason: "excessive_motion"
        )
    )
    // Same sample replayed and an older normal sample arriving late.
    await store.recordTrackingEvent(
        TrackingQualityEvent(
            sessionTimestampSeconds: 2,
            state: .limited,
            reason: "excessive_motion"
        )
    )
    await store.recordTrackingEvent(
        TrackingQualityEvent(
            sessionTimestampSeconds: 1,
            state: .normal
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

    // Sorted canonical history: normal@1 then limited@2; the duplicate
    // sample did not add a second identical event.
    #expect(
        report.trackingEvents.map(\.sessionTimestampSeconds) == [1, 2]
    )
    #expect(
        report.trackingEvents.filter { $0.state == .limited }.count == 1
    )
}

@Test
func trackingHistoryIsDeterministicallyBounded() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let store = try CaptureWorkingSetStore(rootDirectory: root)

    // Alternating states defeat run compaction; the interval bound must
    // still cap retained history.
    for step in 0..<400 {
        await store.recordTrackingEvent(
            TrackingQualityEvent(
                sessionTimestampSeconds: Double(step),
                state: step.isMultiple(of: 2) ? .normal : .limited,
                reason: step.isMultiple(of: 2) ? nil : "insufficient_features"
            )
        )
    }

    let report = await store.evaluateQuality(
        requirements: CaptureQualityRequirements(
            rulesetVersion: "0.0.0-test",
            requireCompletedRoomPlan: false,
            minimumActiveMeshAnchors: 0,
            minimumEvidenceFrames: 0
        )
    )

    #expect(
        report.trackingEvents.count
            <= CaptureWorkingSetStore.maxTrackingIntervals * 2
    )
    // The degraded state observed during the scan remains represented.
    #expect(
        report.trackingEvents.contains { $0.state == .limited }
    )
}

@Test
func unavailableIntervalSurvivesEviction() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let store = try CaptureWorkingSetStore(rootDirectory: root)

    await store.recordTrackingEvent(
        TrackingQualityEvent(
            sessionTimestampSeconds: 0,
            state: .unavailable
        )
    )
    for step in 1...400 {
        await store.recordTrackingEvent(
            TrackingQualityEvent(
                sessionTimestampSeconds: Double(step),
                state: step.isMultiple(of: 2) ? .normal : .limited
            )
        )
    }

    let report = await store.evaluateQuality(
        requirements: CaptureQualityRequirements(
            rulesetVersion: "0.0.0-test",
            requireCompletedRoomPlan: false,
            minimumActiveMeshAnchors: 0,
            minimumEvidenceFrames: 0
        )
    )

    // Eviction never drops the last carrier of a state: the unavailable
    // observation still produces the blocking diagnostic.
    #expect(
        report.trackingEvents.contains { $0.state == .unavailable }
    )
    #expect(
        report.diagnostics.contains {
            $0.code == "tracking_unavailable_observed"
                && $0.severity == .error
        }
    )
    #expect(!report.readyForHTDTIngestion)
}
