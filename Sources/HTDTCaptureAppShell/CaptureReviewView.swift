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
                        ? "Ready"
                        : "Not ready"
                )
                LabeledContent(
                    "RoomPlan",
                    value: quality.roomPlanStatus.rawValue
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
                            Text(diagnostic.message)
                            Text(diagnostic.severity.rawValue)
                                .font(.caption)
                        }
                    }
                }
            }

            Section("Bundle integrity") {
                LabeledContent(
                    "Quality record",
                    value: quality.integrityStatus.rawValue
                )
                if let validation {
                    LabeledContent(
                        "Validator",
                        value: validation.valid ? "Pass" : "Fail"
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
        _ title: String,
        status: CompletenessStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if status.missing.isEmpty {
                Text("Complete")
            } else {
                Text(
                    "Missing: " + status.missing.joined(separator: ", ")
                )
            }
        }
    }
}
