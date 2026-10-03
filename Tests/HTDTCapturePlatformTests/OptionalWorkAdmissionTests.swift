import Foundation
import HTDTCaptureCore
import Testing
@testable import HTDTCapturePlatform

private func health(
    thermal: ProcessInfo.ThermalState = .nominal,
    storage: CaptureStoragePressureTracker.State = .healthy,
    memoryPressure: Bool = false,
    interrupted: Bool = false,
    persistenceBacklog: Bool = false,
    renderingMitigation: Bool = false,
    tracking: TrackingQualityState? = nil,
    depthAbsent: Bool? = nil
) -> CaptureHealthSnapshot {
    CaptureHealthSnapshot(
        thermalState: thermal,
        storageBand: storage,
        memoryPressureActive: memoryPressure,
        interruptionActive: interrupted,
        persistenceBacklogActive: persistenceBacklog,
        renderingMitigationActive: renderingMitigation,
        latestTrackingState: tracking,
        sceneDepthRecentlyAbsent: depthAbsent
    )
}

private let assist = OptionalWorkload(
    identifier: "test_assist",
    workloadClass: .activeAssist
)
private let assistEssential = OptionalWorkload(
    identifier: "test_assist_essential",
    workloadClass: .activeAssist,
    benchmarkedEssentialAssist: true
)
private let semanticShot = OptionalWorkload(
    identifier: "test_semantic_shot",
    workloadClass: .optionalSemantic
)
private let semanticPeriodic = OptionalWorkload(
    identifier: "test_semantic_periodic",
    workloadClass: .optionalSemantic,
    execution: .periodic
)
private let semanticContinuous = OptionalWorkload(
    identifier: "test_semantic_continuous",
    workloadClass: .optionalSemantic,
    execution: .continuous
)
private let language = OptionalWorkload(
    identifier: "test_language",
    workloadClass: .optionalLanguage
)
private let criticalWork = OptionalWorkload(
    identifier: "test_capture_critical",
    workloadClass: .captureCritical
)

// MARK: - Pressure derivation (legacy bolph71656-ai/HTDT-Capture#273)

@Test
func nominalHealthIsNominal() {
    #expect(health().pressureState == .nominal)
}

@Test
func thermalBandsMapMonotonically() {
    #expect(health(thermal: .fair).pressureState == .elevated)
    #expect(health(thermal: .serious).pressureState == .serious)
    #expect(health(thermal: .critical).pressureState == .critical)
}

@Test
func storageBandsMap() {
    #expect(health(storage: .warning).pressureState == .elevated)
    #expect(health(storage: .critical).pressureState == .critical)
    // Undetermined capacity is not proof of headroom (legacy bolph71656-ai/HTDT-Capture#181).
    #expect(health(storage: .undetermined).pressureState == .elevated)
}

@Test
func memoryWarningAndInterruptionAreSerious() {
    #expect(health(memoryPressure: true).pressureState == .serious)
    #expect(health(interrupted: true).pressureState == .serious)
}

@Test
func backlogAndMitigationAreElevated() {
    #expect(health(persistenceBacklog: true).pressureState == .elevated)
    #expect(health(renderingMitigation: true).pressureState == .elevated)
}

@Test
func trackingQualityMaps() {
    #expect(health(tracking: .normal).pressureState == .nominal)
    #expect(health(tracking: .limited).pressureState == .elevated)
    #expect(health(tracking: .unavailable).pressureState == .serious)
}

@Test
func absentExpectedDepthIsElevated() {
    #expect(health(depthAbsent: true).pressureState == .elevated)
    #expect(health(depthAbsent: false).pressureState == .nominal)
    #expect(health(depthAbsent: nil).pressureState == .nominal)
}

@Test
func worstSignalWins() {
    let combined = health(
        thermal: .fair,
        storage: .healthy,
        memoryPressure: true,
        tracking: .limited,
        depthAbsent: true
    )
    #expect(combined.pressureState == .serious)
}

// MARK: - Phase decision table (legacy bolph71656-ai/HTDT-Capture#273 Stage 1 rules)

@Test
func captureCriticalIsNeverGated() {
    for phase in OptionalWorkPhase.allCases {
        for thermal: ProcessInfo.ThermalState in [.nominal, .critical] {
            let decision = OptionalWorkAdmissionPolicy.decision(
                for: criticalWork,
                in: phase,
                health: health(thermal: thermal)
            )
            #expect(decision == .allow)
        }
    }
}

@Test
func criticalPressureRejectsAllOptionalWork() {
    let criticalHealth = health(thermal: .critical)
    for workload in [assist, semanticShot, language] {
        for phase in OptionalWorkPhase.allCases {
            let decision = OptionalWorkAdmissionPolicy.decision(
                for: workload,
                in: phase,
                health: criticalHealth
            )
            #expect(decision == .reject(.pressureCritical))
        }
    }
}

@Test
func inactivePhaseDefersOptionalWork() {
    for workload in [assist, semanticShot, language] {
        let decision = OptionalWorkAdmissionPolicy.decision(
            for: workload,
            in: .inactive,
            health: health()
        )
        #expect(decision == .defer(.captureInactive))
    }
}

@Test
func finalizationRejectsSpeculativeWork() {
    for workload in [assist, semanticShot, language] {
        let decision = OptionalWorkAdmissionPolicy.decision(
            for: workload,
            in: .finalizationOrExport,
            health: health()
        )
        #expect(decision == .reject(.phaseProhibited))
    }
}

@Test
func roomScanProhibitsContinuousOptionalWork() {
    let decision = OptionalWorkAdmissionPolicy.decision(
        for: semanticContinuous,
        in: .roomScan,
        health: health()
    )
    #expect(decision == .reject(.phaseProhibited))
    let continuousLanguage = OptionalWorkload(
        identifier: "fm_continuous",
        workloadClass: .optionalLanguage,
        execution: .continuous
    )
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: continuousLanguage,
            in: .roomScan,
            health: health()
        ) == .reject(.phaseProhibited)
    )
}

@Test
func roomScanAdmitsBoundedSemanticOnlyAtNominal() {
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: semanticShot,
            in: .roomScan,
            health: health()
        ) == .allow
    )
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: semanticPeriodic,
            in: .roomScan,
            health: health(thermal: .fair)
        ) == .defer(.pressureElevated)
    )
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: semanticShot,
            in: .roomScan,
            health: health(thermal: .serious)
        ) == .reject(.pressureSerious)
    )
}

@Test
func roomScanDefersLanguageWorkToReview() {
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: language,
            in: .roomScan,
            health: health()
        ) == .defer(.phaseDeferred)
    )
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: language,
            in: .roomScan,
            health: health(thermal: .serious)
        ) == .reject(.pressureSerious)
    )
}

@Test
func targetPhaseAllowsAssistDefersUnrelatedWork() {
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: assist,
            in: .targetOrMeasurement,
            health: health()
        ) == .allow
    )
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: semanticShot,
            in: .targetOrMeasurement,
            health: health()
        ) == .defer(.phaseDeferred)
    )
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: language,
            in: .targetOrMeasurement,
            health: health()
        ) == .defer(.phaseDeferred)
    )
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: semanticContinuous,
            in: .targetOrMeasurement,
            health: health()
        ) == .reject(.phaseProhibited)
    )
}

@Test
func reviewPhaseIsPreferredForSemanticAndLanguage() {
    for workload in [semanticShot, semanticPeriodic,
                     semanticContinuous, language]
    {
        #expect(
            OptionalWorkAdmissionPolicy.decision(
                for: workload,
                in: .reviewAnnotation,
                health: health()
            ) == .allow
        )
        #expect(
            OptionalWorkAdmissionPolicy.decision(
                for: workload,
                in: .reviewAnnotation,
                health: health(thermal: .fair)
            ) == .defer(.pressureElevated)
        )
        #expect(
            OptionalWorkAdmissionPolicy.decision(
                for: workload,
                in: .reviewAnnotation,
                health: health(thermal: .serious)
            ) == .reject(.pressureSerious)
        )
    }
}

@Test
func assistSlotAndInFlightGuardsGateAdmission() {
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: assist,
            in: .roomScan,
            health: health(),
            activeAssistOccupied: true
        ) == .defer(.activeAssistOccupied)
    )
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: assist,
            in: .reviewAnnotation,
            health: health(),
            requestInFlight: true
        ) == .defer(.requestInFlight)
    )
}

@Test
func nonEssentialAssistDefersUnderSeriousPressure() {
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: assist,
            in: .roomScan,
            health: health(thermal: .serious)
        ) == .defer(.pressureSerious)
    )
    #expect(
        OptionalWorkAdmissionPolicy.decision(
            for: assistEssential,
            in: .roomScan,
            health: health(thermal: .serious)
        ) == .allow
    )
}

// MARK: - In-flight actions

@Test
func elevatedSuspendsSustainedWorkKeepsOneShots() {
    #expect(
        OptionalWorkAdmissionPolicy.inflightAction(
            for: semanticPeriodic,
            pressure: .elevated
        ) == .suspend
    )
    #expect(
        OptionalWorkAdmissionPolicy.inflightAction(
            for: semanticContinuous,
            pressure: .elevated
        ) == .suspend
    )
    #expect(
        OptionalWorkAdmissionPolicy.inflightAction(
            for: semanticShot,
            pressure: .elevated
        ) == .continueWork
    )
}

@Test
func seriousCancelsOneShotsSuspendsSustainedKeepsEssential() {
    #expect(
        OptionalWorkAdmissionPolicy.inflightAction(
            for: semanticShot,
            pressure: .serious
        ) == .cancel
    )
    #expect(
        OptionalWorkAdmissionPolicy.inflightAction(
            for: semanticPeriodic,
            pressure: .serious
        ) == .suspend
    )
    #expect(
        OptionalWorkAdmissionPolicy.inflightAction(
            for: assist,
            pressure: .serious
        ) == .cancel
    )
    #expect(
        OptionalWorkAdmissionPolicy.inflightAction(
            for: assistEssential,
            pressure: .serious
        ) == .continueWork
    )
}

@Test
func criticalCancelsEveryOptionalWorkload() {
    for workload in [assist, assistEssential, semanticShot,
                     semanticPeriodic, semanticContinuous, language]
    {
        #expect(
            OptionalWorkAdmissionPolicy.inflightAction(
                for: workload,
                pressure: .critical
            ) == .cancel
        )
    }
    #expect(
        OptionalWorkAdmissionPolicy.inflightAction(
            for: criticalWork,
            pressure: .critical
        ) == .continueWork
    )
}

// MARK: - Tracker lifecycle

@Test
func beginRegistersTicketAndBlocksSecondRequest() {
    var tracker = OptionalWorkAdmissionTracker()
    let ticket = tracker.begin(
        assist,
        phase: .roomScan,
        health: health()
    ).ticket
    #expect(ticket != nil)
    #expect(ticket.map { tracker.isCurrent($0) } == true)
    #expect(tracker.activeAssistIdentifier == "test_assist")

    // The feature-owned one-in-flight guard: a second begin defers.
    let second = tracker.begin(
        assist,
        phase: .roomScan,
        health: health()
    ).ticket
    #expect(second == nil)
    #expect(
        tracker.outcomes["test_assist"]?.deferredCount == 1
    )
}

@Test
func singleAssistSlotIsEnforcedAcrossWorkloads() {
    var tracker = OptionalWorkAdmissionTracker()
    let ticket = tracker.begin(
        assist,
        phase: .reviewAnnotation,
        health: health()
    ).ticket
    #expect(ticket != nil)

    let second = tracker.begin(
        assistEssential,
        phase: .reviewAnnotation,
        health: health()
    ).ticket
    #expect(second == nil)

    // Finishing frees the slot.
    _ = tracker.finish(ticket!, outcome: .completed)
    #expect(tracker.activeAssistIdentifier == nil)
    let retried = tracker.begin(
        assistEssential,
        phase: .reviewAnnotation,
        health: health()
    ).ticket
    #expect(retried != nil)
}

@Test
func finishRecordsOutcomeAndLatency() {
    var tracker = OptionalWorkAdmissionTracker()
    let ticket = tracker.begin(
        assist,
        phase: .reviewAnnotation,
        health: health()
    ).ticket!
    let finished = tracker.finish(
        ticket,
        outcome: .completed,
        latencySeconds: 1.5
    )
    #expect(finished)
    #expect(!tracker.isCurrent(ticket))
    // A stale or double finish must not corrupt the ledger.
    let refinish = tracker.finish(ticket, outcome: .completed)
    #expect(!refinish)

    let aggregate = tracker.outcomes["test_assist"]
    #expect(aggregate?.admittedCount == 1)
    #expect(aggregate?.completedCount == 1)
    #expect(aggregate?.latencySampleCount == 1)
    #expect(aggregate?.maximumLatencySeconds == 1.5)
}

@Test
func deferredBeginLeavesNoTicket() {
    var tracker = OptionalWorkAdmissionTracker()
    let ticket = tracker.begin(
        language,
        phase: .roomScan,
        health: health()
    ).ticket
    #expect(ticket == nil)
    #expect(tracker.activeAssistIdentifier == nil)
    let aggregate = tracker.outcomes["test_language"]
    #expect(aggregate?.deferredCount == 1)
    #expect(aggregate?.admittedCount == 0)
}

@Test
func identicalPeriodicDecisionsCompactInLog() {
    var tracker = OptionalWorkAdmissionTracker()
    for _ in 0 ..< 5 {
        _ = tracker.evaluate(
            semanticPeriodic,
            phase: .roomScan,
            health: health()
        )
    }
    let admissionRecords = tracker.log.filter {
        $0.kind == .admission
    }
    #expect(admissionRecords.count == 1)
    #expect(admissionRecords.first?.outcome == "allow")
    // Evaluation counters still accumulate every attempt.
    #expect(tracker.outcomes["test_semantic_periodic"]?.admittedCount == 5)
}

@Test
func pressureTransitionEmitsNewRecord() {
    var tracker = OptionalWorkAdmissionTracker()
    _ = tracker.evaluate(
        semanticPeriodic,
        phase: .roomScan,
        health: health()
    )
    _ = tracker.evaluate(
        semanticPeriodic,
        phase: .roomScan,
        health: health(thermal: .fair)
    )
    let records = tracker.log.filter { $0.kind == .admission }
    #expect(records.count == 2)
    #expect(records.last?.outcome == "defer")
    #expect(records.last?.reason == .pressureElevated)
    #expect(records.last?.pressure == .elevated)
}

@Test
func inflightActionsOrderAndApply() {
    var tracker = OptionalWorkAdmissionTracker()
    let assistTicket = tracker.begin(
        assist,
        phase: .reviewAnnotation,
        health: health()
    ).ticket!
    let semanticTicket = tracker.begin(
        semanticShot,
        phase: .reviewAnnotation,
        health: health()
    ).ticket!

    let serious = tracker.inflightActions(
        health: health(thermal: .serious)
    )
    #expect(serious.count == 2)
    // Admission order is preserved.
    #expect(serious[0].ticket == assistTicket)
    #expect(serious[1].ticket == semanticTicket)
    #expect(serious[0].action == .cancel)
    #expect(serious[1].action == .cancel)

    let nominal = tracker.inflightActions(health: health())
    #expect(nominal.allSatisfy { $0.action == .continueWork })
}

@Test
func suspendAndResumeTransitionInLog() {
    var tracker = OptionalWorkAdmissionTracker()
    let ticket = tracker.begin(
        semanticPeriodic,
        phase: .roomScan,
        health: health()
    ).ticket!
    tracker.suspend(ticket, pressure: .elevated)
    // Suspending is idempotent; the slot still blocks re-admission.
    tracker.suspend(ticket, pressure: .elevated)
    tracker.resume(ticket)

    let kinds = tracker.log.map(\.kind)
    #expect(kinds.filter { $0 == .suspended }.count == 1)
    #expect(kinds.filter { $0 == .resumed }.count == 1)
}

@Test
func cancelRemovesInFlightAndCountsOutcome() {
    var tracker = OptionalWorkAdmissionTracker()
    let ticket = tracker.begin(
        semanticShot,
        phase: .reviewAnnotation,
        health: health()
    ).ticket!
    let cancelled = tracker.cancel(ticket, pressure: .serious)
    #expect(cancelled)
    #expect(!tracker.isCurrent(ticket))
    let recancel = tracker.cancel(ticket, pressure: .serious)
    #expect(recancel == false)
    #expect(
        tracker.outcomes["test_semantic_shot"]?.cancelledCount == 1
    )
}

@Test
func decisionLogIsBounded() {
    var tracker = OptionalWorkAdmissionTracker()
    var healthState = health()
    // Distinct decisions keep emitting; the log must stay bounded.
    for index in 0 ..< (OptionalWorkAdmissionTracker.logLimit * 2) {
        healthState.memoryPressureActive = index % 2 == 0
        _ = tracker.evaluate(
            OptionalWorkload(
                identifier: "bounded_\(index)",
                workloadClass: .optionalSemantic
            ),
            phase: .reviewAnnotation,
            health: healthState
        )
    }
    #expect(tracker.log.count == OptionalWorkAdmissionTracker.logLimit)
    #expect(tracker.logTruncatedCount > 0)
    // Distinct-workload outcomes are bounded too — overflow folds
    // into the shared bucket.
    #expect(
        tracker.outcomes.count
            <= OptionalWorkAdmissionTracker.outcomeWorkloadLimit + 1
    )
}

@Test
func phaseMappingFromCaptureState() {
    #expect(
        OptionalWorkPhase(
            state: .scanning,
            measurementTaskActive: false
        ) == .roomScan
    )
    #expect(
        OptionalWorkPhase(
            state: .scanning,
            measurementTaskActive: true
        ) == .targetOrMeasurement
    )
    #expect(
        OptionalWorkPhase(state: .reviewing) == .reviewAnnotation
    )
    #expect(
        OptionalWorkPhase(state: .annotating) == .reviewAnnotation
    )
    #expect(
        OptionalWorkPhase(state: .validating) == .finalizationOrExport
    )
    #expect(
        OptionalWorkPhase(state: .finalized) == .finalizationOrExport
    )
    #expect(
        OptionalWorkPhase(state: .exported) == .finalizationOrExport
    )
    #expect(OptionalWorkPhase(state: .idle) == .inactive)
    #expect(OptionalWorkPhase(state: .setup) == .inactive)
    #expect(OptionalWorkPhase(state: .failed) == .inactive)
    #expect(OptionalWorkPhase(state: .preparing) == .inactive)
}

@Test
func registeredWorkloadsMatchIssueAuditBounds() {
    // legacy bolph71656-ai/HTDT-Capture#273 audit: the workloads the repo owns plus the ones sibling
    // issues declare — bounded ones are one-shot/periodic, only
    // reference tracking and the Core AI prototype are continuous.
    let registry: [OptionalWorkload] = [
        .derivedShapePreview, .equipmentLabelScan,
        .targetedObjectPass, .highResolutionFrameEvidence,
        .sourceQualityPreflight, .visionSegmentation,
        .stationaryReferenceDetection, .referenceObjectTracking,
        .coreAIPrototype, .foundationModelsSession,
    ]
    let continuous = registry.filter {
        $0.execution == .continuous
    }
    #expect(
        continuous.map(\.identifier).sorted()
            == ["core_ai_prototype", "reference_object_tracking"]
    )
    let identifiers = registry.map(\.identifier)
    #expect(Set(identifiers).count == identifiers.count)
}
