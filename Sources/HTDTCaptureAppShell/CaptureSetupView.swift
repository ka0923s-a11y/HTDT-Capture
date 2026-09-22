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
    /// Operator's multi-region capture intent (#353): when on, the
    /// connected-space workflow is reachable for this capture.
    public let connectedSpaceIntent: Binding<Bool>
    /// Opens the mission-document importer (task plans, as-built
    /// plans, repair task plans as .json) (#353/#321).
    public let onImportMissionDocument: () -> Void
    public let beginScanning: () -> Void
    public let cancel: () -> Void
    /// Opens the app's iOS Settings page (#295). The host decides
    /// whether the platform offers a direct path; the default is a
    /// no-op so previews/tests stay platform-neutral.
    public let openCameraSettings: () -> Void

    public init(
        presentation: CaptureSetupPresentation,
        connectedSpaceIntent: Binding<Bool>
            = .constant(false),
        onImportMissionDocument: @escaping () -> Void = {},
        beginScanning: @escaping () -> Void = {},
        cancel: @escaping () -> Void = {},
        openCameraSettings: @escaping () -> Void = {}
    ) {
        self.presentation = presentation
        self.connectedSpaceIntent = connectedSpaceIntent
        self.onImportMissionDocument = onImportMissionDocument
        self.beginScanning = beginScanning
        self.cancel = cancel
        self.openCameraSettings = openCameraSettings
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

            // #353: mission opt-in lives at setup so a simple
            // capture is never burdened with mission controls.
            Section("Mission") {
                Toggle(
                    "Multi-region connected capture",
                    isOn: connectedSpaceIntent
                )
                Button("Import mission document (.json)") {
                    onImportMissionDocument()
                }
                Text(
                    "Task plans, as-built plans, and HTDT repair plans import as .json mission documents."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
