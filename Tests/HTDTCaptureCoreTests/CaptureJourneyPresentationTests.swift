import Foundation
import Testing
@testable import HTDTCaptureCore

/// Issue #372: the loop-aware journey presentation maps every
/// `CaptureState` onto one stage, picks a single dominant action, and
/// keeps stage statuses truthful.
struct CaptureJourneyPresentationTests {

    private func resolve(
        _ inputs: CaptureJourneyInputs
    ) -> CaptureJourneyPresentation {
        CaptureJourneyPresentation.resolve(inputs)
    }

    private func status(
        _ presentation: CaptureJourneyPresentation,
        _ stage: CaptureJourneyStage
    ) -> CaptureJourneyStageStatus {
        presentation.status(for: stage)
    }

    @Test func idleIsHome() {
        let p = resolve(.init(state: .idle))
        #expect(p.currentStage == .home)
        #expect(p.primaryAction == .beginScanning)
        #expect(p.secondaryActions == [.importCaptureArchive])
        #expect(status(p, .prepare) == .notStarted)
        #expect(!p.isFailed)
    }

    @Test func capabilityCheckIsPrepareTransient() {
        let p = resolve(.init(state: .capabilityCheck))
        #expect(p.currentStage == .prepare)
        #expect(status(p, .prepare) == .current)
        #expect(p.transientLabelKey != nil)
        #expect(p.primaryAction == nil)
        #expect(p.secondaryActions == [.cancelStart])
    }

    @Test func deniedPermissionOffersSettings() {
        let p = resolve(
            .init(
                state: .permissions,
                cameraPermissionDenied: true
            )
        )
        #expect(p.currentStage == .prepare)
        #expect(p.primaryAction == .openCameraSettings)
        #expect(
            p.secondaryActions == [
                .retryCameraPermission, .cancelStart,
            ]
        )
        #expect(p.transientLabelKey == nil)
    }

    @Test func scanningIsScanStage() {
        let p = resolve(.init(state: .scanning))
        #expect(p.currentStage == .scan)
        #expect(status(p, .prepare) == .complete)
        #expect(status(p, .scan) == .current)
        #expect(p.primaryAction == .endScanAndReview)
        #expect(p.secondaryActions == [.captureEvidenceFrame])
    }

    @Test func integrityFailureOutranksEverything() {
        let p = resolve(
            .init(
                state: .reviewing,
                hasQualityReport: true,
                integrityFail: true,
                hasSpatialAuthority: true,
                mission: CaptureJourneyMissionSummary(
                    requiredTotal: 3,
                    requiredCompleted: 1
                )
            )
        )
        #expect(p.currentStage == .review)
        #expect(p.primaryAction == .reviewDiagnostics)
    }

    @Test func outstandingMissionOutranksCoverage() {
        let p = resolve(
            .init(
                state: .reviewing,
                hasQualityReport: true,
                qualityReadyForIngestion: true,
                integrityPass: true,
                hasSpatialAuthority: true,
                mission: CaptureJourneyMissionSummary(
                    requiredTotal: 9,
                    requiredCompleted: 7
                )
            )
        )
        #expect(p.primaryAction == .completeRequiredTasks)
        #expect(p.secondaryActions.contains(.continueScanning))
    }

    @Test func unknownCoverageKeepsScanning() {
        let p = resolve(
            .init(
                state: .reviewing,
                hasSpatialAuthority: true
            )
        )
        #expect(p.primaryAction == .continueScanning)
        #expect(p.primaryActionBlockedKey != nil)
        #expect(p.secondaryActions.contains(.openReviewWorkspace))
    }

    @Test func reviewStageStatuses() {
        let p = resolve(
            .init(
                state: .reviewing,
                hasQualityReport: true,
                qualityReadyForIngestion: true,
                integrityPass: true,
                hasSpatialAuthority: true,
                detailsCommitted: true
            )
        )
        #expect(p.primaryAction == .validateAndFinalize)
        #expect(p.primaryActionBlockedKey == nil)
        #expect(status(p, .prepare) == .complete)
        #expect(status(p, .scan) == .complete)
        #expect(status(p, .review) == .current)
        #expect(status(p, .details) == .complete)
        #expect(status(p, .finalize) == .notStarted)
        #expect(status(p, .send) == .unavailable)
    }

    @Test func finalizeBlockedUntilReady() {
        let p = resolve(
            .init(
                state: .reviewing,
                hasQualityReport: true,
                qualityReadyForIngestion: false,
                integrityPass: false
            )
        )
        #expect(p.primaryAction == .validateAndFinalize)
        #expect(p.primaryActionBlockedKey != nil)
    }

    @Test func annotatingIsDetailsStage() {
        let p = resolve(.init(state: .annotating))
        #expect(p.currentStage == .details)
        #expect(status(p, .details) == .current)
        #expect(status(p, .review) == .complete)
    }

    @Test func finalizedWithArchiveIsSendStage() {
        let p = resolve(
            .init(
                state: .finalized,
                hasValidationReport: true,
                hasExportArchive: true
            )
        )
        #expect(p.currentStage == .send)
        #expect(status(p, .finalize) == .complete)
        #expect(status(p, .send) == .current)
        #expect(p.primaryAction == .sendToHTDT)
        #expect(p.secondaryActions.contains(.shareArchive))
        #expect(p.secondaryActions.contains(.rescanAsNewRevision))
    }

    @Test func adoptedFinalizedFakesNoEarlierStages() {
        let p = resolve(
            .init(
                state: .finalized,
                hasValidationReport: true,
                isImportedFinalized: true
            )
        )
        #expect(p.currentStage == .finalize)
        #expect(p.primaryAction == .prepareExport)
        #expect(status(p, .prepare) == .unavailable)
        #expect(status(p, .scan) == .unavailable)
        #expect(status(p, .review) == .unavailable)
        #expect(status(p, .finalize) == .complete)
        #expect(status(p, .send) == .notStarted)
    }

    @Test func exportedIsSendCurrent() {
        let p = resolve(.init(state: .exported))
        #expect(p.currentStage == .send)
        #expect(status(p, .send) == .current)
        #expect(p.primaryAction == .sendToHTDT)
    }

    @Test func permissionFailureFailsPrepare() {
        let p = resolve(
            .init(
                state: .failed,
                lastFailure: .permissionDenied
            )
        )
        #expect(p.isFailed)
        #expect(p.currentStage == .prepare)
        #expect(status(p, .prepare) == .failed)
        #expect(status(p, .scan) == .unavailable)
        #expect(status(p, .send) == .unavailable)
        #expect(p.primaryAction == .inspectRetainedEvidence)
    }

    @Test func midCaptureFailurePreservesStage() {
        let p = resolve(
            .init(
                state: .failed,
                lastFailure: .interrupted,
                hasQualityReport: true
            )
        )
        #expect(p.currentStage == .review)
        #expect(status(p, .review) == .failed)
        #expect(status(p, .prepare) == .complete)
        #expect(status(p, .finalize) == .unavailable)
    }

    @Test func stageOrdering() {
        #expect(CaptureJourneyStage.prepare < .scan)
        #expect(CaptureJourneyStage.scan < .review)
        #expect(CaptureJourneyStage.details < .finalize)
        #expect(CaptureJourneyStage.finalize < .send)
    }
}

/// Issue #372 JOURNEY-50: mission progress is evaluated from the plan
/// plus committed records — separate from technical readiness.
struct CaptureJourneyMissionTests {

    private func makePlan(
        requiredEntityItems: Int,
        optionalEntityItems: Int = 0
    ) throws -> HTDTCaptureTaskPlan {
        var items: [HTDTTaskPlanEntityItem] = []
        for i in 0..<requiredEntityItems {
            items.append(
                try HTDTTaskPlanEntityItem(
                    itemID: "req-\(i)",
                    entityType: .referencePoint,
                    requirement: .required
                )
            )
        }
        for i in 0..<optionalEntityItems {
            items.append(
                try HTDTTaskPlanEntityItem(
                    itemID: "opt-\(i)",
                    entityType: .seat,
                    requirement: .optional
                )
            )
        }
        return try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1.0",
            projectRef: "proj-1",
            roomName: "Theater",
            entityChecklist: items
        )
    }

    private func makeEntity(
        type: AnnotationEntityType = .referencePoint,
        label: String = "Ref"
    ) throws -> CaptureAnnotationEntity {
        try CaptureAnnotationEntity(
            type: type,
            coordinateSpaceID: CoordinateSpaceID(),
            worldFromAnnotation: try Matrix4x4F(values: [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                1, 0, 1, 1,
            ]),
            referencePointSemantics:
                ReferencePointSemanticsCatalog.forType(type),
            label: label,
            verificationState: .userAttested,
            placement: PlacementProvenance(method: .manualNumeric)
        )
    }

    @Test func requiredCountsOnlyRequiredItems() throws {
        let plan = try makePlan(
            requiredEntityItems: 2,
            optionalEntityItems: 1
        )
        let mission = try #require(
            CaptureJourneyPresentation.missionSummary(
                plan: plan,
                annotations: [],
                measurements: []
            )
        )
        #expect(mission.requiredTotal == 2)
        #expect(mission.requiredCompleted == 0)
        #expect(mission.outstanding == 2)
    }

    @Test func matchingEntityCompletesItem() throws {
        let plan = try makePlan(requiredEntityItems: 1)
        let mission = try #require(
            CaptureJourneyPresentation.missionSummary(
                plan: plan,
                annotations: [try makeEntity()],
                measurements: []
            )
        )
        #expect(mission.requiredTotal == 1)
        #expect(mission.requiredCompleted == 1)
        #expect(mission.outstanding == 0)
    }

    @Test func noRequiredItemsMeansNoMission() throws {
        let plan = try makePlan(
            requiredEntityItems: 0,
            optionalEntityItems: 1
        )
        #expect(
            CaptureJourneyPresentation.missionSummary(
                plan: plan,
                annotations: [],
                measurements: []
            ) == nil
        )
    }
}
