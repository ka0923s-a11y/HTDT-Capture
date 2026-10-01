import Foundation

/// The operator-visible recovery contract (issue #437): every
/// capture-terminal surface resolves a plain-language reason plus a
/// typed, ordered set of next steps. Stable action ids — the view
/// binds each to a real host action; nothing here is decorative.
///
/// All strings are development-language keys; AppShell resolves them
/// through `Localizable.strings` for Japanese.

/// The reason a finalize attempt was rejected and the capture stayed
/// in Review — typed so the surface can name the specific step that
/// failed and the specific recovery path instead of only a status
/// line.
public enum CaptureFinalizeRejection: String, Sendable, Equatable {
    /// Device was critically hot — transient; retry after cooling.
    case deferredThermal
    /// Free storage was critically low — transient; retry after
    /// freeing space.
    case deferredStorage
    /// Review quality regressed between Review and the attempt.
    case qualityRegression
    /// The commit was aborted and rolled back — the working revision
    /// stayed in Review, mutable.
    case commitRejected
}

/// The reason an export attempt was rejected while the finalized
/// revision stayed intact.
public enum CaptureExportRejection: String, Sendable, Equatable {
    /// The archive destination could not be prepared.
    case destinationUnavailable
    /// A stale/corrupt archive at the destination blocked rebuilding
    /// and could not be removed.
    case staleArchiveBlocked
    /// The archive write or post-write validation itself failed.
    case exportFailed
}

/// A stable action id offered on a capture-terminal recovery surface.
/// The view binds each to a real coordinator/AppShell action — an
/// action that has no working handler is never emitted by the
/// resolver.
public enum CaptureRecoveryAction:
    String, Sendable, Equatable, CaseIterable
{
    /// Preserve the failed end-accepted working set as a recoverable
    /// draft and reopen it into sealed Review.
    case resumeFailedAsDraft
    /// Preserve the failed working set as a recoverable draft without
    /// reopening it — it stays listed on Home.
    case keepFailedAsDraft
    /// Reopen a recoverable draft into sealed Review.
    case resumeDraft
    /// Permanently discard a recoverable draft's working data.
    case discardDraft
    /// Re-run the rejected finalize attempt from Review.
    case retryFinalize
    /// Open the annotation/Details workspace — the concrete
    /// remediation path when the commit rejected promotion for
    /// findings or a quality regression.
    case openAnnotations
    /// Leave Review keeping the draft ("Save and finish later").
    case saveDraftAndFinishLater
    /// Inspect the failed capture's retained working set.
    case inspectRetainedEvidence
    /// Write/share the failed-capture diagnostic package.
    case exportDiagnostics
    /// Retry the archive export from the finalized revision.
    case retryExport
    /// Discard the failed capture's retained data and begin a fresh
    /// capture.
    case discardAndStartNew
    /// Discard the failed capture's retained data.
    case discardFailedCapture
    /// Discard the unfinalized working revision (scan/review).
    case discardCapture
    /// Delete the finalized local capture.
    case deleteLocalCapture
    /// Begin a fresh capture.
    case startNewCapture
    /// Open iOS Settings so the operator can restore camera access.
    case openCameraSettings
    /// Re-check camera permission.
    case retryCameraPermission
}

/// Display emphasis for one recovery step.
public enum CaptureRecoveryStepRole: String, Sendable, Equatable {
    /// The recommended next step — rendered as the primary control.
    case primary
    /// A real alternative action.
    case secondary
    /// An irreversible action — rendered destructive.
    case destructive
    /// Instruction text only — `action` is nil, renders as guidance.
    case guidance
}

/// One ordered step in a capture-terminal recovery contract.
public struct CaptureRecoveryStep: Sendable, Equatable {
    /// Imperative label — button title or guidance line.
    public let titleKey: String
    /// Optional qualifier — consequence, cost, or pre-condition.
    public let detailKey: String?
    /// Stable action id the view binds to a host call; nil on
    /// guidance steps.
    public let action: CaptureRecoveryAction?
    public let role: CaptureRecoveryStepRole

    public init(
        titleKey: String,
        detailKey: String? = nil,
        action: CaptureRecoveryAction?,
        role: CaptureRecoveryStepRole
    ) {
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.action = action
        self.role = role
    }
}

/// The resolved failure-surface contract: which step failed in
/// operator vocabulary, a plain-language reason, what is still true,
/// and the ordered next-step set.
public struct CaptureRecoveryPlan: Sendable, Equatable {
    /// Headline for the surface — names what failed plainly.
    public let titleKey: String
    /// Plain-language reason for the failure.
    public let reasonKey: String
    /// What stays true / what is no longer possible — e.g. whether
    /// the captured data survives as a resumable draft.
    public let detailKey: String?
    /// Ordered steps; the first action-bearing step is the
    /// recommended path.
    public let steps: [CaptureRecoveryStep]

    public init(
        titleKey: String,
        reasonKey: String,
        detailKey: String? = nil,
        steps: [CaptureRecoveryStep]
    ) {
        self.titleKey = titleKey
        self.reasonKey = reasonKey
        self.detailKey = detailKey
        self.steps = steps
    }
}

/// Resolves the failure → recovery contract (#437). Pure value
/// mapping so the "what do I do next?" logic stays unit-testable.
public enum CaptureRecoveryPresentation {

    /// The terminal `.failed` surface. `draftRecoverable` is true
    /// only when the failed working set's durable End boundary
    /// committed — i.e. the working revision can be preserved as a
    /// recoverable draft that reopens into sealed Review. A
    /// mid-scan failure leaves `liveScanIncomplete` data that can
    /// never be resumed, and the plan says so plainly.
    public static func failedPlan(
        failure: CaptureFailureCode,
        draftRecoverable: Bool
    ) -> CaptureRecoveryPlan {
        let titleKey: String
        let reasonKey: String
        switch failure {
        case .permissionDenied:
            titleKey = "Camera access is required"
            reasonKey =
                "Camera access was denied, so the capture could not continue."
        case .unsupportedDevice:
            titleKey = "This device cannot run the capture"
            reasonKey =
                "This device does not support the RoomPlan capture workflow."
        case .trackingUnavailable:
            titleKey = "The scan was interrupted"
            reasonKey =
                "Camera tracking was lost and could not recover, so the scan could not finish."
        case .roomPlanFailure:
            titleKey = "The room model could not be captured"
            reasonKey =
                "The room-model engine failed before the scan could finish."
        case .storagePressure:
            titleKey = "The capture could not be saved — storage is full"
            reasonKey =
                "The device ran out of free storage while the capture was being saved."
        case .persistenceFailure:
            titleKey = "The capture could not be saved"
            reasonKey =
                "The capture data could not be written to storage."
        case .thermalPressure:
            titleKey = "The device overheated"
            reasonKey =
                "The device became critically hot, so the capture was stopped."
        case .interrupted:
            titleKey = "The capture was interrupted"
            reasonKey =
                "The capture session was interrupted — by an app switch, a call, or the app closing."
        case .unknown:
            titleKey = "The capture failed"
            reasonKey =
                "The capture stopped for an unexpected reason."
        }

        let detailKey: String
        if draftRecoverable {
            detailKey =
                "The captured data was saved as a draft. Reopen it to finish the capture — the scan is sealed, so you cannot continue scanning."
        } else {
            detailKey =
                "The scan did not finish, so this data cannot be resumed. It can only be inspected, exported as diagnostics, or discarded."
        }

        let steps: [CaptureRecoveryStep]
        switch failure {
        case .permissionDenied:
            steps = [
                CaptureRecoveryStep(
                    titleKey: "Open Settings",
                    action: .openCameraSettings,
                    role: .primary
                ),
                CaptureRecoveryStep(
                    titleKey: "Check camera access again",
                    action: .retryCameraPermission,
                    role: .secondary
                ),
                CaptureRecoveryStep(
                    titleKey: "Discard the failed capture",
                    detailKey:
                        "Permanently removes the data this attempt kept.",
                    action: .discardFailedCapture,
                    role: .destructive
                ),
            ]
        case .unsupportedDevice:
            steps = [
                CaptureRecoveryStep(
                    titleKey: "Export a diagnostic package",
                    detailKey:
                        "Shares the retained data with support for analysis.",
                    action: .exportDiagnostics,
                    role: .primary
                ),
                CaptureRecoveryStep(
                    titleKey: "Inspect the saved data",
                    action: .inspectRetainedEvidence,
                    role: .secondary
                ),
                CaptureRecoveryStep(
                    titleKey: "Discard the failed capture",
                    detailKey:
                        "Permanently removes the data this attempt kept.",
                    action: .discardFailedCapture,
                    role: .destructive
                ),
            ]
        default:
            if draftRecoverable {
                steps = [
                    CaptureRecoveryStep(
                        titleKey: "Reopen the draft and finish",
                        detailKey:
                            "Continues in Review — annotations and finalize work, resuming the scan does not.",
                        action: .resumeFailedAsDraft,
                        role: .primary
                    ),
                    CaptureRecoveryStep(
                        titleKey: "Keep the draft for later",
                        detailKey:
                            "The draft stays listed on Home under recoverable drafts.",
                        action: .keepFailedAsDraft,
                        role: .secondary
                    ),
                    CaptureRecoveryStep(
                        titleKey: "Inspect the saved data",
                        action: .inspectRetainedEvidence,
                        role: .secondary
                    ),
                    CaptureRecoveryStep(
                        titleKey: "Export a diagnostic package",
                        detailKey:
                            "Shares the retained data with support for analysis.",
                        action: .exportDiagnostics,
                        role: .secondary
                    ),
                    CaptureRecoveryStep(
                        titleKey: "Discard and start a new capture",
                        detailKey:
                            "Permanently removes the failed capture's data.",
                        action: .discardAndStartNew,
                        role: .destructive
                    ),
                ]
            } else {
                var list: [CaptureRecoveryStep] = [
                    CaptureRecoveryStep(
                        titleKey: "Inspect the saved data",
                        action: .inspectRetainedEvidence,
                        role: .primary
                    ),
                    CaptureRecoveryStep(
                        titleKey: "Export a diagnostic package",
                        detailKey:
                            "Shares the retained data with support for analysis.",
                        action: .exportDiagnostics,
                        role: .secondary
                    ),
                ]
                if failure == .storagePressure {
                    list.append(
                        CaptureRecoveryStep(
                            titleKey:
                                "Free device storage, then start a new capture",
                            action: nil,
                            role: .guidance
                        )
                    )
                }
                list.append(
                    CaptureRecoveryStep(
                        titleKey: "Discard and start a new capture",
                        detailKey:
                            "Permanently removes the data this attempt kept.",
                        action: .discardAndStartNew,
                        role: .destructive
                    )
                )
                list.append(
                    CaptureRecoveryStep(
                        titleKey: "Discard the failed capture",
                        detailKey:
                            "Permanently removes the data this attempt kept.",
                        action: .discardFailedCapture,
                        role: .destructive
                    )
                )
                steps = list
            }
        }

        return CaptureRecoveryPlan(
            titleKey: titleKey,
            reasonKey: reasonKey,
            detailKey: detailKey,
            steps: steps
        )
    }

    /// The `.reviewing` surface after a rejected finalize attempt —
    /// the capture stayed mutable, so the plan names the rejection
    /// and offers the retry/save/discard path.
    public static func finalizeRejectedPlan(
        _ rejection: CaptureFinalizeRejection
    ) -> CaptureRecoveryPlan {
        let titleKey = "The capture could not be saved"
        let reasonKey: String
        var guidance: CaptureRecoveryStep?
        switch rejection {
        case .deferredThermal:
            reasonKey =
                "Saving was deferred because the device is critically hot."
            guidance = CaptureRecoveryStep(
                titleKey: "Let the device cool, then retry",
                action: nil,
                role: .guidance
            )
        case .deferredStorage:
            reasonKey =
                "Saving was deferred because free storage is critically low."
            guidance = CaptureRecoveryStep(
                titleKey: "Free storage, then retry",
                action: nil,
                role: .guidance
            )
        case .qualityRegression:
            // Live spatial capture is sealed on every finalize
            // rejection — non-spatial findings can still be corrected
            // in Details, but spatial findings leave retry/save-draft/
            // discard as the honest options.
            reasonKey =
                "Review quality changed before finalization — non-spatial findings can still be corrected in Details; otherwise retry, save the draft, or discard."
        case .commitRejected:
            reasonKey =
                "The save was aborted and rolled back — the capture stays in Review unchanged."
        }

        var steps: [CaptureRecoveryStep] = []
        if let guidance {
            steps.append(guidance)
        }
        switch rejection {
        case .qualityRegression, .commitRejected:
            // Findings or a regression blocked the commit — the
            // concrete fix is resolving them in the annotation
            // workspace before retrying.
            steps.append(
                CaptureRecoveryStep(
                    titleKey:
                        "Open Details and resolve the findings",
                    detailKey:
                        "Opens the annotation workspace to correct the flagged items — spatial capture is sealed, so findings needing more scanning can only be retried, deferred, or discarded.",
                    action: .openAnnotations,
                    role: .primary
                )
            )
            steps.append(
                CaptureRecoveryStep(
                    titleKey: "Retry saving",
                    detailKey:
                        "Runs validation and finalization again — the capture is unchanged.",
                    action: .retryFinalize,
                    role: .secondary
                )
            )
        case .deferredThermal, .deferredStorage:
            steps.append(
                CaptureRecoveryStep(
                    titleKey: "Retry saving",
                    detailKey:
                        "Runs validation and finalization again — the capture is unchanged.",
                    action: .retryFinalize,
                    role: .primary
                )
            )
        }
        steps.append(
            CaptureRecoveryStep(
                titleKey: "Save the draft and finish later",
                detailKey:
                    "The draft stays listed on Home under recoverable drafts.",
                action: .saveDraftAndFinishLater,
                role: .secondary
            )
        )
        steps.append(
            CaptureRecoveryStep(
                titleKey: "Discard the capture",
                detailKey:
                    "Permanently removes the unfinalized data.",
                action: .discardCapture,
                role: .destructive
            )
        )

        return CaptureRecoveryPlan(
            titleKey: titleKey,
            reasonKey: reasonKey,
            detailKey:
                "The capture stays in Review — its data is not lost.",
            steps: steps
        )
    }

    /// The `.finalized` surface after a rejected export — only the
    /// transport step failed; the finalized revision is durable.
    public static func exportRejectedPlan(
        _ rejection: CaptureExportRejection
    ) -> CaptureRecoveryPlan {
        let titleKey = "The export archive could not be created"
        let reasonKey: String
        switch rejection {
        case .destinationUnavailable:
            reasonKey =
                "The archive destination could not be prepared — the finalized capture is preserved."
        case .staleArchiveBlocked:
            reasonKey =
                "A stale export archive blocks rebuilding and could not be removed — the finalized capture is unchanged."
        case .exportFailed:
            reasonKey =
                "The .htdtcapture archive could not be written — the finalized capture is preserved."
        }

        return CaptureRecoveryPlan(
            titleKey: titleKey,
            reasonKey: reasonKey,
            detailKey:
                "Only the export step failed — the finalized capture itself is intact.",
            steps: [
                CaptureRecoveryStep(
                    titleKey: "Retry export",
                    action: .retryExport,
                    role: .primary
                ),
                CaptureRecoveryStep(
                    titleKey: "Start a new capture",
                    detailKey:
                        "Leaves this capture saved and begins a fresh one.",
                    action: .startNewCapture,
                    role: .secondary
                ),
                CaptureRecoveryStep(
                    titleKey: "Delete this capture",
                    detailKey:
                        "Permanently removes the finalized capture and its data.",
                    action: .deleteLocalCapture,
                    role: .destructive
                ),
            ]
        )
    }

    /// The persistent stranded-draft indicator for Home and setup:
    /// a capture ended or was interrupted before it could be saved,
    /// and its draft is discoverable with the same next-step
    /// affordances.
    public static func strandedDraftPlan(
        draftCount: Int
    ) -> CaptureRecoveryPlan {
        CaptureRecoveryPlan(
            titleKey: "Interrupted capture",
            reasonKey:
                "A capture ended or was interrupted before it was saved. Its data is kept as a draft.",
            detailKey:
                "Reopening restores Review — you can finish annotations and save, but you cannot resume scanning.",
            steps: [
                CaptureRecoveryStep(
                    titleKey: "Resume the draft",
                    action: .resumeDraft,
                    role: .primary
                ),
                CaptureRecoveryStep(
                    titleKey: "Discard the draft",
                    detailKey:
                        "Permanently removes the draft's saved data.",
                    action: .discardDraft,
                    role: .destructive
                ),
            ]
        )
    }
}
