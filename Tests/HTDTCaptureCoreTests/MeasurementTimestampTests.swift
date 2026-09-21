import Foundation
import Testing
@testable import HTDTCaptureCore

// #174: measurement and session timestamp authority must satisfy the
// schema's `date` / `date-time` formats at construction, with a single
// canonical UTC-Z policy.

@Test
func validObservedAtUTCRoundTrips() throws {
    let measurement = try CaptureMeasurement(
        quantityType: "room_width",
        value: .scalar(3.4),
        unit: .meter,
        acquisitionMethod: .laserDistanceMeter,
        observedAtUTC: "2026-09-20T01:02:03Z",
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement
    )
    #expect(measurement.observedAtUTC == "2026-09-20T01:02:03Z")

    let fractional = try CaptureMeasurement(
        quantityType: "room_width",
        value: .scalar(3.4),
        unit: .meter,
        acquisitionMethod: .laserDistanceMeter,
        observedAtUTC: "2026-09-20T01:02:03.456Z",
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement
    )
    #expect(fractional.observedAtUTC == "2026-09-20T01:02:03.456Z")
}

@Test
func malformedObservedAtIsRejected() {
    func build(_ timestamp: String) throws -> CaptureMeasurement {
        try CaptureMeasurement(
            quantityType: "room_width",
            value: .scalar(3.4),
            unit: .meter,
            acquisitionMethod: .laserDistanceMeter,
            observedAtUTC: timestamp,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement
        )
    }
    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        _ = try build("not-a-time")
    }
    // Naive timestamp without the Z designator.
    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        _ = try build("2026-09-20T01:02:03")
    }
    // Non-UTC offset form is not the canonical profile.
    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        _ = try build("2026-09-20T01:02:03+02:00")
    }
    // Impossible calendar date.
    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        _ = try build("2026-02-30T01:02:03Z")
    }
    // Out-of-range time fields.
    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        _ = try build("2026-09-20T25:02:03Z")
    }
    // Missing day.
    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        _ = try build("2026-09-T01:02:03Z")
    }
}

@Test
func leapDayAndLeapYearAreHandled() throws {
    let leap = try CaptureMeasurement(
        quantityType: "d",
        value: .scalar(1),
        unit: .meter,
        acquisitionMethod: .tapeMeasure,
        observedAtUTC: "2024-02-29T12:00:00Z",
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement
    )
    #expect(leap.observedAtUTC == "2024-02-29T12:00:00Z")

    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        _ = try CaptureMeasurement(
            quantityType: "d",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .tapeMeasure,
            observedAtUTC: "2026-02-29T12:00:00Z",
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement
        )
    }
}

@Test
func calibrationDateMustBeAValidCalendarDate() throws {
    let valid = try CaptureMeasurement(
        quantityType: "d",
        value: .scalar(1),
        unit: .meter,
        acquisitionMethod: .tapeMeasure,
        instrument: MeasurementInstrument(
            calibrationStatus: "current",
            calibrationDate: "2026-09-01"
        ),
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement
    )
    #expect(valid.instrument?.calibrationDate == "2026-09-01")

    #expect(throws: MeasurementModelError.invalidCalibrationDate) {
        _ = try CaptureMeasurement(
            quantityType: "d",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .tapeMeasure,
            instrument: MeasurementInstrument(
                calibrationDate: "yesterday"
            ),
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement
        )
    }
    #expect(throws: MeasurementModelError.invalidCalibrationDate) {
        _ = try CaptureMeasurement(
            quantityType: "d",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .tapeMeasure,
            instrument: MeasurementInstrument(
                calibrationDate: "2026-13-01"
            ),
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement
        )
    }
    // A date-time is not a date.
    #expect(throws: MeasurementModelError.invalidCalibrationDate) {
        _ = try CaptureMeasurement(
            quantityType: "d",
            value: .scalar(1),
            unit: .meter,
            acquisitionMethod: .tapeMeasure,
            instrument: MeasurementInstrument(
                calibrationDate: "2026-09-01T00:00:00Z"
            ),
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement
        )
    }
}

@Test
func timingCorrelationRejectsNonCanonicalUTC() {
    #expect(throws: CaptureSessionMetadataError.invalidUTCTimestamp) {
        _ = try CaptureTimingCorrelation(
            monotonicSeconds: 1.0,
            utc: "2026-09-20T01:00:00+02:00",
            method: "fixture"
        )
    }
    #expect(throws: CaptureSessionMetadataError.invalidUTCTimestamp) {
        _ = try CaptureTimingCorrelation(
            monotonicSeconds: 1.0,
            utc: "2026-09-20 01:00:00Z",
            method: "fixture"
        )
    }
}

@Test
func sessionDocumentRequiresCanonicalStartedAt() throws {
    let session = try CaptureSessionDocument(
        captureSessionID: CaptureSessionID(),
        coordinateSpaceID: CoordinateSpaceID(),
        captureMode: .evidenceDepth,
        startedAtUTC: "2026-09-20T01:00:00Z",
        configurationRef: "session/capture-configuration.json",
        timingRef: "session/timing.json"
    )
    #expect(session.startedAtUTC == "2026-09-20T01:00:00Z")

    #expect(throws: CaptureSessionMetadataError.invalidUTCTimestamp) {
        _ = try CaptureSessionDocument(
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            captureMode: .evidenceDepth,
            startedAtUTC: "20 Sep 2026",
            configurationRef: "session/capture-configuration.json",
            timingRef: "session/timing.json"
        )
    }
}
