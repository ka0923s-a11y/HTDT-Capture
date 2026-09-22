import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore

/// Support & Diagnostics center (issue #389): a privacy-reviewed app
/// diagnostic package — device/app/capability/build summary plus
/// capture-system health — exported as bounded JSON/text. No
/// telemetry and no capture evidence: the privacy-category preview
/// shows exactly which sections leave the device before export.
/// Category labels and summaries are localized in the app layer
/// (issue #417); the persisted manifest keeps its English text.
struct SupportDiagnosticsView: View {
    let actions: CaptureRootActions

    /// Bounded operator-facing error with the technical detail kept
    /// under a disclosure (issue #417).
    private struct StatusNotice {
        let message: String
        let detail: String
    }

    @State private var collecting = false
    @State private var package: SupportDiagnosticsPackage?
    @State private var notice: StatusNotice?
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
                    notice = nil
                    Task {
                        do {
                            package = try await actions
                                .collectSupportDiagnostics()
                        } catch {
                            notice = StatusNotice(
                                message: String(
                                    localized:
                                        "Diagnostics could not be collected."
                                ),
                                detail: String(
                                    describing: error
                                )
                            )
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
                                    DiagnosticsPresentation
                                        .categoryName(
                                            row.category
                                        )
                                )
                                .font(.callout.weight(.medium))
                                Text(
                                    DiagnosticsPresentation
                                        .contentsSummary(
                                            row.category
                                        )
                                )
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
                        .accessibilityElement(children: .combine)
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

            if let notice {
                Section("Error") {
                    Text(notice.message)
                        .font(.caption)
                        .foregroundStyle(CaptureColorRole.blocked.color)
                    DisclosureGroup(
                        String(localized: "Details")
                    ) {
                        Text(notice.detail)
                            .font(.caption2.monospaced())
                    }
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
            notice = StatusNotice(
                message: String(
                    localized:
                        "Diagnostic export could not be prepared."
                ),
                detail: String(describing: error)
            )
        }
    }
}

/// Localized labels for diagnostics privacy categories (issue
/// #417): the enum's raw tokens and English manifest summaries
/// stay in Core — every operator-facing name maps here.
enum DiagnosticsPresentation {
    static func categoryName(
        _ category: SupportDiagnosticsPrivacyCategory
    ) -> String {
        switch category {
        case .appBuild:
            String(localized: "App build")
        case .deviceSummary:
            String(localized: "Device summary")
        case .capabilitySummary:
            String(localized: "Capability summary")
        case .captureHealth:
            String(localized: "Capture health")
        case .endpointReachability:
            String(localized: "Endpoint reachability")
        }
    }

    static func contentsSummary(
        _ category: SupportDiagnosticsPrivacyCategory
    ) -> String {
        switch category {
        case .appBuild:
            String(
                localized:
                    "App name, version, build number, and emitted schema versions"
            )
        case .deviceSummary:
            String(
                localized:
                    "Device model family and OS version only — no serial numbers or identifiers"
            )
        case .capabilitySummary:
            String(
                localized:
                    "Sensor and feature capability flags (RoomPlan, LiDAR depth, mesh anchoring)"
            )
        case .captureHealth:
            String(
                localized:
                    "Counts of resource warnings, thermal stops, storage preflight verdict, quarantined/orphaned payload counts, last validation failure class"
            )
        case .endpointReachability:
            String(
                localized:
                    "Whether the configured receiver answered a capability preflight — never its URL or token"
            )
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
