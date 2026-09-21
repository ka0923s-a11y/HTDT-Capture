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
            Section("Before scanning") {
                LabeledContent(
                    "Scanning mode",
                    value: resolvedModeLabel
                )
                LabeledContent(
                    "RoomPlan + mesh",
                    value: availabilityLabel(
                        presentation.capabilities
                            .roomPlanMeshEligible
                    )
                )
                LabeledContent(
                    "Scene depth",
                    value: availabilityLabel(
                        presentation.capabilities
                            .sceneDepthSupported
                    )
                )
                LabeledContent(
                    "Storage",
                    value: storageLabel
                )
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
                        LabeledContent(
                            "Device readiness",
                            value: String(localized: "OK")
                        )
                    } else {
                        ForEach(
                            readiness.advisories,
                            id: \.self
                        ) { advisory in
                            Text(advisoryLabel(advisory))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if presentation.storagePreflight.readiness
                    == .critical
                {
                    Text(
                        "Very little free storage remains. Free space before scanning; capture may stop early."
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
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
            VStack(spacing: 8) {
                Button(action: beginScanning) {
                    Text("Begin scanning")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    presentation.storagePreflight.blocksCaptureStart
                )
                .accessibilityIdentifier("captureSetup.begin")

                Button(
                    "Cancel",
                    role: .cancel,
                    action: cancel
                )
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
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

    private var storageLabel: String {
        let preflight = presentation.storagePreflight
        guard let bytes = preflight.availableBytes else {
            return String(localized: "Unknown")
        }
        let formatted = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .file
        )
        switch preflight.readiness {
        case .sufficient:
            return String(
                format: String(localized: "%@ free"),
                formatted
            )
        case .low:
            return String(
                format: String(localized: "%@ free (low)"),
                formatted
            )
        case .critical:
            return String(
                format: String(
                    localized: "%@ free (critically low)"
                ),
                formatted
            )
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    private func availabilityLabel(_ available: Bool) -> String {
        available
            ? String(localized: "Available")
            : String(localized: "Unavailable")
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
