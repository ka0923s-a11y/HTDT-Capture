import Foundation
import SwiftUI
import HTDTCaptureCore

/// Production surface for the merged-but-unreachable advanced
/// workflows (issue bolph71656-ai/HTDT-Capture#353): task-plan checklist, connected-space
/// tracking, as-built verification, post-scan/instrument authoring and
/// HTDT repair tasks (issue bolph71656-ai/HTDT-Capture#321). Each surface is reachable through
/// one `MissionWorkflowEntry` row from the capture root and carries
/// the same state the coordinator holds — nothing here is a test-only
/// construction.
public struct MissionWorkflowsView: View {
    public let entries: [MissionWorkflowEntry]
    public let taskPlan: HTDTCaptureTaskPlan?
    public let taskPlanOutcomes:
        [CaptureTaskPlanStatusDocument.ItemOutcome]
    public let connectedSpaceIntent: Bool
    public let connectedTracker: ConnectedSpaceTracker?
    public let asBuiltPlanLoaded: Bool
    public let asBuiltItems: [AsBuiltVerificationItem]
    public let asBuiltGhostOverlayEnabled: Bool
    public let asBuiltAlignmentInstalled: Bool
    /// The installed plan→capture alignment authority, when one has
    /// been established (issue bolph71656-ai/HTDT-Capture#293) — mechanism/residual surface in
    /// the alignment section.
    public let asBuiltAlignment: PlanAlignmentAuthority?
    /// Ghost-overlay plan model (issue bolph71656-ai/HTDT-Capture#293): planned targets
    /// projected through the alignment authority plus observed
    /// actuals and deviation connectors; nil without alignment.
    public let asBuiltOverlayModel: RoomPlanPreviewModel?
    /// Versioned tolerance policy under which deviations are
    /// evaluated, when the plan supplies one.
    public let asBuiltTolerancePolicyRef: String?
    /// Committed annotation entities offered as "actual" observations
    /// for as-built items.
    public let asBuiltActualCandidates: [CaptureAnnotationEntity]
    /// Whether a committed room reference frame can anchor the
    /// as-built plan→capture alignment.
    public let roomFrameAvailable: Bool
    public let repairRows: [HTDTRepairTaskRow]
    /// legacy bolph71656-ai/HTDT-Capture#364 §10: whether the checklist's plan maps to a mission
    /// record so marking can collect a reason (waiver note).
    public let canRecordReason: Bool
    public let onMarkTaskPlanItem:
        (String, TaskPlanItemOutcome, String?) -> Void
    public let onSetConnectedSpaceIntent: (Bool) -> Void
    public let onBeginConnectedSegment:
        (String, CaptureRegionKind) -> Void
    public let onCompleteConnectedSegment: () -> Void
    public let onRecordPortal: (CaptureRegionID, CapturePortalKind) -> Void
    public let onRevisitRegion: (CaptureRegionID) -> Void
    public let onAsBuiltMarkUnavailable: (String) -> Void
    public let onAsBuiltEstablishAlignment: () -> Void
    public let onAsBuiltRecordActual:
        (String, AnnotationEntityID) -> Void
    public let onResolveRepairTask: (HTDTRepairTaskRow) -> Void
    /// Closes the sheet and opens the annotation workspace on the live
    /// capture (post-scan authoring + instrument import entry).
    public let onOpenAnnotationWorkspace: () -> Void

    @State private var beginSegmentShown = false
    @State private var segmentLabel = ""
    @State private var segmentKind: CaptureRegionKind = .room
    @State private var actualSelections:
        [String: AnnotationEntityID] = [:]
    // Ghost-overlay plan surface state (issue bolph71656-ai/HTDT-Capture#293): selection only —
    // it never persists into any authority document.
    @State private var overlaySelection:
        RoomPlanPreviewModel.PlanMarker?
    @State private var overlayFocusToken = 0
    @State private var overlayLabelMode: ReviewPlanLabelMode = .important
    @Environment(\.dismiss) private var dismiss

    public init(
        entries: [MissionWorkflowEntry] = [],
        taskPlan: HTDTCaptureTaskPlan? = nil,
        taskPlanOutcomes:
            [CaptureTaskPlanStatusDocument.ItemOutcome] = [],
        connectedSpaceIntent: Bool = false,
        connectedTracker: ConnectedSpaceTracker? = nil,
        asBuiltPlanLoaded: Bool = false,
        asBuiltItems: [AsBuiltVerificationItem] = [],
        asBuiltGhostOverlayEnabled: Bool = false,
        asBuiltAlignmentInstalled: Bool = false,
        asBuiltAlignment: PlanAlignmentAuthority? = nil,
        asBuiltOverlayModel: RoomPlanPreviewModel? = nil,
        asBuiltTolerancePolicyRef: String? = nil,
        asBuiltActualCandidates: [CaptureAnnotationEntity] = [],
        roomFrameAvailable: Bool = false,
        repairRows: [HTDTRepairTaskRow] = [],
        canRecordReason: Bool = false,
        onMarkTaskPlanItem: @escaping
            (String, TaskPlanItemOutcome, String?) -> Void =
                { _, _, _ in },
        onSetConnectedSpaceIntent: @escaping (Bool) -> Void
            = { _ in },
        onBeginConnectedSegment: @escaping
            (String, CaptureRegionKind) -> Void = { _, _ in },
        onCompleteConnectedSegment: @escaping () -> Void = {},
        onRecordPortal: @escaping
            (CaptureRegionID, CapturePortalKind) -> Void
            = { _, _ in },
        onRevisitRegion: @escaping (CaptureRegionID) -> Void
            = { _ in },
        onAsBuiltMarkUnavailable: @escaping (String) -> Void
            = { _ in },
        onAsBuiltEstablishAlignment: @escaping () -> Void = {},
        onAsBuiltRecordActual: @escaping
            (String, AnnotationEntityID) -> Void = { _, _ in },
        onResolveRepairTask: @escaping (HTDTRepairTaskRow) -> Void
            = { _ in },
        onOpenAnnotationWorkspace: @escaping () -> Void = {}
    ) {
        self.entries = entries
        self.taskPlan = taskPlan
        self.taskPlanOutcomes = taskPlanOutcomes
        self.connectedSpaceIntent = connectedSpaceIntent
        self.connectedTracker = connectedTracker
        self.asBuiltPlanLoaded = asBuiltPlanLoaded
        self.asBuiltItems = asBuiltItems
        self.asBuiltGhostOverlayEnabled = asBuiltGhostOverlayEnabled
        self.asBuiltAlignmentInstalled = asBuiltAlignmentInstalled
        self.asBuiltAlignment = asBuiltAlignment
        self.asBuiltOverlayModel = asBuiltOverlayModel
        self.asBuiltTolerancePolicyRef = asBuiltTolerancePolicyRef
        self.asBuiltActualCandidates = asBuiltActualCandidates
        self.roomFrameAvailable = roomFrameAvailable
        self.repairRows = repairRows
        self.canRecordReason = canRecordReason
        self.onMarkTaskPlanItem = onMarkTaskPlanItem
        self.onSetConnectedSpaceIntent = onSetConnectedSpaceIntent
        self.onBeginConnectedSegment = onBeginConnectedSegment
        self.onCompleteConnectedSegment = onCompleteConnectedSegment
        self.onRecordPortal = onRecordPortal
        self.onRevisitRegion = onRevisitRegion
        self.onAsBuiltMarkUnavailable = onAsBuiltMarkUnavailable
        self.onAsBuiltEstablishAlignment =
            onAsBuiltEstablishAlignment
        self.onAsBuiltRecordActual = onAsBuiltRecordActual
        self.onResolveRepairTask = onResolveRepairTask
        self.onOpenAnnotationWorkspace = onOpenAnnotationWorkspace
    }

    public var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Section {
                        Text(
                            "No active mission items. Mission workflows appear once a task plan, as-built plan, connected-space intent, or HTDT repair task applies to this capture."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(entries, id: \.surface) { entry in
                            NavigationLink {
                                destination(for: entry)
                            } label: {
                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(entryTitle(entry.surface))
                                    if let detail = entry.detail {
                                        if entry.surface
                                            == .repairTasks,
                                            let count = Int(detail)
                                        {
                                            Text(
                                                captureCountPhrase(
                                                    count,
                                                    singular: String(
                                                        localized:
                                                            "%lld unresolved repair task"
                                                    ),
                                                    plural: String(
                                                        localized:
                                                            "%lld unresolved repair tasks"
                                                    )
                                                )
                                            )
                                            .font(.caption)
                                            .foregroundStyle(
                                                .secondary
                                            )
                                        } else {
                                            Text(
                                                LocalizedStringKey(
                                                    detail
                                                )
                                            )
                                            .font(.caption)
                                            .foregroundStyle(
                                                .secondary
                                            )
                                        }
                                    }
                                }
                            }
                            .disabled(
                                entry.availability
                                    != .ready
                            )
                        }
                    } footer: {
                        Text(
                            "Mission items are visible only when they apply to this capture; a simple capture is not burdened with them."
                        )
                    }
                }
            }
            .navigationTitle("Mission workflows")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $beginSegmentShown) {
                beginSegmentSheet
            }
        }
    }

    private func entryTitle(
        _ surface: MissionWorkflowSurface
    ) -> String {
        switch surface {
        case .taskPlanChecklist:
            return String(localized: "Task plan checklist")
        case .connectedSpace:
            return String(localized: "Connected regions")
        case .asBuiltVerification:
            return String(localized: "As-built verification")
        case .postScanAuthoring:
            return String(
                localized: "Post-scan annotations & measurements"
            )
        case .instrumentImport:
            return String(
                localized: "Instrument measurement import"
            )
        case .repairTasks:
            return String(localized: "HTDT repair tasks")
        }
    }

    @ViewBuilder
    private func destination(
        for entry: MissionWorkflowEntry
    ) -> some View {
        switch entry.surface {
        case .taskPlanChecklist:
            taskPlanDestination
        case .connectedSpace:
            connectedSpaceDestination
        case .asBuiltVerification:
            asBuiltDestination
        case .postScanAuthoring:
            authoringDestination(
                title: "Post-scan annotations & measurements",
                explainer:
                    "Label, role, and measure the captured room in the annotation workspace. Committed records stay bound to the live coordinate authority."
            )
        case .instrumentImport:
            authoringDestination(
                title: "Instrument measurement import",
                explainer:
                    "Open a measurement form inside the annotation workspace and use the Instrument reading section to import a reading file — the staged value is confirmed explicitly before it commits."
            )
        case .repairTasks:
            repairDestination
        }
    }

    @ViewBuilder
    private var taskPlanDestination: some View {
        if let taskPlan {
            CaptureTaskPlanChecklistView(
                plan: taskPlan,
                outcomes: taskPlanOutcomes,
                canRecordReason: canRecordReason,
                onMark: onMarkTaskPlanItem
            )
            .navigationTitle("Task plan checklist")
        } else {
            ContentUnavailableView(
                "No task plan",
                systemImage: "checklist",
                description: Text(
                    "Import a capture task plan (.json) to drive the mission checklist."
                )
            )
        }
    }

    @ViewBuilder
    private var connectedSpaceDestination: some View {
        if let connectedTracker {
            ConnectedSpaceStatusView(
                tracker: connectedTracker,
                onBeginSegment: { beginSegmentShown = true },
                onCompleteActiveSegment:
                    onCompleteConnectedSegment,
                onRecordPortal: onRecordPortal,
                onRevisitRegion: onRevisitRegion
            )
            .navigationTitle("Connected regions")
        } else if connectedSpaceIntent {
            List {
                Section {
                    Button("Begin region") {
                        beginSegmentShown = true
                    }
                } footer: {
                    Text(
                        "Multi-region capture is enabled. Each region you begin and complete here is tracked into the bundle."
                    )
                }
            }
            .navigationTitle("Connected regions")
        } else {
            ContentUnavailableView(
                "Connected-space capture off",
                systemImage: "square.split.2x1",
                description: Text(
                    "Enable it for this capture only when the mission calls for multi-region coverage."
                )
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Enable") {
                        onSetConnectedSpaceIntent(true)
                    }
                }
            }
        }
    }

    private var beginSegmentSheet: some View {
        NavigationStack {
            Form {
                TextField("Region label", text: $segmentLabel)
                Picker("Kind", selection: $segmentKind) {
                    ForEach(
                        [
                            CaptureRegionKind.room,
                            .openPlanArea,
                            .hallway,
                            .stairwell,
                            .alcove,
                            .other,
                        ],
                        id: \.self
                    ) { kind in
                        DescribedPickerOption(
                            title: MissionPresentation
                                .regionKindName(kind),
                            detail: MissionPresentation
                                .regionKindDescription(kind)
                        )
                        .tag(kind)
                    }
                }
            }
            .navigationTitle("Begin region")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Begin") {
                        onBeginConnectedSegment(
                            segmentLabel,
                            segmentKind
                        )
                        segmentLabel = ""
                        segmentKind = .room
                        beginSegmentShown = false
                    }
                    .disabled(
                        segmentLabel.trimmingCharacters(
                            in: .whitespaces
                        ).isEmpty
                    )
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        beginSegmentShown = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var asBuiltDestination: some View {
        List {
            if !asBuiltPlanLoaded {
                Section {
                    Text(
                        "Import an as-built plan (.json) to compare planned positions against captured observations."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                if !asBuiltAlignmentInstalled {
                    Section {
                        Button(
                            "Establish plan alignment",
                            action: onAsBuiltEstablishAlignment
                        )
                        .disabled(!roomFrameAvailable)
                    } footer: {
                        Text(
                            roomFrameAvailable
                                ? String(localized: "Uses the committed room reference frame to anchor the plan to this capture's coordinate authority.")
                                : String(localized: "Requires a committed room reference frame. Confirm the room frame in the review workspace, then return.")
                        )
                    }
                }
                // legacy bolph71656-ai/HTDT-Capture#293: the ghost overlay exists only under an explicit
                // alignment authority — planned targets render as
                // reference ghosts, never as observed geometry.
                if let overlay = asBuiltOverlayModel {
                    Section {
                        ReviewPlanSurface(
                            model: overlay,
                            markers: overlay.markers,
                            selection: $overlaySelection,
                            focusToken: $overlayFocusToken,
                            labelMode: $overlayLabelMode
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 8, leading: 0,
                                bottom: 8, trailing: 0
                            )
                        )
                    } header: {
                        Text("Planned positions")
                    } footer: {
                        Text(
                            "Dashed rings are planned targets (design reference). Solid glyphs are captured actuals; dashed links show the measured deviation. Tapping a marker selects its item."
                        )
                    }
                }
                if let alignment = asBuiltAlignment {
                    Section {
                        LabeledContent(
                            String(localized: "Mechanism"),
                            value: TheaterAuthorityPresentation
                                .planAlignmentMechanismName(
                                    alignment.mechanism
                                )
                        )
                        LabeledContent(
                            String(localized: "Residual"),
                            value: alignment.residualMeters.map {
                                String(
                                    format: "%.1f cm",
                                    $0 * 100
                                )
                            } ?? String(localized: "Not declared")
                        )
                        LabeledContent(
                            String(localized: "Authority"),
                            value: alignment.authorityRef
                        )
                        .font(.caption)
                    } header: {
                        Text("Alignment")
                    } footer: {
                        Text(
                            "The ghost overlay and spatial verdicts rest on this explicit authority. Without it the workflow degrades to the non-spatial checklist."
                        )
                    }
                }
                if !asBuiltItems.isEmpty {
                    Section("Planned items") {
                        ForEach(
                            asBuiltItems,
                            id: \.spec.plannedEntityID
                        ) { item in
                            asBuiltItemRow(item)
                        }
                    }
                }
            }
        }
        .navigationTitle("As-built verification")
    }

    @ViewBuilder
    private func asBuiltItemRow(
        _ item: AsBuiltVerificationItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(
                    item.spec.label
                        ?? item.spec.plannedEntityID
                )
                Spacer()
                Text(
                    TheaterAuthorityPresentation.asBuiltStateName(
                        item.state
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let deviation = item.deviation {
                // legacy bolph71656-ai/HTDT-Capture#293: delta vector + heading + the declared
                // tolerance and uncertainty band — the quantities
                // stay separate authorities, never folded into a
                // single favorable number.
                Text(
                    String(
                        format: "%.1f cm",
                        deviation.distanceMeters * 100
                    )
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    item.state == .deviated
                        ? .orange
                        : .secondary
                )
                let delta = deviation.translationScene
                Text(
                    String(
                        format: String(
                            localized: "Δ %.1f / %.1f / %.1f cm"
                        ),
                        Double(delta.x) * 100,
                        Double(delta.y) * 100,
                        Double(delta.z) * 100
                    )
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                if let heading = deviation.headingDeltaRadians {
                    Text(
                        String(
                            format: String(
                                localized: "Heading Δ %.1f°"
                            ),
                            heading * 180 / .pi
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                if let tolerance = item.spec.toleranceMeters {
                    Text(
                        asBuiltTolerancePolicyRef == nil
                            ? String(
                                format: String(
                                    localized:
                                        "Tolerance %.1f cm (no policy — not evaluated)"
                                ),
                                tolerance * 100
                            )
                            : String(
                                format: String(
                                    localized: "Tolerance %.1f cm"
                                ),
                                tolerance * 100
                            )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Text(asBuiltUncertaintySummary(item))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if item.state == .pending {
                HStack {
                    Picker(
                        "Actual",
                        selection: actualSelection(
                            for: item.spec.plannedEntityID
                        )
                    ) {
                        DescribedPickerOption(
                            title: String(localized: "Choose entity"),
                            detail: String(localized:
                                "Pick the captured entity that matches this planned target.")
                        )
                        .tag(AnnotationEntityID?.none)
                        ForEach(
                            asBuiltActualCandidates,
                            id: \.entityID
                        ) { entity in
                            DescribedPickerOption(
                                title: entity.label,
                                detail: AnnotationPresentation
                                    .entityTypeName(entity.type)
                            )
                            .tag(
                                Optional(entity.entityID)
                            )
                        }
                    }
                    .labelsHidden()
                    .font(.caption)
                    Button("Record") {
                        if let entityID =
                            actualSelections[
                                item.spec.plannedEntityID
                            ]
                        {
                            onAsBuiltRecordActual(
                                item.spec.plannedEntityID,
                                entityID
                            )
                        }
                    }
                    .disabled(
                        actualSelections[
                            item.spec.plannedEntityID
                        ] == nil
                    )
                }
                Button("Mark unavailable") {
                    onAsBuiltMarkUnavailable(
                        item.spec.plannedEntityID
                    )
                }
                .font(.caption)
            }
        }
    }

    /// legacy bolph71656-ai/HTDT-Capture#293/legacy bolph71656-ai/HTDT-Capture#356: the additive uncertainty band behind the verdict —
    /// observation uncertainty and alignment residual stay separate
    /// fields; an undeclared input is reported as undeclared, never
    /// silently zero.
    private func asBuiltUncertaintySummary(
        _ item: AsBuiltVerificationItem
    ) -> String {
        let observation = item.observation?
            .positionalUncertaintyMeters
        let residual = asBuiltAlignment?.residualMeters
        guard let observation, let residual else {
            return String(
                localized:
                    "Uncertainty band not declared — verdicts stay indeterminate under a tolerance policy."
            )
        }
        return String(
            format: String(
                localized:
                    "Uncertainty band ±%.1f cm (observation %.1f + residual %.1f)"
            ),
            (observation + residual) * 100,
            observation * 100,
            residual * 100
        )
    }

    private func actualSelection(
        for plannedEntityID: String
    ) -> Binding<AnnotationEntityID?> {
        Binding(
            get: { actualSelections[plannedEntityID] },
            set: { actualSelections[plannedEntityID] = $0 }
        )
    }

    @ViewBuilder
    private func authoringDestination(
        title: String,
        explainer: String
    ) -> some View {
        List {
            Section {
                Text(explainer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Open annotation workspace") {
                    onOpenAnnotationWorkspace()
                    dismiss()
                }
            }
        }
        .navigationTitle(title)
    }

    @ViewBuilder
    private var repairDestination: some View {
        List {
            ForEach(repairRows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(
                            MissionPresentation.repairTaskKindName(
                                row.task.kind
                            )
                        )
                        .font(.callout.weight(.medium))
                        Spacer()
                        if row.task.requirement == .required {
                            Text(
                                MissionPresentation
                                    .taskPlanRequirementName(
                                        row.task.requirement
                                    )
                            )
                            .font(.caption2)
                            .foregroundStyle(CaptureColorRole.attention.color)
                        }
                    }
                    Text(row.task.reason)
                        .font(.caption)
                    // Task/issue/plan identifiers stay inspectable
                    // for plan follow-up — never the row's title
                    // (issue bolph71656-ai/HTDT-Capture#412).
                    Text(
                        "\(row.task.taskID) · \(row.task.issueCode) · Plan \(row.planID) v\(row.planVersion)"
                    )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    if let resolvedBy = row.resolvedByRevisionID {
                        Text(
                                String(
                                    format: String(
                                        localized: "Resolved — revision %@"
                                    ),
                                    resolvedBy.description
                                )
                            )
                        .font(.caption2)
                        .foregroundStyle(CaptureColorRole.success.color)
                    } else {
                        Button("Fix in Capture") {
                            onResolveRepairTask(row)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .navigationTitle("HTDT repair tasks")
    }
}
