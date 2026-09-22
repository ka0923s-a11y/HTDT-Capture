import Foundation

/// A corrective affordance offered next to a quality finding in Review
/// (issue #298). Each case maps to an existing host action; the enum
/// carries the contract, the view carries the localized label, and the
/// coordinator carries the implementation — so actions never bypass
/// the quality gate, they only route the operator to the surface that
/// can legitimately clear it.
public enum CaptureRemediationAction:
    String,
    Codable,
    Sendable,
    CaseIterable
{
    /// Roll back the accepted End transaction and resume the live scan
    /// — the only path that can add spatial evidence. Requires a live
    /// working set; never offered on a relaunch-recovered draft
    /// (issue #297).
    case continueScanning = "continue_scanning"
    /// Commit one operator-triggered evidence frame (still capture) —
    /// also live-only.
    case saveEvidenceFrame = "save_evidence_frame"
    /// Open the annotation workspace to add or repair entities,
    /// speakers, or identity evidence. Works on live and recovered
    /// working sets — it is semantic, not spatial.
    case addAnnotation = "add_annotation"
    /// Open the measurement workspace for the missing quantity.
    case addMeasurement = "add_measurement"
    /// Open the capture-task profile/requirement surface
    /// (#217/#259) to reselect the profile or acknowledge a skipped
    /// requirement.
    case reviewTaskRequirements = "review_task_requirements"
    /// Re-run integrity verification against the committed bytes.
    case verifyIntegrityAgain = "verify_integrity_again"
    /// Discard this revision's working set and begin a replacement
    /// capture — the repair for authority-damaged findings (tracking
    /// loss, coordinate discontinuity) that no in-place action can fix.
    case startReplacementRevision = "start_replacement_revision"
    /// Delete the working revision entirely.
    case discardDraft = "discard_draft"

    /// Actions that need a live AR coordinate authority. A recovered
    /// draft (#297) must never offer them — its spatial evidence set
    /// is sealed by definition.
    public var requiresLiveSpatialAuthority: Bool {
        switch self {
        case .continueScanning, .saveEvidenceFrame:
            return true
        case .addAnnotation, .addMeasurement,
             .reviewTaskRequirements, .verifyIntegrityAgain,
             .startReplacementRevision, .discardDraft:
            return false
        }
    }
}

/// The review-facing remediation for one quality diagnostic: whether
/// it blocks finalization, whether an action can repair it in place,
/// and the ordered affordance list (issue #298). `title` and
/// `whyItMatters` are symbolic keys resolved by the view layer, which
/// owns `Localizable.strings` for both locales.
public struct QualityRemediation: Sendable, Equatable {
    /// The diagnostic code this remediation answers.
    public let diagnosticCode: String
    /// True when the diagnostic blocks `readyForHTDTIngestion`
    /// (severity `.error`).
    public let blocking: Bool
    /// True when at least one offered action can clear the finding on
    /// this working set without starting a replacement revision.
    public let repairableInPlace: Bool
    /// Ordered affordances; first is the recommended action.
    public let actions: [CaptureRemediationAction]

    public init(
        diagnosticCode: String,
        blocking: Bool,
        repairableInPlace: Bool,
        actions: [CaptureRemediationAction]
    ) {
        self.diagnosticCode = diagnosticCode
        self.blocking = blocking
        self.repairableInPlace = repairableInPlace
        self.actions = actions
    }

    /// The actions a recovered draft may offer — live-spatial actions
    /// are stripped rather than shown disabled-and-mysterious.
    public var draftActions: [CaptureRemediationAction] {
        actions.filter { !$0.requiresLiveSpatialAuthority }
    }
}

/// Catalog mapping ruleset diagnostic codes to remediation plans
/// (issue #298). Every blocking diagnostic the evaluator can emit is
/// classified here; advisory (warning/info) findings get the same
/// surface with non-blocking plans, and unknown codes degrade to a
/// discard-only plan instead of a dead end.
public enum QualityRemediationCatalog {
    /// Blocking diagnostics that no in-place action can repair — the
    /// spatial authority they describe is already gone.
    private static let authorityDamagedCodes: Set<String> = [
        "tracking_unavailable_unrecovered",
        "tracking_unavailable_extended",
        "tracking_coordinate_discontinuity",
    ]

    public static func remediation(
        for diagnostic: QualityDiagnostic
    ) -> QualityRemediation {
        let blocking = diagnostic.severity == .error
        switch diagnostic.code {
        case "roomplan_not_completed":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: true,
                actions: [
                    .continueScanning,
                    .startReplacementRevision,
                ]
            )
        case "insufficient_mesh_anchors",
             "depth_fallback_insufficient",
             "depth_evidence_missing":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: true,
                actions: [
                    .continueScanning,
                    .startReplacementRevision,
                ]
            )
        case "insufficient_evidence_frames":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: true,
                actions: [
                    .saveEvidenceFrame,
                    .continueScanning,
                    .startReplacementRevision,
                ]
            )
        case "annotation_missing":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: true,
                actions: [.addAnnotation]
            )
        case "measurement_missing":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: true,
                actions: [.addMeasurement]
            )
        case "tracking_unavailable_recovering":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: true,
                actions: [
                    .continueScanning,
                    .startReplacementRevision,
                ]
            )
        case "integrity_not_checked":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: true,
                actions: [.verifyIntegrityAgain]
            )
        case "integrity_failed":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: true,
                actions: [
                    .verifyIntegrityAgain,
                    .discardDraft,
                ]
            )
        case "resource_error":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: false,
                actions: [
                    .startReplacementRevision,
                    .discardDraft,
                ]
            )
        case "mesh_depth_fallback",
             "tracking_limited_observed",
             "tracking_unavailable_observed",
             "tracking_unavailable_recovered":
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: true,
                actions: [.continueScanning]
            )
        default:
            if authorityDamagedCodes.contains(diagnostic.code) {
                return QualityRemediation(
                    diagnosticCode: diagnostic.code,
                    blocking: blocking,
                    repairableInPlace: false,
                    actions: [
                        .startReplacementRevision,
                        .discardDraft,
                    ]
                )
            }
            // Unknown diagnostic: surface the discard affordance so the
            // operator is never trapped behind an unexplained disabled
            // Finalize.
            return QualityRemediation(
                diagnosticCode: diagnostic.code,
                blocking: blocking,
                repairableInPlace: false,
                actions: [.discardDraft]
            )
        }
    }

    /// Every diagnostic in the report mapped to its remediation plan.
    public static func remediations(
        for diagnostics: [QualityDiagnostic]
    ) -> [QualityRemediation] {
        diagnostics.map(remediation(for:))
    }
}

extension CaptureTaskCompletenessReport {
    /// Remediation for an unmet task profile (#217/#259): the same
    /// affordance surface as quality diagnostics — unsatisfied
    /// annotation/measurement requirements route to the authoring
    /// workspaces, a missing profile or a deliberate-skip correction
    /// routes to the task-requirement picker. A fully satisfied
    /// evaluation offers nothing.
    public var remediationActions: [CaptureRemediationAction] {
        switch evaluationState {
        case .noProfileSelected,
             .noRequirementsConfigured:
            return [.reviewTaskRequirements]
        case .evaluated:
            guard !overallSatisfied else { return [] }
            var needsAnnotation = false
            var needsMeasurement = false
            for outcome in outcomes {
                switch outcome.status {
                case .missing, .partial, .overMaximum:
                    break
                case .satisfied, .satisfiedByAlternative,
                     .skipped, .optionalAbsent:
                    continue
                }
                switch outcome.requirement.match.kind {
                case .annotationEntityType,
                     .annotationChannelRole,
                     .annotationRoleBinding:
                    needsAnnotation = true
                case .measurementQuantityType,
                     .measurementEndpointPair:
                    needsMeasurement = true
                }
            }
            var actions: [CaptureRemediationAction] = []
            if needsAnnotation {
                actions.append(.addAnnotation)
            }
            if needsMeasurement {
                actions.append(.addMeasurement)
            }
            actions.append(.reviewTaskRequirements)
            return actions
        }
    }
}
