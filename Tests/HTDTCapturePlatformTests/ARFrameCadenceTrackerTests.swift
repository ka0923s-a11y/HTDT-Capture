import Foundation
import Testing
@testable import HTDTCapturePlatform

/// First frame after reset only establishes the baseline timestamp —
/// an interval requires a previous observation.
@Test
func firstFrameAfterResetProducesNoInterval() {
    var tracker = ARFrameCadenceTracker()
    tracker.record(timestampSeconds: 10.0)
    let summary = tracker.summary()
    #expect(summary.frameCount == 1)
    #expect(summary.windowCount == 0)
    #expect(summary.maximumIntervalSeconds == 0)
}

/// Nominal 60 Hz cadence yields a near-16.7 ms mean and zero
/// stretched frames.
@Test
func nominalCadenceReportsCleanSummary() {
    var tracker = ARFrameCadenceTracker()
    var timestamp = 0.0
    for _ in 0..<120 {
        tracker.record(timestampSeconds: timestamp)
        timestamp += 1.0 / 60.0
    }
    let summary = tracker.summary()
    #expect(summary.frameCount == 120)
    #expect(summary.windowCount == 119)
    #expect(summary.windowStretchedCount == 0)
    #expect(summary.totalStretchedCount == 0)
    let delta = abs(summary.windowMeanIntervalSeconds - 1.0 / 60.0)
    #expect(delta < 0.0005)
}

/// An interval beyond `nominal * stretchFactor` (1.5 × 16.7 ms =
/// 25 ms) counts as stretched, cumulatively and in the window.
@Test
func stretchedIntervalsAreCounted() {
    var tracker = ARFrameCadenceTracker()
    let timestamps: [Double] = [
        0.0,
        1.0 / 60.0,   // nominal
        0.045,        // ~28.3 ms — stretched
        0.045 + 1.0 / 60.0,
        0.100         // ~38.3 ms — stretched
    ]
    for t in timestamps { tracker.record(timestampSeconds: t) }
    let summary = tracker.summary()
    #expect(summary.frameCount == 5)
    #expect(summary.windowCount == 4)
    #expect(summary.windowStretchedCount == 2)
    #expect(summary.totalStretchedCount == 2)
    #expect(summary.windowStretchedFraction == 0.5)
    #expect(abs(summary.maximumIntervalSeconds - 0.0383333) < 0.001)
}

/// The recent window stays bounded at `windowLimit` while cumulative
/// counters keep their full history.
@Test
func windowStaysBoundedWhileTotalsAccumulate() {
    var tracker = ARFrameCadenceTracker()
    tracker.windowLimit = 10
    var timestamp = 0.0
    for _ in 0..<20 {
        tracker.record(timestampSeconds: timestamp)
        timestamp += 1.0 / 60.0
    }
    // One stretched frame far in the past — outside the retained
    // window but inside the cumulative counter.
    timestamp += 0.1
    tracker.record(timestampSeconds: timestamp)
    for _ in 0..<30 {
        timestamp += 1.0 / 60.0
        tracker.record(timestampSeconds: timestamp)
    }
    let summary = tracker.summary()
    #expect(summary.frameCount == 51)
    #expect(summary.windowCount == 10)
    #expect(summary.windowStretchedCount == 0)
    #expect(summary.totalStretchedCount == 1)
}

/// A non-positive delta (clock regression or duplicate timestamp)
/// produces no interval and no stretched counting.
@Test
func nonPositiveIntervalsAreIgnored() {
    var tracker = ARFrameCadenceTracker()
    tracker.record(timestampSeconds: 1.0)
    tracker.record(timestampSeconds: 1.0)
    tracker.record(timestampSeconds: 0.5)
    let summary = tracker.summary()
    #expect(summary.frameCount == 3)
    #expect(summary.windowCount == 0)
    #expect(summary.maximumIntervalSeconds == 0)
}

/// Reset clears every cumulative and windowed observation.
@Test
func resetClearsAllObservations() {
    var tracker = ARFrameCadenceTracker()
    for i in 0..<30 {
        tracker.record(timestampSeconds: Double(i) * 0.05)
    }
    tracker.reset()
    let summary = tracker.summary()
    #expect(summary.frameCount == 0)
    #expect(summary.windowCount == 0)
    #expect(summary.totalStretchedCount == 0)
    #expect(summary.maximumIntervalSeconds == 0)
}
