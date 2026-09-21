import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureReviewView: View {
    public let quality: CaptureQualityReport
    public let validation: BundleValidationReport?
    /// Advisory spatial-plausibility findings for the committed
    /// annotations (#247). nil means the accepted room geometry was
    /// unavailable — the section then reports "analysis unavailable"
    /// rather than implying a pass.
    public let spatialFindings: [SpatialPlausibilityFinding]?

    public init(
        quality: CaptureQualityReport,
        validation: BundleValidationReport? = nil,
        spatialFindings: [SpatialPlausibilityFinding]? = nil
    ) {
        self.quality = quality
        self.validation = validation
        self.spatialFindings = spatialFindings
    }

    public var body: some View {
        List {
            Section("Readiness") {
                LabeledContent(
                    "HTDT ingestion",
                    value: quality.readyForHTDTIngestion
                        ? String(localized: "Ready")
                        : String(localized: "Not ready")
                )
                LabeledContent(
                    "RoomPlan",
                    value: localizedRoomPlanStatus(
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
                            Text(
                                localizedSeverity(diagnostic.severity)
                            )
                                .font(.caption)
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
                LabeledContent(
                    "Quality record",
                    value: localizedIntegrity(
                        quality.integrityStatus
                    )
                )
                if let validation {
                    LabeledContent(
                        "Validator",
                        value: validation.valid
                            ? String(localized: "Pass")
                            : String(localized: "Fail")
                    )
                    LabeledContent(
                        "Bundle digest",
                        value: validation.bundleDigest.description
                    )
                    .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Capture Review")
    }

    @ViewBuilder
    private func completenessRow(
        _ title: LocalizedStringKey,
        status: CompletenessStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if status.missing.isEmpty {
                Text("Complete")
            } else {
                Text(
                    String(
                        format: String(localized: "Missing: %@"),
                        status.missing.joined(separator: ", ")
                    )
                )
            }
        }
    }

    private func localizedRoomPlanStatus(
        _ status: RoomPlanQualityStatus
    ) -> String {
        switch status {
        case .notStarted:
            return String(localized: "Not started")
        case .running:
            return String(localized: "Running")
        case .completed:
            return String(localized: "Completed")
        case .failed:
            return String(localized: "Failed")
        case .unavailable:
            return String(localized: "Unavailable")
        }
    }

    private func localizedIntegrity(
        _ status: BundleIntegrityStatus
    ) -> String {
        switch status {
        case .notChecked:
            return String(localized: "Not checked")
        case .pass:
            return String(localized: "Pass")
        case .fail:
            return String(localized: "Fail")
        }
    }

    private func localizedSeverity(
        _ severity: QualityDiagnosticSeverity
    ) -> String {
        switch severity {
        case .info:
            return String(localized: "Info")
        case .warning:
            return String(localized: "Warning")
        case .error:
            return String(localized: "Error")
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
        let severity = localizedSeverity(group.event.severity)
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
