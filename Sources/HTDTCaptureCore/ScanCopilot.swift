import Foundation

/// Scan copilot (#272): an *optional* on-device model layer that
/// re-ranks or re-words operator guidance derived from the existing
/// deterministic diagnostics — never a new authority.
///
/// The pipeline is fixed:
///   deterministic diagnostics
///     -> bounded/versioned `ScanCopilotContext`
///     -> optional model draft (`ScanCopilotModelProducing`)
///     -> deterministic `ScanCopilotValidator`
///     -> advisory-only presentation.
///
/// `ScanCopilotBaseline` produces the same class of suggestion with
/// no model at all; it is both the evaluation's deterministic arm
/// and the fallback whenever the model is unavailable, errors, or
/// fails validation. Nothing here can start, stop, or finish a
/// capture, mutate annotations, or overwrite observations.

/// Surface the copilot reasons over: the live scan itself, or the
/// end-of-scan review where repair items compete for attention.
public enum ScanCopilotStage: String, Codable, Sendable, Equatable {
    case scanning
    case review
}

/// Whitelisted advisory actions (#272 output schema). There is
/// deliberately no finish/complete/discard case: an accepted
/// suggestion can never express capture lifecycle control by
/// construction.
public enum ScanCopilotAction: String, Codable, Sendable, Equatable, CaseIterable {
    /// Hold position / keep the camera on already-seen features.
    case hold
    /// Turn in place toward uncovered directions.
    case rotate
    /// Physically move toward a weak/gap region — movement-qualified.
    case moveToGap = "move_to_gap"
    /// Re-observe a targeted item — movement-qualified.
    case rescanTarget = "rescan_target"
    /// Add missing annotation/task items.
    case annotate
    /// Open/act on the review surface.
    case review
    /// Pause for AR tracking to recover.
    case waitForTracking = "wait_for_tracking"
    /// Back off optional work under resource pressure.
    case reduceWorkload = "reduce_workload"
    /// Nothing actionable — keep scanning.
    case noAction = "no_action"

    /// Whether accepting this action asks the operator to physically
    /// translate. Movement actions may only be suggested when the
    /// deterministic movement-safety policy currently allows
    /// translation guidance (#257/#313).
    public var requiresMovementQualification: Bool {
        switch self {
        case .moveToGap, .rescanTarget:
            return true
        case .hold, .rotate, .annotate, .review,
             .waitForTracking, .reduceWorkload, .noAction:
            return false
        }
    }
}

/// Whitelisted advisory instruction templates. Every user-visible
/// copilot line resolves through `ScanCopilotCopy` in the app shell,
/// so a model can select phrasing but can never originate free-form
/// instruction text.
public enum ScanCopilotAdvisoryTemplate:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable
{
    case holdSteady = "hold_steady"
    case improveLighting = "improve_lighting"
    case slowDown = "slow_down"
    case turnInPlace = "turn_in_place"
    case revisitArea = "revisit_area"
    case moveCloser = "move_closer"
    case rescanTarget = "rescan_target"
    case waitForTracking = "wait_for_tracking"
    case reduceWorkload = "reduce_workload"
    case addMissingDetails = "add_missing_details"
    case reviewFlaggedItems = "review_flagged_items"
    case keepScanning = "keep_scanning"
    case scanOnTrack = "scan_on_track"

    /// Actions a template may be attached to. A template referencing
    /// movement only ever sits on movement-qualified actions.
    public var allowedActions: Set<ScanCopilotAction> {
        switch self {
        case .holdSteady, .improveLighting, .slowDown:
            return [.hold]
        case .turnInPlace:
            return [.rotate]
        case .revisitArea, .moveCloser:
            return [.moveToGap]
        case .rescanTarget:
            return [.rescanTarget]
        case .waitForTracking:
            return [.waitForTracking]
        case .reduceWorkload:
            return [.reduceWorkload]
        case .addMissingDetails:
            return [.annotate]
        case .reviewFlaggedItems:
            return [.review]
        case .keepScanning, .scanOnTrack:
            return [.noAction]
        }
    }
}

public enum ScanCopilotPriority:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable,
    Comparable
{
    case low
    case normal
    case high

    public static func < (
        lhs: ScanCopilotPriority,
        rhs: ScanCopilotPriority
    ) -> Bool {
        func rank(_ value: ScanCopilotPriority) -> Int {
            switch value {
            case .low: 0
            case .normal: 1
            case .high: 2
            }
        }
        return rank(lhs) < rank(rhs)
    }
}

/// Bounded diagnostic categories a suggestion may cite. These are
/// coarse machine categories — the persisted suggestion links the
/// concrete diagnostic items by ID, never prose.
public enum ScanCopilotReasonCode:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable
{
    case trackingLimited = "tracking_limited"
    case trackingUnavailable = "tracking_unavailable"
    case coverageGap = "coverage_gap"
    case weakRegion = "weak_region"
    case remoteWeakRegion = "remote_weak_region"
    case lowLight = "low_light"
    case resourcePressure = "resource_pressure"
    case revisitFlagsPending = "revisit_flags_pending"
    case targetScanIncomplete = "target_scan_incomplete"
    case taskItemsMissing = "task_items_missing"
    case guidanceSaturated = "guidance_saturated"
    case reviewReady = "review_ready"
    case noFindings = "no_findings"
}

/// One bounded diagnostic row inside the copilot context: the
/// identifier the suggestion cites plus the machine code/severity and
/// a short summary — never a raw payload.
public struct ScanCopilotDiagnosticItem: Codable, Sendable, Equatable {
    /// Small caller-assigned identifier (`d0`, `d1`, …); the only
    /// token a suggestion may reference in `source_diagnostic_ids`.
    public let id: String
    /// Deterministic diagnostic code (e.g. `tracking_limited`,
    /// `resource_thermal`).
    public let code: String
    public let severity: QualityDiagnosticSeverity
    /// Bounded human-facing summary line (capped by the context).
    public let summary: String

    public init(
        id: String,
        code: String,
        severity: QualityDiagnosticSeverity,
        summary: String
    ) {
        self.id = id
        self.code = code
        self.severity = severity
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case code
        case severity
        case summary
    }
}

/// Bounded, versioned snapshot of the deterministic diagnostic state
/// the copilot may reason over (#272). Construction caps every field:
/// lists truncate, strings clamp, counts floor at zero — the encoded
/// context stays well inside the model's context budget and can never
/// smuggle raw bundles, frame payloads, or unbounded history.
public struct ScanCopilotContext: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.scan_copilot_context"
    public static let schemaVersion = "1.0.0"
    /// Maximum diagnostic rows the model ever sees.
    public static let maximumDiagnostics = 8
    /// Maximum candidate region/flag/item identifiers.
    public static let maximumCandidateIDs = 8
    /// Maximum reason-code list accepted back from a draft.
    public static let maximumReasonCodes = 6
    /// Maximum referenced diagnostic IDs accepted back from a draft.
    public static let maximumSourceDiagnosticIDs = 8
    /// Per-field UTF-8 budget for free strings carried in the context.
    public static let maximumFieldCharacters = 64

    public let schema: String
    public let schemaVersion: String
    public let stage: ScanCopilotStage
    public let trackingState: TrackingQualityState?
    public let trackingReason: String?
    /// Direction-coverage fraction reported by the deterministic
    /// coverage tracker, clamped to 0...1.
    public let directionCoverageFraction: Double
    public let guidanceComplete: Bool
    public let guidanceCompletionSource: String?
    public let movementCapability: ScanMovementCapability
    /// Weak/gap region keys eligible as move targets — the model may
    /// only cite these identifiers (capped, ordered).
    public let weakRegionKeys: [String]
    public let actionableWeakRegionCount: Int
    public let saturatedWeakRegionCount: Int
    public let remoteWeakRegionCount: Int
    public let lowLightActive: Bool
    /// Unresolved revisit-flag IDs (capped).
    public let unresolvedRevisitFlagIDs: [String]
    /// Coarse targeted-scan state (`none`, `active`, `stalled`,
    /// `expired`, `complete`) — an ID the target may be cited under
    /// goes in `candidateTargetIDs`, never coordinates.
    public let targetScanState: String?
    /// Region/flag/target identifiers a `move_to_gap`/`rescan_target`
    /// suggestion may legitimately point at (capped).
    public let candidateTargetIDs: [String]
    public let missingTaskItemCount: Int
    /// Resource-pressure kinds currently active
    /// (`CaptureResourceEventKind` raw values, capped).
    public let resourcePressureKinds: [String]
    /// Whether the normal End affordance is currently usable — the
    /// only thing that permits a `review`-class suggestion outside
    /// the review stage.
    public let endScanAvailable: Bool
    public let diagnostics: [ScanCopilotDiagnosticItem]

    public init(
        stage: ScanCopilotStage,
        trackingState: TrackingQualityState? = nil,
        trackingReason: String? = nil,
        directionCoverageFraction: Double = 0,
        guidanceComplete: Bool = false,
        guidanceCompletionSource: String? = nil,
        movementCapability: ScanMovementCapability = .unrestricted,
        weakRegionKeys: [String] = [],
        actionableWeakRegionCount: Int = 0,
        saturatedWeakRegionCount: Int = 0,
        remoteWeakRegionCount: Int = 0,
        lowLightActive: Bool = false,
        unresolvedRevisitFlagIDs: [String] = [],
        targetScanState: String? = nil,
        candidateTargetIDs: [String] = [],
        missingTaskItemCount: Int = 0,
        resourcePressureKinds: [String] = [],
        endScanAvailable: Bool = false,
        diagnostics: [ScanCopilotDiagnosticItem] = []
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.stage = stage
        self.trackingState = trackingState
        self.trackingReason = Self.clamp(
            trackingReason
        )
        self.directionCoverageFraction = min(
            1,
            max(0, directionCoverageFraction.isFinite
                ? directionCoverageFraction : 0)
        )
        self.guidanceComplete = guidanceComplete
        self.guidanceCompletionSource = Self.clamp(
            guidanceCompletionSource
        )
        self.movementCapability = movementCapability
        self.weakRegionKeys = Self.capList(
            weakRegionKeys,
            limit: Self.maximumCandidateIDs
        )
        self.actionableWeakRegionCount = max(
            0, actionableWeakRegionCount
        )
        self.saturatedWeakRegionCount = max(
            0, saturatedWeakRegionCount
        )
        self.remoteWeakRegionCount = max(0, remoteWeakRegionCount)
        self.lowLightActive = lowLightActive
        self.unresolvedRevisitFlagIDs = Self.capList(
            unresolvedRevisitFlagIDs,
            limit: Self.maximumCandidateIDs
        )
        self.targetScanState = Self.clamp(targetScanState)
        self.candidateTargetIDs = Self.capList(
            candidateTargetIDs,
            limit: Self.maximumCandidateIDs
        )
        self.missingTaskItemCount = max(0, missingTaskItemCount)
        self.resourcePressureKinds = Self.capList(
            resourcePressureKinds,
            limit: Self.maximumReasonCodes
        )
        self.endScanAvailable = endScanAvailable
        self.diagnostics = Array(
            diagnostics.prefix(Self.maximumDiagnostics)
        ).map {
            ScanCopilotDiagnosticItem(
                id: Self.clamp($0.id) ?? "d?",
                code: Self.clamp($0.code) ?? "unknown",
                severity: $0.severity,
                summary: Self.clamp($0.summary) ?? ""
            )
        }
    }

    private static func clamp(_ value: String?) -> String? {
        guard let value else { return nil }
        return String(value.prefix(maximumFieldCharacters))
    }

    private static func capList(
        _ values: [String],
        limit: Int
    ) -> [String] {
        values.prefix(limit).map {
            String($0.prefix(maximumFieldCharacters))
        }
    }

    /// Stable identity of this exact diagnostic state. A suggestion is
    /// only meaningful against the context it was generated for —
    /// equivalent states share a digest so repeated taps debounce to
    /// one model request (#272 trigger policy).
    public var contextDigest: String {
        guard let data = try? JSONEncoder.canonical.encode(self)
        else {
            return "unknown"
        }
        return String(
            EvidenceIntegrity.sha256(of: data).value.prefix(16)
        )
    }

    /// Reason codes this context legitimately supports — anything
    /// outside this set is a claim about state the deterministic
    /// layer never reported.
    public var supportedReasonCodes: Set<ScanCopilotReasonCode> {
        var codes = Set<ScanCopilotReasonCode>()
        switch trackingState {
        case .limited: codes.insert(.trackingLimited)
        case .unavailable: codes.insert(.trackingUnavailable)
        case .normal, nil: break
        }
        if directionCoverageFraction < 1 {
            codes.insert(.coverageGap)
        }
        if actionableWeakRegionCount > 0 {
            codes.insert(.weakRegion)
        }
        if remoteWeakRegionCount > 0 {
            codes.insert(.remoteWeakRegion)
        }
        if lowLightActive {
            codes.insert(.lowLight)
        }
        if !resourcePressureKinds.isEmpty {
            codes.insert(.resourcePressure)
        }
        if !unresolvedRevisitFlagIDs.isEmpty {
            codes.insert(.revisitFlagsPending)
        }
        if let targetScanState, targetScanState != "none" {
            codes.insert(.targetScanIncomplete)
        }
        if missingTaskItemCount > 0 {
            codes.insert(.taskItemsMissing)
        }
        if saturatedWeakRegionCount > 0 {
            codes.insert(.guidanceSaturated)
        }
        if endScanAvailable || stage == .review {
            codes.insert(.reviewReady)
        }
        if codes.isEmpty {
            codes.insert(.noFindings)
        }
        return codes
    }

    /// True when any carried diagnostic is error severity — a
    /// `no_action` suggestion must never sit on top of a blocking
    /// finding.
    public var hasBlockingDiagnostics: Bool {
        diagnostics.contains { $0.severity == .error }
    }

    /// A smaller variant for the one allowed retry after the model
    /// reports `contextSizeExceeded` — diagnostics and identifiers
    /// shrink but are never silently dropped to zero coverage of the
    /// authoritative findings (the top rows are kept, counts remain).
    public func reduced() -> ScanCopilotContext {
        ScanCopilotContext(
            stage: stage,
            trackingState: trackingState,
            trackingReason: trackingReason,
            directionCoverageFraction: directionCoverageFraction,
            guidanceComplete: guidanceComplete,
            guidanceCompletionSource: guidanceCompletionSource,
            movementCapability: movementCapability,
            weakRegionKeys: Array(weakRegionKeys.prefix(4)),
            actionableWeakRegionCount: actionableWeakRegionCount,
            saturatedWeakRegionCount: saturatedWeakRegionCount,
            remoteWeakRegionCount: remoteWeakRegionCount,
            lowLightActive: lowLightActive,
            unresolvedRevisitFlagIDs: Array(
                unresolvedRevisitFlagIDs.prefix(4)
            ),
            targetScanState: targetScanState,
            candidateTargetIDs: Array(candidateTargetIDs.prefix(4)),
            missingTaskItemCount: missingTaskItemCount,
            resourcePressureKinds: resourcePressureKinds,
            endScanAvailable: endScanAvailable,
            diagnostics: Array(diagnostics.prefix(4))
        )
    }

    /// Compact, instruction-friendly rendering of the context — the
    /// exact payload handed to the model. Bounded identifiers only.
    public var promptDescription: String {
        var lines: [String] = [
            "stage=\(stage.rawValue)",
            "tracking=\(trackingState?.rawValue ?? "none")",
            "coverage=\(String(format: "%.2f", directionCoverageFraction))",
            "guidance_complete=\(guidanceComplete)",
            "movement=\(movementCapability.rawValue)",
            "weak_regions=\(actionableWeakRegionCount)",
            "saturated_regions=\(saturatedWeakRegionCount)",
            "remote_weak=\(remoteWeakRegionCount)",
            "low_light=\(lowLightActive)",
            "revisit_flags=\(unresolvedRevisitFlagIDs.count)",
            "target_scan=\(targetScanState ?? "none")",
            "missing_tasks=\(missingTaskItemCount)",
            "resource_pressure=\(resourcePressureKinds.joined(separator: ","))",
            "end_available=\(endScanAvailable)",
            "allowed_actions=\(ScanCopilotAction.allCases.map(\.rawValue).joined(separator: ","))",
            "allowed_templates=\(ScanCopilotAdvisoryTemplate.allCases.map(\.rawValue).joined(separator: ","))",
            "allowed_reasons=\(supportedReasonCodes.map(\.rawValue).sorted().joined(separator: ","))",
            "candidate_ids=\(candidateTargetIDs.joined(separator: ","))",
        ]
        if !diagnostics.isEmpty {
            let rendered = diagnostics.map {
                "\($0.id):\($0.code):\($0.severity.rawValue)"
            }.joined(separator: ";")
            lines.append("diagnostics=\(rendered)")
        }
        return lines.joined(separator: "\n")
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case stage
        case trackingState = "tracking_state"
        case trackingReason = "tracking_reason"
        case directionCoverageFraction =
            "direction_coverage_fraction"
        case guidanceComplete = "guidance_complete"
        case guidanceCompletionSource =
            "guidance_completion_source"
        case movementCapability = "movement_capability"
        case weakRegionKeys = "weak_region_keys"
        case actionableWeakRegionCount =
            "actionable_weak_region_count"
        case saturatedWeakRegionCount =
            "saturated_weak_region_count"
        case remoteWeakRegionCount = "remote_weak_region_count"
        case lowLightActive = "low_light_active"
        case unresolvedRevisitFlagIDs =
            "unresolved_revisit_flag_ids"
        case targetScanState = "target_scan_state"
        case candidateTargetIDs = "candidate_target_ids"
        case missingTaskItemCount = "missing_task_item_count"
        case resourcePressureKinds = "resource_pressure_kinds"
        case endScanAvailable = "end_scan_available"
        case diagnostics
    }
}

/// What a model may express: bounded string fields only. There is no
/// free-text instruction field — the draft names a whitelisted
/// template, so an accepted suggestion can never carry model-originated
/// prose (unsafe-movement or finish semantics cannot be smuggled in).
public struct ScanCopilotModelDraft: Sendable, Equatable {
    public let actionID: String
    public let templateID: String
    public let priorityID: String
    public let targetID: String?
    public let reasonCodes: [String]
    public let sourceDiagnosticIDs: [String]
    /// Digest of the context the draft was produced against; the app
    /// stamps it, so a draft replayed against a changed context fails
    /// as stale.
    public let contextDigest: String?

    public init(
        actionID: String,
        templateID: String,
        priorityID: String,
        targetID: String? = nil,
        reasonCodes: [String] = [],
        sourceDiagnosticIDs: [String] = [],
        contextDigest: String? = nil
    ) {
        self.actionID = actionID
        self.templateID = templateID
        self.priorityID = priorityID
        self.targetID = targetID
        self.reasonCodes = reasonCodes
        self.sourceDiagnosticIDs = sourceDiagnosticIDs
        self.contextDigest = contextDigest
    }
}

/// A validated, accepted suggestion (#272 output shape). Every field
/// is typed; the template ID is the `short_instruction` a persisted
/// record would carry (localized text resolves at presentation).
public struct ScanCopilotSuggestion: Sendable, Equatable {
    public let action: ScanCopilotAction
    public let template: ScanCopilotAdvisoryTemplate
    public let priority: ScanCopilotPriority
    public let targetID: String?
    public let reasonCodes: [ScanCopilotReasonCode]
    public let sourceDiagnosticIDs: [String]
    /// Digest of the context this suggestion was validated against.
    public let contextDigest: String

    public init(
        action: ScanCopilotAction,
        template: ScanCopilotAdvisoryTemplate,
        priority: ScanCopilotPriority,
        targetID: String? = nil,
        reasonCodes: [ScanCopilotReasonCode] = [],
        sourceDiagnosticIDs: [String] = [],
        contextDigest: String
    ) {
        self.action = action
        self.template = template
        self.priority = priority
        self.targetID = targetID
        self.reasonCodes = reasonCodes
        self.sourceDiagnosticIDs = sourceDiagnosticIDs
        self.contextDigest = contextDigest
    }
}

/// Why a draft failed deterministic validation. Machine-readable so
/// evaluation records can count rejection categories (#272 metrics).
public enum ScanCopilotValidationViolation:
    String,
    Sendable,
    Equatable,
    CaseIterable
{
    /// Action string is not a whitelisted `ScanCopilotAction`.
    case unknownAction = "unknown_action"
    /// Template string is not a whitelisted
    /// `ScanCopilotAdvisoryTemplate`.
    case unknownTemplate = "unknown_template"
    /// Template cannot legally sit on the chosen action.
    case templateActionMismatch = "template_action_mismatch"
    /// A finish/complete-class suggestion where normal
    /// review/finalization does not permit one.
    case finishNotPermitted = "finish_not_permitted"
    /// Movement instruction while the deterministic movement policy
    /// does not allow translation guidance.
    case movementNotQualified = "movement_not_qualified"
    /// The action cites state the context does not support (e.g.
    /// rescanning a target that does not exist).
    case actionNotSupported = "action_not_supported"
    /// A target ID outside the context's candidate set.
    case unknownTargetID = "unknown_target_id"
    /// A reason code outside the whitelisted set.
    case unknownReasonCode = "unknown_reason_code"
    /// A whitelisted reason the context does not actually support —
    /// e.g. claiming a depth/mesh problem none of the diagnostics
    /// reported.
    case reasonNotSupported = "reason_not_supported"
    /// A source diagnostic ID the context never carried.
    case unknownDiagnosticID = "unknown_diagnostic_id"
    /// The draft was produced against a different context digest.
    case staleContext = "stale_context"
    /// A draft field exceeded its bound.
    case fieldTooLong = "field_too_long"
    /// `no_action` over blocking (error-severity) diagnostics.
    case noActionWhileBlocking = "no_action_while_blocking"
}

/// Deterministic validator (#272): the only path from a model draft
/// to a displayed suggestion. Enforces the whitelist, the movement
/// qualification, the finish prohibition, ID provenance, staleness,
/// and the no-suppression rule. Zero unsafe-movement/finish actions
/// may ever pass — that is a construction guarantee this validator
/// double-checks, so tests exercise the full rejection surface.
public enum ScanCopilotValidator {
    public static func violations(
        draft: ScanCopilotModelDraft,
        context: ScanCopilotContext
    ) -> [ScanCopilotValidationViolation] {
        var violations: [ScanCopilotValidationViolation] = []
        let fieldLimit = ScanCopilotContext.maximumFieldCharacters

        if draft.actionID.count > fieldLimit
            || draft.templateID.count > fieldLimit
            || draft.priorityID.count > fieldLimit
            || (draft.targetID?.count ?? 0) > fieldLimit
            || draft.reasonCodes.count
                > ScanCopilotContext.maximumReasonCodes
            || draft.sourceDiagnosticIDs.count
                > ScanCopilotContext.maximumSourceDiagnosticIDs
        {
            violations.append(.fieldTooLong)
        }

        guard let action = ScanCopilotAction(
            rawValue: draft.actionID
        ) else {
            return violations + [.unknownAction]
        }
        guard let template = ScanCopilotAdvisoryTemplate(
            rawValue: draft.templateID
        ) else {
            return violations + [.unknownTemplate]
        }
        guard ScanCopilotPriority(rawValue: draft.priorityID) != nil
        else {
            return violations + [.unknownAction]
        }

        if !template.allowedActions.contains(action) {
            violations.append(.templateActionMismatch)
        }
        if action.requiresMovementQualification
            && context.movementCapability != .unrestricted
        {
            violations.append(.movementNotQualified)
        }
        if action == .review
            && context.stage != .review
            && !context.endScanAvailable
        {
            violations.append(.finishNotPermitted)
        }
        if !actionSupported(action, in: context) {
            violations.append(.actionNotSupported)
        }
        if let targetID = draft.targetID,
           !context.candidateTargetIDs.contains(targetID)
        {
            violations.append(.unknownTargetID)
        }

        let supportedReasons = context.supportedReasonCodes
        for raw in draft.reasonCodes {
            guard let code = ScanCopilotReasonCode(rawValue: raw) else {
                violations.append(.unknownReasonCode)
                continue
            }
            if !supportedReasons.contains(code) {
                violations.append(.reasonNotSupported)
            }
        }

        let diagnosticIDs = Set(context.diagnostics.map(\.id))
        for id in draft.sourceDiagnosticIDs
        where !diagnosticIDs.contains(id) {
            violations.append(.unknownDiagnosticID)
        }

        if let digest = draft.contextDigest,
           digest != context.contextDigest
        {
            violations.append(.staleContext)
        }

        return violations
    }

    /// Accepted typed suggestion, or nil with the violations.
    public static func validate(
        draft: ScanCopilotModelDraft,
        context: ScanCopilotContext
    ) -> (
        suggestion: ScanCopilotSuggestion?,
        violations: [ScanCopilotValidationViolation]
    ) {
        let violations = violations(draft: draft, context: context)
        guard violations.isEmpty,
              let action = ScanCopilotAction(
                  rawValue: draft.actionID
              ),
              let template = ScanCopilotAdvisoryTemplate(
                  rawValue: draft.templateID
              ),
              let priority = ScanCopilotPriority(
                  rawValue: draft.priorityID
              )
        else {
            return (nil, violations)
        }
        let suggestion = ScanCopilotSuggestion(
            action: action,
            template: template,
            priority: priority,
            targetID: draft.targetID,
            reasonCodes: draft.reasonCodes.compactMap {
                ScanCopilotReasonCode(rawValue: $0)
            },
            sourceDiagnosticIDs: draft.sourceDiagnosticIDs,
            contextDigest: context.contextDigest
        )
        return (suggestion, [])
    }

    /// Whether the action has support in the current diagnostic
    /// state. This is the "reject claims about state the
    /// deterministic layer never reported" gate: a suggestion may not
    /// point at a target, tracking problem, resource pressure, or
    /// missing-items claim the context does not carry.
    private static func actionSupported(
        _ action: ScanCopilotAction,
        in context: ScanCopilotContext
    ) -> Bool {
        let reasons = context.supportedReasonCodes
        switch action {
        case .waitForTracking:
            return reasons.contains(.trackingLimited)
                || reasons.contains(.trackingUnavailable)
        case .reduceWorkload:
            return reasons.contains(.resourcePressure)
        case .moveToGap:
            return reasons.contains(.weakRegion)
                || reasons.contains(.coverageGap)
                || reasons.contains(.remoteWeakRegion)
        case .rescanTarget:
            return reasons.contains(.targetScanIncomplete)
        case .annotate:
            return reasons.contains(.taskItemsMissing)
                || reasons.contains(.revisitFlagsPending)
        case .review:
            return reasons.contains(.reviewReady)
        case .noAction:
            return !context.hasBlockingDiagnostics
                && (context.guidanceComplete
                    || context.actionableWeakRegionCount == 0)
        case .hold, .rotate:
            // In-place advisories are always safe to suggest; the
            // model still ranks them behind supported actions via
            // the prompt's allowed-reasons list.
            return true
        }
    }
}

/// The deterministic arm of the copilot (#272): the same bounded
/// suggestion type, produced with no model at all. It is the
/// fallback whenever the model path is unavailable, fails, or is
/// rejected — the deterministic UX is complete on its own.
public enum ScanCopilotBaseline {
    /// Deterministic priority chain mirroring the app's existing
    /// guidance precedence (tracking > resources > lighting >
    /// coverage gaps > task work > on-track).
    public static func suggest(
        context: ScanCopilotContext
    ) -> ScanCopilotSuggestion {
        func make(
            _ action: ScanCopilotAction,
            _ template: ScanCopilotAdvisoryTemplate,
            _ priority: ScanCopilotPriority,
            targetID: String? = nil,
            reasons: [ScanCopilotReasonCode],
            sourceIDs: [String] = []
        ) -> ScanCopilotSuggestion {
            ScanCopilotSuggestion(
                action: action,
                template: template,
                priority: priority,
                targetID: targetID,
                reasonCodes: reasons,
                sourceDiagnosticIDs: sourceIDs,
                contextDigest: context.contextDigest
            )
        }

        let reasons = context.supportedReasonCodes
        let weakSourceIDs = context.diagnostics
            .filter {
                $0.code.hasPrefix("tracking")
                    || $0.code.hasPrefix("resource")
            }
            .map(\.id)

        switch context.trackingState {
        case .limited:
            return make(
                .waitForTracking, .waitForTracking, .high,
                reasons: [.trackingLimited],
                sourceIDs: weakSourceIDs
            )
        case .unavailable:
            return make(
                .waitForTracking, .waitForTracking, .high,
                reasons: [.trackingUnavailable],
                sourceIDs: weakSourceIDs
            )
        case .normal, nil:
            break
        }

        if !context.resourcePressureKinds.isEmpty {
            return make(
                .reduceWorkload, .reduceWorkload, .high,
                reasons: [.resourcePressure],
                sourceIDs: weakSourceIDs
            )
        }

        if context.lowLightActive {
            return make(
                .hold, .improveLighting, .normal,
                reasons: [.lowLight]
            )
        }

        if context.stage == .review {
            if context.missingTaskItemCount > 0 {
                return make(
                    .annotate, .addMissingDetails, .high,
                    reasons: [.taskItemsMissing]
                )
            }
            if !context.unresolvedRevisitFlagIDs.isEmpty {
                return make(
                    .review, .reviewFlaggedItems, .normal,
                    reasons: [.revisitFlagsPending, .reviewReady]
                )
            }
        }

        if let targetState = context.targetScanState,
           targetState == "stalled" || targetState == "expired",
           context.movementCapability == .unrestricted
        {
            return make(
                .rescanTarget, .rescanTarget, .normal,
                reasons: [.targetScanIncomplete]
            )
        }

        if context.actionableWeakRegionCount > 0 {
            if context.movementCapability == .unrestricted {
                return make(
                    .moveToGap, .revisitArea, .normal,
                    targetID: context.candidateTargetIDs.first,
                    reasons: [.weakRegion]
                )
            }
            // Movement constrained: still surface the gap, but as an
            // in-place rotation prompt instead of a translation one.
            return make(
                .rotate, .turnInPlace, .normal,
                reasons: [.weakRegion]
            )
        }

        if context.missingTaskItemCount > 0 {
            return make(
                .annotate, .addMissingDetails, .normal,
                reasons: [.taskItemsMissing]
            )
        }

        if !context.unresolvedRevisitFlagIDs.isEmpty,
           context.endScanAvailable
        {
            return make(
                .review, .reviewFlaggedItems, .low,
                reasons: [.revisitFlagsPending, .reviewReady]
            )
        }

        if context.directionCoverageFraction < 1,
           !context.guidanceComplete
        {
            return make(
                .noAction, .keepScanning, .low,
                reasons: [.coverageGap]
            )
        }

        return make(
            .noAction, .scanOnTrack, .low,
            reasons: [.noFindings]
        )
    }
}

/// Which producer supplied a displayed suggestion — provenance the
/// UI chip and the eval record both carry.
public enum ScanCopilotSuggestionSource:
    String,
    Sendable,
    Equatable
{
    /// No model ran; deterministic baseline produced it.
    case deterministicBaseline = "deterministic_baseline"
    /// The model produced a draft that passed validation.
    case modelValidated = "model_validated"
    /// The model produced a draft the validator rejected; the
    /// deterministic baseline is shown instead.
    case modelRejectedFallback = "model_rejected_fallback"
    /// The model was unavailable/failed; the deterministic baseline
    /// is shown instead.
    case modelUnavailableFallback = "model_unavailable_fallback"
}

/// Only fields the API actually exposes — never a fabricated model
/// revision (#272 audit rule).
public struct ScanCopilotModelProvenance: Sendable, Equatable {
    /// `SystemLanguageModel.variant.displayName` when the SDK exposes
    /// it (iOS 27+); nil when unavailable — never invented.
    public let modelVariantDisplayName: String?
    public let osVersion: String
    public let localeIdentifier: String
    /// `SystemLanguageModel.contextSize` when known.
    public let contextSizeLimit: Int?
    /// `LanguageModelSession.Usage` input tokens when the SDK exposes
    /// them (iOS 27+).
    public let inputTokenCount: Int?
    public let outputTokenCount: Int?
    /// App-owned prompt/schema revision marker.
    public let promptRevision: String

    public init(
        modelVariantDisplayName: String?,
        osVersion: String,
        localeIdentifier: String,
        contextSizeLimit: Int?,
        inputTokenCount: Int?,
        outputTokenCount: Int?,
        promptRevision: String
    ) {
        self.modelVariantDisplayName = modelVariantDisplayName
        self.osVersion = osVersion
        self.localeIdentifier = localeIdentifier
        self.contextSizeLimit = contextSizeLimit
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.promptRevision = promptRevision
    }
}

/// Why the model path did not produce a draft — counts toward the
/// eval's availability/failure metrics.
public enum ScanCopilotModelFailure: String, Sendable, Equatable {
    case modelUnavailable = "model_unavailable"
    case localeUnsupported = "locale_unsupported"
    case contextExceeded = "context_exceeded"
    case generationFailed = "generation_failed"
}

public struct ScanCopilotModelOutcome: Sendable {
    public let draft: ScanCopilotModelDraft?
    public let failure: ScanCopilotModelFailure?
    public let provenance: ScanCopilotModelProvenance?

    public init(
        draft: ScanCopilotModelDraft?,
        failure: ScanCopilotModelFailure?,
        provenance: ScanCopilotModelProvenance?
    ) {
        self.draft = draft
        self.failure = failure
        self.provenance = provenance
    }
}

/// The model boundary. Deterministic producers and test fakes
/// implement this; the Foundation Models adapter lives in
/// `ScanCopilotFoundationModel.swift` behind a toolchain gate.
public protocol ScanCopilotModelProducing: Sendable {
    /// One bounded suggestion attempt against a fresh, task-scoped
    /// session. Implementations return `draft: nil` plus a failure
    /// reason on any model/locale/context error — they never throw
    /// the copilot into an unusable state.
    func suggest(
        context: ScanCopilotContext
    ) async -> ScanCopilotModelOutcome
}

/// The full resolution the UI shows: always a deterministic-baseline
/// suggestion, upgraded to the model's pick only when it exists and
/// passes validation.
public struct ScanCopilotResolution: Sendable, Equatable {
    public let suggestion: ScanCopilotSuggestion
    public let source: ScanCopilotSuggestionSource
    /// Violations recorded when a model draft was rejected (empty for
    /// deterministic/model-validated resolutions).
    public let validatorViolations: [ScanCopilotValidationViolation]
    /// Model-path failure category when the model did not produce a
    /// draft.
    public let modelFailure: ScanCopilotModelFailure?
    public let provenance: ScanCopilotModelProvenance?

    public init(
        suggestion: ScanCopilotSuggestion,
        source: ScanCopilotSuggestionSource,
        validatorViolations: [ScanCopilotValidationViolation] = [],
        modelFailure: ScanCopilotModelFailure? = nil,
        provenance: ScanCopilotModelProvenance? = nil
    ) {
        self.suggestion = suggestion
        self.source = source
        self.validatorViolations = validatorViolations
        self.modelFailure = modelFailure
        self.provenance = provenance
    }

    /// Digest of the context the displayed suggestion was validated
    /// against — the staleness marker a caller compares before
    /// re-rendering.
    public var contextDigest: String {
        suggestion.contextDigest
    }
}

/// Orchestrator: deterministic first, optional model second,
/// deterministic validation last. Equivalent contexts (same digest)
/// are debounced to one model request by the caller.
public struct ScanCopilotEngine: Sendable {
    public let model: (any ScanCopilotModelProducing)?

    public init(model: (any ScanCopilotModelProducing)? = nil) {
        self.model = model
    }

    public func resolve(
        context: ScanCopilotContext
    ) async -> ScanCopilotResolution {
        let baseline = ScanCopilotBaseline.suggest(context: context)
        guard let model else {
            return ScanCopilotResolution(
                suggestion: baseline,
                source: .deterministicBaseline
            )
        }

        let outcome = await model.suggest(context: context)
        guard let draft = outcome.draft else {
            return ScanCopilotResolution(
                suggestion: baseline,
                source: .modelUnavailableFallback,
                modelFailure: outcome.failure ?? .generationFailed,
                provenance: outcome.provenance
            )
        }

        // Bind the draft to the context it was generated for; the
        // staleness gate then protects against a replayed draft.
        let bound = ScanCopilotModelDraft(
            actionID: draft.actionID,
            templateID: draft.templateID,
            priorityID: draft.priorityID,
            targetID: draft.targetID,
            reasonCodes: draft.reasonCodes,
            sourceDiagnosticIDs: draft.sourceDiagnosticIDs,
            contextDigest: context.contextDigest
        )
        let (suggestion, violations) = ScanCopilotValidator.validate(
            draft: bound,
            context: context
        )
        if let suggestion {
            return ScanCopilotResolution(
                suggestion: suggestion,
                source: .modelValidated,
                provenance: outcome.provenance
            )
        }
        return ScanCopilotResolution(
            suggestion: baseline,
            source: .modelRejectedFallback,
            validatorViolations: violations,
            provenance: outcome.provenance
        )
    }
}

/// Localized operator-facing copy for copilot output. The only
/// instruction text a suggestion can ever render — the model selects
/// a template, this table supplies the wording, and movement
/// templates keep the #313 qualified-path phrasing. Additional
/// captioning always labels the suggestion source so model output
/// is never presented as authoritative (#272).
public enum ScanCopilotCopy {
    /// The advisory instruction line for a whitelisted template.
    public static func instruction(
        for template: ScanCopilotAdvisoryTemplate
    ) -> String {
        switch template {
        case .holdSteady:
            return String(
                localized:
                    "Hold the phone steady and keep viewing this area."
            )
        case .improveLighting:
            return String(
                localized:
                    "Lighting is weak — add light if you can, or slow down."
            )
        case .slowDown:
            return String(
                localized:
                    "Slow down and keep pointing at seen features."
            )
        case .turnInPlace:
            return String(
                localized:
                    "Turn in place toward the uncovered directions."
            )
        case .revisitArea:
            return String(
                localized:
                    "If the path is clear, revisit the weak area."
            )
        case .moveCloser:
            return String(
                localized:
                    "If the path is clear, move a little closer to the target area."
            )
        case .rescanTarget:
            return String(
                localized:
                    "If the path is clear, re-scan the target object."
            )
        case .waitForTracking:
            return String(
                localized:
                    "Hold still and let tracking recover."
            )
        case .reduceWorkload:
            return String(
                localized:
                    "Pause heavy actions while the device recovers."
            )
        case .addMissingDetails:
            return String(
                localized:
                    "Add the missing task details."
            )
        case .reviewFlaggedItems:
            return String(
                localized:
                    "Review the flagged items."
            )
        case .keepScanning:
            return String(
                localized:
                    "Keep scanning — nothing needs attention yet."
            )
        case .scanOnTrack:
            return String(
                localized:
                    "Scan is on track — no extra action needed."
            )
        }
    }

    /// The source label stamped on every displayed suggestion so a
    /// model pick is never indistinguishable from the deterministic
    /// baseline (#272 provenance).
    public static func sourceCaption(
        for resolution: ScanCopilotResolution
    ) -> String {
        switch resolution.source {
        case .deterministicBaseline:
            return String(localized: "Deterministic guidance")
        case .modelValidated:
            if let variant = resolution.provenance?
                .modelVariantDisplayName
            {
                return String(
                    format: String(
                        localized: "Copilot suggestion (%@)"
                    ),
                    variant
                )
            }
            return String(localized: "Copilot suggestion")
        case .modelRejectedFallback:
            return String(
                localized:
                    "Deterministic guidance (model check failed)"
            )
        case .modelUnavailableFallback:
            return String(
                localized:
                    "Deterministic guidance (copilot unavailable)"
            )
        }
    }

    /// Priority caption; only high-priority picks get one.
    public static func priorityCaption(
        for priority: ScanCopilotPriority
    ) -> String? {
        guard priority == .high else { return nil }
        return String(localized: "Priority: high")
    }
}

private extension JSONEncoder {
    /// Canonical deterministic encoding for digests — sorted keys so
    /// the same context always hashes identically.
    static let canonical: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
