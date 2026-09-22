import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureReviewView: View {
    public let quality: CaptureQualityReport
    public let advisory: CaptureAdvisoryReport?
    public let validation: BundleValidationReport?
    /// Advisory spatial-plausibility findings for the committed
    /// annotations (#247). nil means the accepted room geometry was
    /// unavailable — the section then reports "analysis unavailable"
    /// rather than implying a pass.
    public let spatialFindings: [SpatialPlausibilityFinding]?

    public init(
        quality: CaptureQualityReport,
        advisory: CaptureAdvisoryReport? = nil,
        validation: BundleValidationReport? = nil,
        spatialFindings: [SpatialPlausibilityFinding]? = nil
    ) {
        self.quality = quality
        self.advisory = advisory
        self.validation = validation
        self.spatialFindings = spatialFindings
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
                    ForEach(
                        Array(quality.diagnostics.enumerated()),
                        id: \.offset
                    ) { _, diagnostic in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(diagnostic.code)
                                .font(.headline)
                            Text(localizedDiagnosticMessage(diagnostic))
                            CaptureStatusView(
                                severityStatus(
                                    diagnostic.severity
                                )
                            )
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
                                localizedResourceEventKind(
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

    /// #217: an empty requirement set must not read "Complete" — that
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
                value: title
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
                    Text(outcome.requirement.identifier)
                        .font(.caption.monospaced())
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
            // #347: retained weak regions beyond the operator's final
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
            // #336: capacity eviction is reported, never silent.
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
            // #343: the convention marker identifies whether labels
            // were start-relative or bound to a room reference frame.
            LabeledContent(
                "Direction reference",
                value: directionReference == "start_relative"
                    ? String(localized: "Start direction")
                    : directionReference
            )
        }
        LabeledContent(
            "Geometry evidence",
            value: summary.geometryEvidenceMode
        )
        LabeledContent(
            "Movement mode",
            value: summary.movementCapability
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
        Text(
            String(
                localized: "Coverage is advisory; unobserved areas do not prove missing geometry."
            )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
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

    /// The frozen status vocabulary (#361) applied to the review
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

    private func localizedResourceEventKind(
        _ kind: CaptureResourceEventKind
    ) -> String {
        switch kind {
        case .thermalPressure:
            return String(localized: "Thermal pressure")
        case .memoryPressure:
            return String(localized: "Memory pressure")
        case .storagePressure:
            return String(localized: "Storage pressure")
        case .persistenceBacklog:
            return String(localized: "Persistence backlog")
        case .persistenceFailure:
            return String(localized: "Persistence failure")
        case .interruption:
            return String(localized: "Interruption")
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

    private func localizedDiagnosticMessage(
        _ diagnostic: QualityDiagnostic
    ) -> String {
        switch diagnostic.code {
        case "roomplan_not_completed":
            return String(
                localized: "RoomPlan capture has not completed successfully."
            )
        case "insufficient_mesh_anchors":
            return String(
                localized: "Active mesh anchor count is below the required minimum."
            )
        case "insufficient_evidence_frames":
            return String(
                localized: "Evidence frame count is below the required minimum."
            )
        case "depth_evidence_missing":
            return String(
                localized: "This quality ruleset requires at least one depth observation."
            )
        case "tracking_unavailable_observed":
            return String(
                localized: "AR tracking became unavailable during the capture."
            )
        case "tracking_limited_observed":
            return String(
                localized: "AR tracking was limited during part of the capture."
            )
        case "tracking_unavailable_unrecovered":
            return String(
                localized: "AR tracking became unavailable and never recovered."
            )
        case "tracking_unavailable_extended":
            return String(
                localized: "A recovered tracking-unavailable interval exceeded the recoverable duration for this ruleset."
            )
        case "tracking_unavailable_recovering":
            return String(
                localized: "Tracking recovered but has not yet stayed normal for the required stable interval."
            )
        case "tracking_unavailable_recovered":
            return String(
                localized: "AR tracking was briefly unavailable but recovered within the allowed policy."
            )
        case "tracking_coordinate_discontinuity":
            return String(
                localized: "The spatial coordinate space was reset during capture; earlier evidence may not line up."
            )
        case "depth_fallback_insufficient":
            return String(
                localized: "Retained scene-depth evidence does not satisfy the depth-fallback sufficiency policy."
            )
        case "mesh_depth_fallback":
            return String(
                localized: "Mesh evidence is below minimum; retained scene depth is used as bounded fallback."
            )
        case "integrity_not_checked":
            return String(
                localized: "Bundle integrity must pass before finalization."
            )
        case "integrity_failed":
            return String(
                localized: "Bundle integrity validation failed."
            )
        default:
            return diagnostic.message
        }
    }
}
