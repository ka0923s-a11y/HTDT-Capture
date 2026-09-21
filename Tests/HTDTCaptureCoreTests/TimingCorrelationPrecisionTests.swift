import Foundation
import Testing
@testable import HTDTCaptureCore

// MARK: - Fractional-second UTC timing correlation (#156)
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
        ISO8601DateFormatter().date(from: crossing)
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
