import Foundation
import Testing
@testable import HTDTCaptureCore

private func chronologyObservation(
    resourceEvents: [CaptureResourceEvent]
) -> CaptureQualityObservation {
    CaptureQualityObservation(
        roomPlanStatus: .completed,
        activeMeshAnchorCount: 1,
        evidenceFrameCount: 1,
        resourceEvents: resourceEvents,
        integrityStatus: .pass
    )
}

private let chronologyRequirements = CaptureQualityRequirements(
    rulesetVersion: "test-ruleset"
)

@Test
func sequencedResourceEventsSerializeInCanonicalOrder() {
    let second = CaptureResourceEvent(
        kind: .thermalPressure,
        severity: .warning,
        detail: "second sequence",
        sequence: 2
    )
    let firstTimed = CaptureResourceEvent(
        kind: .storagePressure,
        severity: .warning,
        detail: "first sequence earlier",
        occurredAtUtc: "2026-09-20T00:00:01Z",
        sequence: 1
    )
    let firstTimedLater = CaptureResourceEvent(
        kind: .memoryPressure,
        severity: .warning,
        detail: "first sequence later",
        occurredAtUtc: "2026-09-20T00:00:02Z",
        sequence: 1
    )
    let firstUntimed = CaptureResourceEvent(
        kind: .interruption,
        severity: .warning,
        detail: "first sequence untimed",
        sequence: 1
    )

    // Sequence orders first and ascending; equal sequences fall back to
    // occurred_at_utc (absent sorts before any timestamp).
    let expected = [
        firstUntimed,
        firstTimed,
        firstTimedLater,
        second,
    ]

    let forward = CaptureQualityEvaluator.evaluate(
        chronologyObservation(
            resourceEvents: [
                firstUntimed, firstTimed, firstTimedLater, second,
            ]
        ),
        requirements: chronologyRequirements
    )
    #expect(forward.resourceEvents == expected)

    // Reversing async arrival order must not reverse the canonical
    // chronology when events carry temporal authority.
    let reversed = CaptureQualityEvaluator.evaluate(
        chronologyObservation(
            resourceEvents: [
                second, firstTimedLater, firstTimed, firstUntimed,
            ]
        ),
        requirements: chronologyRequirements
    )
    #expect(reversed.resourceEvents == expected)
}

@Test
func unsequencedResourceEventsKeepInsertionOrderAfterSequenced() {
    let sequenced = CaptureResourceEvent(
        kind: .storagePressure,
        severity: .warning,
        detail: "sequenced",
        sequence: 0
    )
    let untimedA = CaptureResourceEvent(
        kind: .memoryPressure,
        severity: .warning,
        detail: "untimed a"
    )
    let timed = CaptureResourceEvent(
        kind: .persistenceBacklog,
        severity: .warning,
        detail: "timed only",
        occurredAtUtc: "2026-09-20T01:00:00Z"
    )
    let untimedB = CaptureResourceEvent(
        kind: .thermalPressure,
        severity: .warning,
        detail: "untimed b"
    )

    let report = CaptureQualityEvaluator.evaluate(
        chronologyObservation(
            resourceEvents: [untimedA, timed, sequenced, untimedB]
        ),
        requirements: chronologyRequirements
    )
    // Events without sequence sort after sequenced ones; among them,
    // absent occurred_at_utc sorts first and equal keys keep insertion
    // order.
    #expect(
        report.resourceEvents == [sequenced, untimedA, untimedB, timed]
    )
}

@Test
func legacyResourceEventDecodesWithoutChronologyFields() throws {
    let legacyJSON = #"{"kind":"memory_pressure","severity":"warning","detail":"legacy warning"}"#
    let event = try JSONDecoder().decode(
        CaptureResourceEvent.self,
        from: Data(legacyJSON.utf8)
    )
    #expect(event.kind == .memoryPressure)
    #expect(event.severity == .warning)
    #expect(event.detail == "legacy warning")
    #expect(event.occurredAtUtc == nil)
    #expect(event.sequence == nil)

    // Re-encoding omits the additive fields so bytes match the
    // pre-chronology wire format.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let reencoded = try encoder.encode(event)
    let object = try #require(
        JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
    )
    #expect(object["occurred_at_utc"] == nil)
    #expect(object["sequence"] == nil)
}

@Test
func resourceEventChronologyFieldsRoundTrip() throws {
    let event = CaptureResourceEvent(
        kind: .persistenceFailure,
        severity: .error,
        detail: "recoverable failure",
        occurredAtUtc: "2026-09-20T12:34:56.789Z",
        sequence: 42
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(event)

    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(
        object["occurred_at_utc"] as? String == "2026-09-20T12:34:56.789Z"
    )
    #expect((object["sequence"] as? NSNumber)?.uint64Value == 42)

    let decoded = try JSONDecoder().decode(
        CaptureResourceEvent.self,
        from: data
    )
    #expect(decoded == event)
}

@Test
func qualitySchemaResourceEventContractMatchesModel() throws {
    // Model/schema parity regression: the persisted resource-event
    // kind enum must equal the model enum exactly (unknown kinds fail
    // closed) and chronology fields stay additive-optional.
    let testFile = URL(fileURLWithPath: #filePath)
    let repoRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let schemaURL = repoRoot
        .appendingPathComponent("schemas")
        .appendingPathComponent("capture-bundle-v1")
        .appendingPathComponent("quality.schema.json")
    let object = try #require(
        JSONSerialization.jsonObject(
            with: Data(contentsOf: schemaURL)
        ) as? [String: Any]
    )

    let defs = try #require(object["$defs"] as? [String: Any])
    let resourceEvent = try #require(
        defs["resourceEvent"] as? [String: Any]
    )
    let properties = try #require(
        resourceEvent["properties"] as? [String: Any]
    )
    let kind = try #require(properties["kind"] as? [String: Any])
    let enumValues = try #require(kind["enum"] as? [String])

    let modelKinds: Set<String> = [
        CaptureResourceEventKind.thermalPressure.rawValue,
        CaptureResourceEventKind.memoryPressure.rawValue,
        CaptureResourceEventKind.storagePressure.rawValue,
        CaptureResourceEventKind.persistenceBacklog.rawValue,
        CaptureResourceEventKind.persistenceFailure.rawValue,
        CaptureResourceEventKind.interruption.rawValue,
    ]
    #expect(Set(enumValues) == modelKinds)

    let severity = try #require(properties["severity"] as? [String: Any])
    let severityEnum = try #require(severity["enum"] as? [String])
    #expect(Set(severityEnum) == ["info", "warning", "error"])

    // Required list is unchanged; chronology fields are optional.
    let required = try #require(resourceEvent["required"] as? [String])
    #expect(Set(required) == ["kind", "severity", "detail"])
    #expect(properties["occurred_at_utc"] != nil)
    #expect(properties["sequence"] != nil)
}
