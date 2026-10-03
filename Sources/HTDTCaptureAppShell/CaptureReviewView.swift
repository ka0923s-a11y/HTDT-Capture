import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureReviewView: View {
    public let quality: CaptureQualityReport
    public let advisory: CaptureAdvisoryReport?
    public let validation: BundleValidationReport?
    /// Advisory spatial-plausibility findings for the committed
    /// annotations (legacy bolph71656-ai/HTDT-Capture#247). nil means the accepted room geometry was
    /// unavailable — the section then reports "analysis unavailable"
    /// rather than implying a pass.
    public let spatialFindings: [SpatialPlausibilityFinding]?
    /// Whether the working set's spatial authority is live (issue
    /// legacy bolph71656-ai/HTDT-Capture#297): false on a relaunch-recovered draft, where actions
    /// requiring a live scan (Continue scanning, save evidence frame)
    /// are filtered out of every remediation plan.
    public let spatialAuthorityLive: Bool
    /// Whether spatial capture is sealed for finalization (issue
    /// legacy bolph71656-ai/HTDT-Capture#276): a live review interrupted post-End keeps
    /// `spatialAuthorityLive` true but must not offer scan-time
    /// remediation — those actions are guaranteed dead taps.
    public let spatialAuthoritySealed: Bool
    /// Practice-mode capture (issue bolph71656-ai/HTDT-Capture#320): remediation reads as
    /// rehearsal guidance; finalization is never offered.
    public let practiceCapture: Bool
    /// Corrective-action sink (issue bolph71656-ai/HTDT-Capture#298). nil renders remediation
    /// explanations without buttons — e.g. a finalized-capture viewer.
    public let onRemediationAction:
        ((CaptureRemediationAction) -> Void)?

    public init(
        quality: CaptureQualityReport,
        advisory: CaptureAdvisoryReport? = nil,
        validation: BundleValidationReport? = nil,
        spatialFindings: [SpatialPlausibilityFinding]? = nil,
        spatialAuthorityLive: Bool = true,
        spatialAuthoritySealed: Bool = false,
        practiceCapture: Bool = false,
        onRemediationAction: (
            (CaptureRemediationAction) -> Void
        )? = nil
    ) {
        self.quality = quality
        self.advisory = advisory
        self.validation = validation
        self.spatialFindings = spatialFindings
        self.spatialAuthorityLive = spatialAuthorityLive
        self.spatialAuthoritySealed = spatialAuthoritySealed
        self.practiceCapture = practiceCapture
        self.onRemediationAction = onRemediationAction
    }

    public var body: some View {
        List {
            Section("Readiness") {
                CaptureStatusContent(
                    "HTDT ingestion",
                    status: quality.readyForHTDTIngestion
                        ? .ready : .incomplete
                )
                LabeledContent(
                    "Ruleset",
                    value: quality.rulesetVersion
                )
                CaptureStatusContent(
                    "RoomPlan",
                    status: roomPlanStatus(
                        quality.roomPlanStatus
                    )
                )
                LabeledContent(
                    "Mesh anchors",
                    value: String(quality.activeMeshAnchorCount)
                )
                LabeledContent(
                    "Evidence frames",
                    value: String(quality.evidenceFrameCount)
                )
                LabeledContent(
                    "Depth observations",
                    value: String(quality.depthEvidenceCount)
                )
                if let endCoverage = advisory?.endCoverage,
                   let trackingState =
                    endCoverage.latestTrackingState
                {
                    CaptureStatusContent(
                        "Tracking at End",
                        status: trackingStatus(
                            trackingState
                        )
                    )
                    if let reason = endCoverage
                        .latestTrackingReason,
                       !reason.isEmpty
                    {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !quality.benchmarkRefs.isEmpty {
                    ForEach(
                        quality.benchmarkRefs,
                        id: \.self
                    ) { ref in
                        LabeledContent(
                            "Benchmark evidence",
                            value: ref
                        )
                        .textSelection(.enabled)
                    }
                }
            }

            Section("Completeness") {
                completenessRow(
                    "Annotations",
                    status: quality.annotationCompleteness
                )
                completenessRow(
                    "Measurements",
                    status: quality.measurementCompleteness
                )
            }

            Section("Annotation plausibility") {
                if let spatialFindings {
                    if spatialFindings.isEmpty {
                        Text(
                            "No plausibility findings — annotations look consistent with the scanned geometry (advisory rules v"
                        )
                        + Text(
                            SpatialPlausibilityThresholds.current
                                .rulesVersion
                        )
                        + Text(")")
                    } else {
                        ForEach(spatialFindings) { finding in
                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                Text(
                                    localizedPlausibilityRule(
                                        finding.rule
                                    )
                                )
                                .font(.headline)
                                Text(
                                    finding.entityLabel
                                )
                                .font(.subheadline)
                                Text(finding.detail)
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                            }
                        }
                        Text(
                            "Advisory only — annotations are never moved automatically. Edit an annotation to correct it, or keep it as recorded."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text(
                        "Spatial analysis unavailable — no accepted room geometry was persisted for this revision."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            if let task = advisory?.taskCompleteness {
                Section("Capture task") {
                    taskCompletenessRows(task)
                    // legacy bolph71656-ai/HTDT-Capture#298: task-completeness gaps get the same
                    // corrective-action surface as quality
                    // diagnostics — an unmet requirement is actionable,
                    // not just reported.
                    let taskActions = task.remediationActions
                        .filter {
                            (spatialAuthorityLive
                                && !spatialAuthoritySealed)
                                || !$0.requiresLiveSpatialAuthority
                        }
                    if !taskActions.isEmpty,
                       onRemediationAction != nil
                    {
                        HStack(spacing: 8) {
                            ForEach(taskActions, id: \.self) {
                                action in
                                Button(
                                    localizedRemediationAction(action)
                                ) {
                                    onRemediationAction?(action)
                                }
                            }
                        }
                        .font(.callout)
                    }
                }
            }

            if let conflicts = advisory?.conflicts {
                Section("Conflicts") {
                    conflictRows(conflicts)
                }
            }

            if let consistency = advisory?.geometryConsistency {
                Section("Geometry consistency") {
                    geometryConsistencyRows(consistency)
                }
            }

            if let endCoverage = advisory?.endCoverage {
                Section("End coverage") {
                    endCoverageRows(endCoverage)
                }
            }

            if let guidance = advisory?.roomPlanGuidance {
                Section("RoomPlan guidance") {
                    roomPlanGuidanceRows(guidance)
                }
            }

            if let mesh = advisory?.meshLifecycle {
                Section("Mesh stability") {
                    meshLifecycleRows(mesh)
                }
            }

            if let depth = advisory?.depthSufficiency {
                Section("Depth evidence") {
                    depthSufficiencyRows(depth)
                }
            }
            Section("Diagnostics") {
                if quality.diagnostics.isEmpty {
                    Text("No quality diagnostics.")
                } else {
                    // legacy bolph71656-ai/HTDT-Capture#298: every diagnostic carries a typed
                    // remediation — why it matters, whether it blocks
                    // finalization, and the direct corrective action
                    // affordances. Live-spatial actions are filtered on
                    // a recovered draft; buttons are hidden entirely
                    // when no remediation sink is wired (e.g. the
                    // finalized-capture viewer).
                    ForEach(
                        Array(quality.diagnostics.enumerated()),
                        id: \.offset
                    ) { _, diagnostic in
                        let remediation = QualityRemediationCatalog
                            .remediation(for: diagnostic)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                localizedQualityDiagnosticMessage(
                                    diagnostic
                                )
                            )
                                .font(.headline)
                            Text(diagnostic.code)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                            CaptureStatusView(
                                severityStatus(
                                    diagnostic.severity
                                )
                            )
                                .font(.caption)
                            Text(
                                remediationWhyText(remediation)
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            remediationButtons(remediation)
                        }
                    }
                }
            }

            Section("Resource warnings") {
                let warnings = compactedResourceWarnings
                if warnings.visible.isEmpty {
                    Text("No resource warnings.")
                } else {
                    ForEach(
                        Array(warnings.visible.enumerated()),
                        id: \.offset
                    ) { _, group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                localizedResourceEventKindLabel(
                                    group.event.kind
                                )
                            )
                                .font(.headline)
                            Text(group.event.detail)
                            Text(localizedResourceWarningSummary(group))
                                .font(.caption)
                        }
                    }
                    if warnings.hiddenCount > 0 {
                        Text(
                            String(
                                format: String(
                                    localized: "%d additional resource warnings not shown."
                                ),
                                warnings.hiddenCount
                            )
                        )
                            .font(.caption)
                    }
                }
            }

            Section("Bundle integrity") {
                CaptureStatusContent(
                    "Quality record",
                    status: integrityStatus(
                        quality.integrityStatus
                    )
                )
                if let validation {
                    CaptureStatusContent(
                        "Validator",
                        status: validation.valid
                            ? .verified : .blocked
                    )
                    CaptureTechnicalDetail(
                        "Bundle digest",
                        value: validation.bundleDigest.description
                    )
                }
            }
        }
        .navigationTitle("Capture Review")
    }

    /// legacy bolph71656-ai/HTDT-Capture#217: an empty requirement set must not read "Complete" — that
    /// conflates technical ingestion readiness with capture-task
    /// completeness. The technical row states the requirement
    /// configuration plus the observed count; the task-level verdict
    /// lives in the advisory "Capture task" section.
    @ViewBuilder
    private func completenessRow(
        _ title: LocalizedStringKey,
        status: CompletenessStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if status.required.isEmpty {
                CaptureStatusView(.unknown)
                Text(
                    String(
                        localized: "No requirements configured"
                    )
                )
            } else if status.missing.isEmpty {
                CaptureStatusView(.verified)
            } else {
                CaptureStatusView(.incomplete)
                Text(
                    String(
                        format: String(localized: "Missing: %@"),
                        status.missing.joined(separator: ", ")
                    )
                )
            }
            Text(
                String(
                    format: String(localized: "%d captured"),
                    status.present.count
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func taskCompletenessRows(
        _ report: CaptureTaskCompletenessReport
    ) -> some View {
        if let title = report.profileTitle {
            LabeledContent(
                "Profile",
                value: CaptureMissionNeeds.taskProfileName(
                    identifier: report.profileIdentifier ?? "",
                    fallbackTitle: title
                )
            )
        }
        switch report.evaluationState {
        case .noProfileSelected:
            Text(
                String(
                    localized: "No capture task profile selected; geometry-only capture."
                )
            )
        case .noRequirementsConfigured:
            Text(
                String(
                    localized: "The selected profile has no task requirements."
                )
            )
        case .evaluated:
            LabeledContent(
                "Required unsatisfied",
                value: String(report.requiredUnsatisfiedCount)
            )
            ForEach(
                Array(report.outcomes.enumerated()),
                id: \.offset
            ) { _, outcome in
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        CaptureMissionNeeds.requirementName(
                            outcome.requirement
                        )
                    )
                    .font(.caption)
                    Text(outcome.requirement.identifier)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    CaptureStatusView(
                        taskRequirementStatus(
                            outcome.status
                        )
                    )
                    LabeledContent(
                        "Observed count",
                        value:
                            "\(outcome.observedCount)/\(outcome.requirement.minimumCount)"
                    )
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func conflictRows(
        _ report: CaptureConflictReport
    ) -> some View {
        switch report.status {
        case .unavailable:
            Text(
                String(
                    localized: "Conflict analysis was unavailable for this capture."
                )
            )
        case .analyzed:
            if report.conflicts.isEmpty {
                Text(
                    String(
                        localized: "No conflicts detected between recorded authorities."
                    )
                )
            } else {
                ForEach(
                    Array(report.conflicts.enumerated()),
                    id: \.offset
                ) { _, conflict in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(conflict.subject)
                            .font(.caption.monospaced())
                        Text(
                            localizedConflictKind(conflict.kind)
                        )
                        .font(.headline)
                        Text(conflict.detail)
                        ForEach(
                            conflict.candidates,
                            id: \.recordRef
                        ) { candidate in
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(candidate.valueText)
                                    .font(
                                        .caption.monospaced()
                                    )
                                Text(
                                    candidate.provenanceClass
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text(
                    String(
                        localized: "Conflicts are advisory; correct the annotations or measurements before finalizing."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func geometryConsistencyRows(
        _ report: RoomPlanMeshConsistencyReport
    ) -> some View {
        switch report.status {
        case .meshEvidenceAbsent:
            Text(
                String(
                    localized: "No mesh evidence was retained, so RoomPlan consistency could not be analyzed."
                )
            )
        case .roomPlanSummaryAbsent:
            Text(
                String(
                    localized: "No RoomPlan summary was produced, so consistency could not be analyzed."
                )
            )
        case .authorityUnshared:
            Text(
                String(
                    localized: "Mesh and RoomPlan evidence use different coordinate authorities; consistency is unknown."
                )
            )
        case .analyzed:
            if let residuals = report.extentResidualMeters {
                ForEach(
                    ["x", "y", "z"],
                    id: \.self
                ) { axis in
                    if let residual = residuals[axis] {
                        LabeledContent(
                            "Extent residual \(axis)",
                            value:
                                String(
                                    format:
                                        "%.2f m",
                                    residual
                                )
                        )
                    }
                }
            }
            if report.discrepantAxes.isEmpty {
                Text(
                    String(
                        localized: "RoomPlan dimensions agree with retained mesh extent within tolerance."
                    )
                )
            } else {
                Text(
                    String(
                        localized: "Discrepant axes: %@"
                    )
                    .replacingOccurrences(
                        of: "%@",
                        with: report.discrepantAxes
                            .joined(separator: ", ")
                    )
                )
            }
            LabeledContent(
                "Floor faces",
                value: String(report.floorFaceCount)
            )
            LabeledContent(
                "Wall faces",
                value: String(report.wallFaceCount)
            )
            LabeledContent(
                "Ceiling faces",
                value: String(report.ceilingFaceCount)
            )
        }
    }

    @ViewBuilder
    private func endCoverageRows(
        _ summary: CaptureEndCoverageSummary
    ) -> some View {
        LabeledContent(
            "Coverage",
            value: String(
                format: "%.0f %%",
                summary.coverageFraction * 100
            )
        )
        LabeledContent(
            "Weak sectors",
            value: String(summary.weakCells.count)
        )
        LabeledContent(
            "Observed regions",
            value: String(summary.observedRegionCount)
        )
        LabeledContent(
            "Weak regions",
            value: String(summary.weakRegionCount)
        )
        if let remoteWeak = summary.remoteWeakRegionCount,
           remoteWeak > 0
        {
            // legacy bolph71656-ai/HTDT-Capture#347: retained weak regions beyond the operator's final
            // map window stay unresolved and are reported as such.
            LabeledContent(
                "Weak beyond map view",
                value: String(remoteWeak)
            )
        }
        LabeledContent(
            "Unobserved display cells",
            value: String(summary.displayUnknownRegionCount)
        )
        if let evictions = summary.spatialRegionEvictionCount,
           evictions > 0
        {
            // legacy bolph71656-ai/HTDT-Capture#336: capacity eviction is reported, never silent.
            LabeledContent(
                "Dropped for capacity",
                value: String(
                    format: String(localized: "%d of %d cells"),
                    evictions,
                    summary.spatialMaxRegionCount ?? 0
                )
            )
        }
        if let directionReference = summary.directionReference {
            // legacy bolph71656-ai/HTDT-Capture#343: the convention marker identifies whether labels
            // were start-relative or bound to a room reference frame.
            LabeledContent(
                "Direction reference",
                value: directionReferenceName(
                    directionReference
                )
            )
        }
        LabeledContent(
            "Geometry evidence",
            value: ObservationGeometryEvidenceMode(
                rawValue: summary.geometryEvidenceMode
            ).map {
                observationGeometryEvidenceModeName($0)
            } ?? captureHumanizedToken(
                summary.geometryEvidenceMode
            )
        )
        LabeledContent(
            "Movement mode",
            value: movementCapabilityLabel(
                summary.movementCapability
            )
        )
        LabeledContent(
            "Guidance",
            value: summary.guidanceComplete
                ? String(localized: "Complete")
                : String(
                    format: "%d/%d",
                    summary.guidanceCompletedAttempts,
                    summary.guidanceMaximumAttempts
                )
        )
        // legacy bolph71656-ai/HTDT-Capture#329: the 3D vertical layer, when persisted, is reported
        // separately so a floor-level "observed" cannot hide an
        // unobserved ceiling at the same X/Z cell.
        if let voxelCount = summary.verticalVoxelCount,
           voxelCount > 0
        {
            LabeledContent(
                "Vertical cells",
                value: String(
                    format: String(
                        localized: "%d total · %d observed · %d weak"
                    ),
                    voxelCount,
                    summary.verticalObservedVoxelCount ?? 0,
                    summary.verticalWeakVoxelCount ?? 0
                )
            )
            ForEach(
                summary.sortedVerticalBandKeys,
                id: \.self
            ) { bandKey in
                if let band = summary.verticalBandSummaries?[bandKey] {
                    LabeledContent(
                        verticalBandReviewLabel(bandKey),
                        value: String(
                            format: String(
                                localized:
                                    "%d cells · %d observed · %d weak"
                            ),
                            band.voxelCount,
                            band.observedCount,
                            band.weakCount
                        )
                    )
                }
            }
        }
        LabeledContent(
            "Guidance completion",
            value: localizedGuidanceCompletionSource(
                summary.guidanceCompletionSource
            )
        )
        if let source = ScanGuidanceCompletionSource(
            rawValue: summary.guidanceCompletionSource ?? ""
        ), source != .observed, source != .incomplete {
            Text(
                captureCountPhrase(
                    summary.actionableWeakRegionCount
                        + summary.saturatedWeakRegionCount,
                    singular: String(
                        localized: "%lld weak area unresolved when guidance ended"
                    ),
                    plural: String(
                        localized: "%lld weak areas unresolved when guidance ended"
                    )
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(
            String(
                localized: "Coverage is advisory; unobserved areas do not prove missing geometry."
            )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func movementCapabilityLabel(
        _ raw: String
    ) -> String {
        switch ScanMovementCapability(rawValue: raw) {
        case .unrestricted:
            return String(localized: "Free movement")
        case .stationaryOnly:
            return String(
                localized: "Stayed in place (operator chose)"
            )
        case .safetyConstrained:
            return String(
                localized: "Movement marked unsafe by operator"
            )
        case nil:
            return captureHumanizedToken(raw)
        }
    }

    private func verticalBandReviewLabel(
        _ bandKey: String
    ) -> String {
        switch bandKey {
        case "lowest":
            return String(localized: "Floor band")
        case "lower":
            return String(localized: "Lower band")
        case "middle":
            return String(localized: "Middle band")
        case "upper":
            return String(localized: "Upper band")
        case "highest":
            return String(localized: "Ceiling band")
        default:
            return bandKey
        }
    }

    @ViewBuilder
    private func roomPlanGuidanceRows(
        _ history: RoomPlanGuidanceHistory
    ) -> some View {
        switch history.source {
        case .unavailable:
            Text(
                String(
                    localized: "RoomPlan coaching history is unavailable on this run."
                )
            )
        case .roomPlanDelegate:
            if history.transitions.isEmpty {
                Text(
                    String(
                        localized: "No coaching interruptions reported."
                    )
                )
            } else {
                ForEach(
                    Array(history.transitions.enumerated()),
                    id: \.offset
                ) { _, transition in
                    LabeledContent(
                        transition.instruction,
                        value: String(
                            format: String(
                                localized: "×%d"
                            ),
                            transition.count
                        )
                    )
                }
            }
            if history.truncated {
                Text(
                    String(
                        localized: "History truncated; only the earliest transitions are retained."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func meshLifecycleRows(
        _ summary: MeshAnchorLifecycleSummary
    ) -> some View {
        LabeledContent(
            "Anchors added",
            value: String(summary.addedCount)
        )
        LabeledContent(
            "Anchor updates",
            value: String(summary.updatedCount)
        )
        LabeledContent(
            "Anchors removed",
            value: String(summary.removedCount)
        )
        LabeledContent(
            "Final active",
            value: String(summary.finalActiveAnchors)
        )
        if let since = summary.secondsSinceLastUpdate {
            LabeledContent(
                "Since last update",
                value: String(format: "%.0f s", since)
            )
        }
        if summary.truncated {
            Text(
                String(
                    localized: "Anchor history bounded; earliest statistics retained."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func depthSufficiencyRows(
        _ summary: DepthEvidenceSufficiency
    ) -> some View {
        LabeledContent(
            "Depth frames analyzed",
            value: String(summary.framesAnalyzed)
        )
        LabeledContent(
            "Valid samples",
            value: String(summary.validSamples)
        )
        if let confident = summary.confidentFraction {
            LabeledContent(
                "Confident fraction",
                value: String(
                    format: "%.0f %%",
                    confident * 100
                )
            )
        }
        LabeledContent(
            "Best-frame coverage",
            value: String(
                format: "%.0f %%",
                summary.bestFrameSpatialCoverageFraction * 100
            )
        )
    }

    private func taskRequirementStatus(
        _ status: CaptureTaskRequirementStatus
    ) -> CaptureSemanticStatus {
        switch status {
        case .satisfied:
            return .verified
        case .partial:
            return .incomplete
        case .missing:
            return .blocked
        case .satisfiedByAlternative:
            return .derived
        case .skipped:
            return .skipped
        case .optionalAbsent:
            return .unknown
        case .overMaximum:
            return .needsReview
        }
    }

    private func localizedConflictKind(
        _ kind: CaptureConflictKind
    ) -> String {
        switch kind {
        case .sameQuantityValueDisagreement:
            return String(
                localized: "Same quantity, different values"
            )
        case .roomPlanDimensionDisagreement:
            return String(
                localized: "RoomPlan dimension disagrees with measurement"
            )
        case .annotationOrientationMissing:
            return String(
                localized: "Speaker/display annotation lacks orientation"
            )
        case .endpointBindingMissing:
            return String(
                localized: "Measurement has no endpoint binding"
            )
        }
    }

    /// The frozen status vocabulary (legacy bolph71656-ai/HTDT-Capture#361) applied to the review
    /// diagnostic surfaces.
    private func roomPlanStatus(
        _ status: RoomPlanQualityStatus
    ) -> CaptureSemanticStatus {
        switch status {
        case .notStarted:
            return .pending
        case .running:
            return .pending
        case .completed:
            return .verified
        case .failed:
            return .blocked
        case .unavailable:
            return .unavailable
        }
    }

    private func integrityStatus(
        _ status: BundleIntegrityStatus
    ) -> CaptureSemanticStatus {
        switch status {
        case .notChecked:
            return .pending
        case .pass:
            return .verified
        case .fail:
            return .blocked
        }
    }

    private func trackingStatus(
        _ state: TrackingQualityState
    ) -> CaptureSemanticStatus {
        switch state {
        case .normal:
            return .ready
        case .limited:
            return .needsReview
        case .unavailable:
            return .blocked
        }
    }

    private func severityStatus(
        _ severity: QualityDiagnosticSeverity
    ) -> CaptureSemanticStatus {
        switch severity {
        case .info:
            return .advisory
        case .warning:
            return .needsReview
        case .error:
            return .blocked
        }
    }

    /// One warning group per distinct persisted resource event;
    /// identical warnings collapse into a counted row and the visible
    /// set is bounded so long captures stay readable. Warnings remain
    /// non-blocking presentation only.
    private struct ResourceWarningGroup {
        let event: CaptureResourceEvent
        let count: Int
    }

    private var maximumResourceWarningGroups: Int { 5 }

    private var compactedResourceWarnings:
        (visible: [ResourceWarningGroup], hiddenCount: Int)
    {
        var groups: [ResourceWarningGroup] = []
        for event in quality.resourceEvents
        where event.severity == .warning
        {
            if let index = groups.firstIndex(where: {
                $0.event == event
            }) {
                groups[index] = ResourceWarningGroup(
                    event: event,
                    count: groups[index].count + 1
                )
            } else {
                groups.append(
                    ResourceWarningGroup(event: event, count: 1)
                )
            }
        }
        let visible = Array(groups.prefix(maximumResourceWarningGroups))
        let hiddenCount = groups
            .dropFirst(maximumResourceWarningGroups)
            .reduce(0) { $0 + $1.count }
        return (visible, hiddenCount)
    }

    private func localizedPlausibilityRule(
        _ rule: SpatialPlausibilityRule
    ) -> String {
        switch rule {
        case .outsideRoomExtent:
            return String(
                localized: "Outside scanned room extent"
            )
        case .belowFloor:
            return String(
                localized: "Below the scanned floor"
            )
        case .aboveRoomExtent:
            return String(
                localized: "Above the scanned room height"
            )
        case .farFromSurfaces:
            return String(
                localized: "Far from all scanned geometry"
            )
        case .duplicatePosition:
            return String(
                localized: "Duplicate position"
            )
        }
    }

    private func localizedResourceWarningSummary(
        _ group: ResourceWarningGroup
    ) -> String {
        let severity = severityStatus(
            group.event.severity
        ).localizedLabel
        if group.count > 1 {
            return String(
                format: String(localized: "%@ (×%d)"),
                severity,
                group.count
            )
        }
        return severity
    }

    /// User-facing label for the persisted guidance-completion source
    /// (issue bolph71656-ai/HTDT-Capture#296): "completed" is always qualified by *how* it
    /// completed so a bounded termination never reads as observed
    /// completeness. Pre-legacy bolph71656-ai/HTDT-Capture#296 payloads carry nil and stay honest.
    private func localizedGuidanceCompletionSource(
        _ source: String?
    ) -> String {
        guard let source,
              let value = ScanGuidanceCompletionSource(
                  rawValue: source
              )
        else {
            return String(localized: "Not recorded")
        }
        switch value {
        case .incomplete:
            return String(localized: "Not complete")
        case .observed:
            return String(
                localized: "Observed — all guidance satisfied"
            )
        case .weakRegionRetriesExhausted:
            return String(
                localized:
                    "Finished after weak-area retries were exhausted"
            )
        case .attemptBudgetExhausted:
            return String(
                localized:
                    "Finished when the guidance attempt budget ran out"
            )
        case .movementConstrained:
            return String(
                localized:
                    "Movement-constrained scan; movement checks skipped"
            )
        case .operatorDeclaredUnresolved:
            return String(
                localized:
                    "Finished with areas marked intentionally unresolved"
            )
        }
    }

    /// Corrective affordances for one diagnostic (issue bolph71656-ai/HTDT-Capture#298). When
    /// no remediation sink is wired — the finalized-capture viewer —
    /// nothing renders; on a recovered draft the live-spatial actions
    /// are already filtered by `draftActions`.
    @ViewBuilder
    private func remediationButtons(
        _ remediation: QualityRemediation
    ) -> some View {
        let available = spatialAuthorityLive
            && !spatialAuthoritySealed
            ? remediation.actions
            : remediation.draftActions
        if !available.isEmpty, let onRemediationAction {
            HStack(spacing: 8) {
                ForEach(available, id: \.self) { action in
                    Button(localizedRemediationAction(action)) {
                        onRemediationAction(action)
                    }
                }
            }
            .font(.callout)
        }
        if spatialAuthoritySealed, spatialAuthorityLive,
           remediation.actions.count != available.count
        {
            Text(
                String(
                    localized: "Spatial capture is sealed for finalization — scanning actions are unavailable."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if !spatialAuthorityLive,
           remediation.actions.count != available.count
        {
            Text(
                String(
                    localized: "Scanning actions are unavailable on a recovered draft — spatial evidence is sealed."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Why-this-matters copy keyed to the diagnostic code (issue
    /// legacy bolph71656-ai/HTDT-Capture#298): an action surface without the consequence it clears is
    /// noise. The prefix states blocking vs advisory.
    private func remediationWhyText(
        _ remediation: QualityRemediation
    ) -> String {
        let consequence: String
        if remediation.blocking {
            consequence = String(
                localized: "Blocking: this must clear before Validate and finalize."
            )
        } else {
            consequence = String(
                localized: "Advisory: finalization stays available; fixing it improves the bundle."
            )
        }
        switch remediation.diagnosticCode {
        case "roomplan_not_completed":
            return consequence + " " + String(
                localized: "Continue scanning lets RoomPlan finish its accepted geometry."
            )
        case "insufficient_mesh_anchors",
             "depth_evidence_missing":
            return consequence + " " + String(
                localized: "More scan coverage adds the geometric or depth evidence the ruleset requires."
            )
        case "depth_fallback_insufficient":
            // The diagnostic names the sub-gate(s) that failed; only
            // the matching evidence clears it — more coverage alone
            // cannot fix a confidence or per-frame-validity failure.
            return consequence + " " + String(
                localized: "Continue scanning targeting the listed depth failures — each names the evidence the gate still needs."
            )
        case "insufficient_evidence_frames":
            return consequence + " " + String(
                localized: "Saved evidence frames give reviewers the visual record the ruleset requires."
            )
        case "annotation_missing":
            return consequence + " " + String(
                localized: "The missing annotation is a semantic fix — open the annotation workspace."
            )
        case "measurement_missing":
            return consequence + " " + String(
                localized: "The missing measurement is a semantic fix — open the measurement workspace."
            )
        case "tracking_unavailable_recovering":
            return consequence + " " + String(
                localized: "Keep scanning until tracking stays normal for the required stable interval."
            )
        case "integrity_not_checked",
             "integrity_failed":
            return consequence + " " + String(
                localized: "Re-verifying reads the committed bytes again; a real corruption needs a discard."
            )
        case "resource_error":
            return consequence + " " + String(
                localized: "A resource failure damaged capture authority; only a replacement revision clears it."
            )
        default:
            if !remediation.repairableInPlace {
                return consequence + " " + String(
                    localized: "The spatial authority for this capture is already damaged; a replacement capture is the only repair."
                )
            }
            return consequence
        }
    }

    private func localizedRemediationAction(
        _ action: CaptureRemediationAction
    ) -> String {
        switch action {
        case .continueScanning:
            return String(localized: "Continue scanning")
        case .saveEvidenceFrame:
            return String(localized: "Save evidence frame")
        case .addAnnotation:
            return String(localized: "Add annotations")
        case .addMeasurement:
            return String(localized: "Add measurement")
        case .reviewTaskRequirements:
            return String(localized: "Review task requirements")
        case .verifyIntegrityAgain:
            return String(localized: "Re-verify integrity")
        case .startReplacementRevision:
            return String(localized: "Start replacement capture")
        case .discardDraft:
            return String(localized: "Discard this capture")
        }
    }
}
