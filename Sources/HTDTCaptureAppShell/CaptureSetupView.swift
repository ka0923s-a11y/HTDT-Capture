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
    /// Current finalized-data backup policy so the privacy disclosure
    /// states the actual behavior before the operator confirms
    /// (#305).
    public let finalizedBackupPolicy: FinalizedBackupPolicy
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
    /// End-accepted drafts that survived an interrupted capture
    /// (#437) — surfaced on setup so a stranded capture is
    /// discoverable with its next-step affordances before a new
    /// capture starts.
    public let interruptedDrafts: [RecoverableWorkingRevision]

    public init(
        capabilities: CaptureCapabilityMatrix,
        storagePreflight: CaptureStoragePreflight,
        deviceReadiness: CaptureDeviceReadiness?,
        resolvedMode: CaptureMode?,
        finalizedBackupPolicy: FinalizedBackupPolicy
            = .backupEligible,
        taskProfile: CaptureTaskProfile? = nil,
        importedTaskPlan: HTDTCaptureTaskPlan? = nil,
        taskPlanImportError: String? = nil,
        cameraPermission: CameraPermissionStatus? = nil,
        interruptedDrafts: [RecoverableWorkingRevision] = []
    ) {
        self.capabilities = capabilities
        self.storagePreflight = storagePreflight
        self.deviceReadiness = deviceReadiness
        self.resolvedMode = resolvedMode
        self.finalizedBackupPolicy = finalizedBackupPolicy
        self.taskProfile = taskProfile
        self.importedTaskPlan = importedTaskPlan
        self.taskPlanImportError = taskPlanImportError
        self.cameraPermission = cameraPermission
        self.interruptedDrafts = interruptedDrafts
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
    /// Operator's multi-region capture intent (#353): when on, the
    /// connected-space workflow is reachable for this capture.
    public let connectedSpaceIntent: Binding<Bool>
    /// Opens the mission-document importer (task plans, as-built
    /// plans, repair task plans as .json) (#353/#321).
    public let onImportMissionDocument: () -> Void
    /// Selected capture-strategy profile (#307): guidance/evidence
    /// budgets only — the choice steers prompts, never quality gates.
    /// `strategyPinned` means a task plan fixed the strategy and the
    /// picker is display-only.
    public let selectedStrategyID: CaptureStrategyIdentifier
    public let strategyPinnedByTaskPlan: Bool
    /// Imported plan-reference underlay, when the operator attached
    /// one (#322). Reference-only authority — displayed here so the
    /// operator sees the plan is registered before scanning.
    public let planUnderlay: PlanUnderlayDocument?
    public let selectCaptureStrategy:
        (CaptureStrategyIdentifier) -> Void
    /// Presents the plan-document importer (#322).
    public let importPlanReference: () -> Void
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
    /// #437: reopens a stranded draft — leaves setup for the sealed
    /// Review so the capture can be finished.
    public let onResumeDraft: (RecoverableWorkingRevision) -> Void
    /// #437: permanently removes a stranded draft's saved data.
    public let onDiscardDraft: (RecoverableWorkingRevision) -> Void

    @State private var importingTaskPlan = false
    /// Draft pending discard confirmation (#437) — removing it is
    /// irreversible, so the affordance confirms first.
    @State private var pendingDraftDiscard:
        RecoverableWorkingRevision?
    /// Opens the app's iOS Settings page (#295). The host decides
    /// whether the platform offers a direct path; the default is a
    /// no-op so previews/tests stay platform-neutral.
    public let openCameraSettings: () -> Void

    public init(
        presentation: CaptureSetupPresentation,
        connectedSpaceIntent: Binding<Bool>
            = .constant(false),
        onImportMissionDocument: @escaping () -> Void = {},
        selectedStrategyID: CaptureStrategyIdentifier = .standard,
        strategyPinnedByTaskPlan: Bool = false,
        planUnderlay: PlanUnderlayDocument? = nil,
        selectCaptureStrategy: @escaping
            (CaptureStrategyIdentifier) -> Void = { _ in },
        importPlanReference: @escaping () -> Void = {},
        beginScanning: @escaping () -> Void = {},
        cancel: @escaping () -> Void = {},
        selectTaskProfile: @escaping
            (CaptureTaskProfile?) -> Void = { _ in },
        importTaskPlan: @escaping (URL) -> Void = { _ in },
        clearTaskPlan: @escaping () -> Void = {},
        onResumeDraft: @escaping
            (RecoverableWorkingRevision) -> Void = { _ in },
        onDiscardDraft: @escaping
            (RecoverableWorkingRevision) -> Void = { _ in },
        openCameraSettings: @escaping () -> Void = {}
    ) {
        self.presentation = presentation
        self.connectedSpaceIntent = connectedSpaceIntent
        self.onImportMissionDocument = onImportMissionDocument
        self.selectedStrategyID = selectedStrategyID
        self.strategyPinnedByTaskPlan = strategyPinnedByTaskPlan
        self.planUnderlay = planUnderlay
        self.selectCaptureStrategy = selectCaptureStrategy
        self.importPlanReference = importPlanReference
        self.beginScanning = beginScanning
        self.cancel = cancel
        self.selectTaskProfile = selectTaskProfile
        self.importTaskPlan = importTaskPlan
        self.clearTaskPlan = clearTaskPlan
        self.onResumeDraft = onResumeDraft
        self.onDiscardDraft = onDiscardDraft
        self.openCameraSettings = openCameraSettings
    }

    public var body: some View {
        List {
            captureMissionSection

            // #437: a stranded draft is discoverable before a new
            // capture starts — the same resume/discard affordances
            // the home surface offers.
            if !presentation.interruptedDrafts.isEmpty {
                Section {
                    CaptureNotice(
                        status: .draft,
                        title: "Interrupted capture",
                        message:
                            "A capture ended or was interrupted before it was saved. Its data is kept as a draft — reopen it to finish, or discard it."
                    )
                    .listRowSeparator(.hidden)
                    ForEach(
                        presentation.interruptedDrafts
                    ) { draft in
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(
                                workingRevisionPhaseName(
                                    draft.phase
                                )
                            )
                            CaptureTechnicalText(
                                draft.revisionID.description
                            )
                            HStack(spacing: 12) {
                                Button("Resume the draft") {
                                    onResumeDraft(draft)
                                }
                                Button(
                                    "Discard the draft",
                                    role: .destructive
                                ) {
                                    pendingDraftDiscard = draft
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } footer: {
                    Text(
                        "Reopening restores Review — you can finish annotations and save, but you cannot resume scanning."
                    )
                }
            }

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

            // #364 §4: actionable readiness summary first; the
            // capability diagnostics behind it are evidence, not
            // tasks, so they live in a collapsed device-details
            // disclosure instead of competing with the Begin path.
            Section("Device readiness") {
                LabeledContent(
                    "Scanning mode",
                    value: resolvedModeLabel
                )
                LabeledContent("Storage") {
                    CaptureStatusView(storageStatus)
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
                DisclosureGroup("Device details") {
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
                    if let bytes = presentation.storagePreflight
                        .availableBytes
                    {
                        LabeledContent(
                            "Free storage",
                            value: ByteCountFormatter.string(
                                fromByteCount: Int64(
                                    clamping: bytes
                                ),
                                countStyle: .file
                            )
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

            // #364 §4: strategy choice is a setup control in its own
            // right — it must render for every readiness state, not
            // only when storage is critical.
            Section("Capture strategy") {
                Picker(
                    String(localized: "Capture strategy"),
                    selection: Binding(
                        get: { selectedStrategyID },
                        set: selectCaptureStrategy
                    )
                ) {
                    ForEach(
                        CaptureStrategyIdentifier.allCases,
                        id: \.self
                    ) { identifier in
                        Text(
                            strategyLabel(identifier)
                        ).tag(identifier)
                    }
                }
                .disabled(strategyPinnedByTaskPlan)
                .accessibilityIdentifier(
                    "captureSetup.strategy"
                )
                if strategyPinnedByTaskPlan {
                    Text(
                        "Strategy is set by the task plan for this capture."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "The strategy adjusts guidance prompts and evidence budgets. It does not change whether the capture meets HTDT ingestion quality."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Plan reference") {
                if let underlay = planUnderlay {
                    LabeledContent(
                        String(localized: "Source"),
                        value: underlaySourceLabel(underlay)
                    )
                    LabeledContent(
                        String(localized: "Alignment"),
                        value: planUnderlayAlignmentMethodName(
                            underlay.alignment.method
                        )
                    )
                    if let residual =
                        underlay.alignment.residualMeters
                    {
                        LabeledContent(
                            String(localized: "Alignment residual"),
                            value: String(
                                format: "%.3f m", residual
                            )
                        )
                    }
                    Text(
                        "The plan is reference only. Scale and alignment come from the plan document; observed coverage is never replaced by plan geometry."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Button(
                    planUnderlay == nil
                        ? String(
                            localized: "Import plan reference…"
                        )
                        : String(
                            localized: "Replace plan reference…"
                        )
                ) {
                    importPlanReference()
                }
                .accessibilityIdentifier(
                    "captureSetup.planReference"
                )
                cameraPermissionRows
            }

            // #364 §4: prep items read as a checklist with a
            // single "Why?" disclosure; privacy disclosures stay
            // separate so they are never mistaken for technique.
            Section("Room preparation") {
                Label(
                    "Pause people and pets moving through the room during the scan.",
                    systemImage: "figure.2"
                )
                Label(
                    "Note mirrors, glass, and other reflective or transparent surfaces and observe them from several angles.",
                    systemImage: "rectangle.dashed"
                )
                Label(
                    "Move slowly, keep the phone steady, and overlap each view with the previous one. Stay within a few meters of walls and furniture.",
                    systemImage: "figure.walk.motion"
                )
                Label(
                    "Where practical, plan a path that returns to where you started so the scan can close the loop.",
                    systemImage: "arrow.uturn.left.circle"
                )
                Label(
                    "Turn on normal room lighting for the scan if you can — visual tracking and evidence frames still need light even though depth works in the dark. You can dim the room again afterward.",
                    systemImage: "lightbulb"
                )
                DisclosureGroup("Why are these recommended?") {
                    Text(
                        "Moving objects and reflective surfaces can confuse tracking or leave gaps in the room model. Slow, overlapping movement with a loop-closing path gives the reconstruction redundant views to check itself against."
                    )
                    .font(.callout)
                }
            }

            Section("Privacy") {
                Text(
                    "Everything stays on this device until you choose to share the .htdtcapture archive."
                )
                Text(
                    "While you scan, working scan data stays app-private and is always excluded from device backup."
                )
                Text(finalizedDisclosureText)
                Text(
                    "Sharing or sending to HTDT is always an explicit action you choose — device backup never sends data to HTDT."
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
        .confirmationDialog(
            "Discard the draft?",
            isPresented: Binding(
                get: { pendingDraftDiscard != nil },
                set: { presented in
                    if !presented { pendingDraftDiscard = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingDraftDiscard
        ) { draft in
            Button("Discard the draft", role: .destructive) {
                onDiscardDraft(draft)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Permanently removes the draft's saved data.")
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
                        || cameraPermissionBlocksStart
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

    /// Working-vs-finalized retention disclosure (#305): states the
    /// configured policy before the capture starts rather than
    /// implying one.
    private var finalizedDisclosureText: String {
        switch presentation.finalizedBackupPolicy {
        case .backupEligible:
            return String(
                localized:
                    "After a successful capture, the finalized capture and its export archive stay in this app's storage on this device and may be included in your device backup."
            )
        case .excludedFromBackup:
            return String(
                localized:
                    "After a successful capture, the finalized capture and its export archive stay in this app's storage on this device and are excluded from device backup."
            )
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

            missionNeedsRows

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
                DescribedPickerOption(
                    title: String(localized: "No task profile"),
                    detail: String(localized:
                        "Plain capture — geometry is recorded and no task requirements are checked.")
                )
                .tag("none")
                DescribedPickerOption(
                    title: CaptureMissionNeeds.taskProfileName(
                        CaptureTaskProfile.geometryOnly
                    ),
                    detail: CaptureMissionNeeds
                        .taskProfileDescription(
                            identifier: CaptureTaskProfile
                                .geometryOnly.identifier
                        )
                )
                .tag(CaptureTaskProfile.geometryOnly.identifier)
                DescribedPickerOption(
                    title: CaptureMissionNeeds.taskProfileName(
                        CaptureTaskProfile.roomAndListeningPosition
                    ),
                    detail: CaptureMissionNeeds
                        .taskProfileDescription(
                            identifier: CaptureTaskProfile
                                .roomAndListeningPosition.identifier
                        )
                )
                .tag(
                    CaptureTaskProfile
                        .roomAndListeningPosition.identifier
                )
                DescribedPickerOption(
                    title: CaptureMissionNeeds.taskProfileName(
                        Self.theaterProfile
                    ),
                    detail: CaptureMissionNeeds
                        .taskProfileDescription(
                            identifier: Self.theaterProfile.identifier
                        )
                )
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
                    .foregroundStyle(CaptureColorRole.blocked.color)
            }

            Text(
                ScanMotionGuidanceCopy.safetyDisclaimer()
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("Capture mission")
        } footer: {
            Text(
                "Mission intent is bound when scanning starts; changing it mid-scan is an explicit recorded action."
            )
        }
    }

    /// "This capture needs" (#364 §4): the mission's itemized needs
    /// in operator vocabulary — counts and optional flags, never
    /// schema identifiers. Shown for every mission kind; a general
    /// capture lists only the baseline room-geometry need.
    @ViewBuilder
    private var missionNeedsRows: some View {
        let needs = missionNeeds
        if !needs.isEmpty {
            Text("This capture needs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(needs, id: \.self) { need in
                HStack {
                    Label(
                        need.title,
                        systemImage: missionNeedIcon(need.kind)
                    )
                    Spacer()
                    if need.isOptional {
                        Text("Optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if need.count > 1 {
                        Text(String(format: "%d×", need.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var missionNeeds: [CaptureMissionNeed] {
        switch presentation.missionKind {
        case .htdtTaskPlan:
            if let plan = presentation.importedTaskPlan {
                return CaptureMissionNeeds.needs(for: plan)
            }
            return []
        case .taskProfile:
            if let profile = presentation.taskProfile {
                return CaptureMissionNeeds.needs(for: profile)
            }
            return []
        case .generalCapture:
            return [CaptureMissionNeeds.roomGeometry]
        }
    }

    private func missionNeedIcon(
        _ kind: CaptureMissionNeed.Kind
    ) -> String {
        switch kind {
        case .roomGeometry:
            return "cube"
        case .annotationEntity:
            return "mappin.and.ellipse"
        case .speakerRole:
            return "speaker.wave.2"
        case .measurement:
            return "ruler"
        case .semanticTask:
            return "tag"
        case .surfaceReview:
            return "rectangle.checkered"
        }
    }

    /// The default theater topology offered by the profile picker —
    /// the same `SpeakerLayoutProfile`-derived preset the annotation
    /// workspace offers (#426).
    private static var theaterProfile: CaptureTaskProfile {
        .theaterLayout
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

    /// Begin stays disabled while the camera is known-denied,
    /// restricted, or unavailable (#429): starting would land on a
    /// guaranteed permission failure, so the permission row's "Open
    /// Settings" action and explanation remain the single path out.
    /// A not-determined status may still begin — the system prompt
    /// runs inside the normal start flow.
    private var cameraPermissionBlocksStart: Bool {
        switch presentation.cameraPermission {
        case .denied, .restricted, .unavailable:
            return true
        case .authorized, .notDetermined, nil:
            return false
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
            .foregroundStyle(CaptureColorRole.attention.color)
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
            .foregroundStyle(CaptureColorRole.attention.color)
        case .unavailable:
            LabeledContent(
                "Camera permission",
                value: String(localized: "Unavailable")
            )
            Text(
                "The camera is unavailable on this device, so capture cannot start."
            )
            .font(.caption)
            .foregroundStyle(CaptureColorRole.attention.color)
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

    private func strategyLabel(
        _ identifier: CaptureStrategyIdentifier
    ) -> String {
        switch identifier {
        case .quickScan:
            return String(localized: "Quick scan")
        case .standard:
            return String(localized: "Standard")
        case .detailed:
            return String(localized: "Detailed")
        case .commissioning:
            return String(localized: "Commissioning")
        }
    }

    private func underlaySourceLabel(
        _ underlay: PlanUnderlayDocument
    ) -> String {
        if underlay.sourceKind == .htdtReference {
            return underlay.htdtReferenceID
                ?? String(localized: "HTDT reference")
        }
        return underlay.sourceFilename
            ?? String(localized: "Imported file")
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
