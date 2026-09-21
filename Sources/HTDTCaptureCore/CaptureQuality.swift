import Foundation

public enum QualityDiagnosticSeverity: String, Codable, Sendable, Comparable {
    case info
    case warning
    case error

    public static func < (
        lhs: QualityDiagnosticSeverity,
        rhs: QualityDiagnosticSeverity
    ) -> Bool {
        func rank(_ value: QualityDiagnosticSeverity) -> Int {
            switch value {
            case .info: 0
            case .warning: 1
            case .error: 2
            }
        }
        return rank(lhs) < rank(rhs)
    }
}

public struct QualityDiagnostic: Codable, Sendable, Equatable {
    public let code: String
    public let severity: QualityDiagnosticSeverity
    public let message: String
    public let evidenceRefs: [String]

    public init(
        code: String,
        severity: QualityDiagnosticSeverity,
        message: String,
        evidenceRefs: [String] = []
    ) {
        // Producer-side wire invariants: the quality schema requires
        // non-empty code/message and unique, non-empty evidence refs.
        precondition(
            !code.isEmpty,
            "quality diagnostic code must be non-empty"
        )
        precondition(
            !message.isEmpty,
            "quality diagnostic message must be non-empty"
        )
        self.code = code
        self.severity = severity
        self.message = message
        var seen = Set<String>()
        self.evidenceRefs = evidenceRefs.filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case severity
        case message
        case evidenceRefs = "evidence_refs"
    }
}

public enum RoomPlanQualityStatus: String, Codable, Sendable {
    case notStarted = "not_started"
    case running
    case completed
    case failed
    case unavailable
}

public enum BundleIntegrityStatus: String, Codable, Sendable {
    case notChecked = "not_checked"
    case pass
    case fail
}

public enum TrackingQualityState: String, Codable, Sendable {
    case normal
    case limited
    case unavailable
}

public struct TrackingQualityEvent: Codable, Sendable, Equatable {
    public let sessionTimestampSeconds: Double
    public let state: TrackingQualityState
    public let reason: String?

    public init(
        sessionTimestampSeconds: Double,
        state: TrackingQualityState,
        reason: String? = nil
    ) {
        // The quality schema requires a finite, non-negative session
        // timestamp and canonical JSON cannot represent non-finite
        // values, so invalid inputs normalize to the session origin.
        self.sessionTimestampSeconds = sessionTimestampSeconds.isFinite
            ? max(0, sessionTimestampSeconds)
            : 0
        self.state = state
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case sessionTimestampSeconds = "session_timestamp_s"
        case state
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionTimestampSeconds: try container.decode(
                Double.self,
                forKey: .sessionTimestampSeconds
            ),
            state: try container.decode(
                TrackingQualityState.self,
                forKey: .state
            ),
            reason: try container.decodeIfPresent(
                String.self,
                forKey: .reason
            )
        )
    }
}

public enum CaptureResourceEventKind: String, Codable, Sendable {
    case thermalPressure = "thermal_pressure"
    case memoryPressure = "memory_pressure"
    case storagePressure = "storage_pressure"
    case persistenceBacklog = "persistence_backlog"
    case persistenceFailure = "persistence_failure"
    case interruption
}

public struct CaptureResourceEvent: Codable, Sendable, Equatable {
    public let kind: CaptureResourceEventKind
    public let severity: QualityDiagnosticSeverity
    public let detail: String
    /// RFC 3339 UTC timestamp identifying when the event occurred. A nil
    /// value means the producing clock authority could not supply an
    /// occurrence time; precision is never fabricated.
    public let occurredAtUtc: String?
    /// Monotonic per-session sequence number assigned by the recording
    /// authority. A nil value marks an event recorded before sequencing
    /// existed (or by a producer without a clock domain); see
    /// `CaptureQualityEvaluator` for the deterministic ordering policy.
    public let sequence: UInt64?

    public init(
        kind: CaptureResourceEventKind,
        severity: QualityDiagnosticSeverity,
        detail: String,
        occurredAtUtc: String? = nil,
        sequence: UInt64? = nil
    ) {
        self.kind = kind
        self.severity = severity
        self.detail = detail
        self.occurredAtUtc = occurredAtUtc
        self.sequence = sequence
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case severity
        case detail
        case occurredAtUtc = "occurred_at_utc"
        case sequence
    }

    // `occurred_at_utc` and `sequence` are additive optional fields:
    // events persisted by earlier versions decode with nil values.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(
                CaptureResourceEventKind.self,
                forKey: .kind
            ),
            severity: try container.decode(
                QualityDiagnosticSeverity.self,
                forKey: .severity
            ),
            detail: try container.decode(String.self, forKey: .detail),
            occurredAtUtc: try container.decodeIfPresent(
                String.self,
                forKey: .occurredAtUtc
            ),
            sequence: try container.decodeIfPresent(
                UInt64.self,
                forKey: .sequence
            )
        )
    }
}

public struct CompletenessStatus: Codable, Sendable, Equatable {
    public let required: [String]
    public let present: [String]
    public let missing: [String]

    public init(required: Set<String>, present: Set<String>) {
        // The quality schema requires unique, non-empty string entries.
        let normalizedRequired = required.filter { !$0.isEmpty }
        let normalizedPresent = present.filter { !$0.isEmpty }
        self.required = normalizedRequired.sorted()
        self.present = normalizedPresent.sorted()
        self.missing = normalizedRequired
            .subtracting(normalizedPresent)
            .sorted()
    }

    public var isComplete: Bool {
        missing.isEmpty
    }
}

public struct CaptureQualityObservation: Sendable, Equatable {
    public var trackingEvents: [TrackingQualityEvent]
    public var roomPlanStatus: RoomPlanQualityStatus
    public var activeMeshAnchorCount: Int
    public var evidenceFrameCount: Int
    public var depthEvidenceCount: Int
    /// Number of mesh anchors that carry at least one geometric
    /// primitive (a usable anchor), as summarized by the persistence
    /// authority. A nil value means usable geometry was not measured;
    /// the evaluator then falls back to `activeMeshAnchorCount` so
    /// pre-metric observations keep their legacy semantics.
    public var usableMeshAnchorCount: Int?
    /// Number of valid, positive depth samples observed across the
    /// retained depth evidence. A nil value means usable geometry was
    /// not measured; the evaluator then falls back to
    /// `depthEvidenceCount` so pre-metric observations keep their
    /// legacy semantics.
    public var usableDepthSampleCount: Int?
    public var annotationKeysPresent: Set<String>
    public var measurementQuantityTypesPresent: Set<String>
    public var resourceEvents: [CaptureResourceEvent]
    public var integrityStatus: BundleIntegrityStatus
    public var benchmarkRefs: [String]

    public init(
        trackingEvents: [TrackingQualityEvent] = [],
        roomPlanStatus: RoomPlanQualityStatus = .notStarted,
        activeMeshAnchorCount: Int = 0,
        evidenceFrameCount: Int = 0,
        depthEvidenceCount: Int = 0,
        usableMeshAnchorCount: Int? = nil,
        usableDepthSampleCount: Int? = nil,
        annotationKeysPresent: Set<String> = [],
        measurementQuantityTypesPresent: Set<String> = [],
        resourceEvents: [CaptureResourceEvent] = [],
        integrityStatus: BundleIntegrityStatus = .notChecked,
        benchmarkRefs: [String] = []
    ) {
        self.trackingEvents = trackingEvents
        self.roomPlanStatus = roomPlanStatus
        // The quality schema requires non-negative counts.
        self.activeMeshAnchorCount = max(0, activeMeshAnchorCount)
        self.evidenceFrameCount = max(0, evidenceFrameCount)
        self.depthEvidenceCount = max(0, depthEvidenceCount)
        self.usableMeshAnchorCount = usableMeshAnchorCount
            .map { max(0, $0) }
        self.usableDepthSampleCount = usableDepthSampleCount
            .map { max(0, $0) }
        self.annotationKeysPresent = annotationKeysPresent
        self.measurementQuantityTypesPresent =
            measurementQuantityTypesPresent
        self.resourceEvents = resourceEvents
        self.integrityStatus = integrityStatus
        self.benchmarkRefs = benchmarkRefs
    }
}

public struct CaptureQualityRequirements: Sendable, Equatable {
    public let rulesetVersion: String
    public let requireCompletedRoomPlan: Bool
    public let minimumActiveMeshAnchors: Int
    public let allowDepthEvidenceAsMeshFallback: Bool
    public let minimumEvidenceFrames: Int
    public let requireDepthEvidence: Bool
    public let requiredAnnotationKeys: Set<String>
    public let requiredMeasurementQuantityTypes: Set<String>
    public let requireIntegrityPass: Bool

    /// Canonical requirement definitions bound to published ruleset
    /// versions. A published version identifier always denotes exactly
    /// this requirement set: constructing requirements with a published
    /// version pins every gate parameter to the registry entry, so an
    /// arbitrary threshold set can never claim a published identity.
    /// Ruleset changes require a new version entry here; existing
    /// bundles keep decoding only `ruleset_version` and remain
    /// interpretable through `forRuleset(version:)`.
    /// Versions absent from this registry are unpublished/experimental
    /// identities and may carry arbitrary parameters.
    private static let publishedRequirements:
        [String: CaptureQualityRequirements] = [
            "1.1.0": CaptureQualityRequirements(
                pinnedRulesetVersion: "1.1.0",
                requireCompletedRoomPlan: true,
                minimumActiveMeshAnchors: 1,
                allowDepthEvidenceAsMeshFallback: true,
                minimumEvidenceFrames: 1,
                requireDepthEvidence: false,
                requiredAnnotationKeys: [],
                requiredMeasurementQuantityTypes: [],
                requireIntegrityPass: true
            )
        ]

    /// Returns the canonical requirements bound to a published ruleset
    /// version, or nil when the version is not published.
    public static func forRuleset(
        version: String
    ) -> CaptureQualityRequirements? {
        publishedRequirements[version]
    }

    /// Published ruleset version identities, sorted for deterministic
    /// presentation.
    public static var publishedRulesetVersions: [String] {
        publishedRequirements.keys.sorted()
    }

    private init(
        pinnedRulesetVersion: String,
        requireCompletedRoomPlan: Bool,
        minimumActiveMeshAnchors: Int,
        allowDepthEvidenceAsMeshFallback: Bool,
        minimumEvidenceFrames: Int,
        requireDepthEvidence: Bool,
        requiredAnnotationKeys: Set<String>,
        requiredMeasurementQuantityTypes: Set<String>,
        requireIntegrityPass: Bool
    ) {
        self.rulesetVersion = pinnedRulesetVersion
        self.requireCompletedRoomPlan = requireCompletedRoomPlan
        self.minimumActiveMeshAnchors = minimumActiveMeshAnchors
        self.allowDepthEvidenceAsMeshFallback =
            allowDepthEvidenceAsMeshFallback
        self.minimumEvidenceFrames = minimumEvidenceFrames
        self.requireDepthEvidence = requireDepthEvidence
        self.requiredAnnotationKeys = requiredAnnotationKeys
        self.requiredMeasurementQuantityTypes =
            requiredMeasurementQuantityTypes
        self.requireIntegrityPass = requireIntegrityPass
    }

    public init(
        rulesetVersion: String = "1.0.0",
        requireCompletedRoomPlan: Bool = true,
        minimumActiveMeshAnchors: Int = 1,
        allowDepthEvidenceAsMeshFallback: Bool = false,
        minimumEvidenceFrames: Int = 1,
        requireDepthEvidence: Bool = false,
        requiredAnnotationKeys: Set<String> = [],
        requiredMeasurementQuantityTypes: Set<String> = [],
        requireIntegrityPass: Bool = true
    ) {
        precondition(
            !rulesetVersion.isEmpty,
            "quality ruleset version must be a non-empty identity"
        )
        if let published = Self.publishedRequirements[rulesetVersion] {
            self = published
            return
        }
        self.rulesetVersion = rulesetVersion
        self.requireCompletedRoomPlan = requireCompletedRoomPlan
        self.minimumActiveMeshAnchors = max(0, minimumActiveMeshAnchors)
        self.allowDepthEvidenceAsMeshFallback =
            allowDepthEvidenceAsMeshFallback
        self.minimumEvidenceFrames = max(0, minimumEvidenceFrames)
        self.requireDepthEvidence = requireDepthEvidence
        self.requiredAnnotationKeys = requiredAnnotationKeys
        self.requiredMeasurementQuantityTypes =
            requiredMeasurementQuantityTypes
        self.requireIntegrityPass = requireIntegrityPass
    }
}

public struct CaptureQualityReport: Codable, Sendable, Equatable {
    public let schema: String
    public let schemaVersion: String
    public let rulesetVersion: String
    public let readyForHTDTIngestion: Bool
    public let trackingEvents: [TrackingQualityEvent]
    public let roomPlanStatus: RoomPlanQualityStatus
    public let activeMeshAnchorCount: Int
    public let evidenceFrameCount: Int
    public let depthEvidenceCount: Int
    /// Usable-geometry summary the gate actually evaluated; nil when
    /// the observation predates usable-geometry measurement (additive
    /// schema fields, omitted from the payload when absent).
    public let usableMeshAnchorCount: Int?
    public let usableDepthSampleCount: Int?
    public let annotationCompleteness: CompletenessStatus
    public let measurementCompleteness: CompletenessStatus
    public let resourceEvents: [CaptureResourceEvent]
    public let integrityStatus: BundleIntegrityStatus
    public let benchmarkRefs: [String]
    public let diagnostics: [QualityDiagnostic]

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case rulesetVersion = "ruleset_version"
        case readyForHTDTIngestion = "ready_for_htdt_ingestion"
        case trackingEvents = "tracking_events"
        case roomPlanStatus = "roomplan_status"
        case activeMeshAnchorCount = "active_mesh_anchor_count"
        case evidenceFrameCount = "evidence_frame_count"
        case depthEvidenceCount = "depth_evidence_count"
        case usableMeshAnchorCount = "usable_mesh_anchor_count"
        case usableDepthSampleCount = "usable_depth_sample_count"
        case annotationCompleteness = "annotation_completeness"
        case measurementCompleteness = "measurement_completeness"
        case resourceEvents = "resource_events"
        case integrityStatus = "integrity_status"
        case benchmarkRefs = "benchmark_refs"
        case diagnostics
    }
}

public enum CaptureQualityEvaluator {
    public static func evaluate(
        _ observation: CaptureQualityObservation,
        requirements: CaptureQualityRequirements
    ) -> CaptureQualityReport {
        let annotationStatus = CompletenessStatus(
            required: requirements.requiredAnnotationKeys,
            present: observation.annotationKeysPresent
        )
        let measurementStatus = CompletenessStatus(
            required: requirements.requiredMeasurementQuantityTypes,
            present: observation.measurementQuantityTypesPresent
        )

        // Geometry readiness counts usable geometry, not containers.
        // When the persistence authority did not measure usable
        // geometry the legacy container counts stand in so pre-metric
        // observations keep their semantics.
        let usableMeshAnchors = observation.usableMeshAnchorCount
            ?? observation.activeMeshAnchorCount
        let usableDepthSamples = observation.usableDepthSampleCount
            ?? observation.depthEvidenceCount

        // Deterministic resource chronology: events carrying an
        // explicit sequence number order first, ascending; events
        // without a sequence then order by occurred_at_utc (absent
        // sorts first); the final tie-breaker is original insertion
        // order so equal-time events serialize deterministically.
        let orderedResourceEvents = observation.resourceEvents
            .enumerated()
            .sorted { lhs, rhs in
                let lhsSequence = lhs.element.sequence ?? UInt64.max
                let rhsSequence = rhs.element.sequence ?? UInt64.max
                if lhsSequence != rhsSequence {
                    return lhsSequence < rhsSequence
                }
                let lhsTime = lhs.element.occurredAtUtc ?? ""
                let rhsTime = rhs.element.occurredAtUtc ?? ""
                if lhsTime != rhsTime {
                    return lhsTime < rhsTime
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        var diagnostics: [QualityDiagnostic] = []

        if requirements.requireCompletedRoomPlan,
           observation.roomPlanStatus != .completed
        {
            diagnostics.append(
                QualityDiagnostic(
                    code: "roomplan_not_completed",
                    severity: .error,
                    message:
                        "RoomPlan capture has not completed successfully."
                )
            )
        }

        if usableMeshAnchors
            < requirements.minimumActiveMeshAnchors
        {
            if requirements.allowDepthEvidenceAsMeshFallback,
               usableDepthSamples > 0
            {
                diagnostics.append(
                    QualityDiagnostic(
                        code: "mesh_depth_fallback",
                        severity: .warning,
                        message:
                            "Active mesh evidence is unavailable; retained scene-depth evidence is being used as the bounded geometric fallback."
                    )
                )
            } else {
                diagnostics.append(
                    QualityDiagnostic(
                        code: "insufficient_mesh_anchors",
                        severity: .error,
                        message:
                            "Active mesh anchor count is below the required minimum."
                    )
                )
            }
        }

        if observation.evidenceFrameCount
            < requirements.minimumEvidenceFrames
        {
            diagnostics.append(
                QualityDiagnostic(
                    code: "insufficient_evidence_frames",
                    severity: .error,
                    message:
                        "Evidence frame count is below the required minimum."
                )
            )
        }

        if requirements.requireDepthEvidence,
           usableDepthSamples == 0
        {
            diagnostics.append(
                QualityDiagnostic(
                    code: "depth_evidence_missing",
                    severity: .error,
                    message:
                        "This quality ruleset requires at least one depth observation."
                )
            )
        }

        for missing in annotationStatus.missing {
            diagnostics.append(
                QualityDiagnostic(
                    code: "annotation_missing",
                    severity: .error,
                    message: "Required annotation is missing: \(missing)"
                )
            )
        }

        for missing in measurementStatus.missing {
            diagnostics.append(
                QualityDiagnostic(
                    code: "measurement_missing",
                    severity: .error,
                    message:
                        "Required measurement quantity is missing: \(missing)"
                )
            )
        }

        if observation.trackingEvents.contains(where: {
            $0.state == .unavailable
        }) {
            diagnostics.append(
                QualityDiagnostic(
                    code: "tracking_unavailable_observed",
                    severity: .error,
                    message:
                        "AR tracking became unavailable during the capture."
                )
            )
        } else if observation.trackingEvents.contains(where: {
            $0.state == .limited
        }) {
            diagnostics.append(
                QualityDiagnostic(
                    code: "tracking_limited_observed",
                    severity: .warning,
                    message:
                        "AR tracking was limited during part of the capture."
                )
            )
        }

        for event in orderedResourceEvents where event.severity == .error {
            diagnostics.append(
                QualityDiagnostic(
                    code: "resource_error",
                    severity: .error,
                    message: "\(event.kind.rawValue): \(event.detail)"
                )
            )
        }

        if requirements.requireIntegrityPass {
            switch observation.integrityStatus {
            case .pass:
                break
            case .notChecked:
                diagnostics.append(
                    QualityDiagnostic(
                        code: "integrity_not_checked",
                        severity: .error,
                        message:
                            "Bundle integrity must pass before finalization."
                    )
                )
            case .fail:
                diagnostics.append(
                    QualityDiagnostic(
                        code: "integrity_failed",
                        severity: .error,
                        message:
                            "Bundle integrity validation failed."
                    )
                )
            }
        }

        // Total deterministic ordering for serialized diagnostics:
        // severity rank (error first), then code, then message, then a
        // lexicographic evidence-ref comparison. Distinct diagnostics
        // can never tie on insertion order alone, so the canonical
        // payload is stable regardless of sort-implementation details.
        diagnostics.sort {
            if $0.severity != $1.severity {
                return $0.severity > $1.severity
            }
            if $0.code != $1.code {
                return $0.code < $1.code
            }
            if $0.message != $1.message {
                return $0.message < $1.message
            }
            return $0.evidenceRefs.lexicographicallyPrecedes(
                $1.evidenceRefs
            )
        }

        let ready = !diagnostics.contains {
            $0.severity == .error
        }

        return CaptureQualityReport(
            schema: "htdt.capture.quality",
            schemaVersion: "1.0.0",
            rulesetVersion: requirements.rulesetVersion,
            readyForHTDTIngestion: ready,
            trackingEvents: observation.trackingEvents,
            roomPlanStatus: observation.roomPlanStatus,
            activeMeshAnchorCount: observation.activeMeshAnchorCount,
            evidenceFrameCount: observation.evidenceFrameCount,
            depthEvidenceCount: observation.depthEvidenceCount,
            usableMeshAnchorCount: observation.usableMeshAnchorCount,
            usableDepthSampleCount: observation.usableDepthSampleCount,
            annotationCompleteness: annotationStatus,
            measurementCompleteness: measurementStatus,
            resourceEvents: orderedResourceEvents,
            integrityStatus: observation.integrityStatus,
            benchmarkRefs: canonicalBenchmarkRefs(
                observation.benchmarkRefs
            ),
            diagnostics: diagnostics
        )
    }

    /// Canonical benchmark-ref policy: empty refs are dropped and the
    /// remainder is deduplicated then sorted ascending, matching the
    /// unique, non-empty wire invariant deterministically.
    private static func canonicalBenchmarkRefs(
        _ refs: [String]
    ) -> [String] {
        var seen = Set<String>()
        var canonical: [String] = []
        for ref in refs.sorted() where !ref.isEmpty {
            if seen.insert(ref).inserted {
                canonical.append(ref)
            }
        }
        return canonical
    }
}
