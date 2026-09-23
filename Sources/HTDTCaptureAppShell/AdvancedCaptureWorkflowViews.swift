import Foundation
import SwiftUI
import HTDTCaptureCore

/// Connected-room workflow surface (issue #222): the active segment is
/// always visible, completed segments stay revisitable before
/// finalization, and every portal relationship is listed explicitly.
public struct ConnectedSpaceStatusView: View {
    public let tracker: ConnectedSpaceTracker
    public let onBeginSegment: () -> Void
    public let onCompleteActiveSegment: () -> Void
    public let onRecordPortal: (CaptureRegionID) -> Void
    public let onRevisitRegion: (CaptureRegionID) -> Void

    public init(
        tracker: ConnectedSpaceTracker,
        onBeginSegment: @escaping () -> Void = {},
        onCompleteActiveSegment: @escaping () -> Void = {},
        onRecordPortal: @escaping (CaptureRegionID) -> Void = { _ in },
        onRevisitRegion: @escaping (CaptureRegionID) -> Void = { _ in }
    ) {
        self.tracker = tracker
        self.onBeginSegment = onBeginSegment
        self.onCompleteActiveSegment = onCompleteActiveSegment
        self.onRecordPortal = onRecordPortal
        self.onRevisitRegion = onRevisitRegion
    }

    public var body: some View {
        List {
            if let active = tracker.activeSegment {
                Section("Active region") {
                    HStack {
                        Text(active.label)
                        Spacer()
                        Text(
                            MissionPresentation.regionKindName(
                                active.kind
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                    Button("Complete region") {
                        onCompleteActiveSegment()
                    }
                }
                let others = tracker.segments.filter {
                    $0.regionID != active.regionID
                }
                if !others.isEmpty {
                    Section("Portal to completed region") {
                        ForEach(others, id: \.regionID) { region in
                            Button(region.label) {
                                onRecordPortal(region.regionID)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Button("Begin region") {
                        onBeginSegment()
                    }
                }
            }
            let completed = tracker.segments.filter {
                $0.state == .completed
            }
            if !completed.isEmpty {
                Section("Completed regions") {
                    ForEach(completed, id: \.regionID) { region in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(region.label)
                                Text(
                                    String(
                                        format: String(
                                            localized:
                                                "revisits: %lld"
                                        ),
                                        region.revisitCount
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Revisit") {
                                onRevisitRegion(region.regionID)
                            }
                            .disabled(tracker.activeSegment != nil)
                        }
                    }
                }
            }
            if !tracker.portals.isEmpty {
                Section("Portals") {
                    ForEach(tracker.portals, id: \.portalID) { portal in
                        Text(
                            String(
                                format: String(
                                    localized: "%1$@ ↔ %2$@ (%3$@)"
                                ),
                                regionLabel(portal.regionAID),
                                regionLabel(portal.regionBID),
                                MissionPresentation.portalKindName(
                                    portal.kind
                                )
                            )
                        )
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func regionLabel(_ id: CaptureRegionID) -> String {
        tracker.segments.first { $0.regionID == id }?.label
            ?? id.description
    }
}

/// Task-plan checklist surface (issue #240): every imported plan item
/// shows its operator-visible outcome before finalization —
/// completed, skipped, or unavailable — against committed evidence.
/// #364 §10: when the plan maps to a mission record the "Mark" menu is
/// task-specific — skip/unavailable collect a reason that persists as
/// a mission-level waiver note (#397); the status document contract
/// has no reason field and stays unchanged.
public struct CaptureTaskPlanChecklistView: View {
    public let plan: HTDTCaptureTaskPlan
    public let outcomes:
        [CaptureTaskPlanStatusDocument.ItemOutcome]
    /// Whether a mission record exists for this plan so a reason can
    /// persist as a waiver note — gates the "with reason" menu items.
    public let canRecordReason: Bool
    public let onMark:
        (String, TaskPlanItemOutcome, String?) -> Void

    @State private var reasonDraft = ""
    @State private var reasonPrompt:
        MarkReasonPrompt?

    private struct MarkReasonPrompt: Identifiable {
        let itemID: String
        let outcome: TaskPlanItemOutcome
        var id: String {
            itemID + "\u{0}" + outcome.rawValue
        }
    }

    public init(
        plan: HTDTCaptureTaskPlan,
        outcomes: [CaptureTaskPlanStatusDocument.ItemOutcome],
        canRecordReason: Bool = false,
        onMark: @escaping
            (String, TaskPlanItemOutcome, String?) -> Void =
            { _, _, _ in }
    ) {
        self.plan = plan
        self.outcomes = outcomes
        self.canRecordReason = canRecordReason
        self.onMark = onMark
    }

    public var body: some View {
        List {
            Section(
                String(
                    format: String(
                        localized: "Plan %@ v%@ — %@"
                    ),
                    plan.planID,
                    plan.planVersion,
                    plan.roomName
                )
            ) {
                // Plan identity stays inspectable but secondary — it
                // is a reference, not the row's job (issue #412).
                Text("Plan \(plan.planID) v\(plan.planVersion)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                ForEach(plan.entityChecklist, id: \.itemID) { item in
                    row(
                        itemID: item.itemID,
                        title: MissionPresentation
                            .entityTaskTitle(item),
                        requirement: item.requirement
                    )
                }
                ForEach(
                    plan.measurementRequests,
                    id: \.itemID
                ) { item in
                    row(
                        itemID: item.itemID,
                        title: MissionPresentation
                            .measurementTaskTitle(item),
                        requirement: item.requirement
                    )
                }
                ForEach(
                    plan.surfaceReviewTasks,
                    id: \.itemID
                ) { item in
                    row(
                        itemID: item.itemID,
                        title: MissionPresentation
                            .surfaceTaskTitle(item),
                        requirement: item.requirement
                    )
                }
            }
        }
        .sheet(item: $reasonPrompt) { prompt in
            reasonSheet(prompt)
        }
    }

    /// The reason interposes before the mark is written — a
    /// reason-less non-evidence outcome can never reach the waiver
    /// ledger, matching the field-return outcome contract (#418).
    private func reasonSheet(
        _ prompt: MarkReasonPrompt
    ) -> some View {
        NavigationStack {
            Form {
                TextField(
                    String(localized: "Reason"),
                    text: $reasonDraft,
                    axis: .vertical
                )
            }
            .navigationTitle(
                String(localized: "Outcome reason")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        reasonPrompt = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        let reason =
                            reasonDraft.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        onMark(
                            prompt.itemID,
                            prompt.outcome,
                            reason.isEmpty ? nil : reason
                        )
                        reasonPrompt = nil
                    }
                    .disabled(
                        reasonDraft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func row(
        itemID: String,
        title: String,
        requirement: TaskPlanRequirement
    ) -> some View {
        let outcome = outcomes.first { $0.itemID == itemID }?.outcome
            ?? .pending
        HStack {
            Image(systemName: symbol(for: outcome))
            VStack(alignment: .leading) {
                Text(title)
                Text(
                    MissionPresentation.taskPlanItemOutcomeName(
                        outcome
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(itemID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if requirement == .required {
                Text(
                    MissionPresentation.taskPlanRequirementName(
                        requirement
                    )
                )
                .font(.caption2)
                .foregroundStyle(CaptureColorRole.attention.color)
            }
            Menu(String(localized: "Mark")) {
                if canRecordReason {
                    Button(
                        String(
                            localized: "Skip with reason…"
                        )
                    ) {
                        reasonDraft = ""
                        reasonPrompt = MarkReasonPrompt(
                            itemID: itemID,
                            outcome: .skipped
                        )
                    }
                    Button(
                        String(
                            localized:
                                "Mark unavailable with reason…"
                        )
                    ) {
                        reasonDraft = ""
                        reasonPrompt = MarkReasonPrompt(
                            itemID: itemID,
                            outcome: .unavailable
                        )
                    }
                } else {
                    Button(
                        MissionPresentation
                            .taskPlanItemOutcomeName(
                                .skipped
                            )
                    ) {
                        onMark(itemID, .skipped, nil)
                    }
                    Button(
                        MissionPresentation
                            .taskPlanItemOutcomeName(
                                .unavailable
                            )
                    ) {
                        onMark(itemID, .unavailable, nil)
                    }
                }
            }
            .font(.caption)
        }
    }

    private func symbol(
        for outcome: TaskPlanItemOutcome
    ) -> String {
        switch outcome {
        case .pending:
            return "circle"
        case .completed:
            return "checkmark.circle.fill"
        case .skipped:
            return "forward.circle"
        case .unavailable:
            return "minus.circle"
        }
    }
}

/// As-built verification surface (issue #293): planned-vs-observed
/// deviations per item, only when an explicit alignment authority is
/// installed — otherwise the list degrades to the non-spatial
/// checklist states.
public struct AsBuiltVerificationStatusView: View {
    public let items: [AsBuiltVerificationItem]
    public let ghostOverlayEnabled: Bool

    public init(
        items: [AsBuiltVerificationItem],
        ghostOverlayEnabled: Bool
    ) {
        self.items = items
        self.ghostOverlayEnabled = ghostOverlayEnabled
    }

    public var body: some View {
        List {
            if !ghostOverlayEnabled {
                Section {
                    Text(
                        "No alignment authority — spatial verdicts unavailable; checklist mode only."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Section("As-built verification") {
                ForEach(
                    items,
                    id: \.spec.plannedEntityID
                ) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(
                                item.spec.label
                                    ?? item.spec.plannedEntityID
                            )
                            Text(
                                TheaterAuthorityPresentation
                                    .asBuiltStateName(item.state)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let deviation = item.deviation {
                            Text(
                                String(
                                    format: "%.1f cm",
                                    deviation.distanceMeters * 100
                                )
                            )
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }
}
