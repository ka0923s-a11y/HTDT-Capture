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
    /// The generic task profile chosen before acquisition (#352).
    /// Nil means a general capture with no task checklist.
    public let taskProfile: CaptureTaskProfile?
    /// The imported HTDT task plan bound for this capture (#240/#352),
    /// decoded for display. Its bytes persist verbatim at Begin.
    public let importedTaskPlan: HTDTCaptureTaskPlan?
    /// Human-readable import failure for the last attempted plan file.
    public let taskPlanImportError: String?
    /// Last-known camera authorization shown as denied-state UI
    /// (#295): setup surfaces a denied prerequisite with a direct
    /// Settings path instead of letting Begin run into a failure.
    public let cameraPermission: CameraPermissionStatus?

    public init(
        capabilities: CaptureCapabilityMatrix,
        storagePreflight: CaptureStoragePreflight,
        deviceReadiness: CaptureDeviceReadiness?,
        resolvedMode: CaptureMode?,
        taskProfile: CaptureTaskProfile? = nil,
        importedTaskPlan: HTDTCaptureTaskPlan? = nil,
        taskPlanImportError: String? = nil,
        cameraPermission: CameraPermissionStatus? = nil
    ) {
        self.capabilities = capabilities
        self.storagePreflight = storagePreflight
        self.deviceReadiness = deviceReadiness
        self.resolvedMode = resolvedMode
        self.taskProfile = taskProfile
        self.importedTaskPlan = importedTaskPlan
        self.taskPlanImportError = taskPlanImportError
        self.cameraPermission = cameraPermission
    }

    /// Which mission authority will bind at Begin: an imported HTDT
    /// task plan wins over the generic profile (#352).
    public var missionKind: CaptureMissionKind {
        importedTaskPlan != nil ? .htdtTaskPlan
            : taskProfile != nil ? .taskProfile
            : .generalCapture
    }

    /// A short human-readable mission statement — what this capture is
    /// for — shown before Start Scan and carried into the binding
    /// advisory note.
    public var missionStatement: String {
        switch missionKind {
        case .htdtTaskPlan:
            guard let plan = importedTaskPlan else { break }
            let required = plan.entityChecklist.filter {
                $0.requirement == .required
            }.count
                + plan.measurementRequests.filter {
                    $0.requirement == .required
                }.count
                + plan.surfaceReviewTasks.filter {
                    $0.requirement == .required
                }.count
            let optional = plan.allItemIDs.count - required
            return String(
                format: String(
                    localized:
                        "Mission: HTDT task plan %@ v%@ — %d required and %d optional checklist items. Mission completeness is tracked in Review and never gates ingestion readiness."
                ),
                plan.planID,
                plan.planVersion,
                required,
                optional
            )
        case .taskProfile:
            guard let profile = taskProfile else { break }
            if profile.requirements.isEmpty {
                return String(
                    format: String(
                        localized:
                            "Mission: %@ — a general room capture with no required checklist items."
                    ),
                    profile.title
                )
            }
            let required = profile.requirements.filter {
                !$0.isOptional
            }.count
            let optional = profile.requirements.count - required
            return String(
                format: String(
                    localized:
                        "Mission: %@ — %d required and %d optional items. Mission completeness is advisory and never gates ingestion readiness."
                ),
                profile.title,
                required,
                optional
            )
        case .generalCapture:
            return String(
                localized:
                    "Mission: general capture — no task checklist. You can flag anything for review while scanning."
            )
        }
        return String(localized: "Mission: general capture")
    }
}

/// The mission authority chosen pre-capture (#352).
public enum CaptureMissionKind: String, Sendable, Equatable {
    /// No task profile or plan — a short happy-path standalone scan.
    case generalCapture = "general_capture"
    /// A generic operator task profile (#217/#352).
    case taskProfile = "task_profile"
    /// An imported HTDT task plan (#240) bound verbatim.
    case htdtTaskPlan = "htdt_task_plan"
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
    /// Picks (or clears) the generic task profile bound at Begin
    /// (#352). Called with nil for a general capture.
    public let selectTaskProfile: (CaptureTaskProfile?) -> Void
    /// Imports an HTDT task plan file (#240) — the URL is opened
    /// inside the coordinator which handles security scope.
    public let importTaskPlan: (URL) -> Void
    /// Removes the imported plan, returning to generic profile intent.
    public let clearTaskPlan: () -> Void

    @State private var importingTaskPlan = false
    /// Opens the app's iOS Settings page (#295). The host decides
    /// whether the platform offers a direct path; the default is a
    /// no-op so previews/tests stay platform-neutral.
    public let openCameraSettings: () -> Void

    public init(
        presentation: CaptureSetupPresentation,
        beginScanning: @escaping () -> Void = {},
        cancel: @escaping () -> Void = {},
        selectTaskProfile: @escaping
            (CaptureTaskProfile?) -> Void = { _ in },
        importTaskPlan: @escaping (URL) -> Void = { _ in },
        clearTaskPlan: @escaping () -> Void = {},
        openCameraSettings: @escaping () -> Void = {}
    ) {
        self.presentation = presentation
        self.beginScanning = beginScanning
        self.cancel = cancel
        self.selectTaskProfile = selectTaskProfile
        self.importTaskPlan = importTaskPlan
        self.clearTaskPlan = clearTaskPlan
        self.openCameraSettings = openCameraSettings
    }

    public var body: some View {
        List {
            captureMissionSection


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

            Section {
                Text(
                    "These steps are advisory capture technique; canonical quality gates decide whether the capture can finalize."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Capture setup")
        .fileImporter(
            isPresented: $importingTaskPlan,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result,
               let url = urls.first
            {
                importTaskPlan(url)
            }
        }
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

    /// #352: mission intent is configured here — before acquisition
    /// begins — never after scanning. The chosen authority (a generic
    /// task profile or an imported HTDT plan) is bound to the working
    /// capture at Begin with its identity and version recorded.
    private var captureMissionSection: some View {
        Section {
            Text(presentation.missionStatement)
                .font(.callout)

            // `CaptureTaskProfile` isn't Hashable — the picker keys on
            // the stable identifier string instead.
            Picker(
                "Task profile",
                selection: Binding<String>(
                    get: {
                        presentation.taskProfile?.identifier
                            ?? "none"
                    },
                    set: { identifier in
                        selectTaskProfile(
                            Self.profile(forIdentifier: identifier)
                        )
                    }
                )
            ) {
                Text("No task profile")
                    .tag("none")
                Text("Geometry only")
                    .tag(CaptureTaskProfile.geometryOnly.identifier)
                Text("Room + listening position")
                    .tag(
                        CaptureTaskProfile
                            .roomAndListeningPosition.identifier
                    )
                Text("Theater layout")
                    .tag(Self.theaterProfile.identifier)
            }
            .disabled(presentation.importedTaskPlan != nil)

            if let plan = presentation.importedTaskPlan {
                LabeledContent(
                    "HTDT task plan",
                    value: "\(plan.planID) · v\(plan.planVersion)"
                )
                LabeledContent(
                    "Checklist",
                    value: String(
                        format: String(
                            localized: "%d items"
                        ),
                        plan.allItemIDs.count
                    )
                )
                Button("Remove task plan", role: .destructive) {
                    clearTaskPlan()
                }
            } else {
                Button("Import HTDT task plan…") {
                    importingTaskPlan = true
                }
            }

            if let error = presentation.taskPlanImportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            LabeledContent(
                "Strategy profile",
                value: String(localized: "Standard")
            )

            Text(
                ScanMotionGuidanceCopy.safetyDisclaimer(
                    language:
                        ScanMotionGuidanceCopy.preferredLanguage
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("Capture mission")
        } footer: {
            Text(
                "Mission intent is bound when scanning starts; changing it mid-scan is an explicit recorded action. Capture strategy profiles (#307) plug into this setup in a future update."
            )
        }
    }

    /// The default theater topology offered by the profile picker —
    /// matches the annotation workspace preset.
    private static var theaterProfile: CaptureTaskProfile {
        .theaterLayout(
            speakerRoles: standardSpeakerRoles,
            subwooferCount: 1
        )
    }

    private static func profile(
        forIdentifier identifier: String
    ) -> CaptureTaskProfile? {
        switch identifier {
        case CaptureTaskProfile.geometryOnly.identifier:
            return .geometryOnly
        case CaptureTaskProfile.roomAndListeningPosition.identifier:
            return .roomAndListeningPosition
        case theaterProfile.identifier:
            return theaterProfile
        default:
            return nil
        }
    }

    private static let standardSpeakerRoles: [String] = [
        "L", "C", "R", "LS", "RS", "LB", "RB",
        "LTF", "RTF", "LTB", "RTB",
    ]


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
