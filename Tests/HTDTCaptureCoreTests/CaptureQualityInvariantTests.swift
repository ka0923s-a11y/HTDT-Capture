import Foundation
import Testing
@testable import HTDTCaptureCore

private let invariantRequirements = CaptureQualityRequirements(
    rulesetVersion: "test-ruleset",
    requireCompletedRoomPlan: false,
    minimumActiveMeshAnchors: 0,
    minimumEvidenceFrames: 0,
    requireIntegrityPass: false
)

@Test
func evaluatorDiagnosticsHaveTotalDeterministicOrder() {
    let requirements = CaptureQualityRequirements(
        rulesetVersion: "test-ruleset",
        requireCompletedRoomPlan: false,
        minimumEvidenceFrames: 0,
        requiredAnnotationKeys: ["z-key", "a-key"],
        requiredMeasurementQuantityTypes: ["m-2", "m-1"],
        requireIntegrityPass: false
    )
    let firstEvent = CaptureResourceEvent(
        kind: .memoryPressure,
        severity: .error,
        detail: "second"
    )
    let secondEvent = CaptureResourceEvent(
        kind: .storagePressure,
        severity: .error,
        detail: "first"
    )

    func evaluate(
        _ events: [CaptureResourceEvent]
    ) -> [QualityDiagnostic] {
        CaptureQualityEvaluator.evaluate(
            CaptureQualityObservation(
                roomPlanStatus: .completed,
                activeMeshAnchorCount: 0,
                evidenceFrameCount: 1,
                resourceEvents: events,
                integrityStatus: .pass
            ),
            requirements: requirements
        ).diagnostics
    }

    let expected: [(String, String)] = [
        ("annotation_missing", "Required annotation is missing: a-key"),
        ("annotation_missing", "Required annotation is missing: z-key"),
        (
            "insufficient_mesh_anchors",
            "Active mesh anchor count is below the required minimum."
        ),
        (
            "measurement_missing",
            "Required measurement quantity is missing: m-1"
        ),
        (
            "measurement_missing",
            "Required measurement quantity is missing: m-2"
        ),
        ("resource_error", "memory_pressure: second"),
        ("resource_error", "storage_pressure: first"),
    ]

    let forward = evaluate([firstEvent, secondEvent])
    #expect(forward.map { ($0.code, $0.message) } == expected)

    // Same logical observation, different arrival order: identical
    // serialized diagnostics.
    let reversed = evaluate([secondEvent, firstEvent])
    #expect(reversed == forward)
}

@Test
func observationClampsNegativeCountsToZero() {
    let observation = CaptureQualityObservation(
        activeMeshAnchorCount: -3,
        evidenceFrameCount: -1,
        depthEvidenceCount: -2,
        usableMeshAnchorCount: -4,
        usableDepthSampleCount: -5
    )
    #expect(observation.activeMeshAnchorCount == 0)
    #expect(observation.evidenceFrameCount == 0)
    #expect(observation.depthEvidenceCount == 0)
    #expect(observation.usableMeshAnchorCount == 0)
    #expect(observation.usableDepthSampleCount == 0)
}

@Test
func trackingEventNormalizesInvalidTimestamps() throws {
    #expect(
        TrackingQualityEvent(
            sessionTimestampSeconds: -2,
            state: .limited
        ).sessionTimestampSeconds == 0
    )
    #expect(
        TrackingQualityEvent(
            sessionTimestampSeconds: .nan,
            state: .normal
        ).sessionTimestampSeconds == 0
    )
    #expect(
        TrackingQualityEvent(
            sessionTimestampSeconds: .infinity,
            state: .normal
        ).sessionTimestampSeconds == 0
    )

    // Decoding shares the same normalization path.
    let decoded = try JSONDecoder().decode(
        TrackingQualityEvent.self,
        from: Data(
            #"{"session_timestamp_s":-4,"state":"limited"}"#.utf8
        )
    )
    #expect(decoded.sessionTimestampSeconds == 0)
    #expect(decoded.state == .limited)
    #expect(decoded.reason == nil)
}

@Test
func diagnosticEvidenceRefsAreCanonicalized() {
    let diagnostic = QualityDiagnostic(
        code: "fixture",
        severity: .info,
        message: "fixture message",
        evidenceRefs: ["b", "a", "b", "", "a"]
    )
    #expect(diagnostic.evidenceRefs == ["b", "a"])
}

@Test
func benchmarkRefsAreCanonicalizedInReport() {
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            integrityStatus: .pass,
            benchmarkRefs: ["b", "a", "b", "", "a"]
        ),
        requirements: invariantRequirements
    )
    #expect(report.benchmarkRefs == ["a", "b"])
}

@Test
func usableGeometryGovernsMeshReadinessNotContainers() {
    // Container counts are high but measured usable geometry is empty:
    // the mesh gate must fail and the depth fallback cannot rescue it.
    let containerOnly = CaptureQualityObservation(
        roomPlanStatus: .completed,
        activeMeshAnchorCount: 3,
        evidenceFrameCount: 1,
        depthEvidenceCount: 2,
        usableMeshAnchorCount: 0,
        usableDepthSampleCount: 0,
        integrityStatus: .pass
    )
    let blocked = CaptureQualityEvaluator.evaluate(
        containerOnly,
        requirements: CaptureQualityRequirements(
            rulesetVersion: "test-ruleset",
            allowDepthEvidenceAsMeshFallback: true
        )
    )
    #expect(!blocked.readyForHTDTIngestion)
    #expect(
        blocked.diagnostics.contains {
            $0.code == "insufficient_mesh_anchors"
                && $0.severity == .error
        }
    )
    #expect(
        !blocked.diagnostics.contains { $0.code == "mesh_depth_fallback" }
    )
    #expect(blocked.usableMeshAnchorCount == 0)
    #expect(blocked.usableDepthSampleCount == 0)

    // Usable depth samples still satisfy the bounded fallback.
    let fallback = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 0,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            usableMeshAnchorCount: 0,
            usableDepthSampleCount: 4,
            integrityStatus: .pass
        ),
        requirements: CaptureQualityRequirements(
            rulesetVersion: "test-ruleset",
            allowDepthEvidenceAsMeshFallback: true
        )
    )
    #expect(fallback.readyForHTDTIngestion)
    #expect(
        fallback.diagnostics.contains {
            $0.code == "mesh_depth_fallback"
                && $0.severity == .warning
        }
    )

    // Usable mesh anchors satisfy the mesh requirement directly.
    let meshReady = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 5,
            evidenceFrameCount: 1,
            usableMeshAnchorCount: 2,
            integrityStatus: .pass
        ),
        requirements: CaptureQualityRequirements(
            rulesetVersion: "test-ruleset",
            minimumActiveMeshAnchors: 2
        )
    )
    #expect(meshReady.readyForHTDTIngestion)

    // Observations without usable metrics keep legacy container
    // semantics and omit the additive report fields.
    let legacy = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            integrityStatus: .pass
        ),
        requirements: invariantRequirements
    )
    #expect(legacy.readyForHTDTIngestion)
    #expect(legacy.usableMeshAnchorCount == nil)
    #expect(legacy.usableDepthSampleCount == nil)
}

@Test
func usableDepthGovernsExplicitDepthRequirement() {
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 1,
            evidenceFrameCount: 1,
            depthEvidenceCount: 3,
            usableDepthSampleCount: 0,
            integrityStatus: .pass
        ),
        requirements: CaptureQualityRequirements(
            rulesetVersion: "test-ruleset",
            requireDepthEvidence: true
        )
    )
    #expect(!report.readyForHTDTIngestion)
    #expect(
        report.diagnostics.contains { $0.code == "depth_evidence_missing" }
    )
}

@Test
func usableGeometryFieldsAreAdditiveInSchema() throws {
    // The report's usable-geometry summary is an additive-optional
    // contract: permitted by the schema but not required, so older
    // payloads keep validating.
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
    let properties = try #require(
        object["properties"] as? [String: Any]
    )
    let required = try #require(object["required"] as? [String])
    #expect(properties["usable_mesh_anchor_count"] != nil)
    #expect(properties["usable_depth_sample_count"] != nil)
    #expect(!required.contains("usable_mesh_anchor_count"))
    #expect(!required.contains("usable_depth_sample_count"))
}

@Test
func evaluatorOutputSatisfiesQualitySchemaShape() throws {
    let report = CaptureQualityEvaluator.evaluate(
        CaptureQualityObservation(
            trackingEvents: [
                TrackingQualityEvent(
                    sessionTimestampSeconds: 1,
                    state: .limited,
                    reason: "insufficient_features"
                )
            ],
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 0,
            evidenceFrameCount: 2,
            depthEvidenceCount: 1,
            usableMeshAnchorCount: 0,
            usableDepthSampleCount: 3,
            annotationKeysPresent: ["speaker:L"],
            resourceEvents: [
                CaptureResourceEvent(
                    kind: .memoryPressure,
                    severity: .warning,
                    detail: "memory pressure observed"
                ),
                CaptureResourceEvent(
                    kind: .interruption,
                    severity: .error,
                    detail: "capture interrupted",
                    occurredAtUtc: "2026-09-20T00:00:01Z",
                    sequence: 7
                ),
            ],
            integrityStatus: .pass,
            benchmarkRefs: ["bench-1"]
        ),
        requirements: CaptureQualityRequirements(
            rulesetVersion: "test-ruleset",
            allowDepthEvidenceAsMeshFallback: true,
            requiredAnnotationKeys: ["speaker:L", "speaker:C"],
            requiredMeasurementQuantityTypes: ["room_width"]
        )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(report)

    // Codable round trip is lossless.
    let decoded = try JSONDecoder().decode(
        CaptureQualityReport.self,
        from: data
    )
    #expect(decoded == report)

    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    for key in [
        "schema",
        "schema_version",
        "ruleset_version",
        "ready_for_htdt_ingestion",
        "tracking_events",
        "roomplan_status",
        "active_mesh_anchor_count",
        "evidence_frame_count",
        "depth_evidence_count",
        "annotation_completeness",
        "measurement_completeness",
        "resource_events",
        "integrity_status",
        "benchmark_refs",
        "diagnostics",
    ] {
        #expect(object[key] != nil, "missing required key \(key)")
    }
    #expect(object["schema"] as? String == "htdt.capture.quality")
    #expect(object["schema_version"] as? String == "1.0.0")
    #expect(!(object["ruleset_version"] as? String ?? "").isEmpty)
    #expect(
        (object["ready_for_htdt_ingestion"] as? NSNumber)?.boolValue
            == report.readyForHTDTIngestion
    )
    #expect(object["roomplan_status"] as? String == "completed")
    #expect(object["integrity_status"] as? String == "pass")

    for key in [
        "active_mesh_anchor_count",
        "evidence_frame_count",
        "depth_evidence_count",
        "usable_mesh_anchor_count",
        "usable_depth_sample_count",
    ] {
        let value = try #require(object[key] as? NSNumber)
        #expect(value.intValue >= 0)
    }
    #expect(
        (object["usable_mesh_anchor_count"] as? NSNumber)?.intValue == 0
    )
    #expect(
        (object["usable_depth_sample_count"] as? NSNumber)?.intValue == 3
    )

    let benchmarks = try #require(object["benchmark_refs"] as? [String])
    #expect(Set(benchmarks).count == benchmarks.count)
    #expect(benchmarks.allSatisfy { !$0.isEmpty })

    let diagnostics = try #require(
        object["diagnostics"] as? [[String: Any]]
    )
    let severities: Set<String> = ["info", "warning", "error"]
    for diagnostic in diagnostics {
        #expect(!(diagnostic["code"] as? String ?? "").isEmpty)
        #expect(!(diagnostic["message"] as? String ?? "").isEmpty)
        #expect(
            severities.contains(diagnostic["severity"] as? String ?? "")
        )
        let refs = try #require(diagnostic["evidence_refs"] as? [String])
        #expect(Set(refs).count == refs.count)
    }

    let resourceEvents = try #require(
        object["resource_events"] as? [[String: Any]]
    )
    let kinds: Set<String> = [
        "thermal_pressure",
        "memory_pressure",
        "storage_pressure",
        "persistence_backlog",
        "persistence_failure",
        "interruption",
    ]
    for event in resourceEvents {
        #expect(kinds.contains(event["kind"] as? String ?? ""))
        #expect(
            severities.contains(event["severity"] as? String ?? "")
        )
        #expect(event["detail"] != nil)
    }
    let sequenced = resourceEvents.first {
        $0["sequence"] != nil
    }
    #expect(
        sequenced?["occurred_at_utc"] as? String == "2026-09-20T00:00:01Z"
    )
    #expect((sequenced?["sequence"] as? NSNumber)?.uint64Value == 7)

    let trackingEvents = try #require(
        object["tracking_events"] as? [[String: Any]]
    )
    for event in trackingEvents {
        let timestamp = try #require(
            event["session_timestamp_s"] as? NSNumber
        )
        #expect(timestamp.doubleValue >= 0)
        #expect(
            ["normal", "limited", "unavailable"].contains(
                event["state"] as? String ?? ""
            )
        )
    }

    for key in ["annotation_completeness", "measurement_completeness"] {
        let completeness = try #require(object[key] as? [String: Any])
        for listKey in ["required", "present", "missing"] {
            let list = try #require(completeness[listKey] as? [String])
            #expect(Set(list).count == list.count)
            #expect(list.allSatisfy { !$0.isEmpty })
        }
    }

    // Readiness is consistent with the emitted diagnostics.
    let hasError = report.diagnostics.contains {
        $0.severity == .error
    }
    #expect(report.readyForHTDTIngestion == !hasError)
}
