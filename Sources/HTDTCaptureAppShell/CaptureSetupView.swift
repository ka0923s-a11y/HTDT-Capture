import Foundation
import SwiftUI
import HTDTCaptureCore
import HTDTCapturePlatform

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
    /// Last-known camera authorization shown as denied-state UI
    /// (#295): setup surfaces a denied prerequisite with a direct
    /// Settings path instead of letting Begin run into a failure.
    public let cameraPermission: CameraPermissionStatus?

    public init(
        capabilities: CaptureCapabilityMatrix,
        storagePreflight: CaptureStoragePreflight,
        deviceReadiness: CaptureDeviceReadiness?,
        resolvedMode: CaptureMode?,
        cameraPermission: CameraPermissionStatus? = nil
    ) {
        self.capabilities = capabilities
        self.storagePreflight = storagePreflight
        self.deviceReadiness = deviceReadiness
        self.resolvedMode = resolvedMode
        self.cameraPermission = cameraPermission
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
    /// Opens the app's iOS Settings page (#295). The host decides
    /// whether the platform offers a direct path; the default is a
    /// no-op so previews/tests stay platform-neutral.
    public let openCameraSettings: () -> Void

    public init(
        presentation: CaptureSetupPresentation,
        beginScanning: @escaping () -> Void = {},
        cancel: @escaping () -> Void = {},
        openCameraSettings: @escaping () -> Void = {}
    ) {
        self.presentation = presentation
        self.beginScanning = beginScanning
        self.cancel = cancel
        self.openCameraSettings = openCameraSettings
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
                cameraPermissionRows
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

    /// Camera-authorization state in setup (#295): denied gets a
    /// direct path to iOS Settings where the platform permits it,
    /// restricted is explained as device-managed, and a valid
    /// authorization adds no friction.
    @ViewBuilder
    private var cameraPermissionRows: some View {
        switch presentation.cameraPermission {
        case .denied:
            LabeledContent(
                "Camera permission",
                value: String(localized: "Denied")
            )
            Text(
                "Camera access is off for this app. HTDT Capture needs the camera to record RoomPlan and AR evidence — enable it in iOS Settings, then Begin scanning."
            )
            .font(.caption)
            .foregroundStyle(.orange)
            #if os(iOS)
            Button(
                String(localized: "Open Settings"),
                action: openCameraSettings
            )
            .font(.callout)
            #endif
        case .restricted:
            LabeledContent(
                "Camera permission",
                value: String(localized: "Restricted")
            )
            Text(
                "Camera access is restricted on this device — for example by Screen Time or a device-management profile — so it cannot be enabled in Settings."
            )
            .font(.caption)
            .foregroundStyle(.orange)
        case .unavailable:
            LabeledContent(
                "Camera permission",
                value: String(localized: "Unavailable")
            )
            Text(
                "The camera is unavailable on this device, so capture cannot start."
            )
            .font(.caption)
            .foregroundStyle(.orange)
        case .authorized, .notDetermined, nil:
            EmptyView()
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
