import Foundation
import SwiftUI
import HTDTCaptureCore

/// Label-scan suggestion review (legacy bolph71656-ai/HTDT-Capture#345): lists OCR/QR/barcode-derived
/// equipment candidates for explicit operator confirmation. The sheet
/// NEVER commits anything itself — a candidate is applied only when
/// the operator taps it, and the serial stays editable text.
public struct EquipmentLabelScanSheet: View {
    public let result: EquipmentLabelScanResult
    public let onPick: (EquipmentLabelScanCandidate) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        result: EquipmentLabelScanResult,
        onPick: @escaping (EquipmentLabelScanCandidate) -> Void
    ) {
        self.result = result
        self.onPick = onPick
    }

    public var body: some View {
        List {
            Section {
                LabeledContent(
                    String(localized: "Algorithm"),
                    value: result.algorithm
                        + " @ " + result.algorithmVersion
                )
                .font(.caption)
            } header: {
                Text(
                    String(localized:
                        "Suggestions only — pick one to apply")
                )
            } footer: {
                Text(
                    result.isAmbiguous
                        ? String(localized:
                            "Multiple candidates matched. Choose one explicitly, or cancel and enter the equipment manually. Serial numbers are a hint, not proof.")
                        : String(localized:
                            "One candidate matched. Confirm it explicitly, or cancel and enter the equipment manually. Serial numbers are a hint, not proof.")
                )
            }

            Section(String(localized: "Candidates")) {
                if result.candidates.isEmpty {
                    Text(
                        String(localized:
                            "No candidates. Enter the equipment manually or pick from the catalog.")
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        Array(result.candidates.enumerated()),
                        id: \.offset
                    ) { _, candidate in
                        Button {
                            onPick(candidate)
                            dismiss()
                        } label: {
                            candidateRow(candidate)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !result.rawObservations.isEmpty {
                Section(String(localized: "Recognized text")) {
                    ForEach(
                        result.rawObservations,
                        id: \.self
                    ) { rawText in
                        Text(rawText)
                            .font(.caption.monospaced())
                    }
                }
            }
        }
        .navigationTitle(
            String(localized: "Label scan suggestions")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func candidateRow(
        _ candidate: EquipmentLabelScanCandidate
    ) -> some View {
        let name = [
            candidate.manufacturer,
            candidate.model,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(
                    name.isEmpty
                        ? String(localized: "Unknown device")
                        : name
                )
                .foregroundStyle(.primary)
                Spacer()
                Text(
                    String(
                        format: "%.0f%%",
                        Double(candidate.confidence * 100)
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if let serial = candidate.serialOrAssetTag {
                Text(
                    String(localized: "Serial/asset: ")
                        + serial
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if candidate.catalogSelectionKey != nil {
                Label(
                    String(localized: "Catalog match"),
                    systemImage: "checkmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

extension EquipmentLabelScanResult: Identifiable {
    public var id: String { evidenceRef }
}
