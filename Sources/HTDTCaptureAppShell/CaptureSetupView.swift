import Foundation
import SwiftUI
import HTDTCaptureCore

/// Presentation model for the pre-capture setup screen (#212).
/// Built by the host while the session is in `.setup` — before
/// RoomPlan/the capture clock exist — so every field is a snapshot of
/// what the operator confirmed at Begin.
public struct CaptureSetupPresentation: Sendable, Equatable {
    public let capabilities: CaptureCapabilityMatrix
    public let storagePreflight: CaptureStoragePreflight
    public let deviceReadiness: CaptureDeviceReadiness?
    /// The capture mode the host will actually start in (#248,
    /// Option B): mesh when the device is mesh-eligible, nil when the
    /// host cannot start a production capture at all.
    public let resolvedMode: CaptureMode?

    public init(
        capabilities: CaptureCapabilityMatrix,
        storagePreflight: CaptureStoragePreflight,
        deviceReadiness: CaptureDeviceReadiness?,
        resolvedMode: CaptureMode?
    ) {
        self.capabilities = capabilities
        self.storagePreflight = storagePreflight
        self.deviceReadiness = deviceReadiness
        self.resolvedMode = resolvedMode
    }
}

/// The explicit pre-capture setup step (#212).
///
/// Shown between Idle and capability check: the operator reads the
/// device/storage readiness and the room-preparation protocol, then
/// explicitly taps Begin scanning or cancels back to Idle. Advisory
/// technique copy is separated from canonical quality gates, and no
/// capture clock or RoomPlan session starts from this view.
public struct CaptureSetupView: View {
    public let presentation: CaptureSetupPresentation
    public let beginScanning: () -> Void
    public let cancel: () -> Void

    public init(
        presentation: CaptureSetupPresentation,
        beginScanning: @escaping () -> Void = {},
        cancel: @escaping () -> Void = {}
    ) {
        self.presentation = presentation
        self.beginScanning = beginScanning
        self.cancel = cancel
    }

    public var body: some View {
        List {
            Section {
                CaptureTaskHeader(
                    "Before scanning",
                    status: resolvedMode == nil ? .blocked : .ready
                )
            } footer: {
                if presentation.resolvedMode == nil {
                    Text(
                        "Mesh capture is not available on this device. Use a supported LiDAR-capable iPhone or iPad."
                    )
                }
            }

            Section("Device readiness") {
                LabeledContent(
                    "Scanning mode",
                    value: resolvedModeLabel
                )
                CaptureStatusContent(
                    "RoomPlan + mesh",
                    status: presentation.capabilities
                        .roomPlanMeshEligible
                        ? .ready : .unavailable
                )
                CaptureStatusContent(
                    "Scene depth",
                    status: presentation.capabilities
                        .sceneDepthSupported
                        ? .ready : .unavailable
                )
                LabeledContent("Storage") {
                    CaptureStatusView(storageStatus)
                }
                if let bytes = presentation.storagePreflight
                    .availableBytes
                {
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(
                                clamping: bytes
                            ),
                            countStyle: .file
                        ) + " "
                            + String(localized: "free")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let readiness = presentation.deviceReadiness {
                    if let battery = readiness.batteryLevel {
                        LabeledContent(
                            "Battery",
                            value: String(
                                format: "%.0f%%",
                                battery * 100
                            )
                        )
                    }
                    if readiness.advisories.isEmpty {
                        CaptureStatusContent(
                            "Device readiness",
                            status: .ready
                        )
                    }
                }
            }

            if let readiness = presentation.deviceReadiness,
               !readiness.advisories.isEmpty
            {
                Section {
                    ForEach(
                        readiness.advisories,
                        id: \.self
                    ) { advisory in
                        CaptureNotice(
                            status: .advisory,
                            title: "Device advisory",
                            message: LocalizedStringKey(
                                advisoryLabel(advisory)
                            )
                        )
                        .listRowSeparator(.hidden)
                    }
                }
            }

            if presentation.storagePreflight.readiness
                == .critical
            {
                Section {
                    CaptureNotice(
                        status: .blocked,
                        title: "Not enough free storage",
                        message:
                            "Very little free storage remains. Free space before scanning; capture may stop early."
                    )
                    .listRowSeparator(.hidden)
                }
            }

            Section("Room preparation") {
                Text(
                    "Everything stays on this device until you choose to share the .htdtcapture archive."
                )
                Text(
                    "Pause people and pets moving through the room during the scan."
                )
                Text(
                    "Note mirrors, glass, and other reflective or transparent surfaces and observe them from several angles."
                )
                Text(
                    "Move slowly, keep the phone steady, and overlap each view with the previous one. Stay within a few meters of walls and furniture."
                )
                Text(
                    "Where practical, plan a path that returns to where you started so the scan can close the loop."
                )
                Text(
                    "Turn on normal room lighting for the scan if you can — visual tracking and evidence frames still need light even though depth works in the dark. You can dim the room again afterward."
                )
            }

            Section {
                Text(
                    "These steps are advisory capture technique; canonical quality gates decide whether the capture can finalize."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Capture setup")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: CaptureDesign.Spacing.row) {
                Button(action: beginScanning) {
                    Text("Begin scanning")
                        .font(
                            CaptureDesign.Typography
                                .taskHeadline
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .capturePrimaryAction()
                .disabled(
                    presentation.storagePreflight.blocksCaptureStart
                        || presentation.resolvedMode == nil
                )
                .accessibilityIdentifier("captureSetup.begin")

                Button(
                    "Cancel",
                    role: .cancel,
                    action: cancel
                )
                .controlSize(.regular)
            }
            .padding(.horizontal, CaptureDesign.Spacing.edge)
            .padding(.vertical, CaptureDesign.Spacing.row)
            .background(.bar)
        }
    }

    private var resolvedMode: CaptureMode? {
        presentation.resolvedMode
    }

    private var storageStatus: CaptureSemanticStatus {
        switch presentation.storagePreflight.readiness {
        case .sufficient:
            return .ready
        case .low:
            return .needsReview
        case .critical:
            return .blocked
        case .unknown:
            return .unknown
        }
    }

    private var resolvedModeLabel: String {
        switch presentation.resolvedMode {
        case .roomPlanMesh:
            return String(
                localized: "RoomPlan mesh capture"
            )
        case .evidenceDepth:
            return String(
                localized: "Depth evidence capture"
            )
        case .degradedNoDepth:
            return String(
                localized: "Degraded capture (no depth)"
            )
        case nil:
            return String(
                localized: "Cannot start: mesh capture is not available on this device"
            )
        }
    }

    private func advisoryLabel(
        _ advisory: CaptureDeviceReadinessAdvisory
    ) -> String {
        switch advisory {
        case .lowBattery:
            return String(
                localized:
                    "Battery is low; charge before a long scan if possible."
            )
        case .lowPowerMode:
            return String(
                localized:
                    "Low Power Mode is on; consider turning it off for a long scan."
            )
        }
    }
}
