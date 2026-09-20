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
        self.code = code
        self.severity = severity
        self.message = message
        self.evidenceRefs = evidenceRefs
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
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.state = state
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case sessionTimestampSeconds = "session_timestamp_s"
        case state
        case reason
    }
}

public enum CaptureResourceEventKind: String, Codable, Sendable {
    case thermalPressure = "thermal_pressure"
    case memoryPressure = "memory_pressure"
    case storagePressure = "storage_pressure"
    case persistenceBacklog = "persistence_backlog"
    case persistenceFailure = "persistence_failure"
    case roomPlanRawSerializationUnavailable =
        "roomplan_raw_serialization_unavailable"
    case interruption
}

public struct CaptureResourceEvent: Codable, Sendable, Equatable {
    public let kind: CaptureResourceEventKind
    public let severity: QualityDiagnosticSeverity
    public let detail: String

    public init(
        kind: CaptureResourceEventKind,
        severity: QualityDiagnosticSeverity,
        detail: String
    ) {
        self.kind = kind
        self.severity = severity
        self.detail = detail
    }
}

public struct CompletenessStatus: Codable, Sendable, Equatable {
    public let required: [String]
    public let present: [String]
    public let missing: [String]

    public init(required: Set<String>, present: Set<String>) {
        self.required = required.sorted()
        self.present = present.sorted()
        self.missing = required.subtracting(present).sorted()
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
        annotationKeysPresent: Set<String> = [],
        measurementQuantityTypesPresent: Set<String> = [],
        resourceEvents: [CaptureResourceEvent] = [],
        integrityStatus: BundleIntegrityStatus = .notChecked,
        benchmarkRefs: [String] = []
    ) {
        self.trackingEvents = trackingEvents
        self.roomPlanStatus = roomPlanStatus
        self.activeMeshAnchorCount = activeMeshAnchorCount
        self.evidenceFrameCount = evidenceFrameCount
        self.depthEvidenceCount = depthEvidenceCount
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
        self.rulesetVersion = rulesetVersion
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

        if observation.activeMeshAnchorCount
            < requirements.minimumActiveMeshAnchors
        {
            if requirements.allowDepthEvidenceAsMeshFallback,
               observation.depthEvidenceCount > 0
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
           observation.depthEvidenceCount == 0
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

        for event in observation.resourceEvents where event.severity == .error {
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

        diagnostics.sort {
            if $0.severity != $1.severity {
                return $0.severity > $1.severity
            }
            return $0.code < $1.code
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
            annotationCompleteness: annotationStatus,
            measurementCompleteness: measurementStatus,
            resourceEvents: observation.resourceEvents,
            integrityStatus: observation.integrityStatus,
            benchmarkRefs: observation.benchmarkRefs.sorted(),
            diagnostics: diagnostics
        )
    }
}
