import Foundation
import SwiftUI
import HTDTCaptureCore

/// Production surface for the merged-but-unreachable advanced
/// workflows (issue #353): task-plan checklist, connected-space
/// tracking, as-built verification, post-scan/instrument authoring and
/// HTDT repair tasks (issue #321). Each surface is reachable through
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
    /// Committed annotation entities offered as "actual" observations
    /// for as-built items.
    public let asBuiltActualCandidates: [CaptureAnnotationEntity]
    /// Whether a committed room reference frame can anchor the
    /// as-built plan→capture alignment.
    public let roomFrameAvailable: Bool
    public let repairRows: [HTDTRepairTaskRow]
    public let onMarkTaskPlanItem:
        (String, TaskPlanItemOutcome) -> Void
    public let onSetConnectedSpaceIntent: (Bool) -> Void
    public let onBeginConnectedSegment:
        (String, CaptureRegionKind) -> Void
    public let onCompleteConnectedSegment: () -> Void
    public let onRecordPortal: (CaptureRegionID) -> Void
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
        asBuiltActualCandidates: [CaptureAnnotationEntity] = [],
        roomFrameAvailable: Bool = false,
        repairRows: [HTDTRepairTaskRow] = [],
        onMarkTaskPlanItem: @escaping
            (String, TaskPlanItemOutcome) -> Void = { _, _ in },
        onSetConnectedSpaceIntent: @escaping (Bool) -> Void
            = { _ in },
        onBeginConnectedSegment: @escaping
            (String, CaptureRegionKind) -> Void = { _, _ in },
        onCompleteConnectedSegment: @escaping () -> Void = {},
        onRecordPortal: @escaping (CaptureRegionID) -> Void
            = { _ in },
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
        self.asBuiltActualCandidates = asBuiltActualCandidates
        self.roomFrameAvailable = roomFrameAvailable
        self.repairRows = repairRows
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
                            NavigationLink(
                                entryTitle(entry.surface)
                            ) {
                                destination(for: entry)
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
                Text(
                    String(
                        format: "%.1f cm",
                        deviation.distanceMeters * 100
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    item.state == .deviated
                        ? .orange
                        : .secondary
                )
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
                            .foregroundStyle(.orange)
                        }
                    }
                    Text(row.task.reason)
                        .font(.caption)
                    // Task/issue/plan identifiers stay inspectable
                    // for plan follow-up — never the row's title
                    // (issue #412).
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
                        .foregroundStyle(.green)
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
