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
    let baseline = gate.shouldRecord(first)
    #expect(baseline)

    // Same state and reason, advancing timestamps: compacted away.
    let repeatA = gate.shouldRecord(
        TrackingQualityEvent(
            sessionTimestampSeconds: 1.25,
            state: .normal
        )
    )
    #expect(!repeatA)
    let repeatB = gate.shouldRecord(
        TrackingQualityEvent(
            sessionTimestampSeconds: 1.5,
            state: .normal
        )
    )
    #expect(!repeatB)
}

@Test
func trackingGateEmitsStateAndReasonTransitions() {
    var gate = ScanTrackingTransitionGate()

    let baseline = gate.shouldRecord(
        TrackingQualityEvent(
            sessionTimestampSeconds: 0.0,
            state: .normal
        )
    )
    #expect(baseline)

    // normal -> limited (with reason) is a transition.
    let toLimited = gate.shouldRecord(
        TrackingQualityEvent(
            sessionTimestampSeconds: 0.5,
            state: .limited,
            reason: "insufficient_features"
        )
    )
    #expect(toLimited)

    // Same state, changed reason is also a transition.
    let reasonChange = gate.shouldRecord(
        TrackingQualityEvent(
            sessionTimestampSeconds: 0.75,
            state: .limited,
            reason: "excessive_motion"
        )
    )
    #expect(reasonChange)

    // limited -> unavailable is a transition.
    let toUnavailable = gate.shouldRecord(
        TrackingQualityEvent(
            sessionTimestampSeconds: 1.0,
            state: .unavailable
        )
    )
    #expect(toUnavailable)

    // unavailable -> normal recovery is a transition.
    let recovered = gate.shouldRecord(
        TrackingQualityEvent(
            sessionTimestampSeconds: 1.5,
            state: .normal
        )
    )
    #expect(recovered)
}

@Test
func trackingGateResetRestoresBaselineRecording() {
    var gate = ScanTrackingTransitionGate()

    let event = TrackingQualityEvent(
        sessionTimestampSeconds: 3.0,
        state: .limited,
        reason: "relocalizing"
    )
    let first = gate.shouldRecord(event)
    #expect(first)
    let repeatSame = gate.shouldRecord(event)
    #expect(!repeatSame)

    gate.reset()
    let afterReset = gate.shouldRecord(event)
    #expect(afterReset)
}
