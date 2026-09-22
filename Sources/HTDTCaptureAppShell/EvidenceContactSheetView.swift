import Foundation
import SwiftUI
import HTDTCaptureCore

/// The pre-finalization evidence contact sheet (issue #376): every
/// retained frame as a tile with thumbnail, scan order, heading,
/// depth/confidence summary, usability warnings, reference counts,
/// retained bytes, and the privacy flag. Removal always goes through
/// the model's assessment/plan so referenced and end-boundary frames
/// can never be deleted silently.
struct EvidenceContactSheetView: View {
    let model: CaptureReviewWorkspaceModel
    let removeEvidenceFrame:
        (EvidenceFrameID) async -> Void
    let flagForPrivacy: (EvidenceFrameID) -> Void
    /// #460: clears a frame's privacy flag — the paired action of
    /// `flagForPrivacy`.
    let unflagForPrivacy: (EvidenceFrameID) -> Void

    @State private var filter: EvidenceContactSheetFilter = .all
    @State private var sort: EvidenceContactSheetSort = .captureTime
    @State private var selecting = false
    @State private var selection = Set<EvidenceFrameID>()
    @State private var removalPlan: ContactSheetRemovalPlan?
    @State private var removing = false

    private var sheet: EvidenceContactSheetModel? {
        model.contactSheet
    }

    private var displayedItems: [EvidenceContactSheetItem] {
        sheet?.items(matching: filter, sortedBy: sort) ?? []
    }

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(displayedItems) { item in
                    tile(item)
                }
            }
            .padding(10)
        }
        .navigationTitle("Contact sheet")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(
                    selecting ? "Done" : "Select"
                ) {
                    selecting.toggle()
                    if !selecting {
                        selection.removeAll()
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            controlBar
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                selectionBar
            } else {
                totalsBar
            }
        }
        .sheet(item: $removalPlan) { plan in
            removalPlanSheet(plan)
        }
    }

    // MARK: Controls

    private var controlBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All", .all)
                    filterChip("Referenced", .referenced)
                    filterChip("Unreferenced", .unreferenced)
                    filterChip("Warnings", .warnings)
                    filterChip("Has depth", .hasDepth)
                    filterChip("Identity", .identityPhotos)
                    filterChip("Auto", .automaticKeyframes)
                    filterChip("Privacy", .privacyFlagged)
                }
                .padding(.horizontal, 10)
            }
            Picker("Sort", selection: $sort) {
                Text("Time").tag(EvidenceContactSheetSort.captureTime)
                Text("Direction")
                    .tag(EvidenceContactSheetSort.roomDirection)
                Text("Refs")
                    .tag(EvidenceContactSheetSort.referenceCount)
                Text("Size")
                    .tag(EvidenceContactSheetSort.byteSize)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)

            Text(
                sort == .captureTime
                    ? "Frames appear in the order they were captured."
                    : sort == .roomDirection
                        ? "Frames are ordered by the direction they face — a walk around the room."
                        : sort == .referenceCount
                            ? "Frames with the most authority bindings come first."
                            : "Largest frames come first."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func filterChip(
        _ title: String,
        _ value: EvidenceContactSheetFilter
    ) -> some View {
        Button(title) {
            if value == .all {
                filter = .all
            } else if filter.contains(value) {
                filter.remove(value)
            } else {
                filter.insert(value)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            filter.contains(value)
                || (value == .all && filter == .all)
                ? Color.accentColor.opacity(0.2)
                : Color.secondary.opacity(0.12),
            in: Capsule()
        )
    }

    private var totalsBar: some View {
        HStack {
            Text(
                String(
                    format: String(
                        localized: "%d frames · %@ retained"
                    ),
                    sheet?.items.count ?? 0,
                    ByteCountFormatter.string(
                        fromByteCount: sheet?.totalRetainedBytes ?? 0,
                        countStyle: .file
                    )
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var selectionBar: some View {
        let selectionBytes =
            sheet?.bytes(for: selection) ?? 0
        return HStack(spacing: 12) {
            Text(
                String(
                    format: String(
                        localized: "%d selected · %@"
                    ),
                    selection.count,
                    ByteCountFormatter.string(
                        fromByteCount: selectionBytes,
                        countStyle: .file
                    )
                )
            )
            .font(.caption)
            Spacer()
            Button("Assess removal") {
                removalPlan = sheet?.removalPlan(
                    for: selection
                )
            }
            .font(.caption.weight(.semibold))
            .disabled(selection.isEmpty || removing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: Tiles

    @ViewBuilder
    private func tile(
        _ item: EvidenceContactSheetItem
    ) -> some View {
        let selected = selection.contains(item.item.frameID)
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    #if os(iOS)
                    if let url = item.item.previewFileURL {
                        AsyncPreviewImage(url: url)
                            .aspectRatio(
                                4 / 3,
                                contentMode: .fill
                            )
                    } else {
                        placeholderTile
                    }
                    #else
                    placeholderTile
                    #endif
                }
                .frame(height: 110)
                .clipped()
                .cornerRadius(6)

                if selecting {
                    Image(
                        systemName: selected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        selected ? Color.accentColor : .secondary
                    )
                    .padding(6)
                }
            }

            HStack(spacing: 4) {
                Text("#\(item.captureOrder)")
                    .font(.caption2.monospaced())
                if let heading = item.headingDegrees {
                    Label(
                        String(format: "%.0f°", heading),
                        systemImage: "location.north"
                    )
                    .font(.caption2)
                }
                Spacer()
                if item.privacyFlagged {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if item.hasUsabilityWarning {
                    Image(
                        systemName:
                            "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }
            Text(depthSummaryLabel(item.depthSummary))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(
                String(
                    format: String(
                        localized: "%d refs · %@"
                    ),
                    item.item.referencedBy.count,
                    ByteCountFormatter.string(
                        fromByteCount: item.item.byteCount,
                        countStyle: .file
                    )
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(
                MissionPresentation.retentionReasonName(
                    item.item.retentionReason
                )
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(6)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    selected
                        ? Color.accentColor
                        : Color.clear,
                    lineWidth: 2
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting {
                if selected {
                    selection.remove(item.item.frameID)
                } else {
                    selection.insert(item.item.frameID)
                }
            }
        }
        .contextMenu {
            if item.privacyFlagged {
                Button("Remove privacy flag") {
                    unflagForPrivacy(item.item.frameID)
                }
            } else {
                Button("Flag for privacy review") {
                    flagForPrivacy(item.item.frameID)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            "contactSheet.tile.\(item.item.frameID.description)"
        )
    }

    private var placeholderTile: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            )
    }

    private func depthSummaryLabel(
        _ summary: ContactSheetDepthSummary
    ) -> String {
        switch summary {
        case .none:
            return "No depth"
        case .discrete(let confidence):
            return confidence
                ? "Scene depth + confidence"
                : "Scene depth"
        case .smoothed(let confidence):
            return confidence
                ? "Smoothed depth + confidence"
                : "Smoothed depth"
        case .unavailable:
            return "Depth unavailable"
        }
    }

    // MARK: Removal

    @ViewBuilder
    private func removalPlanSheet(
        _ plan: ContactSheetRemovalPlan
    ) -> some View {
        NavigationStack {
            List {
                if !plan.removable.isEmpty {
                    Section {
                        ForEach(
                            plan.removable,
                            id: \.self
                        ) { frameID in
                            Label(
                                frameID.description,
                                systemImage: "checkmark.circle"
                            )
                            .font(.caption.monospaced())
                        }
                    } header: {
                        Text(
                            "Removable — \(ByteCountFormatter.string(fromByteCount: plan.reclaimableBytes, countStyle: .file)) reclaimed"
                        )
                    }
                }
                if !plan.blocked.isEmpty {
                    Section("Blocked") {
                        ForEach(
                            plan.blocked,
                            id: \.frameID
                        ) { blocked in
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(blocked.frameID.description)
                                    .font(.caption.monospaced())
                                Text(blocked.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                ForEach(
                                    blocked.dependents,
                                    id: \.self
                                ) { dependent in
                                    Text(dependent)
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Removal plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { removalPlan = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remove", role: .destructive) {
                        let frames = plan.removable
                        removalPlan = nil
                        removing = true
                        Task {
                            for frameID in frames {
                                await removeEvidenceFrame(frameID)
                            }
                            await MainActor.run {
                                removing = false
                                selecting = false
                                selection.removeAll()
                            }
                        }
                    }
                    .disabled(plan.removable.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension ContactSheetRemovalPlan: Identifiable {
    public var id: Int {
        removable.count ^ blocked.count
            ^ Int(reclaimableBytes & 0x7FFFFFFF)
    }
}
