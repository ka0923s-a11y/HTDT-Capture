import Foundation

/// The operator-visible capture loop (issue #372): Home → Prepare →
/// Scan → Review → Details → Finalize → Send. Transient `CaptureState`
/// values map onto their containing stage — they are progress inside a
/// stage, never destinations themselves.
public enum CaptureJourneyStage: String, Sendable, Equatable,
    CaseIterable, Comparable
{
    case home
    case prepare
    case scan
    case review
    case details
    case finalize
    case send

    public static func < (
        lhs: CaptureJourneyStage,
        rhs: CaptureJourneyStage
    ) -> Bool {
        order(of: lhs) < order(of: rhs)
    }

    private static func order(of stage: CaptureJourneyStage) -> Int {
        Self.allCases.firstIndex(of: stage) ?? 0
    }

    /// Short operator-facing label key — kept deliberately terse so the
    /// expanded journey trail stays readable on iPad (#372 JOURNEY-90).
    public var titleKey: String {
        switch self {
        case .home: return "Home"
        case .prepare: return "Prepare"
        case .scan: return "Scan"
        case .review: return "Review"
        case .details: return "Details"
        case .finalize: return "Finalize"
        case .send: return "Send"
        }
    }

    /// Longer human navigation title for the stage's own page.
    public var pageTitleKey: String {
        switch self {
        case .home: return "HTDT Capture"
        case .prepare: return "Prepare capture"
        case .scan: return "Scan room"
        case .review: return "Review capture"
        case .details: return "Add details"
        case .finalize: return "Finalized capture"
        case .send: return "Send to HTDT"
        }
    }
}

/// Per-stage status shown in the journey trail (issue #372 JOURNEY-40):
/// statuses come from real workflow facts — a stage is never
/// "complete" merely because it was opened.
public enum CaptureJourneyStageStatus: String, Sendable, Equatable,
    CaseIterable
{
    case notStarted
    case current
    case complete
    case needsAttention
    case optionalStage
    case unavailable
    case failed

    public var labelKey: String {
        switch self {
        case .notStarted: return "Not started"
        case .current: return "Current"
        case .complete: return "Complete"
        case .needsAttention: return "Needs attention"
        case .optionalStage: return "Optional"
        case .unavailable: return "Unavailable"
        case .failed: return "Failed"
        }
    }

    public var symbolName: String {
        switch self {
        case .notStarted: return "circle"
        case .current: return "circle.inset.filled"
        case .complete: return "checkmark.circle.fill"
        case .needsAttention:
            return "exclamationmark.triangle.fill"
        case .optionalStage: return "circle.dashed"
        case .unavailable: return "minus.circle"
        case .failed: return "xmark.octagon.fill"
        }
    }

    public var colorRole: CaptureColorRole {
        switch self {
        case .notStarted, .optionalStage:
            return .secondary
        case .current:
            return .accent
        case .complete:
            return .success
        case .needsAttention:
            return .attention
        case .unavailable:
            return .unknown
        case .failed:
            return .blocked
        }
    }
}

/// Stable action identifiers the journey presentation recommends
/// (issue #372 JOURNEY-60). The view binds each id to its host
/// callback; the presentation itself never performs work.
public enum CaptureJourneyAction: String, Sendable, Equatable,
    CaseIterable
{
    case beginScanning
    case captureEvidenceFrame
    case endScanAndReview
    case openReviewWorkspace
    case reviewDiagnostics
    case continueScanning
    case addDetails
    case completeRequiredTasks
    case editSavedDetails
    case validateAndFinalize
    case prepareExport
    case sendToHTDT
    case shareArchive
    case inspectRetainedEvidence
    case exportDiagnostics
    case startNewCapture
    case rescanAsNewRevision
    case compareWithRevisedCapture
    case discardCapture
    case discardFailedCapture
    case deleteLocalCapture
    case importCaptureArchive
    case cancelStart
    case openCameraSettings
    case retryCameraPermission

    public enum Role: String, Sendable, Equatable {
        /// The one dominant workflow-advancing action of the stage.
        case primaryWorkflow
        /// Supporting workflow action (Continue scanning, Add details,
        /// Share) — rendered beside/under the primary.
        case secondaryWorkflow
        /// Opens an inspection/read-only surface.
        case inspect
        /// Destroys local data — always separated from workflow
        /// actions.
        case destructive
        /// Low-emphasis extra (cancel, retry).
        case overflow
    }

    public var role: Role {
        switch self {
        case .beginScanning, .endScanAndReview, .completeRequiredTasks,
             .validateAndFinalize, .prepareExport, .sendToHTDT,
             .startNewCapture:
            return .primaryWorkflow
        case .captureEvidenceFrame, .openReviewWorkspace,
             .continueScanning, .addDetails, .editSavedDetails,
             .shareArchive, .rescanAsNewRevision,
             .compareWithRevisedCapture, .importCaptureArchive:
            return .secondaryWorkflow
        case .reviewDiagnostics, .inspectRetainedEvidence,
             .exportDiagnostics:
            return .inspect
        case .discardCapture, .discardFailedCapture,
             .deleteLocalCapture:
            return .destructive
        case .cancelStart, .openCameraSettings,
             .retryCameraPermission:
            return .overflow
        }
    }

    public var titleKey: String {
        switch self {
        case .beginScanning: return "Begin scanning"
        case .captureEvidenceFrame: return "Capture evidence frame"
        case .endScanAndReview: return "End scan and review"
        case .openReviewWorkspace: return "Open review workspace"
        case .reviewDiagnostics: return "Review diagnostics"
        case .continueScanning: return "Continue scanning"
        case .addDetails: return "Add details"
        case .completeRequiredTasks: return "Complete required tasks"
        case .editSavedDetails:
            return "Edit saved annotations & measurements"
        case .validateAndFinalize: return "Validate and finalize"
        case .prepareExport: return "Prepare .htdtcapture"
        case .sendToHTDT: return "Send to HTDT…"
        case .shareArchive: return "Share .htdtcapture"
        case .inspectRetainedEvidence: return "Inspect retained evidence"
        case .exportDiagnostics: return "Export diagnostic package"
        case .startNewCapture: return "Start new capture"
        case .rescanAsNewRevision: return "Rescan as new revision"
        case .compareWithRevisedCapture:
            return "Compare with revised capture"
        case .discardCapture: return "Discard capture"
        case .discardFailedCapture: return "Discard failed capture"
        case .deleteLocalCapture: return "Delete local capture"
        case .importCaptureArchive: return "Import .htdtcapture"
        case .cancelStart: return "Cancel"
        case .openCameraSettings: return "Open Settings"
        case .retryCameraPermission: return "Check again"
        }
    }
}

/// Mission progress the journey header may surface (issue #372
/// JOURNEY-50): required-task completion is distinct from technical
/// capture readiness — a capture can be technically ready while the
/// plan's required tasks are still outstanding.
public struct CaptureJourneyMissionSummary: Sendable, Equatable {
    public let requiredTotal: Int
    public let requiredCompleted: Int

    public init(requiredTotal: Int, requiredCompleted: Int) {
        self.requiredTotal = requiredTotal
        self.requiredCompleted = requiredCompleted
    }

    public var outstanding: Int {
        max(0, requiredTotal - requiredCompleted)
    }
}

/// Technical readiness facts (issue #372 JOURNEY-50), surfaced as a
/// compact check list separate from mission progress.
public struct CaptureJourneyReadinessSummary: Sendable, Equatable {
    /// Bundle/evidence integrity preflight status: nil = not checked.
    public let integrityReady: Bool?
    /// Persisted spatial capture (RoomPlan/mesh/frames) exists.
    public let spatialCapturePersisted: Bool

    public init(
        integrityReady: Bool?,
        spatialCapturePersisted: Bool
    ) {
        self.integrityReady = integrityReady
        self.spatialCapturePersisted = spatialCapturePersisted
    }
}

/// Inputs the host supplies when resolving the journey presentation
/// (issue #372 JOURNEY-30). Every fact is already available on the
/// root view's public model — the presentation adds no persistence.
public struct CaptureJourneyInputs: Sendable, Equatable {
    public let state: CaptureState
    /// Operator-facing failure code when `state == .failed`.
    public let lastFailure: CaptureFailureCode?
    /// A finalized-quality report exists for the reviewing working set.
    public let hasQualityReport: Bool
    /// `qualityReport.readyForHTDTIngestion`.
    public let qualityReadyForIngestion: Bool
    /// `qualityReport.integrityStatus == .pass`.
    public let integrityPass: Bool
    /// `qualityReport.integrityStatus == .fail`.
    public let integrityFail: Bool
    /// The working set's spatial coordinate authority still exists —
    /// Continue scanning is a legal boundary transition.
    public let hasSpatialAuthority: Bool
    /// Annotation authority (entities/measurements) already committed.
    public let detailsCommitted: Bool
    /// Finalization has sealed the spatial capture (read-only detail
    /// editing only).
    public let spatialCaptureSealed: Bool
    /// Bundle validation report exists — the capture is finalized.
    public let hasValidationReport: Bool
    /// An export archive exists — the Send stage is actionable.
    public let hasExportArchive: Bool
    /// The finalized capture came from an imported archive only —
    /// earlier stages must not fake completion (issue #372).
    public let isImportedFinalized: Bool
    /// Mission progress; nil when no task plan is active.
    public let mission: CaptureJourneyMissionSummary?
    /// The stage that was active when the capture failed — kept so the
    /// failure surface preserves where the operator was.
    public let failedStageHint: CaptureJourneyStage?
    /// A camera permission denial is currently blocking Prepare.
    public let cameraPermissionDenied: Bool

    public init(
        state: CaptureState,
        lastFailure: CaptureFailureCode? = nil,
        hasQualityReport: Bool = false,
        qualityReadyForIngestion: Bool = false,
        integrityPass: Bool = false,
        integrityFail: Bool = false,
        hasSpatialAuthority: Bool = false,
        detailsCommitted: Bool = false,
        spatialCaptureSealed: Bool = false,
        hasValidationReport: Bool = false,
        hasExportArchive: Bool = false,
        isImportedFinalized: Bool = false,
        mission: CaptureJourneyMissionSummary? = nil,
        failedStageHint: CaptureJourneyStage? = nil,
        cameraPermissionDenied: Bool = false
    ) {
        self.state = state
        self.lastFailure = lastFailure
        self.hasQualityReport = hasQualityReport
        self.qualityReadyForIngestion = qualityReadyForIngestion
        self.integrityPass = integrityPass
        self.integrityFail = integrityFail
        self.hasSpatialAuthority = hasSpatialAuthority
        self.detailsCommitted = detailsCommitted
        self.spatialCaptureSealed = spatialCaptureSealed
        self.hasValidationReport = hasValidationReport
        self.hasExportArchive = hasExportArchive
        self.isImportedFinalized = isImportedFinalized
        self.mission = mission
        self.failedStageHint = failedStageHint
        self.cameraPermissionDenied = cameraPermissionDenied
    }
}

/// The resolved journey presentation (issue #372 JOURNEY-00): one
/// current stage, per-stage statuses, one dominant primary action, and
/// the compact copy the header shows. Pure value — derived from host
/// state, never persisted to the bundle.
public struct CaptureJourneyPresentation: Sendable, Equatable {
    public let currentStage: CaptureJourneyStage
    /// Ordered by `CaptureJourneyStage.allCases`; `.home` is the idle
    /// library and never appears in the trail.
    public let stageStatuses: [CaptureJourneyStageStatus]
    /// Transient in-stage progress ("Checking this device…") — when
    /// present the stage is not a destination.
    public let transientLabelKey: String?
    /// Short summary shown under the stage title in compact layout —
    /// e.g. "Scan complete" or "2 required tasks remaining".
    public let subtitleKey: String
    public let primaryAction: CaptureJourneyAction?
    public let secondaryActions: [CaptureJourneyAction]
    /// Concise reason the primary action is unavailable, when it is.
    public let primaryActionBlockedKey: String?
    public let mission: CaptureJourneyMissionSummary?
    public let readiness: CaptureJourneyReadinessSummary?
    /// True on the failure surface — the presentation preserves the
    /// stage the operator was in rather than resetting to Home.
    public let isFailed: Bool

    public init(
        currentStage: CaptureJourneyStage,
        stageStatuses: [CaptureJourneyStageStatus],
        transientLabelKey: String?,
        subtitleKey: String,
        primaryAction: CaptureJourneyAction?,
        secondaryActions: [CaptureJourneyAction],
        primaryActionBlockedKey: String?,
        mission: CaptureJourneyMissionSummary?,
        readiness: CaptureJourneyReadinessSummary?,
        isFailed: Bool
    ) {
        self.currentStage = currentStage
        self.stageStatuses = stageStatuses
        self.transientLabelKey = transientLabelKey
        self.subtitleKey = subtitleKey
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
        self.primaryActionBlockedKey = primaryActionBlockedKey
        self.mission = mission
        self.readiness = readiness
        self.isFailed = isFailed
    }

    public func status(for stage: CaptureJourneyStage) -> CaptureJourneyStageStatus {
        let index = CaptureJourneyStage.allCases.firstIndex(of: stage) ?? 0
        return stageStatuses[index]
    }

    // MARK: - Resolution

    public static func resolve(
        _ inputs: CaptureJourneyInputs
    ) -> CaptureJourneyPresentation {
        var statuses = [CaptureJourneyStageStatus](
            repeating: .notStarted,
            count: CaptureJourneyStage.allCases.count
        )
        func set(_ stage: CaptureJourneyStage, _ status: CaptureJourneyStageStatus) {
            statuses[
                CaptureJourneyStage.allCases.firstIndex(of: stage) ?? 0
            ] = status
        }

        let missionOutstanding = inputs.mission?.outstanding ?? 0
        let readiness = CaptureJourneyReadinessSummary(
            integrityReady: inputs.hasQualityReport
                ? inputs.integrityPass
                : nil,
            spatialCapturePersisted: inputs.hasQualityReport
        )

        switch inputs.state {
        case .idle:
            set(.home, .current)
            return CaptureJourneyPresentation(
                currentStage: .home,
                stageStatuses: statuses,
                transientLabelKey: nil,
                subtitleKey: "",
                primaryAction: .beginScanning,
                secondaryActions: [.importCaptureArchive],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: nil,
                isFailed: false
            )

        case .setup:
            set(.prepare, .current)
            return CaptureJourneyPresentation(
                currentStage: .prepare,
                stageStatuses: statuses,
                transientLabelKey: nil,
                subtitleKey: "",
                primaryAction: .beginScanning,
                secondaryActions: [.importCaptureArchive],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: nil,
                isFailed: false
            )

        case .capabilityCheck:
            set(.prepare, .current)
            return CaptureJourneyPresentation(
                currentStage: .prepare,
                stageStatuses: statuses,
                transientLabelKey: "Checking this device…",
                subtitleKey: "Checking this device…",
                primaryAction: nil,
                secondaryActions: [.cancelStart],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: nil,
                isFailed: false
            )

        case .permissions:
            set(.prepare, .current)
            return CaptureJourneyPresentation(
                currentStage: .prepare,
                stageStatuses: statuses,
                transientLabelKey: inputs.cameraPermissionDenied
                    ? nil
                    : "Camera access is needed",
                subtitleKey: inputs.cameraPermissionDenied
                    ? "Camera access is off"
                    : "Camera access is needed",
                primaryAction: inputs.cameraPermissionDenied
                    ? .openCameraSettings : nil,
                secondaryActions: inputs.cameraPermissionDenied
                    ? [.retryCameraPermission, .cancelStart]
                    : [.cancelStart],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: nil,
                isFailed: false
            )

        case .preparing:
            set(.prepare, .current)
            return CaptureJourneyPresentation(
                currentStage: .prepare,
                stageStatuses: statuses,
                transientLabelKey: "Preparing capture…",
                subtitleKey: "Preparing capture…",
                primaryAction: nil,
                secondaryActions: [],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: nil,
                isFailed: false
            )

        case .scanning:
            set(.prepare, .complete)
            set(.scan, .current)
            return CaptureJourneyPresentation(
                currentStage: .scan,
                stageStatuses: statuses,
                transientLabelKey: nil,
                subtitleKey: "",
                primaryAction: .endScanAndReview,
                secondaryActions: [.captureEvidenceFrame],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: nil,
                isFailed: false
            )

        case .reviewing:
            set(.prepare, .complete)
            set(.scan, .complete)
            set(.review, .current)
            set(
                .details,
                inputs.detailsCommitted
                    ? .complete : .optionalStage
            )
            set(.finalize, .notStarted)
            set(.send, .unavailable)

            var primary: CaptureJourneyAction
            var blocked: String? = nil
            var secondary: [CaptureJourneyAction] = []
            if inputs.integrityFail {
                // A blocking integrity/authority problem outranks every
                // workflow suggestion (issue #372 JOURNEY-60).
                primary = .reviewDiagnostics
            } else if missionOutstanding > 0 {
                primary = .completeRequiredTasks
            } else if !inputs.hasQualityReport {
                // Coverage/quality unknown: keep scanning is the honest
                // next step — finalize stays blocked until evidence is
                // evaluated.
                primary = inputs.hasSpatialAuthority
                    && !inputs.spatialCaptureSealed
                    ? .continueScanning : .openReviewWorkspace
                blocked = "Waiting for persisted evidence…"
            } else {
                primary = .validateAndFinalize
                if !inputs.qualityReadyForIngestion || !inputs.integrityPass {
                    blocked = "Resolve readiness before finalizing"
                }
            }
            // A rejected finalize keeps the spatial seal — Continue
            // scanning can never run, so the row must not offer it.
            if inputs.hasSpatialAuthority, !inputs.spatialCaptureSealed,
               primary != .continueScanning {
                secondary.append(.continueScanning)
            }
            secondary.append(
                inputs.detailsCommitted ? .editSavedDetails : .addDetails
            )
            secondary.append(.openReviewWorkspace)

            let subtitle: String
            if missionOutstanding > 0 {
                subtitle = String(
                    format: String(
                        localized: "%lld required tasks remaining"
                    ),
                    missionOutstanding
                )
            } else {
                subtitle = String(localized: "Scan complete")
            }
            return CaptureJourneyPresentation(
                currentStage: .review,
                stageStatuses: statuses,
                transientLabelKey: nil,
                subtitleKey: subtitle,
                primaryAction: primary,
                secondaryActions: secondary,
                primaryActionBlockedKey: blocked,
                mission: inputs.mission,
                readiness: readiness,
                isFailed: false
            )

        case .annotating:
            set(.prepare, .complete)
            set(.scan, .complete)
            set(.review, .complete)
            set(.details, .current)
            set(.send, .unavailable)
            return CaptureJourneyPresentation(
                currentStage: .details,
                stageStatuses: statuses,
                transientLabelKey: nil,
                subtitleKey: "Scan complete",
                primaryAction: nil,
                secondaryActions: [],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: readiness,
                isFailed: false
            )

        case .validating:
            set(.prepare, .complete)
            set(.scan, .complete)
            set(.review, .complete)
            set(
                .details,
                inputs.detailsCommitted
                    ? .complete : .optionalStage
            )
            set(.finalize, .current)
            return CaptureJourneyPresentation(
                currentStage: .finalize,
                stageStatuses: statuses,
                transientLabelKey: "Validating capture…",
                subtitleKey: "Validating capture…",
                primaryAction: nil,
                secondaryActions: [],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: readiness,
                isFailed: false
            )

        case .finalized:
            if inputs.isImportedFinalized {
                // Imported finalized archive: earlier stages are
                // unknown lineage — never fake a checked trail.
                for stage in CaptureJourneyStage.allCases
                where stage != .finalize && stage != .send {
                    set(stage, .unavailable)
                }
            } else {
                set(.prepare, .complete)
                set(.scan, .complete)
                set(.review, .complete)
                set(
                    .details,
                    inputs.detailsCommitted
                        ? .complete : .optionalStage
                )
            }
            set(.finalize, .complete)
            set(.send, inputs.hasExportArchive ? .current : .notStarted)
            return CaptureJourneyPresentation(
                currentStage: inputs.hasExportArchive ? .send : .finalize,
                stageStatuses: statuses,
                transientLabelKey: nil,
                subtitleKey: inputs.isImportedFinalized
                    ? String(localized: "Imported finalized capture")
                    : "",
                primaryAction: inputs.hasExportArchive
                    ? .sendToHTDT : .prepareExport,
                secondaryActions: inputs.hasExportArchive
                    ? [.shareArchive, .rescanAsNewRevision]
                    : [.rescanAsNewRevision],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: readiness,
                isFailed: false
            )

        case .exported:
            set(.prepare, .complete)
            set(.scan, .complete)
            set(.review, .complete)
            set(
                .details,
                inputs.detailsCommitted
                    ? .complete : .optionalStage
            )
            set(.finalize, .complete)
            set(.send, .current)
            return CaptureJourneyPresentation(
                currentStage: .send,
                stageStatuses: statuses,
                transientLabelKey: nil,
                subtitleKey: "Ready to send",
                primaryAction: .sendToHTDT,
                secondaryActions: [
                    .shareArchive, .rescanAsNewRevision,
                ],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: readiness,
                isFailed: false
            )

        case .failed:
            let failedStage = inputs.failedStageHint
                ?? Self.defaultFailedStage(
                    for: inputs.lastFailure,
                    hasWorkingSet: inputs.hasQualityReport
                        || inputs.hasSpatialAuthority
                )
            // Preserve the stage the failure interrupted: completed
            // stages keep their truth, the interrupted stage fails in
            // place, later stages are unavailable — never silently
            // reset to Home (issue #372 JOURNEY-70).
            for stage in CaptureJourneyStage.allCases {
                if stage == .home { continue }
                if stage < failedStage {
                    set(stage, .complete)
                } else if stage == failedStage {
                    set(stage, .failed)
                } else {
                    set(stage, .unavailable)
                }
            }
            return CaptureJourneyPresentation(
                currentStage: failedStage,
                stageStatuses: statuses,
                transientLabelKey: nil,
                subtitleKey: String(
                    localized: "Capture interrupted"
                ),
                primaryAction: .inspectRetainedEvidence,
                secondaryActions: [
                    .exportDiagnostics, .startNewCapture,
                ],
                primaryActionBlockedKey: nil,
                mission: inputs.mission,
                readiness: readiness,
                isFailed: true
            )
        }
    }

    /// Failure stage inference when the host does not supply a hint:
    /// pre-scan failures belong to Prepare, everything else that kept
    /// a working set interrupted the Scan.
    private static func defaultFailedStage(
        for failure: CaptureFailureCode?,
        hasWorkingSet: Bool
    ) -> CaptureJourneyStage {
        switch failure {
        case .permissionDenied, .unsupportedDevice:
            return .prepare
        case .interrupted, .trackingUnavailable, .roomPlanFailure,
             .storagePressure, .thermalPressure, .persistenceFailure,
             .unknown, nil:
            return hasWorkingSet ? .review : .scan
        }
    }

    /// Required-task mission progress for the journey header (issue
    /// #372 JOURNEY-50). The same typed fulfillment rules
    /// `CaptureTaskPlanStatus.itemOutcomes` applies. `status` lets
    /// the caller evaluate against the live operator-edited status
    /// (marks, bindings, fulfillments); nil falls back to a fresh
    /// status computed from committed records alone, which can only
    /// understate completion. Returns nil when no required items
    /// exist.
    public static func missionSummary(
        plan: HTDTCaptureTaskPlan,
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        authorities: TheaterAuthorityCollection = .empty,
        committedEvidenceRefs: [String] = [],
        status: CaptureTaskPlanStatus? = nil
    ) -> CaptureJourneyMissionSummary? {
        let resolvedStatus: CaptureTaskPlanStatus
        if let status {
            resolvedStatus = status
        } else {
            guard let data = try? JSONEncoder().encode(plan),
                  let planImport = try? CaptureTaskPlanImport(
                      data: data
                  )
            else { return nil }
            resolvedStatus = CaptureTaskPlanStatus(
                planImport: planImport
            )
        }
        let outcomes = resolvedStatus
            .itemOutcomes(
                annotations: annotations,
                measurements: measurements,
                authorities: authorities,
                committedEvidenceRefs: committedEvidenceRefs
            )
        let requiredIDs = Set(
            plan.entityChecklist
                .filter { $0.requirement == .required }.map(\.itemID)
                + plan.measurementRequests
                .filter { $0.requirement == .required }.map(\.itemID)
                + plan.surfaceReviewTasks
                .filter { $0.requirement == .required }.map(\.itemID)
                + plan.semanticTasks
                .filter { $0.requirement == .required }.map(\.itemID)
                + plan.evidenceTasks
                .filter { $0.requirement == .required }.map(\.itemID)
        )
        guard !requiredIDs.isEmpty else { return nil }
        let completed = outcomes.filter {
            requiredIDs.contains($0.itemID)
                && $0.outcome == .completed
        }.count
        return CaptureJourneyMissionSummary(
            requiredTotal: requiredIDs.count,
            requiredCompleted: completed
        )
    }
}
