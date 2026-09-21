import Foundation
import Testing
@testable import HTDTCaptureCore

@Test
func trackingGateRecordsBaselineThenCompactsIdenticalSamples() {
    var gate = ScanTrackingTransitionGate()

    let first = TrackingQualityEvent(
        sessionTimestampSeconds: 1.0,
        state: .normal
    )
    #expect(gate.shouldRecord(first))

    // Same state and reason, advancing timestamps: compacted away.
    #expect(
        !gate.shouldRecord(
            TrackingQualityEvent(
                sessionTimestampSeconds: 1.25,
                state: .normal
            )
        )
    )
    #expect(
        !gate.shouldRecord(
            TrackingQualityEvent(
                sessionTimestampSeconds: 1.5,
                state: .normal
            )
        )
    )
}

@Test
func trackingGateEmitsStateAndReasonTransitions() {
    var gate = ScanTrackingTransitionGate()

    #expect(
        gate.shouldRecord(
            TrackingQualityEvent(
                sessionTimestampSeconds: 0.0,
                state: .normal
            )
        )
    )

    // normal -> limited (with reason) is a transition.
    #expect(
        gate.shouldRecord(
            TrackingQualityEvent(
                sessionTimestampSeconds: 0.5,
                state: .limited,
                reason: "insufficient_features"
            )
        )
    )

    // Same state, changed reason is also a transition.
    #expect(
        gate.shouldRecord(
            TrackingQualityEvent(
                sessionTimestampSeconds: 0.75,
                state: .limited,
                reason: "excessive_motion"
            )
        )
    )

    // limited -> unavailable is a transition.
    #expect(
        gate.shouldRecord(
            TrackingQualityEvent(
                sessionTimestampSeconds: 1.0,
                state: .unavailable
            )
        )
    )

    // unavailable -> normal recovery is a transition.
    #expect(
        gate.shouldRecord(
            TrackingQualityEvent(
                sessionTimestampSeconds: 1.5,
                state: .normal
            )
        )
    )
}

@Test
func trackingGateResetRestoresBaselineRecording() {
    var gate = ScanTrackingTransitionGate()

    let event = TrackingQualityEvent(
        sessionTimestampSeconds: 3.0,
        state: .limited,
        reason: "relocalizing"
    )
    #expect(gate.shouldRecord(event))
    #expect(!gate.shouldRecord(event))

    gate.reset()
    #expect(gate.shouldRecord(event))
}
