import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureReviewView: View {
    public let quality: CaptureQualityReport
    public let validation: BundleValidationReport?

    public init(
        quality: CaptureQualityReport,
        validation: BundleValidationReport? = nil
    ) {
        self.quality = quality
        self.validation = validation
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
