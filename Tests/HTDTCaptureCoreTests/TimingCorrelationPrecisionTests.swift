import Foundation
import Testing
@testable import HTDTCaptureCore

// MARK: - Fractional-second UTC timing correlation (legacy bolph71656-ai/HTDT-Capture#156)
//
// The platform layer emits non-manifest UTC timestamps with fractional
// (millisecond) precision so the declared `estimated_uncertainty_s` is
// supported by the serialized text. These tests pin the acceptance
// contract on the core timing model: fractional UTC strings are
// accepted, round-trip unchanged, and work near a second boundary.
// Manifest canonicalization (`BundleTimestamp.utcString`) intentionally
// stays whole-second and is not exercised here.

private func fractionalUTCFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
        .withInternetDateTime,
        .withDashSeparatorInDate,
        .withColonSeparatorInTime,
        .withFractionalSeconds,
    ]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}

@Test
func timingCorrelationAcceptsFractionalUTC() throws {
    let correlation = try CaptureTimingCorrelation(
        monotonicSeconds: 12.5,
        utc: "2026-09-20T01:00:12.900Z",
        method: "bracketed_arframe_current_frame",
        estimatedUncertaintySeconds: 0.002
    )

    #expect(correlation.utc == "2026-09-20T01:00:12.900Z")
    #expect(correlation.estimatedUncertaintySeconds == 0.002)
}

@Test
func timingCorrelationRoundTripsFractionalUTC() throws {
    let correlation = try CaptureTimingCorrelation(
        monotonicSeconds: 7.25,
        utc: "2026-09-20T01:00:07.042Z",
        method: "bracketed_arframe_current_frame",
        estimatedUncertaintySeconds: 0.0015
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(correlation)
    let decoded = try JSONDecoder().decode(
        CaptureTimingCorrelation.self,
        from: data
    )

    #expect(decoded == correlation)
    #expect(decoded.utc == "2026-09-20T01:00:07.042Z")
}

@Test
func fractionalUTCRenderingNearSecondBoundaryIsAccepted() throws {
    // A midpoint just below a whole second must serialize with the
    // fractional component rather than collapsing to the lower second,
    // and must remain a valid correlation timestamp after rounding up
    // across the boundary.
    let formatter = fractionalUTCFormatter()

    let belowBoundary = formatter.string(
        from: Date(timeIntervalSince1970: 1_800_000_000.499)
    )
    #expect(belowBoundary.hasSuffix(".499Z"))

    // A midpoint just below a second boundary must keep its fractional
    // component (either `.999` when truncated or `+1s.000` when rounded)
    // rather than silently collapsing to the lower whole second.
    let crossingInput = Date(
        timeIntervalSince1970: 1_800_000_000.999_6
    )
    let crossing = formatter.string(from: crossingInput)
    #expect(crossing.hasSuffix("Z"))
    #expect(crossing.contains("."))
    #expect(crossing != "2027-01-15T08:00:00Z")
    let reparsed = try #require(
        formatter.date(from: crossing)
    )
    #expect(
        abs(reparsed.timeIntervalSince(crossingInput)) <= 0.001
    )

    let correlation = try CaptureTimingCorrelation(
        monotonicSeconds: 30.0,
        utc: crossing,
        method: "bracketed_arframe_current_frame",
        estimatedUncertaintySeconds: 0.000_5
    )
    #expect(correlation.utc == crossing)
}

@Test
func timingPackageBuildsWithFractionalCorrelations() throws {
    let start = try CaptureTimingCorrelation(
        monotonicSeconds: 10.0,
        utc: "2026-09-20T01:00:10.120Z",
        method: "bracketed_arframe_current_frame",
        estimatedUncertaintySeconds: 0.001
    )
    let end = try CaptureTimingCorrelation(
        monotonicSeconds: 20.0,
        utc: "2026-09-20T01:00:59.980Z",
        method: "bracketed_arframe_current_frame",
        estimatedUncertaintySeconds: 0.002
    )

    let package = try CaptureTimingPackageBuilder.build(
        start: start,
        end: end
    )

    let decoded = try JSONDecoder().decode(
        CaptureTimingDocument.self,
        from: package.data
    )
    #expect(decoded.correlations == [start, end])
    #expect(decoded.correlations[0].utc == "2026-09-20T01:00:10.120Z")
    #expect(decoded.correlations[1].utc == "2026-09-20T01:00:59.980Z")
}

@Test
func wholeSecondUTCRendersUnchangedForManifestPath() {
    // Manifest timestamps intentionally remain whole-second; pin that
    // the platform's fractional path is a separate formatter choice.
    let whole = BundleTimestamp.utcString(
        from: Date(timeIntervalSince1970: 1_800_000_000.750)
    )
    #expect(whole == "2027-01-15T08:00:00Z")
}

// MARK: - Frame-age-corrected correlation (legacy bolph71656-ai/HTDT-Capture#206)
//
// `ARSession.currentFrame` vends the latest already-produced frame;
// its monotonic timestamp is capture time, not read time, and can lag
// the wall-clock read by at least a frame interval. The estimator
// must project the capture instant by the measured monotonic delta
// and fold the observed frame age into the declared uncertainty, so a
// stale frame can never report a near-zero error budget.

@Test
func staleFrameProjectsCaptureInstantAndInflatesUncertainty() {
    // A frame 10.002 s old at read time: the paired UTC must be
    // projected back by the measured monotonic delta, and the declared
    // uncertainty must cover the full observed frame age rather than
    // only the millisecond-scale read bracket.
    let estimate = FrameTimingCorrelationEstimator.estimate(
        frameTimestampSeconds: 100.0,
        monotonicReadBeforeSeconds: 110.000,
        monotonicReadAfterSeconds: 110.004,
        wallClockReadBefore: Date(
            timeIntervalSince1970: 1_800_000_000.000
        ),
        wallClockReadAfter: Date(
            timeIntervalSince1970: 1_800_000_000.006
        ),
        utcSerializationQuantizationSeconds: 0.000_5
    )

    #expect(
        abs(estimate.observedFrameDeltaSeconds - 10.002) < 0.000_01
    )
    #expect(
        abs(
            estimate.captureInstantUTC.timeIntervalSince1970
                - (1_800_000_000.003 - 10.002)
        ) < 0.000_01
    )
    // wallHalf 0.003 + monoHalf 0.002 + age 10.002 + quant 0.0005.
    #expect(
        abs(
            estimate.uncertaintySeconds
                - (0.003 + 0.002 + 10.002 + 0.000_5)
        ) < 0.000_01
    )
    #expect(estimate.uncertaintySeconds >= 10.0)
}

@Test
func freshFrameCorrelationRemainsPrecise() {
    // A sub-frame-interval-old frame projects only ~1 ms and keeps a
    // small honest uncertainty (brackets + age + quantization).
    let estimate = FrameTimingCorrelationEstimator.estimate(
        frameTimestampSeconds: 110.001,
        monotonicReadBeforeSeconds: 110.000,
        monotonicReadAfterSeconds: 110.004,
        wallClockReadBefore: Date(
            timeIntervalSince1970: 1_800_000_000.000
        ),
        wallClockReadAfter: Date(
            timeIntervalSince1970: 1_800_000_000.006
        ),
        utcSerializationQuantizationSeconds: 0.000_5
    )

    #expect(
        abs(estimate.observedFrameDeltaSeconds - 0.001) < 0.000_01
    )
    #expect(estimate.uncertaintySeconds < 0.01)
    #expect(estimate.uncertaintySeconds >= 0.000_5)
}

@Test
func futureDatedFrameTimestampIsNeverProjectedForward() {
    // A timestamp later than the read bracket is a clock-domain
    // anomaly: the UTC estimate must not move forward, but the skew
    // magnitude still widens the declared uncertainty.
    let estimate = FrameTimingCorrelationEstimator.estimate(
        frameTimestampSeconds: 110.010,
        monotonicReadBeforeSeconds: 110.000,
        monotonicReadAfterSeconds: 110.004,
        wallClockReadBefore: Date(
            timeIntervalSince1970: 1_800_000_000.000
        ),
        wallClockReadAfter: Date(
            timeIntervalSince1970: 1_800_000_000.006
        ),
        utcSerializationQuantizationSeconds: 0.000_5
    )

    #expect(estimate.observedFrameDeltaSeconds < 0)
    #expect(
        abs(
            estimate.captureInstantUTC.timeIntervalSince1970
                - 1_800_000_000.003
        ) < 0.000_01
    )
    #expect(estimate.uncertaintySeconds >= 0.008)
}

@Test
func timingPackageBuildsWithDelayedCurrentFrameFixture() throws {
    // Start/end timing fixture with an intentionally delayed end
    // frame: the end correlation keeps its (older) monotonic
    // timestamp, projects the UTC back to capture time, and declares
    // an uncertainty covering the observed 250 ms staleness.
    let formatter = fractionalUTCFormatter()

    let startEstimate = FrameTimingCorrelationEstimator.estimate(
        frameTimestampSeconds: 10.0,
        monotonicReadBeforeSeconds: 10.000,
        monotonicReadAfterSeconds: 10.001,
        wallClockReadBefore: Date(
            timeIntervalSince1970: 1_800_000_000.000
        ),
        wallClockReadAfter: Date(
            timeIntervalSince1970: 1_800_000_000.002
        ),
        utcSerializationQuantizationSeconds: 0.000_5
    )
    let start = try CaptureTimingCorrelation(
        monotonicSeconds: 10.0,
        utc: formatter.string(
            from: startEstimate.captureInstantUTC
        ),
        method: "bracketed_arframe_current_frame_age_projected",
        estimatedUncertaintySeconds:
            startEstimate.uncertaintySeconds
    )

    let endEstimate = FrameTimingCorrelationEstimator.estimate(
        frameTimestampSeconds: 60.0,
        monotonicReadBeforeSeconds: 60.250,
        monotonicReadAfterSeconds: 60.254,
        wallClockReadBefore: Date(
            timeIntervalSince1970: 1_800_000_050.000
        ),
        wallClockReadAfter: Date(
            timeIntervalSince1970: 1_800_000_050.002
        ),
        utcSerializationQuantizationSeconds: 0.000_5
    )
    let end = try CaptureTimingCorrelation(
        monotonicSeconds: 60.0,
        utc: formatter.string(
            from: endEstimate.captureInstantUTC
        ),
        method: "bracketed_arframe_current_frame_age_projected",
        estimatedUncertaintySeconds:
            endEstimate.uncertaintySeconds
    )

    let endUncertainty = try #require(
        end.estimatedUncertaintySeconds
    )
    // A 250 ms-stale frame cannot claim a near-zero uncertainty.
    #expect(endUncertainty >= 0.25)
    #expect(end.utc.hasSuffix("Z"))
    #expect(end.utc.contains("."))

    let package = try CaptureTimingPackageBuilder.build(
        start: start,
        end: end
    )
    #expect(package.document.correlations == [start, end])
}

// MARK: - Start-boundary correlation identity (legacy bolph71656-ai/HTDT-Capture#200)
//
// The v1 timing document orders correlations [start, end] and carries
// no explicit role field, so the boundary semantics ride on `method`.
// The start sample is taken from the first AR frame the shared session
// delivers after the start request — before unrelated configuration or
// persistence work — and the label marks that any framework-internal
// observation between the run request and that first frame precedes
// the stored correlation interval. Production samples also carry the
// `_age_projected` suffix from the frame-age estimator (legacy bolph71656-ai/HTDT-Capture#206).

@Test
func startBoundaryCorrelationCarriesDistinctMethod() throws {
    let start = try CaptureTimingCorrelation(
        monotonicSeconds: 1.25,
        utc: "2026-09-20T01:00:01.250Z",
        method: CaptureTimingBoundary.sessionStart
            .ageProjectedTimingMethod,
        estimatedUncertaintySeconds: 0.001
    )
    let end = try CaptureTimingCorrelation(
        monotonicSeconds: 42.5,
        utc: "2026-09-20T01:00:42.500Z",
        method: CaptureTimingBoundary.sessionEnd
            .ageProjectedTimingMethod,
        estimatedUncertaintySeconds: 0.001
    )

    let package = try CaptureTimingPackageBuilder.build(
        start: start,
        end: end
    )
    let decoded = try JSONDecoder().decode(
        CaptureTimingDocument.self,
        from: package.data
    )

    // The start boundary is identifiable without relying on position:
    // it declares the first-AR-frame-after-start sampling, while the
    // end boundary keeps the current-frame method label.
    #expect(
        decoded.correlations[0].method
            == "bracketed_first_arframe_at_session_start_age_projected"
    )
    #expect(
        decoded.correlations[1].method
            == "bracketed_arframe_current_frame_age_projected"
    )
    #expect(
        decoded.correlations[0].method
            != decoded.correlations[1].method
    )
}
