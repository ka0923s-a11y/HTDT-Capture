import Foundation
import HTDTCaptureCore

/// Stage 1 optional-work admission/degradation policy (issue #273).
///
/// Optional Vision / Core AI / Foundation Models / reference-object /
/// high-quality-visual work must never degrade authoritative
/// RoomPlan/ARKit/depth/persistence capture on iPhone 17 Pro. The
/// existing authorities keep their roles: `CaptureResourceMonitor`
/// owns thermal/storage/memory/background pressure and
/// `SharedARSessionController` owns the live shared AR session,
/// rendering, and resource policy. This file adds only the smallest
/// missing coordination — a phase-aware
/// `canStart(workload, phase, captureHealth) -> allow | defer | reject`
/// decision plus a bounded in-flight ledger — not a generic job
/// scheduler and not a second capture-resource state machine.
///
/// Priority order enforced by the decision table (highest first):
///   1. AR coordinate continuity / tracking health
///   2. RoomPlan / reconstruction / sceneDepth evidence
///   3. canonical evidence writes / persistence / finalization
///   4. operator-critical UI
///   5. the explicit current measurement/evidence task
///   6. optional Vision/Core AI semantic work
///   7. Foundation Models explanation/guidance
///
/// A generalized queued scheduler is only justified if physical
/// profiling (see docs/OPTIONAL_WORK_ADMISSION.md) demonstrates
/// contention these phase/admission rules cannot handle.

/// Minimal workload classes (#273). These are policy values, not a
/// task-orchestration DSL.
public enum OptionalWorkloadClass:
    String, Codable, Sendable, Equatable, CaseIterable
{
    /// AR lifecycle, required depth/mesh/frame evidence, RoomPlan,
    /// canonical persistence/finalization. Admission is always
    /// allowed — the class exists so a call site can classify
    /// uniformly without a special case.
    case captureCritical = "capture_critical"
    /// One operator-requested task that directly supports the current
    /// measurement/evidence step (high-res label frame, one-shot
    /// segmentation, calibrated-marker tracking, targeted object
    /// pass). At most one is admitted at a time.
    case activeAssist = "active_assist"
    /// Core AI discovery/prototype work and other optional semantic
    /// analysis (Vision segmentation, derived-shape fusion,
    /// reference-object work).
    case optionalSemantic = "optional_semantic"
    /// Foundation Models identity enrichment / copilot. Prefers
    /// review-time execution.
    case optionalLanguage = "optional_language"
}

/// Execution bound of an optional workload. Continuous (full-rate,
/// streaming) work is the class most likely to contend with live
/// capture, so phase rules treat it strictly.
public enum OptionalWorkExecution:
    String, Codable, Sendable, Equatable, CaseIterable
{
    /// A single bounded request/operation.
    case oneShot = "one_shot"
    /// Repeated bounded evaluations on a budgeted cadence (e.g. the
    /// fused derived-shape preview, stationary reference-object
    /// detection). Each evaluation is small, but the work is
    /// sustained — pressure sheds it like continuous work.
    case periodic
    /// Full-rate/streaming work (e.g. `trackingObjects` at frame
    /// rate). Rejected during live capture phases.
    case continuous
}

/// One optional workload as the admission policy sees it. Features
/// declare a stable identifier once; the policy decides admission from
/// class + execution + phase + capture health.
public struct OptionalWorkload: Sendable, Equatable {
    /// Stable machine identifier used in instrumentation, e.g.
    /// `derived_shape_preview`.
    public let identifier: String
    public let workloadClass: OptionalWorkloadClass
    public let execution: OptionalWorkExecution
    /// True only for an active assist whose retention under `serious`
    /// pressure is justified by the iPhone 17 Pro benchmark (#273
    /// physical gate). Defaults to false — no assist may claim this
    /// before device evidence exists.
    public let benchmarkedEssentialAssist: Bool

    public init(
        identifier: String,
        workloadClass: OptionalWorkloadClass,
        execution: OptionalWorkExecution = .oneShot,
        benchmarkedEssentialAssist: Bool = false
    ) {
        precondition(
            !identifier.isEmpty,
            "optional workload identifier must be non-empty"
        )
        precondition(
            workloadClass == .activeAssist || !benchmarkedEssentialAssist,
            "benchmarkedEssentialAssist only applies to activeAssist"
        )
        self.identifier = identifier
        self.workloadClass = workloadClass
        self.execution = execution
        self.benchmarkedEssentialAssist = benchmarkedEssentialAssist
    }
}

/// Stable identifiers for the optional workloads the repo owns today
/// and the ones Stage 1 reserves for the issues this policy was
/// audited against (#268–#275). A feature binds one constant once;
/// identifiers must remain stable across releases so persisted
/// admission notes stay interpretable.
extension OptionalWorkload {
    /// Live fused derived-shape preview evaluated on a bounded cadence
    /// during scanning — the pre-#273 `derivedWorkAllowed` gate's
    /// workload.
    public static let derivedShapePreview = OptionalWorkload(
        identifier: "derived_shape_preview",
        workloadClass: .optionalSemantic,
        execution: .periodic
    )
    /// #345 operator-requested Vision OCR/barcode label scan during
    /// annotation — a bounded one-shot assist.
    public static let equipmentLabelScan = OptionalWorkload(
        identifier: "equipment_label_scan",
        workloadClass: .activeAssist
    )
    /// #239/#314 equipment-identity close-up photo during annotation —
    /// a bounded high-quality visual request.
    public static let identityPhotoCapture = OptionalWorkload(
        identifier: "identity_photo_capture",
        workloadClass: .activeAssist
    )
    /// #314 field-evidence close-up photo during annotation — a
    /// bounded high-quality visual request.
    public static let fieldEvidencePhotoCapture = OptionalWorkload(
        identifier: "field_evidence_photo_capture",
        workloadClass: .activeAssist
    )
    /// #250 operator-targeted object orbit pass — the explicit
    /// current measurement task.
    public static let targetedObjectPass = OptionalWorkload(
        identifier: "targeted_object_pass",
        workloadClass: .activeAssist
    )
    /// #275 bounded high-resolution AR visual evidence — one request
    /// in flight, owned by that feature.
    public static let highResolutionFrameEvidence = OptionalWorkload(
        identifier: "high_resolution_frame_evidence",
        workloadClass: .activeAssist
    )
    /// #277 bounded source-quality preflight (one/few stable
    /// samples).
    public static let sourceQualityPreflight = OptionalWorkload(
        identifier: "source_quality_preflight",
        workloadClass: .activeAssist
    )
    /// #269 explicit keyframe/on-demand Vision segmentation.
    public static let visionSegmentation = OptionalWorkload(
        identifier: "vision_segmentation",
        workloadClass: .optionalSemantic
    )
    /// #268 stationary reference-object detection — preferred over
    /// full-rate tracking wherever the use case permits.
    public static let stationaryReferenceDetection = OptionalWorkload(
        identifier: "stationary_reference_detection",
        workloadClass: .optionalSemantic,
        execution: .periodic
    )
    /// #268 full-rate `trackingObjects` reference tracking — the one
    /// potentially continuous optional workload in the audit; rejected
    /// while live capture runs.
    public static let referenceObjectTracking = OptionalWorkload(
        identifier: "reference_object_tracking",
        workloadClass: .optionalSemantic,
        execution: .continuous
    )
    /// #271 Core AI perception prototype — starts on-demand at
    /// review time.
    public static let coreAIPrototype = OptionalWorkload(
        identifier: "core_ai_prototype",
        workloadClass: .optionalSemantic,
        execution: .continuous
    )
    /// #270/#272 Foundation Models identity enrichment / copilot —
    /// fresh task-scoped sessions, preferred at review time.
    public static let foundationModelsSession = OptionalWorkload(
        identifier: "foundation_models_session",
        workloadClass: .optionalLanguage
    )
}

/// The capture phase an admission request is made in. Coarser than
/// `CaptureState`: it describes what the operator is doing, which is
/// what the Stage 1 rules key on.
public enum OptionalWorkPhase:
    String, Sendable, Equatable, CaseIterable
{
    /// Live room scan: RoomPlan/mesh/depth evidence takes priority;
    /// optional work is at its most restricted.
    case roomScan = "room_scan"
    /// The operator's explicit current measurement/evidence task is
    /// running (e.g. a targeted object pass): one task-relevant assist
    /// is allowed, unrelated semantic/language work is deferred.
    case targetOrMeasurement = "target_or_measurement"
    /// Review/annotation — live spatial capture contention is lowest;
    /// the preferred phase for Foundation Models/Core AI work.
    case reviewAnnotation = "review_annotation"
    /// Finalization/export — hashing/writing/integrity wins; no
    /// speculative optional inference.
    case finalizationOrExport = "finalization_or_export"
    /// No live capture context (idle/setup/permissions/preparing/
    /// failed). Optional work has nothing to serve — deferred.
    case inactive

    /// Maps the host's capture state to an admission phase. A running
    /// targeted pass turns `.scanning` into `.targetOrMeasurement`
    /// for the duration of that explicit measurement task.
    public init(
        state: CaptureState,
        measurementTaskActive: Bool = false
    ) {
        switch state {
        case .scanning:
            self = measurementTaskActive
                ? .targetOrMeasurement
                : .roomScan
        case .reviewing, .annotating:
            self = .reviewAnnotation
        case .validating, .finalized, .exported:
            self = .finalizationOrExport
        case .idle, .setup, .capabilityCheck, .permissions,
             .preparing, .failed:
            self = .inactive
        }
    }
}

/// Coarse resource pressure band derived from existing authority
/// signals (#273 pressure policy). The states deliberately reuse the
/// semantics of `CaptureResourceMonitor` — thermal/storage semantics
/// continue to come from that authority; this band only orders
/// optional-work admission.
public enum CapturePressureState:
    String, Sendable, Equatable, CaseIterable, Comparable
{
    /// Phase-allowed optional work may be admitted.
    case nominal
    /// No speculative work: language/semantic starts are deferred.
    /// Bounded one-shot work already in flight may finish.
    case elevated
    /// Cancel/suspend optional semantic/language/high-res work; only
    /// benchmarked-essential active assists may start or continue.
    case serious
    /// Cancel optional work; the existing capture-resource
    /// failure/recovery policy governs what happens to capture itself.
    case critical

    private var rank: Int {
        switch self {
        case .nominal: return 0
        case .elevated: return 1
        case .serious: return 2
        case .critical: return 3
        }
    }

    public static func < (
        lhs: CapturePressureState,
        rhs: CapturePressureState
    ) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// The `captureHealth` input to the admission decision: a point-in-
/// time view of the existing resource/session authorities plus the
/// cheap optional-work signals a feature already owns (#273 Inputs).
/// No hardware counters are invented — every field maps to a signal
/// the codebase already measures.
public struct CaptureHealthSnapshot: Sendable, Equatable {
    /// `ProcessInfo.thermalState` — the same authority
    /// `CaptureResourceMonitor` emits pressure events from.
    public var thermalState: ProcessInfo.ThermalState
    /// The monitor's emitted storage band.
    public var storageBand: CaptureStoragePressureTracker.State
    /// A memory warning is currently suppressing optional work (the
    /// host's existing memory-pressure mitigation flag).
    public var memoryPressureActive: Bool
    /// The live ARSession is interrupted (system interruption in
    /// progress — not yet resolved by `interruptionEnded`).
    public var interruptionActive: Bool
    /// The working-set persistence admission ledger is pressured
    /// (#147 backlog signal).
    public var persistenceBacklogActive: Bool
    /// A rendering mitigation is engaged (RoomPlan model rendering
    /// disabled under pressure).
    public var renderingMitigationActive: Bool
    /// Latest tracking quality while scanning; nil when not live.
    public var latestTrackingState: TrackingQualityState?
    /// True when scene depth is expected by the running configuration
    /// but recently absent; nil when unmeasured — absence is never
    /// fabricated.
    public var sceneDepthRecentlyAbsent: Bool?

    public init(
        thermalState: ProcessInfo.ThermalState,
        storageBand: CaptureStoragePressureTracker.State = .healthy,
        memoryPressureActive: Bool = false,
        interruptionActive: Bool = false,
        persistenceBacklogActive: Bool = false,
        renderingMitigationActive: Bool = false,
        latestTrackingState: TrackingQualityState? = nil,
        sceneDepthRecentlyAbsent: Bool? = nil
    ) {
        self.thermalState = thermalState
        self.storageBand = storageBand
        self.memoryPressureActive = memoryPressureActive
        self.interruptionActive = interruptionActive
        self.persistenceBacklogActive = persistenceBacklogActive
        self.renderingMitigationActive = renderingMitigationActive
        self.latestTrackingState = latestTrackingState
        self.sceneDepthRecentlyAbsent = sceneDepthRecentlyAbsent
    }

    /// The coarse pressure band this snapshot implies (#273 pressure
    /// policy). The mapping takes the worst contribution across
    /// signals; it does not create new thresholds:
    ///
    /// - critical: thermal `.critical`, storage `.critical`
    ///   — the same conditions the existing authority treats as
    ///   capture-failure candidates (`isLifecycleFailure`).
    /// - serious: thermal `.serious`, an active memory warning, an
    ///   unresolved ARSession interruption, `.unavailable` tracking —
    ///   matching the host's existing optional-work suspension gate
    ///   (memory warning or thermal ≥ serious disables the derived
    ///   preview and RoomPlan model rendering).
    /// - elevated: thermal `.fair`, storage `.warning`,
    ///   undetermined storage capacity (not proof of headroom — #181),
    ///   persistence backlog pressure, an engaged rendering
    ///   mitigation, `.limited` tracking, or expected-but-absent scene
    ///   depth.
    /// - nominal: nothing above fired.
    public var pressureState: CapturePressureState {
        var state = CapturePressureState.nominal
        func raise(_ next: CapturePressureState) {
            if next > state { state = next }
        }
        switch thermalState {
        case .nominal:
            break
        case .fair:
            raise(.elevated)
        case .serious:
            raise(.serious)
        case .critical:
            raise(.critical)
        @unknown default:
            raise(.elevated)
        }
        switch storageBand {
        case .healthy:
            break
        case .warning:
            raise(.elevated)
        case .critical:
            raise(.critical)
        case .undetermined:
            // "Could not determine" is not evidence of headroom (#181).
            raise(.elevated)
        }
        if memoryPressureActive { raise(.serious) }
        if interruptionActive { raise(.serious) }
        if persistenceBacklogActive { raise(.elevated) }
        if renderingMitigationActive { raise(.elevated) }
        switch latestTrackingState {
        case .limited:
            raise(.elevated)
        case .unavailable:
            raise(.serious)
        case .normal, nil:
            break
        }
        if sceneDepthRecentlyAbsent == true { raise(.elevated) }
        return state
    }
}

/// Machine-stable denial reason recorded in admission instrumentation.
/// Values are `snake_case` tokens, never localized text, so persisted
/// notes stay interpretable (#183 convention).
public enum OptionalWorkDenialReason:
    String, Codable, Sendable, Equatable, CaseIterable
{
    /// The workload class/execution combination never runs in this
    /// phase (continuous work during a live scan, optional inference
    /// during finalization/export).
    case phaseProhibited = "phase_prohibited"
    /// Phase rules park the workload — it may be admitted in a later
    /// phase (language/semantic work deferring to review).
    case phaseDeferred = "phase_deferred"
    /// `elevated` pressure defers speculative starts.
    case pressureElevated = "pressure_elevated"
    /// `serious` pressure refuses optional starts.
    case pressureSerious = "pressure_serious"
    /// `critical` pressure refuses all optional work.
    case pressureCritical = "pressure_critical"
    /// The single active-assist slot is occupied.
    case activeAssistOccupied = "active_assist_occupied"
    /// A request for this workload identifier is already in flight —
    /// the feature-level one-in-flight guard (#275 convention).
    case requestInFlight = "request_in_flight"
    /// No live capture phase exists for the work to serve.
    case captureInactive = "capture_inactive"
}

/// `canStart` verdict (#273 signature):
/// `allow | defer | reject`.
///
/// - `allow` — the work may start now.
/// - `defer` — not now; retry is meaningful when the phase or pressure
///   changes (the operator/system may re-ask).
/// - `reject` — the workload is prohibited in this context; only a
///   different phase makes it admissible.
public enum OptionalWorkAdmissionDecision: Sendable, Equatable {
    case allow
    case `defer`(OptionalWorkDenialReason)
    case reject(OptionalWorkDenialReason)

    public var isAllowed: Bool {
        if case .allow = self { return true }
        return false
    }

    /// The denial reason for defer/reject, nil when allowed.
    public var denialReason: OptionalWorkDenialReason? {
        switch self {
        case .allow:
            return nil
        case .defer(let reason), .reject(let reason):
            return reason
        }
    }
}

/// What a pressure change means for optional work already running.
public enum OptionalWorkInflightAction:
    String, Sendable, Equatable
{
    /// The workload may continue.
    case continueWork = "continue"
    /// Sustained work pauses until pressure subsides (periodic and
    /// continuous workloads resume by re-admission).
    case suspend
    /// The workload must stop; its results are stale unless completed
    /// before cancellation lands.
    case cancel
}

/// Stateless decision table — the whole Stage 1 rule set. Kept
/// separate from `OptionalWorkAdmissionTracker` so the rules are
/// exhaustively testable without tracker state.
public enum OptionalWorkAdmissionPolicy {
    /// `canStart(workload, phase, captureHealth)` (#273).
    ///
    /// `activeAssistOccupied` and `requestInFlight` carry the two
    /// bounded guards: at most one active assist runs at a time, and
    /// each feature's one-in-flight request bound is enforced here
    /// rather than by a second queue.
    public static func decision(
        for workload: OptionalWorkload,
        in phase: OptionalWorkPhase,
        health: CaptureHealthSnapshot,
        activeAssistOccupied: Bool = false,
        requestInFlight: Bool = false
    ) -> OptionalWorkAdmissionDecision {
        // Authoritative capture work is never admission-gated — the
        // policy only sheds optional work.
        if workload.workloadClass == .captureCritical {
            return .allow
        }

        let pressure = health.pressureState
        if pressure == .critical {
            return .reject(.pressureCritical)
        }

        switch phase {
        case .inactive:
            // No live capture context — the work has nothing to serve.
            // Defer, not reject: asking again once a phase begins is
            // legitimate.
            return .defer(.captureInactive)
        case .finalizationOrExport:
            // Hashing/writing/integrity wins; no speculative optional
            // inference runs inside the commit surface.
            return .reject(.phaseProhibited)
        case .roomScan:
            return roomScanDecision(
                workload: workload,
                pressure: pressure,
                activeAssistOccupied: activeAssistOccupied,
                requestInFlight: requestInFlight
            )
        case .targetOrMeasurement:
            return targetPhaseDecision(
                workload: workload,
                pressure: pressure,
                activeAssistOccupied: activeAssistOccupied,
                requestInFlight: requestInFlight
            )
        case .reviewAnnotation:
            return reviewPhaseDecision(
                workload: workload,
                pressure: pressure,
                activeAssistOccupied: activeAssistOccupied,
                requestInFlight: requestInFlight
            )
        }
    }

    /// The action a pressure change implies for optional work already
    /// in flight. Bounded one-shot work under `elevated` pressure is
    /// allowed to finish (it is already committed and nearly free to
    /// complete); sustained work suspends. `serious` cancels
    /// one-shots and suspends sustained work, retaining only
    /// benchmarked-essential assists. `critical` cancels everything
    /// optional — the existing failure/recovery policy governs the
    /// capture itself.
    public static func inflightAction(
        for workload: OptionalWorkload,
        pressure: CapturePressureState
    ) -> OptionalWorkInflightAction {
        guard workload.workloadClass != .captureCritical else {
            return .continueWork
        }
        switch pressure {
        case .nominal:
            return .continueWork
        case .elevated:
            return workload.execution == .oneShot
                ? .continueWork
                : .suspend
        case .serious:
            if workload.workloadClass == .activeAssist,
               workload.benchmarkedEssentialAssist
            {
                return .continueWork
            }
            return workload.execution == .oneShot ? .cancel : .suspend
        case .critical:
            return .cancel
        }
    }

    // MARK: - Phase tables

    /// Room scan: RoomPlan/mesh/depth evidence takes priority.
    /// Continuous optional work is prohibited outright; one-shot or
    /// periodic optional visual/segmentation work is admitted only at
    /// nominal pressure; language work defers to review (#273 room
    /// scan row).
    private static func roomScanDecision(
        workload: OptionalWorkload,
        pressure: CapturePressureState,
        activeAssistOccupied: Bool,
        requestInFlight: Bool
    ) -> OptionalWorkAdmissionDecision {
        switch workload.workloadClass {
        case .captureCritical:
            return .allow
        case .activeAssist:
            return assistDecision(
                workload: workload,
                pressure: pressure,
                activeAssistOccupied: activeAssistOccupied,
                requestInFlight: requestInFlight
            )
        case .optionalSemantic:
            if workload.execution == .continuous {
                return .reject(.phaseProhibited)
            }
            return speculativeStart(
                pressure: pressure,
                requestInFlight: requestInFlight
            )
        case .optionalLanguage:
            if workload.execution == .continuous {
                return .reject(.phaseProhibited)
            }
            if pressure >= .serious {
                return .reject(.pressureSerious)
            }
            return .defer(.phaseDeferred)
        }
    }

    /// Target/measurement: one task-relevant active assist is allowed;
    /// unrelated semantic/language work defers while the explicit task
    /// runs (#273 target/measurement row).
    private static func targetPhaseDecision(
        workload: OptionalWorkload,
        pressure: CapturePressureState,
        activeAssistOccupied: Bool,
        requestInFlight: Bool
    ) -> OptionalWorkAdmissionDecision {
        switch workload.workloadClass {
        case .captureCritical:
            return .allow
        case .activeAssist:
            return assistDecision(
                workload: workload,
                pressure: pressure,
                activeAssistOccupied: activeAssistOccupied,
                requestInFlight: requestInFlight
            )
        case .optionalSemantic:
            if workload.execution == .continuous {
                return .reject(.phaseProhibited)
            }
            if pressure >= .serious {
                return .reject(.pressureSerious)
            }
            return .defer(.phaseDeferred)
        case .optionalLanguage:
            if pressure >= .serious {
                return .reject(.pressureSerious)
            }
            return .defer(.phaseDeferred)
        }
    }

    /// Review/annotation: the preferred phase for Foundation Models /
    /// Core AI work because live spatial capture contention is lowest
    /// (#273 review/annotation row).
    private static func reviewPhaseDecision(
        workload: OptionalWorkload,
        pressure: CapturePressureState,
        activeAssistOccupied: Bool,
        requestInFlight: Bool
    ) -> OptionalWorkAdmissionDecision {
        switch workload.workloadClass {
        case .captureCritical:
            return .allow
        case .activeAssist:
            return assistDecision(
                workload: workload,
                pressure: pressure,
                activeAssistOccupied: activeAssistOccupied,
                requestInFlight: requestInFlight
            )
        case .optionalSemantic, .optionalLanguage:
            return speculativeStart(
                pressure: pressure,
                requestInFlight: requestInFlight
            )
        }
    }

    // MARK: - Shared rules

    /// Task-relevant assist rule shared by the live phases: the single
    /// slot gates first, then pressure — non-essential assists defer
    /// at `serious` and are already rejected at `critical` by the
    /// caller's global check.
    private static func assistDecision(
        workload: OptionalWorkload,
        pressure: CapturePressureState,
        activeAssistOccupied: Bool,
        requestInFlight: Bool
    ) -> OptionalWorkAdmissionDecision {
        if requestInFlight {
            return .defer(.requestInFlight)
        }
        if activeAssistOccupied {
            return .defer(.activeAssistOccupied)
        }
        if pressure >= .serious,
           !workload.benchmarkedEssentialAssist
        {
            return .defer(.pressureSerious)
        }
        return .allow
    }

    /// Optional semantic/language start shared by the phases that
    /// allow such work at all: nominal admits, elevated defers,
    /// serious rejects.
    private static func speculativeStart(
        pressure: CapturePressureState,
        requestInFlight: Bool
    ) -> OptionalWorkAdmissionDecision {
        switch pressure {
        case .nominal:
            if requestInFlight {
                return .defer(.requestInFlight)
            }
            return .allow
        case .elevated:
            return .defer(.pressureElevated)
        case .serious:
            return .reject(.pressureSerious)
        case .critical:
            return .reject(.pressureCritical)
        }
    }
}

/// One admission log entry — the bounded instrumentation record of
/// "phase + optional-work admission/rejection reason" (#273
/// Instrumentation). Details are machine tokens only; imagery or
/// geometry must never be logged as performance telemetry.
public struct OptionalWorkAdmissionRecord: Sendable, Equatable {
    /// What the record describes.
    public enum Kind: String, Sendable, Equatable {
        /// A `canStart`/`evaluate` decision.
        case admission
        /// In-flight sustained work suspended under pressure.
        case suspended
        /// Suspended sustained work resumed after recovery.
        case resumed
        /// In-flight work cancelled under pressure.
        case cancelled
        /// A registered request completed/failed/was superseded.
        case finished
    }

    /// Monotonic emission counter within the tracker instance.
    public let sequence: UInt64
    /// Session-clock seconds when the host supplies one; nil when no
    /// session clock exists for the request context.
    public let sessionTimestampSeconds: Double?
    public let kind: Kind
    public let phase: OptionalWorkPhase
    public let workloadIdentifier: String
    public let workloadClass: OptionalWorkloadClass
    public let pressure: CapturePressureState
    /// `allow`/`defer`/`reject` for `.admission` records; the in-flight
    /// action name for `.suspended`/`.cancelled`; the outcome name for
    /// `.finished`.
    public let outcome: String
    /// Denial reason for defer/reject admissions.
    public let reason: OptionalWorkDenialReason?

    public init(
        sequence: UInt64,
        sessionTimestampSeconds: Double?,
        kind: Kind,
        phase: OptionalWorkPhase,
        workloadIdentifier: String,
        workloadClass: OptionalWorkloadClass,
        pressure: CapturePressureState,
        outcome: String,
        reason: OptionalWorkDenialReason?
    ) {
        self.sequence = sequence
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.kind = kind
        self.phase = phase
        self.workloadIdentifier = workloadIdentifier
        self.workloadClass = workloadClass
        self.pressure = pressure
        self.outcome = outcome
        self.reason = reason
    }

    /// The `key=value` detail string used for advisory-note
    /// provenance. Machine tokens only.
    public var advisoryDetail: String {
        var parts = [
            "workload=\(workloadIdentifier)",
            "class=\(workloadClass.rawValue)",
            "phase=\(phase.rawValue)",
            "pressure=\(pressure.rawValue)",
            "outcome=\(outcome)",
        ]
        if let reason {
            parts.append("reason=\(reason.rawValue)")
        }
        return parts.joined(separator: " ")
    }
}

/// How a registered request resolved.
public enum OptionalWorkOutcome: String, Sendable, Equatable {
    case completed
    case failed
    case cancelled
    /// The request finished but its result was dropped because a newer
    /// admission superseded it or the capture/target generation moved
    /// on (#273 stale-result rejection).
    case staleRejected = "stale_rejected"
}

/// Bounded per-workload outcome aggregate — the "request
/// latency/failure" half of #273 instrumentation. Counts and latency
/// bounds only; never imagery or content.
public struct OptionalWorkOutcomeAggregate: Sendable, Equatable {
    public private(set) var admittedCount = 0
    public private(set) var deferredCount = 0
    public private(set) var rejectedCount = 0
    public private(set) var completedCount = 0
    public private(set) var failedCount = 0
    public private(set) var cancelledCount = 0
    public private(set) var staleRejectedCount = 0
    /// Sum of recorded request latencies for completed/failed
    /// finishes, seconds.
    public private(set) var totalLatencySeconds: Double = 0
    public private(set) var latencySampleCount = 0
    public private(set) var maximumLatencySeconds: Double?

    public init() {}

    public var averageLatencySeconds: Double? {
        guard latencySampleCount > 0 else { return nil }
        return totalLatencySeconds / Double(latencySampleCount)
    }

    mutating func apply(_ decision: OptionalWorkAdmissionDecision) {
        switch decision {
        case .allow:
            admittedCount += 1
        case .defer:
            deferredCount += 1
        case .reject:
            rejectedCount += 1
        }
    }

    mutating func record(
        _ outcome: OptionalWorkOutcome,
        latencySeconds: Double?
    ) {
        switch outcome {
        case .completed:
            completedCount += 1
        case .failed:
            failedCount += 1
        case .cancelled:
            cancelledCount += 1
        case .staleRejected:
            staleRejectedCount += 1
        }
        if let latencySeconds, latencySeconds.isFinite,
           latencySeconds >= 0
        {
            totalLatencySeconds += latencySeconds
            latencySampleCount += 1
            maximumLatencySeconds = max(
                maximumLatencySeconds ?? 0, latencySeconds
            )
        }
    }

    /// Folds a bounded-out identifier's totals into this aggregate
    /// (`__other__` overflow bucket).
    mutating func merge(_ other: OptionalWorkOutcomeAggregate) {
        admittedCount += other.admittedCount
        deferredCount += other.deferredCount
        rejectedCount += other.rejectedCount
        completedCount += other.completedCount
        failedCount += other.failedCount
        cancelledCount += other.cancelledCount
        staleRejectedCount += other.staleRejectedCount
        totalLatencySeconds += other.totalLatencySeconds
        latencySampleCount += other.latencySampleCount
        if let maximum = other.maximumLatencySeconds {
            maximumLatencySeconds = max(
                maximumLatencySeconds ?? 0, maximum
            )
        }
    }
}

/// The result of a `begin` attempt: the `canStart` verdict plus the
/// ticket when admitted.
public struct OptionalWorkAdmissionResult: Sendable, Equatable {
    public let decision: OptionalWorkAdmissionDecision
    public let ticket: OptionalWorkAdmissionTicket?

    public init(
        decision: OptionalWorkAdmissionDecision,
        ticket: OptionalWorkAdmissionTicket?
    ) {
        self.decision = decision
        self.ticket = ticket
    }
}

/// A ticket proving a workload was admitted. Features pass it back to
/// `finish`/`isCurrent`; a superseded or ended ticket is stale and its
/// result must be rejected by the feature's own boundary (#273
/// request safety).
public struct OptionalWorkAdmissionTicket: Sendable, Equatable {
    /// Monotonic per-workload request generation: re-admitting the
    /// same identifier supersedes the older ticket.
    public let sequence: UInt64
    public let workloadIdentifier: String
    public let workloadClass: OptionalWorkloadClass
    public let phase: OptionalWorkPhase
    public let admittedAtSessionSeconds: Double?

    public init(
        sequence: UInt64,
        workloadIdentifier: String,
        workloadClass: OptionalWorkloadClass,
        phase: OptionalWorkPhase,
        admittedAtSessionSeconds: Double?
    ) {
        self.sequence = sequence
        self.workloadIdentifier = workloadIdentifier
        self.workloadClass = workloadClass
        self.phase = phase
        self.admittedAtSessionSeconds = admittedAtSessionSeconds
    }
}

/// Stateful bounded ledger around `OptionalWorkAdmissionPolicy`
/// (#273). Tracks the single active-assist slot, each workload's
/// one-in-flight guard, a compacted decision log, and per-workload
/// outcome aggregates. Pure value type — the host owns its lifecycle
/// and applies in-flight actions; nothing here touches a clock,
/// a notification center, or a task queue.
public struct OptionalWorkAdmissionTracker: Sendable, Equatable {
    /// Bounded decision/lifecycle log size; identical repeated
    /// decisions for a workload are compacted rather than churning
    /// the budget (#148 convention).
    public static let logLimit = 256
    /// Bounded distinct-workload outcome map. Only a dozen optional
    /// workloads exist by construction; the cap keeps an arbitrary
    /// identifier stream from growing it.
    public static let outcomeWorkloadLimit = 64

    private struct InFlight: Sendable, Equatable {
        var workload: OptionalWorkload
        var ticket: OptionalWorkAdmissionTicket
        var suspended: Bool
    }

    /// Compact latest-decision fingerprint per workload so periodic
    /// re-evaluation does not spam the log with identical verdicts.
    private struct DecisionFingerprint: Sendable, Equatable {
        var phase: OptionalWorkPhase
        var pressure: CapturePressureState
        var decision: String
        var reason: OptionalWorkDenialReason?
    }

    public private(set) var log: [OptionalWorkAdmissionRecord] = []
    public private(set) var logTruncatedCount = 0
    private var inflight: [String: InFlight] = [:]
    public private(set) var outcomes:
        [String: OptionalWorkOutcomeAggregate] = [:]
    private var nextSequence: UInt64 = 0
    private var lastAdmissionFingerprint:
        [String: DecisionFingerprint] = [:]

    public init() {}

    /// The workload currently holding the single active-assist slot,
    /// if any.
    public var activeAssistIdentifier: String? {
        inflight.values.first {
            $0.ticket.workloadClass == .activeAssist && !$0.suspended
        }?.ticket.workloadIdentifier
    }

    /// `canStart` without registering the request — for periodic and
    /// sustained workloads that re-ask each evaluation point and for
    /// features that only need the verdict. Denials and first-time
    /// verdicts are logged; identical consecutive verdicts for the
    /// same workload are compacted into the aggregate counters.
    @discardableResult
    public mutating func evaluate(
        _ workload: OptionalWorkload,
        phase: OptionalWorkPhase,
        health: CaptureHealthSnapshot,
        sessionTimestampSeconds: Double? = nil
    ) -> OptionalWorkAdmissionDecision {
        let decision = OptionalWorkAdmissionPolicy.decision(
            for: workload,
            in: phase,
            health: health,
            activeAssistOccupied: activeAssistIdentifier != nil,
            requestInFlight: inflight[workload.identifier] != nil
        )
        applyOutcome(of: decision, to: workload)
        logAdmissionIfChanged(
            workload,
            phase: phase,
            decision: decision,
            pressure: health.pressureState,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
        return decision
    }

    /// `canStart` plus request registration: on `allow` the returned
    /// ticket binds the admission's request generation so a superseded
    /// or ended request's results are rejected as stale (#273). On
    /// defer/reject the decision is returned without a ticket.
    @discardableResult
    public mutating func begin(
        _ workload: OptionalWorkload,
        phase: OptionalWorkPhase,
        health: CaptureHealthSnapshot,
        sessionTimestampSeconds: Double? = nil
    ) -> OptionalWorkAdmissionResult {
        let decision = evaluate(
            workload,
            phase: phase,
            health: health,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
        guard decision.isAllowed else {
            return OptionalWorkAdmissionResult(
                decision: decision,
                ticket: nil
            )
        }
        let ticket = OptionalWorkAdmissionTicket(
            sequence: nextSequence,
            workloadIdentifier: workload.identifier,
            workloadClass: workload.workloadClass,
            phase: phase,
            admittedAtSessionSeconds: sessionTimestampSeconds
        )
        nextSequence += 1
        inflight[workload.identifier] = InFlight(
            workload: workload,
            ticket: ticket,
            suspended: false
        )
        return OptionalWorkAdmissionResult(
            decision: decision,
            ticket: ticket
        )
    }

    /// Ends a registered request and records its outcome. Latency is
    /// optional — supplied by the feature when cheap to measure
    /// (#273 instrumentation). Returns false for an unknown ticket so
    /// a double-finish cannot corrupt the ledger.
    @discardableResult
    public mutating func finish(
        _ ticket: OptionalWorkAdmissionTicket,
        outcome: OptionalWorkOutcome,
        latencySeconds: Double? = nil,
        sessionTimestampSeconds: Double? = nil
    ) -> Bool {
        guard let entry = inflight[ticket.workloadIdentifier],
              entry.ticket == ticket
        else {
            return false
        }
        inflight[ticket.workloadIdentifier] = nil
        recordOutcome(outcome, for: ticket, latency: latencySeconds)
        appendLog(
            kind: .finished,
            phase: ticket.phase,
            workloadIdentifier: ticket.workloadIdentifier,
            workloadClass: ticket.workloadClass,
            pressure: .nominal,
            outcome: outcome.rawValue,
            reason: nil,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
        return true
    }

    /// Cancels a registered request (e.g. after `inflightAction`
    /// returned `.cancel`). Returns false for an unknown ticket.
    @discardableResult
    public mutating func cancel(
        _ ticket: OptionalWorkAdmissionTicket,
        pressure: CapturePressureState,
        sessionTimestampSeconds: Double? = nil
    ) -> Bool {
        guard let entry = inflight[ticket.workloadIdentifier],
              entry.ticket == ticket
        else {
            return false
        }
        inflight[ticket.workloadIdentifier] = nil
        recordOutcome(.cancelled, for: ticket, latency: nil)
        appendLog(
            kind: .cancelled,
            phase: ticket.phase,
            workloadIdentifier: ticket.workloadIdentifier,
            workloadClass: ticket.workloadClass,
            pressure: pressure,
            outcome: OptionalWorkInflightAction.cancel.rawValue,
            reason: denialReason(for: pressure),
            sessionTimestampSeconds: sessionTimestampSeconds
        )
        return true
    }

    /// Marks a registered sustained workload suspended under
    /// pressure; it stays registered so `resume` can reinstate it.
    public mutating func suspend(
        _ ticket: OptionalWorkAdmissionTicket,
        pressure: CapturePressureState,
        sessionTimestampSeconds: Double? = nil
    ) {
        guard var entry = inflight[ticket.workloadIdentifier],
              entry.ticket == ticket,
              !entry.suspended
        else {
            return
        }
        entry.suspended = true
        inflight[ticket.workloadIdentifier] = entry
        appendLog(
            kind: .suspended,
            phase: ticket.phase,
            workloadIdentifier: ticket.workloadIdentifier,
            workloadClass: ticket.workloadClass,
            pressure: pressure,
            outcome: OptionalWorkInflightAction.suspend.rawValue,
            reason: denialReason(for: pressure),
            sessionTimestampSeconds: sessionTimestampSeconds
        )
    }

    /// Reinstates a suspended workload after pressure recovered.
    public mutating func resume(
        _ ticket: OptionalWorkAdmissionTicket,
        sessionTimestampSeconds: Double? = nil
    ) {
        guard var entry = inflight[ticket.workloadIdentifier],
              entry.ticket == ticket,
              entry.suspended
        else {
            return
        }
        entry.suspended = false
        inflight[ticket.workloadIdentifier] = entry
        appendLog(
            kind: .resumed,
            phase: ticket.phase,
            workloadIdentifier: ticket.workloadIdentifier,
            workloadClass: ticket.workloadClass,
            pressure: .nominal,
            outcome: OptionalWorkInflightAction.continueWork.rawValue,
            reason: nil,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
    }

    /// The action the current pressure implies for every registered
    /// in-flight workload, in admission order. The host calls this on
    /// a resource/health change and applies `.suspend`/`.cancel` per
    /// workload; `.continueWork` entries need no action.
    public func inflightActions(
        health: CaptureHealthSnapshot
    ) -> [(ticket: OptionalWorkAdmissionTicket,
           action: OptionalWorkInflightAction)]
    {
        let pressure = health.pressureState
        return inflight.values
            .sorted { $0.ticket.sequence < $1.ticket.sequence }
            .map { entry in
                (
                    ticket: entry.ticket,
                    action: OptionalWorkAdmissionPolicy.inflightAction(
                        for: entry.workload,
                        pressure: pressure
                    )
                )
            }
    }

    /// True when the ticket still names the live request for its
    /// workload — false once finished, cancelled, or superseded by a
    /// later `begin` (#273 stale-result rejection).
    public func isCurrent(
        _ ticket: OptionalWorkAdmissionTicket
    ) -> Bool {
        inflight[ticket.workloadIdentifier]?.ticket == ticket
    }

    /// Drops all in-flight registrations without touching the log or
    /// outcome aggregates — called by the host when the capture
    /// generation resets, which already invalidates outstanding
    /// results through the existing generation fence.
    public mutating func resetInflight() {
        inflight.removeAll()
        lastAdmissionFingerprint.removeAll()
    }

    // MARK: - Internals

    private mutating func applyOutcome(
        of decision: OptionalWorkAdmissionDecision,
        to workload: OptionalWorkload
    ) {
        var aggregate = outcomes[workload.identifier]
            ?? OptionalWorkOutcomeAggregate()
        aggregate.apply(decision)
        storeOutcome(aggregate, for: workload.identifier)
    }

    private mutating func recordOutcome(
        _ outcome: OptionalWorkOutcome,
        for ticket: OptionalWorkAdmissionTicket,
        latency: Double?
    ) {
        var aggregate = outcomes[ticket.workloadIdentifier]
            ?? OptionalWorkOutcomeAggregate()
        aggregate.record(outcome, latencySeconds: latency)
        storeOutcome(aggregate, for: ticket.workloadIdentifier)
    }

    private mutating func storeOutcome(
        _ aggregate: OptionalWorkOutcomeAggregate,
        for identifier: String
    ) {
        if outcomes[identifier] == nil,
           outcomes.count >= Self.outcomeWorkloadLimit
        {
            // Unknown identifiers beyond the budget collapse into a
            // shared bucket rather than growing the map.
            var other = outcomes["__other__"]
                ?? OptionalWorkOutcomeAggregate()
            other.merge(aggregate)
            outcomes["__other__"] = other
            return
        }
        outcomes[identifier] = aggregate
    }

    /// Logs the verdict only when (phase, pressure, decision, reason)
    /// changed since the workload's last logged verdict — the
    /// transition-only compaction convention of
    /// `ScanTrackingTransitionGate`, so periodic re-admission cannot
    /// churn the bounded log.
    private mutating func logAdmissionIfChanged(
        _ workload: OptionalWorkload,
        phase: OptionalWorkPhase,
        decision: OptionalWorkAdmissionDecision,
        pressure: CapturePressureState,
        sessionTimestampSeconds: Double?
    ) {
        let fingerprint = DecisionFingerprint(
            phase: phase,
            pressure: pressure,
            decision: decision.logToken,
            reason: decision.denialReason
        )
        guard lastAdmissionFingerprint[workload.identifier]
                != fingerprint
        else {
            return
        }
        lastAdmissionFingerprint[workload.identifier] = fingerprint
        appendLog(
            kind: .admission,
            phase: phase,
            workloadIdentifier: workload.identifier,
            workloadClass: workload.workloadClass,
            pressure: pressure,
            outcome: decision.logToken,
            reason: decision.denialReason,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
    }

    private mutating func appendLog(
        kind: OptionalWorkAdmissionRecord.Kind,
        phase: OptionalWorkPhase,
        workloadIdentifier: String,
        workloadClass: OptionalWorkloadClass,
        pressure: CapturePressureState,
        outcome: String,
        reason: OptionalWorkDenialReason?,
        sessionTimestampSeconds: Double?
    ) {
        let record = OptionalWorkAdmissionRecord(
            sequence: nextSequence,
            sessionTimestampSeconds: sessionTimestampSeconds,
            kind: kind,
            phase: phase,
            workloadIdentifier: workloadIdentifier,
            workloadClass: workloadClass,
            pressure: pressure,
            outcome: outcome,
            reason: reason
        )
        nextSequence += 1
        if log.count >= Self.logLimit {
            log.removeFirst()
            logTruncatedCount += 1
        }
        log.append(record)
    }

    private func denialReason(
        for pressure: CapturePressureState
    ) -> OptionalWorkDenialReason? {
        switch pressure {
        case .nominal: return nil
        case .elevated: return .pressureElevated
        case .serious: return .pressureSerious
        case .critical: return .pressureCritical
        }
    }
}

extension OptionalWorkAdmissionDecision {
    /// Stable token for log/instrumentation.
    public var logToken: String {
        switch self {
        case .allow: return "allow"
        case .defer: return "defer"
        case .reject: return "reject"
        }
    }
}
