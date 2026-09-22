import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore

/// Support & Diagnostics center (issue #389): a privacy-reviewed app
/// diagnostic package — device/app/capability/build summary plus
/// capture-system health — exported as bounded JSON/text. No
/// telemetry and no capture evidence: the privacy-category preview
/// shows exactly which sections leave the device before export.
struct SupportDiagnosticsView: View {
    let actions: CaptureRootActions

    @State private var collecting = false
    @State private var package: SupportDiagnosticsPackage?
    @State private var errorText: String?
    @State private var shareItems: [Any]?

    var body: some View {
        List {
            Section {
                Text(
                    "Bundles a privacy-reviewed diagnostic report for support. Capture evidence — images, depth, mesh, annotations — is never included."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    collecting = true
                    errorText = nil
                    Task {
                        do {
                            package = try await actions
                                .collectSupportDiagnostics()
                        } catch {
                            errorText =
                                String(describing: error)
                        }
                        collecting = false
                    }
                } label: {
                    Label(
                        collecting
                            ? "Collecting…"
                            : "Collect diagnostics",
                        systemImage: "stethoscope"
                    )
                    .frame(maxWidth: .infinity)
                }
                .captureSecondaryAction()
                .disabled(collecting)
            }

            if let package {
                Section {
                    Label(
                        package.correlationID.displayTag,
                        systemImage:
                            "number.square"
                    )
                    .font(.headline)
                    LabeledContent(
                        "Generated",
                        value: package.report.generatedAtUTC
                    )
                    LabeledContent(
                        "App",
                        value:
                            "\(package.report.appName) \(package.report.appVersion) (\(package.report.appBuild))"
                    )
                    LabeledContent(
                        "Device",
                        value:
                            "\(package.report.deviceModelFamily) · \(package.report.osFamilyAndVersion)"
                    )
                } header: {
                    Text("Report")
                } footer: {
                    Text(
                        "Quote the correlation tag when contacting support — it matches this report exactly and contains no personal information."
                    )
                }

                Section("Privacy preview") {
                    ForEach(
                        package.privacyPreview,
                        id: \.category
                    ) { row in
                        HStack(alignment: .top) {
                            Image(
                                systemName: row.included
                                    ? "checkmark.circle.fill"
                                    : "minus.circle"
                            )
                            .foregroundStyle(
                                row.included
                                    ? .green : .secondary
                            )
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    row.category.rawValue
                                        .replacingOccurrences(
                                            of: "_",
                                            with: " "
                                        ).capitalized
                                )
                                .font(.callout.weight(.medium))
                                Text(row.contentsSummary)
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                if let reason =
                                    row.exclusionReason
                                {
                                    Text(reason)
                                        .font(.caption2)
                                        .foregroundStyle(
                                            .orange
                                        )
                                }
                            }
                        }
                    }
                    Text(
                        "Excluded by default: capture images, depth, mesh, annotations, serials, project names, secrets, file paths. A separate capture-diagnostic attachment can be produced from a failed capture's inspection screen (issue #224) — it is never bundled here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        shareJSON()
                    } label: {
                        Label(
                            "Share JSON package",
                            systemImage:
                                "square.and.arrow.up"
                        )
                    }
                    Button {
                        shareText()
                    } label: {
                        Label(
                            "Share text summary",
                            systemImage:
                                "doc.plaintext"
                        )
                    }
                } footer: {
                    Text(
                        "Export writes the bounded package to a share destination you choose — nothing is sent automatically."
                    )
                    .font(.caption)
                }
            }

            if let errorText {
                Section("Error") {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Support & Diagnostics")
        .sheet(
            isPresented: Binding(
                get: { shareItems != nil },
                set: { shown in
                    if !shown { shareItems = nil }
                }
            )
        ) {
            DiagnosticsShareSheet(items: shareItems ?? [])
        }
    }

    private func shareJSON() {
        guard let package else { return }
        writeAndShare(
            data: package.jsonPayload,
            filename: package.jsonFilename
        )
    }

    private func shareText() {
        guard let package else { return }
        writeAndShare(
            data: package.textPayload,
            filename: package.textFilename
        )
    }

    private func writeAndShare(
        data: Data,
        filename: String
    ) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            shareItems = [url]
        } catch {
            errorText = String(describing: error)
        }
    }
}

#if os(iOS)
/// System share sheet for the exported diagnostics files (#389):
/// the operator's explicit share action is the only export channel.
struct DiagnosticsShareSheet:
    UIViewControllerRepresentable
{
    let items: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
#else
struct DiagnosticsShareSheet: View {
    let items: [Any]

    var body: some View {
        Text("Sharing is available on iOS only")
    }
}
#endif
