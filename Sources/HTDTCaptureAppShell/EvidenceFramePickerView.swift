import Foundation
import SwiftUI
import HTDTCaptureCore
#if canImport(UIKit)
import UIKit
#endif

/// Why a frame was retained, localized (#255).
extension EvidenceFrameRetentionKind {
    var displayName: String {
        switch self {
        case .manualScan:
            return String(localized: "Manual evidence frame")
        case .annotationPlacement:
            return String(localized: "Placement capture")
        case .speakerHeading:
            return String(localized: "Heading capture")
        case .equipmentIdentity:
            return String(localized: "Equipment identity photo")
        case .unknown:
            return String(localized: "Retained frame")
        }
    }
}

/// Visual evidence selector (#255): each retained frame renders as a
/// preview thumbnail plus capture metadata — timestamp, retention
/// reason, depth availability — so the operator picks evidence by
/// looking at it. The canonical `path:` ref stays the stored authority;
/// it is shown in the per-frame detail surface. Frames without a
/// readable preview degrade to the metadata row rather than becoming
/// unselectable.
public struct EvidenceFramePickerView: View {
    public let frames: [EvidenceFramePresentation]
    /// Any available refs that did not produce a presentation
    /// (non-frame refs) still render as text rows — authority is never
    /// hidden.
    public let remainingRefs: [String]
    @Binding public var selectedRefs: Set<String>

    /// Full-screen inspection target: the frame ID string.
    private struct InspectTarget: Identifiable {
        let frame: EvidenceFramePresentation
        var id: String { frame.id }
    }
    @State private var inspectTarget: InspectTarget?
    #if os(iOS)
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    #endif

    /// #362: regular width renders the frames as a browsing grid
    /// (bigger thumbnails, tap to select, eye for the full preview);
    /// compact width keeps the dense row list.
    private var usesGrid: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular
        #else
        return false
        #endif
    }

    public init(
        frames: [EvidenceFramePresentation],
        remainingRefs: [String] = [],
        selectedRefs: Binding<Set<String>>
    ) {
        self.frames = frames
        self.remainingRefs = remainingRefs
        self._selectedRefs = selectedRefs
    }

    public var body: some View {
        Section(
            String(localized: "Linked evidence frames")
        ) {
            if usesGrid {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 170),
                            spacing: CaptureDesign.Spacing
                                .group
                        ),
                    ],
                    spacing: CaptureDesign.Spacing.group
                ) {
                    ForEach(frames) { frame in
                        gridCard(for: frame)
                    }
                }
                .padding(.vertical,
                         CaptureDesign.Spacing.micro)
            } else {
                ForEach(frames) { frame in
                    row(for: frame)
                }
            }
            ForEach(remainingRefs, id: \.self) { ref in
                textRow(for: ref)
            }

            Text(
                "Links reference exact canonical frame descriptors already persisted in this working revision."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .sheet(item: $inspectTarget) { target in
            NavigationStack {
                inspectView(target.frame)
            }
        }
    }

    @ViewBuilder
    private func row(
        for frame: EvidenceFramePresentation
    ) -> some View {
        let selected = selectedRefs.contains(frame.reference)
        Button {
            if selected {
                selectedRefs.remove(frame.reference)
            } else {
                selectedRefs.insert(frame.reference)
            }
        } label: {
            HStack(spacing: 12) {
                thumbnail(for: frame)

                VStack(alignment: .leading, spacing: 3) {
                    Text(frame.retentionKind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        if let seconds =
                            frame.sessionTimestampSeconds
                        {
                            Text(
                                String(
                                    format: "t=%.1fs",
                                    seconds
                                )
                            )
                        }
                        if frame.hasDepth {
                            Label(
                                String(localized: "Depth"),
                                systemImage: "square.3.layers.3d"
                            )
                        }
                        if !frame.hasPreview {
                            Label(
                                String(localized: "No preview"),
                                systemImage: "photo"
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    inspectTarget = InspectTarget(frame: frame)
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    String(localized: "Preview frame")
                )

                Image(
                    systemName: selected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One regular-width grid cell: large thumbnail, caption, the
    /// selection badge, and an eye button for the detail preview.
    @ViewBuilder
    private func gridCard(
        for frame: EvidenceFramePresentation
    ) -> some View {
        let selected = selectedRefs.contains(frame.reference)
        Button {
            if selected {
                selectedRefs.remove(frame.reference)
            } else {
                selectedRefs.insert(frame.reference)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    gridThumbnail(for: frame)
                    Image(
                        systemName: selected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        selected
                            ? Color.accentColor
                            : .secondary
                    )
                    .padding(6)
                }
                HStack(spacing: 6) {
                    Text(frame.retentionKind.displayName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        inspectTarget = InspectTarget(
                            frame: frame
                        )
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(
                        String(localized: "Preview frame")
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gridThumbnail(
        for frame: EvidenceFramePresentation
    ) -> some View {
        #if canImport(UIKit)
        if let url = frame.previewFileURL,
           let image = UIImage(contentsOfFile: url.path)
        {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 110,
                    maxHeight: 110
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 8)
                )
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.15))
                .frame(
                    maxWidth: .infinity,
                    minHeight: 110,
                    maxHeight: 110
                )
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
        }
        #else
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.15))
            .frame(
                maxWidth: .infinity,
                minHeight: 110,
                maxHeight: 110
            )
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            )
        #endif
    }

    @ViewBuilder
    private func textRow(for ref: String) -> some View {
        let selected = selectedRefs.contains(ref)
        Button {
            if selected {
                selectedRefs.remove(ref)
            } else {
                selectedRefs.insert(ref)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.fileLabel(ref))
                    Text(ref)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(
                    systemName: selected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(
        for frame: EvidenceFramePresentation
    ) -> some View {
        #if canImport(UIKit)
        if let url = frame.previewFileURL,
           let image = UIImage(contentsOfFile: url.path)
        {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholderThumbnail
        }
        #else
        placeholderThumbnail
        #endif
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 64, height: 48)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            )
    }

    /// Full-screen inspection: preview image when present, plus the
    /// canonical ref and every loaded metadata field.
    @ViewBuilder
    private func inspectView(
        _ frame: EvidenceFramePresentation
    ) -> some View {
        List {
            Section {
                #if canImport(UIKit)
                if let url = frame.previewFileURL,
                   let image = UIImage(contentsOfFile: url.path)
                {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(String(localized: "No preview available."))
                        .foregroundStyle(.secondary)
                }
                #else
                Text(String(localized: "No preview available."))
                    .foregroundStyle(.secondary)
                #endif
            }

            Section(String(localized: "Details")) {
                LabeledContent(
                    String(localized: "Reason"),
                    value: frame.retentionKind.displayName
                )
                if let seconds = frame.sessionTimestampSeconds {
                    LabeledContent(
                        String(localized: "Session time"),
                        value: String(format: "%.2f s", seconds)
                    )
                }
                LabeledContent(
                    String(localized: "Depth"),
                    value: frame.hasDepth
                        ? String(localized: "Captured")
                        : String(localized: "Not captured")
                )
                Text(frame.reference)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(String(localized: "Evidence frame"))
        .inlineNavigationBarTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) {
                    inspectTarget = nil
                }
            }
        }
    }

    private static func fileLabel(_ ref: String) -> String {
        let path = ref.hasPrefix("path:")
            ? String(ref.dropFirst(5))
            : ref
        return URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
    }
}
