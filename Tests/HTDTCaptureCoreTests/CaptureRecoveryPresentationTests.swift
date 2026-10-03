import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue bolph71656-ai/HTDT-Capture#437: the capture-terminal failure → recovery contract is a
/// pure value mapping — every failure surface resolves a plain-language
/// reason plus a typed, ordered, fully-bound set of next steps. These
/// tests pin the mapping itself so no surface can offer a dead or
/// unexplained path.
final class CaptureRecoveryPresentationTests: XCTestCase {

    private let allFailures: [CaptureFailureCode] = [
        .permissionDenied,
        .unsupportedDevice,
        .trackingUnavailable,
        .roomPlanFailure,
        .storagePressure,
        .persistenceFailure,
        .thermalPressure,
        .interrupted,
        .unknown,
    ]

    // MARK: - Contract invariants

    /// Every plan: non-empty copy, at least one actionable step, the
    /// first action-bearing step is primary, guidance steps never
    /// carry an action, non-guidance steps always do (no dead
    /// controls).
    private func assertWellFormed(
        _ plan: CaptureRecoveryPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(plan.titleKey.isEmpty, file: file, line: line)
        XCTAssertFalse(plan.reasonKey.isEmpty, file: file, line: line)
        XCTAssertFalse(plan.steps.isEmpty, file: file, line: line)
        for step in plan.steps {
            XCTAssertFalse(
                step.titleKey.isEmpty,
                "a step with no copy reached the surface",
                file: file, line: line
            )
            if step.role == .guidance {
                XCTAssertNil(
                    step.action,
                    "guidance step '\(step.titleKey)' carries a control",
                    file: file, line: line
                )
            } else {
                XCTAssertNotNil(
                    step.action,
                    "action step '\(step.titleKey)' has no handler — a dead control",
                    file: file, line: line
                )
            }
        }
        let firstActionIndex = plan.steps.firstIndex {
            $0.action != nil
        }
        XCTAssertNotNil(firstActionIndex, file: file, line: line)
        if let firstActionIndex {
            XCTAssertEqual(
                plan.steps[firstActionIndex].role, .primary,
                "the recommended path is not marked primary",
                file: file, line: line
            )
            XCTAssertEqual(
                plan.steps[..<firstActionIndex].filter {
                    $0.action != nil
                }.count,
                0,
                file: file, line: line
            )
        }
        // Destructive steps come last — the recovery path leads.
        if let firstDestructive = plan.steps.firstIndex(
            where: { $0.role == .destructive }
        ), let lastNonDestructive = plan.steps.lastIndex(
            where: { $0.role != .destructive }
        ) {
            XCTAssertLessThan(
                firstDestructive, plan.steps.count,
                file: file, line: line
            )
            XCTAssertLessThan(
                lastNonDestructive, firstDestructive,
                "a non-destructive step follows a destructive one",
                file: file, line: line
            )
        }
    }

    private func actions(
        in plan: CaptureRecoveryPlan
    ) -> [CaptureRecoveryAction] {
        plan.steps.compactMap(\.action)
    }

    // MARK: - The `.failed` surface

    func testFailedPlanRecoverableOffersResumeKeepAndDiscard() {
        for failure in allFailures {
            let plan = CaptureRecoveryPresentation.failedPlan(
                failure: failure,
                draftRecoverable: true
            )
            switch failure {
            case .permissionDenied, .unsupportedDevice:
                // These two have their own dominant recovery —
                // covered by dedicated tests below.
                continue
            default:
                assertWellFormed(plan)
                XCTAssertEqual(
                    plan.steps.first?.action, .resumeFailedAsDraft,
                    "\(failure): a resumable draft leads with resume"
                )
                XCTAssertTrue(
                    actions(in: plan).contains(.keepFailedAsDraft),
                    "\(failure)"
                )
                XCTAssertTrue(
                    actions(in: plan).contains(.discardAndStartNew),
                    "\(failure)"
                )
                XCTAssertTrue(
                    plan.detailKey?.contains("draft") == true,
                    "\(failure): the copy must say the data survives"
                )
            }
        }
    }

    func testFailedPlanNonRecoverableNeverOffersResume() {
        for failure in allFailures {
            let plan = CaptureRecoveryPresentation.failedPlan(
                failure: failure,
                draftRecoverable: false
            )
            assertWellFormed(plan)
            XCTAssertFalse(
                actions(in: plan).contains(.resumeFailedAsDraft),
                "\(failure): resume offered for non-resumable data"
            )
            XCTAssertFalse(
                actions(in: plan).contains(.keepFailedAsDraft),
                "\(failure)"
            )
            XCTAssertTrue(
                actions(in: plan).contains(.inspectRetainedEvidence)
                    || failure == .permissionDenied
                    || failure == .unsupportedDevice,
                "\(failure): no way to see what was kept"
            )
            XCTAssertTrue(
                actions(in: plan).contains(.discardAndStartNew)
                    || failure == .permissionDenied
                    || failure == .unsupportedDevice,
                "\(failure): no path to a fresh capture"
            )
        }
    }

    func testFailedPlanStoragePressureExplainsStorage() {
        let plan = CaptureRecoveryPresentation.failedPlan(
            failure: .storagePressure,
            draftRecoverable: false
        )
        assertWellFormed(plan)
        XCTAssertTrue(
            plan.steps.contains {
                $0.role == .guidance
                    && $0.titleKey.localizedCaseInsensitiveContains(
                        "storage"
                    )
            },
            "a storage failure must teach the free-and-retry path"
        )
    }

    func testFailedPlanPermissionDeniedLeadsToSettings() {
        let plan = CaptureRecoveryPresentation.failedPlan(
            failure: .permissionDenied,
            draftRecoverable: false
        )
        assertWellFormed(plan)
        XCTAssertEqual(
            plan.steps.first?.action, .openCameraSettings
        )
        XCTAssertTrue(
            actions(in: plan).contains(.retryCameraPermission)
        )
    }

    func testFailedPlanUnsupportedDeviceLeadsToDiagnostics() {
        let plan = CaptureRecoveryPresentation.failedPlan(
            failure: .unsupportedDevice,
            draftRecoverable: false
        )
        assertWellFormed(plan)
        XCTAssertEqual(
            plan.steps.first?.action, .exportDiagnostics
        )
    }

    func testFailedPlanAlwaysNamesTheFailedStep() {
        for failure in allFailures {
            let plan = CaptureRecoveryPresentation.failedPlan(
                failure: failure,
                draftRecoverable: false
            )
            XCTAssertFalse(
                plan.titleKey.isEmpty
                    || plan.reasonKey.isEmpty,
                "\(failure): the surface must name what failed"
            )
        }
    }

    // MARK: - Finalize rejection (.reviewing)

    func testFinalizeRejectionPlansAreWellFormed() {
        for rejection: CaptureFinalizeRejection in [
            .deferredThermal, .deferredStorage,
            .qualityRegression, .commitRejected,
        ] {
            assertWellFormed(
                CaptureRecoveryPresentation.finalizeRejectedPlan(
                    rejection
                )
            )
        }
    }

    func testDeferredRejectionGuidesThenRetries() {
        let thermal = CaptureRecoveryPresentation
            .finalizeRejectedPlan(.deferredThermal)
        XCTAssertEqual(
            thermal.steps.first?.role, .guidance,
            "a thermal deferral must say the device needs to cool"
        )
        XCTAssertTrue(
            actions(in: thermal).contains(.retryFinalize)
        )
        let storage = CaptureRecoveryPresentation
            .finalizeRejectedPlan(.deferredStorage)
        XCTAssertTrue(
            storage.steps.contains {
                $0.role == .guidance
                    && $0.titleKey.localizedCaseInsensitiveContains(
                        "storage"
                    )
            }
        )
    }

    func testFindingsRejectionLeadsWithTheWorkspace() {
        for rejection in [
            CaptureFinalizeRejection.qualityRegression,
            .commitRejected,
        ] {
            let plan = CaptureRecoveryPresentation
                .finalizeRejectedPlan(rejection)
            XCTAssertEqual(
                plan.steps.first?.action, .openAnnotations,
                "\(rejection): the concrete fix is resolving findings"
            )
        }
    }

    func testFinalizeRejectionAlwaysOffersSaveAndDiscard() {
        for rejection in [
            CaptureFinalizeRejection.deferredThermal,
            .deferredStorage,
            .qualityRegression,
            .commitRejected,
        ] {
            let offered = actions(
                in: CaptureRecoveryPresentation
                    .finalizeRejectedPlan(rejection)
            )
            XCTAssertTrue(
                offered.contains(.saveDraftAndFinishLater),
                "\(rejection)"
            )
            XCTAssertTrue(
                offered.contains(.discardCapture),
                "\(rejection)"
            )
        }
    }

    // MARK: - Export rejection (.finalized)

    func testExportRejectionPlansAreWellFormed() {
        for rejection: CaptureExportRejection in [
            .destinationUnavailable,
            .staleArchiveBlocked,
            .exportFailed,
        ] {
            assertWellFormed(
                CaptureRecoveryPresentation.exportRejectedPlan(
                    rejection
                )
            )
        }
    }

    func testExportRejectionLeadsWithRetryAndStatesDurability() {
        for rejection in [
            CaptureExportRejection.destinationUnavailable,
            .staleArchiveBlocked,
            .exportFailed,
        ] {
            let plan = CaptureRecoveryPresentation
                .exportRejectedPlan(rejection)
            XCTAssertEqual(
                plan.steps.first?.action, .retryExport,
                "\(rejection): retry is the recommended path"
            )
            XCTAssertTrue(
                plan.reasonKey.contains("finalized")
                    || (plan.detailKey?.contains("finalized")
                        ?? false),
                "\(rejection): the copy must say the capture survives"
            )
        }
    }

    // MARK: - Home notice ordering (legacy bolph71656-ai/HTDT-Capture#437)

    func testInterruptedCaptureNoticeLeadsTheList() {
        let notices = CaptureHomePresentation.notices(
            cameraPermissionDenied: true,
            cameraPermissionRestricted: false,
            deviceCaptureEligible: false,
            storageReadiness: .critical,
            maintenanceItemCount: 1,
            recoverableDraftCount: 2
        )
        XCTAssertEqual(
            notices.first, .interruptedCapture(draftCount: 2),
            "a stranded draft is the first thing Home must answer"
        )
    }

    func testInterruptedCaptureNoticeNeedsADraft() {
        let notices = CaptureHomePresentation.notices(
            cameraPermissionDenied: false,
            cameraPermissionRestricted: false,
            deviceCaptureEligible: true,
            storageReadiness: .sufficient,
            maintenanceItemCount: 0,
            recoverableDraftCount: 0
        )
        XCTAssertFalse(
            notices.contains {
                if case .interruptedCapture = $0 { return true }
                return false
            }
        )
    }

    // MARK: - Action exhaustiveness

    /// Every action id the resolver can emit stays in the enum — a
    /// renaming that drops a binding fails here before the surface
    /// renders a dead control.
    func testEveryEmittedActionResolvesToAKnownCase() {
        for failure in allFailures {
            for recoverable in [true, false] {
                let plan = CaptureRecoveryPresentation.failedPlan(
                    failure: failure,
                    draftRecoverable: recoverable
                )
                for step in plan.steps where step.action != nil {
                    XCTAssertTrue(
                        CaptureRecoveryAction.allCases.contains(
                            step.action!
                        ),
                        "\(failure): \(step.action!)"
                    )
                }
            }
        }
    }
}
