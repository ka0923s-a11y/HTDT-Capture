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
                        Text(active.kind.rawValue)
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
                                    "revisits: \(region.revisitCount)"
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
                            "\(regionLabel(portal.regionAID)) ↔ "
                                + "\(regionLabel(portal.regionBID)) "
                                + "(\(portal.kind.rawValue))"
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
public struct CaptureTaskPlanChecklistView: View {
    public let plan: HTDTCaptureTaskPlan
    public let outcomes:
        [CaptureTaskPlanStatusDocument.ItemOutcome]
    public let onMark: (String, TaskPlanItemOutcome) -> Void

    public init(
        plan: HTDTCaptureTaskPlan,
        outcomes: [CaptureTaskPlanStatusDocument.ItemOutcome],
        onMark: @escaping (String, TaskPlanItemOutcome) -> Void =
            { _, _ in }
    ) {
        self.plan = plan
        self.outcomes = outcomes
        self.onMark = onMark
    }

    public var body: some View {
        List {
            Section(
                "Plan \(plan.planID) v\(plan.planVersion) — "
                    + plan.roomName
            ) {
                ForEach(plan.entityChecklist, id: \.itemID) { item in
                    row(
                        itemID: item.itemID,
                        title:
                            "\(item.entityType.rawValue)"
                            + (item.channelRole.map {
                                " · \($0.rawValue)"
                            } ?? ""),
                        requirement: item.requirement
                    )
                }
                ForEach(
                    plan.measurementRequests,
                    id: \.itemID
                ) { item in
                    row(
                        itemID: item.itemID,
                        title: "measure: \(item.quantityType)",
                        requirement: item.requirement
                    )
                }
                ForEach(
                    plan.surfaceReviewTasks,
                    id: \.itemID
                ) { item in
                    row(
                        itemID: item.itemID,
                        title: "review: \(item.surfaceKind)",
                        requirement: item.requirement
                    )
                }
            }
        }
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
                Text(outcome.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if requirement == .required {
                Text("required")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Menu("Mark") {
                Button("Skipped") {
                    onMark(itemID, .skipped)
                }
                Button("Unavailable") {
                    onMark(itemID, .unavailable)
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
                        "No alignment authority — spatial verdicts "
                            + "unavailable; checklist mode only."
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
                            Text(item.state.rawValue)
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
