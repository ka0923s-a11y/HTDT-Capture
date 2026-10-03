import Foundation

/// Advisory provenance notes for operator-driven and policy-driven
/// scan events (#257, #273, #216, #274).
///
/// Notes are operator/advisory context — they never assert geometry or
/// canonical evidence authority. They persist into the working set and
/// the finalized bundle as a derived `capture_app_derived` payload, and
/// they surface in Review through the quality report's diagnostics as
/// info/warning entries, so downstream HTDT can distinguish e.g. an
/// intentionally unresolved region from a forgotten one.
public enum CaptureAdvisoryNoteKind: String, Codable, Sendable {
    /// Operator declared a coverage region intentionally unresolved.
    case declaredRegion = "declared_region"
    /// Operator revoked a previously declared region.
    case revokedRegion = "revoked_region"
    /// The bounded policy retained an evidence frame automatically.
    case automaticKeyframe = "automatic_keyframe"
    /// A retained frame carried a usability warning.
    case frameUsability = "frame_usability"
    /// The optional end-of-scan return-to-start consistency check ran.
    case loopClosureCheck = "loop_closure_check"
    /// An operator-targeted object orbit pass completed (#250).
    case targetScanPass = "target_scan_pass"
    /// An operator-seeded iterative-segmentation attempt ran inside an
    /// object pass (#269): seed kind, mask outcome, bounded refinement
    /// count and the display-mapping authority are recorded.
    case segmentationPass = "segmentation_pass"
    /// An operator revisit flag was dropped mid-scan (#325).
    case revisitFlag = "revisit_flag"
    /// A revisit flag was resolved/skipped/unavailable in Review
    /// (#325).
    case revisitFlagResolution = "revisit_flag_resolution"
    /// A capture mission (generic task profile or imported HTDT task
    /// plan) was bound to the session before scanning started (#352).
    case missionBound = "mission_bound"
    /// The bound task profile changed after scanning started — an
    /// explicit operator action with provenance, never silent (#352).
    case taskProfileChange = "task_profile_change"
    /// The operator flagged an evidence frame as privacy-sensitive
    /// (person visible, credentials on a plate, …) for Review (#376).
    case privacyFlag = "privacy_flag"
    /// The operator cleared a frame's privacy flag — the paired
    /// revocation of `privacy_flag`, mirroring declare/revoke (#460).
    case privacyFlagCleared = "privacy_flag_cleared"
    /// RoomPlan was re-run on the same revision (Continue scanning or
    /// an End-attempt retry). Each `run()` builds a fresh room model,
    /// so the next accepted CapturedRoomData covers only the final
    /// scanning segment while mesh anchors and evidence frames keep
    /// accumulating across all segments.
    case roomPlanRescan = "roomplan_rescan"
    /// The RoomCaptureSession ended on its own — outside the bounded
    /// End transaction — so the room model stopped accumulating while
    /// the operator still sees a scanning surface.
    case roomPlanSessionEnded = "roomplan_session_ended"
    /// The operator's per-mission reference-object selection was
    /// resolved and applied to the ARSession (#268) — records selected
    /// counts plus any dropped requests verbatim.
    case referenceObjectSelection = "reference_object_selection"
    /// The session reconfiguration for reference objects completed
    /// with a non-plain outcome: an artifact failed to load, the
    /// running configuration did not adopt the object sets, or the
    /// platform refused (#268).
    case referenceObjectConfigurationOutcome =
        "reference_object_configuration_outcome"
    /// The operator accepted a matched reference-object observation
    /// into an entity's evidence — the observation ref lands alongside
    /// existing evidence, never overwriting placement/orientation
    /// (#268).
    case referenceObjectAcceptance = "reference_object_acceptance"
}

public struct CaptureAdvisoryNote: Codable, Sendable, Equatable {
    public let kind: CaptureAdvisoryNoteKind
    /// Session-clock seconds of the recorded event; normalized like
    /// other capture timestamps.
    public let sessionTimestampSeconds: Double
    /// Stable machine-readable detail (`key=value` pairs, space
    /// separated) carrying the structured payload, e.g.
    /// `cell_x=3 cell_z=-2 reason=inaccessible`.
    public let detail: String

    public init(
        kind: CaptureAdvisoryNoteKind,
        sessionTimestampSeconds: Double,
        detail: String
    ) {
        self.kind = kind
        self.sessionTimestampSeconds =
            sessionTimestampSeconds.isFinite
            ? max(0, sessionTimestampSeconds)
            : 0
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case sessionTimestampSeconds = "session_timestamp_seconds"
        case detail
    }

    /// The quality diagnostic the note contributes to Review.
    public var qualityDiagnostic: QualityDiagnostic {
        let code: String
        let severity: QualityDiagnosticSeverity
        switch kind {
        case .declaredRegion:
            code = "operator_declared_region"
            severity = .info
        case .revokedRegion:
            code = "operator_revoked_region"
            severity = .info
        case .automaticKeyframe:
            code = "auto_keyframe_retained"
            severity = .info
        case .frameUsability:
            code = "frame_usability_warning"
            severity = .warning
        case .loopClosureCheck:
            code = "loop_closure_check"
            severity = .info
        case .targetScanPass:
            code = "target_scan_pass"
            severity = .info
        case .segmentationPass:
            code = "segmentation_pass"
            severity = .info
        case .revisitFlag:
            code = "revisit_flag"
            severity = .info
        case .revisitFlagResolution:
            code = "revisit_flag_resolution"
            severity = .info
        case .missionBound:
            code = "mission_bound"
            severity = .info
        case .taskProfileChange:
            code = "task_profile_change"
            severity = .info
        case .privacyFlag:
            code = "frame_privacy_flag"
            severity = .info
        case .privacyFlagCleared:
            code = "frame_privacy_flag_cleared"
            severity = .info
        case .roomPlanRescan:
            code = "roomplan_rescan"
            severity = .warning
        case .roomPlanSessionEnded:
            code = "roomplan_session_ended"
            severity = .warning
        case .referenceObjectSelection:
            code = "reference_object_selection"
            severity = .info
        case .referenceObjectConfigurationOutcome:
            code = "reference_object_configuration_outcome"
            severity = .warning
        case .referenceObjectAcceptance:
            code = "reference_object_acceptance"
            severity = .info
        }
        return QualityDiagnostic(
            code: code,
            severity: severity,
            message: detail.isEmpty ? code : detail
        )
    }
}

/// The persisted advisory document written to
/// `advisory/operator-advisories.json` inside the working set. It is a
/// derived payload: the manifest declares it, integrity covers it, but
/// nothing downstream treats it as canonical geometry/evidence
/// authority.
public struct CaptureAdvisoryNoteDocument: Codable, Sendable, Equatable {
    public static let path = "advisory/operator-advisories.json"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let notes: [CaptureAdvisoryNote]

    public init(
        captureRevisionID: CaptureRevisionID,
        notes: [CaptureAdvisoryNote]
    ) {
        self.schema = "htdt.capture.advisory_notes"
        self.schemaVersion = "1.0.0"
        self.captureRevisionID = captureRevisionID
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case notes
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
