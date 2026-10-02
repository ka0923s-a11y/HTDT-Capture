import Foundation
import SwiftUI
import HTDTCaptureCore

/// Which plan labels the surface draws (issue #367): default Off —
/// dense rooms stay readable; Important shows only selected/attention
/// markers; All shows every labeled marker.
public enum ReviewPlanLabelMode: String, CaseIterable, Sendable {
    case off
    case important
    case all
}

/// The interactive spatial-review surface (issue #367): the
/// platform-independent `RoomPlanPreviewModel` plus overlay markers
/// composed by `ReviewPlanPresentation`. Selection is UI state only —
/// it never persists into any authority document.
public struct ReviewPlanSurface: View {
    /// Walls and base plan geometry.
    public let model: RoomPlanPreviewModel
    /// Fully composed marker list (base + overlay).
    public let markers: [RoomPlanPreviewModel.PlanMarker]
    /// Read-only surfaces (persisted/finalized view) keep inspection
    /// and legend but hide nothing — selection stays allowed.
    @Binding public var selection: RoomPlanPreviewModel.PlanMarker?
    /// Bumped by the parent to focus the current selection.
    @Binding public var focusToken: Int
    @Binding public var labelMode: ReviewPlanLabelMode

    @State private var userZoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var legendShown = false
    @State private var disambiguation:
        [RoomPlanPreviewModel.PlanMarker]? = nil
    @State private var viewSize: CGSize = .zero

    public init(
        model: RoomPlanPreviewModel,
        markers: [RoomPlanPreviewModel.PlanMarker],
        selection: Binding<RoomPlanPreviewModel.PlanMarker?>,
        focusToken: Binding<Int>,
        labelMode: Binding<ReviewPlanLabelMode>
    ) {
        self.model = model
        self.markers = markers
        self._selection = selection
        self._focusToken = focusToken
        self._labelMode = labelMode
    }

    private var spanX: Double { max(model.maxX - model.minX, 0.01) }
    private var spanZ: Double { max(model.maxZ - model.minZ, 0.01) }

    /// Plan-space tolerance for a tap, ~4% of the larger span so dense
    /// rooms still get a usable hit radius (issue #367 RVIS-50).
    private var tapTolerance: Double {
        max(spanX, spanZ) * 0.045
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CaptureDesign.Spacing.row) {
            GeometryReader { geometry in
                let size = geometry.size
                Canvas { context, _ in
                    let transform = Self.planTransform(
                        in: size,
                        model: model,
                        userZoom: userZoom,
                        pan: pan
                    )
                    // Layer 1: room geometry — neutral consistent
                    // stroke, never status-colored (#367).
                    for wall in model.walls {
                        var path = Path()
                        path.move(
                            to: transform.point(
                                wall.startX, wall.startZ
                            )
                        )
                        path.addLine(
                            to: transform.point(
                                wall.endX, wall.endZ
                            )
                        )
                        context.stroke(
                            path,
                            with: .color(.primary.opacity(0.75)),
                            lineWidth: 1.5
                        )
                    }
                    // Layer 2: deviation connectors (issue #293) —
                    // planned ghost → observed actual links drawn under
                    // the markers, dashed so they read as derived
                    // emphasis rather than geometry.
                    for connector in model.connectors {
                        var link = Path()
                        link.move(
                            to: transform.point(
                                connector.startX, connector.startZ
                            )
                        )
                        link.addLine(
                            to: transform.point(
                                connector.endX, connector.endZ
                            )
                        )
                        context.stroke(
                            link,
                            with: .color(
                                connectorColor(connector.status)
                            ),
                            style: StrokeStyle(
                                lineWidth: 1.5,
                                dash: [5, 4]
                            )
                        )
                    }
                    // Layers 3–5: semantic objects, review items and
                    // temporary state — glyph shape carries the
                    // category, status only adds a badge (#367).
                    for marker in markers {
                        draw(marker, in: &context, transform: transform)
                    }
                }
                .onAppear { viewSize = size }
                .onChange(of: size) { _, newSize in
                    viewSize = newSize
                }
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            userZoom = min(
                                max(lastZoom * value.magnification, 0.5),
                                12
                            )
                        }
                        .onEnded { _ in lastZoom = userZoom }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            pan = CGSize(
                                width: lastPan.width
                                    + value.translation.width,
                                height: lastPan.height
                                    + value.translation.height
                            )
                        }
                        .onEnded { _ in lastPan = pan }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            handleTap(
                                at: value.location,
                                in: size
                            )
                        }
                )
                .highPriorityGesture(
                    TapGesture(count: 2).onEnded { fitToContent() }
                )
                .onChange(of: focusToken) { _, _ in
                    focusOnSelection()
                }
                .accessibilityElement()
                .accessibilityLabel(accessibilitySummary)
            }
            .frame(minHeight: 220, idealHeight: 320)

            HStack(spacing: CaptureDesign.Spacing.group) {
                Button("Fit") { fitToContent() }
                    .font(CaptureDesign.Typography.secondary)
                    .disabled(model.isEmpty)
                Menu {
                    ForEach(
                        ReviewPlanLabelMode.allCases,
                        id: \.self
                    ) { mode in
                        Button {
                            labelMode = mode
                        } label: {
                            if labelMode == mode {
                                Label(
                                    Self.labelModeName(mode),
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(Self.labelModeName(mode))
                            }
                        }
                    }
                } label: {
                    Label("Labels", systemImage: "tag")
                        .font(CaptureDesign.Typography.secondary)
                }
                Spacer()
                Button {
                    legendShown = true
                } label: {
                    Label("Legend", systemImage: "info.circle")
                        .font(CaptureDesign.Typography.secondary)
                }
            }
            .padding(.horizontal, CaptureDesign.Spacing.micro)

            if let selection {
                selectedDetail(selection)
            }
        }
        .sheet(isPresented: $legendShown) {
            legendSheet
        }
        .confirmationDialog(
            "Which item?",
            isPresented: Binding(
                get: { disambiguation != nil },
                set: { shown in
                    if !shown { disambiguation = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: disambiguation
        ) { candidates in
            // One action-producing child — iOS 26 renders only
            // the first child, so a bare trailing Cancel never
            // appears.
            Group {
                ForEach(candidates, id: \.identifier) { marker in
                    Button(markerTitle(marker)) {
                        selection = marker
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Transforms

    private struct PlanTransform {
        let scale: CGFloat
        let centerX: CGFloat
        let centerY: CGFloat
        let planCenterX: Double
        let planCenterZ: Double

        func point(_ x: Double, _ z: Double) -> CGPoint {
            CGPoint(
                x: centerX + CGFloat(x - planCenterX) * scale,
                y: centerY + CGFloat(z - planCenterZ) * scale
            )
        }

        func planPoint(_ p: CGPoint) -> (x: Double, z: Double) {
            (
                x: Double((p.x - centerX) / scale) + planCenterX,
                z: Double((p.y - centerY) / scale) + planCenterZ
            )
        }
    }

    private static func planTransform(
        in size: CGSize,
        model: RoomPlanPreviewModel,
        userZoom: CGFloat,
        pan: CGSize
    ) -> PlanTransform {
        let spanX = max(model.maxX - model.minX, 0.01)
        let spanZ = max(model.maxZ - model.minZ, 0.01)
        let fit = min(
            size.width / CGFloat(spanX),
            size.height / CGFloat(spanZ)
        ) * CGFloat(0.9)
        let scale = fit * userZoom
        let planCX = (model.minX + model.maxX) / 2
        let planCZ = (model.minZ + model.maxZ) / 2
        return PlanTransform(
            scale: scale,
            centerX: size.width / 2 + pan.width,
            centerY: size.height / 2 + pan.height,
            planCenterX: planCX,
            planCenterZ: planCZ
        )
    }

    private func fitToContent() {
        withAnimation(.easeInOut(duration: 0.25)) {
            userZoom = 1
            lastZoom = 1
            pan = .zero
            lastPan = .zero
        }
    }

    private func focusOnSelection() {
        guard let selection else { return }
        let zoom = max(userZoom, 2)
        withAnimation(.easeInOut(duration: 0.25)) {
            userZoom = zoom
            lastZoom = zoom
            // Solve the pan that centers the marker at this zoom:
            // screen = viewCenter + pan + (plan - planCenter) * scale.
            let spanX = max(model.maxX - model.minX, 0.01)
            let spanZ = max(model.maxZ - model.minZ, 0.01)
            let fit = min(
                viewSize.width / CGFloat(spanX),
                viewSize.height / CGFloat(spanZ)
            ) * CGFloat(0.9)
            let scale = fit * userZoom
            let planCX = (model.minX + model.maxX) / 2
            let planCZ = (model.minZ + model.maxZ) / 2
            pan = CGSize(
                width: -CGFloat(selection.x - planCX) * scale,
                height: -CGFloat(selection.z - planCZ) * scale
            )
            lastPan = pan
        }
    }

    // MARK: - Selection

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let transform = Self.planTransform(
            in: size,
            model: model,
            userZoom: userZoom,
            pan: pan
        )
        let planPoint = transform.planPoint(location)
        let hits = ReviewPlanPresentation.hitTest(
            markers: markers,
            at: planPoint,
            tolerance: tapTolerance
        )
        switch hits.count {
        case 0:
            selection = nil
        case 1:
            selection = hits[0]
        default:
            // Overlapping markers never guess — the operator picks
            // from a nearest-first disambiguation list (#367).
            disambiguation = hits
        }
    }

    private func markerTitle(
        _ marker: RoomPlanPreviewModel.PlanMarker
    ) -> String {
        if let label = marker.label, !label.isEmpty {
            return label
        }
        return TheaterAuthorityPresentation.planMarkerKindName(
            marker.kind
        )
    }

    @ViewBuilder
    private func selectedDetail(
        _ marker: RoomPlanPreviewModel.PlanMarker
    ) -> some View {
        HStack(spacing: CaptureDesign.Spacing.group) {
            Image(
                systemName: marker.reviewStatus.semanticStatus
                    .symbolName
            )
            .foregroundStyle(
                marker.reviewStatus.semanticStatus.colorRole.color
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(markerTitle(marker))
                    .font(CaptureDesign.Typography.body)
                Text(
                    [
                        TheaterAuthorityPresentation
                            .planMarkerKindName(marker.kind),
                        marker.reviewStatus == .nominal
                            ? nil
                            : marker.reviewStatus.semanticStatus
                                .localizedLabel,
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(CaptureDesign.Typography.secondary)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, CaptureDesign.Spacing.micro)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Legend

    private var legendSheet: some View {
        NavigationStack {
            List {
                let presentKinds = Set(markers.map(\.kind))
                Section("Shapes") {
                    ForEach(
                        RoomPlanPreviewModel.PlanMarker.Kind
                            .legendOrder,
                        id: \.self
                    ) { kind in
                        if presentKinds.contains(kind) {
                            HStack(
                                spacing: CaptureDesign.Spacing.group
                            ) {
                                LegendGlyph(kind: kind)
                                    .frame(width: 24, height: 24)
                                Text(
                                    TheaterAuthorityPresentation
                                        .planMarkerKindName(kind)
                                )
                            }
                        }
                    }
                }
                let presentStatuses = Set(
                    markers.map(\.reviewStatus)
                ).filter { $0 != .nominal }
                if !presentStatuses.isEmpty {
                    Section("Review badges") {
                        ForEach(
                            PlanMarkerReviewStatus.allCases
                                .filter {
                                    presentStatuses.contains($0)
                                },
                            id: \.self
                        ) { status in
                            Label {
                                Text(
                                    status.semanticStatus
                                        .localizedLabel
                                )
                            } icon: {
                                Image(
                                    systemName: status.semanticStatus
                                        .symbolName
                                )
                                .foregroundStyle(
                                    status.semanticStatus.colorRole
                                        .color
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan legend")
        }
        .presentationDetents([.medium, .large])
    }

    private static func labelModeName(
        _ mode: ReviewPlanLabelMode
    ) -> String {
        switch mode {
        case .off: return String(localized: "Labels off")
        case .important: return String(localized: "Important labels")
        case .all: return String(localized: "All labels")
        }
    }

    private var accessibilitySummary: String {
        let doors = markers.filter { $0.kind == .door }.count
        let windows = markers.filter { $0.kind == .window }.count
        let openings = markers.filter { $0.kind == .opening }.count
        let items = markers.filter {
            $0.selectable
                && ![.door, .window, .opening].contains($0.kind)
        }.count
        let frontConfirmed = markers.contains {
            $0.kind == .roomFrameFront
        }
        return ReviewPlanPresentation.accessibilitySummary(
            wallCount: model.walls.count,
            doorCount: doors,
            windowCount: windows,
            openingCount: openings,
            markerCount: items,
            frontConfirmed: frontConfirmed
        ) ?? String(localized: "Room plan. Empty.")
    }

    // MARK: - Drawing

    private func draw(
        _ marker: RoomPlanPreviewModel.PlanMarker,
        in context: inout GraphicsContext,
        transform: PlanTransform
    ) {
        let p = transform.point(marker.x, marker.z)
        let isSelected =
            selection?.identifier == marker.identifier
            && marker.identifier != nil
        let dimmed = marker.reviewStatus == .intentionallySkipped
        let category = categoryColor(marker.kind)
            .opacity(dimmed ? 0.4 : 1)

        drawGlyph(
            marker, at: p, in: &context, color: category
        )

        // Direction ticks stay part of the glyph (speaker wedge,
        // front arrow), not a separate status channel.
        if let dirX = marker.dirX, let dirZ = marker.dirZ {
            let len = max((dirX * dirX + dirZ * dirZ).squareRoot(), 0.001)
            let ux = dirX / len
            let uz = dirZ / len
            var arrow = Path()
            arrow.move(to: p)
            arrow.addLine(
                to: CGPoint(
                    x: p.x + ux * 16,
                    y: p.y + uz * 16
                )
            )
            context.stroke(
                arrow,
                with: .color(category),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
            if marker.kind == .roomFrameFront {
                var head = Path()
                let tip = CGPoint(
                    x: p.x + ux * 16,
                    y: p.y + uz * 16
                )
                head.move(
                    to: CGPoint(
                        x: tip.x - ux * 6 - uz * 4,
                        y: tip.y - uz * 6 + ux * 4
                    )
                )
                head.addLine(to: tip)
                head.addLine(
                    to: CGPoint(
                        x: tip.x - ux * 6 + uz * 4,
                        y: tip.y - uz * 6 - ux * 4
                    )
                )
                context.stroke(
                    head,
                    with: .color(category),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
            }
        }

        drawStatusBadge(marker, at: p, in: &context)

        if isSelected {
            // Selection = halo + stronger stroke + the marker's short
            // label — exactly one primary selection (#367).
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: p.x - 10, y: p.y - 10, width: 20, height: 20
                )),
                with: .color(.accentColor),
                lineWidth: 2
            )
            context.draw(
                Text(markerTitle(marker))
                    .font(.caption2.weight(.medium)),
                at: CGPoint(x: p.x, y: p.y - 18)
            )
        } else if showsLabel(marker) {
            context.draw(
                Text(markerTitle(marker))
                    .font(.caption2)
                    .foregroundStyle(.secondary),
                at: CGPoint(x: p.x, y: p.y - 14)
            )
        }
    }

    private func showsLabel(
        _ marker: RoomPlanPreviewModel.PlanMarker
    ) -> Bool {
        guard marker.label?.isEmpty == false else { return false }
        switch labelMode {
        case .off: return false
        case .important:
            return marker.reviewStatus == .needsAttention
                || marker.reviewStatus == .pending
        case .all: return true
        }
    }

    private func drawStatusBadge(
        _ marker: RoomPlanPreviewModel.PlanMarker,
        at p: CGPoint,
        in context: inout GraphicsContext
    ) {
        let origin = CGPoint(x: p.x + 7, y: p.y - 7)
        let r: CGFloat = 4
        switch marker.reviewStatus {
        case .nominal:
            break
        case .pending:
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: origin.x - r, y: origin.y - r,
                    width: r * 2, height: r * 2
                )),
                with: .color(.secondary),
                lineWidth: 1.5
            )
        case .confirmed:
            context.fill(
                Path(ellipseIn: CGRect(
                    x: origin.x - r, y: origin.y - r,
                    width: r * 2, height: r * 2
                )),
                with: .color(.green)
            )
            var check = Path()
            check.move(to: CGPoint(x: origin.x - 2, y: origin.y))
            check.addLine(to: CGPoint(x: origin.x - 0.5, y: origin.y + 2))
            check.addLine(to: CGPoint(x: origin.x + 2.5, y: origin.y - 2))
            context.stroke(
                check,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
        case .needsAttention:
            var tri = Path()
            tri.move(to: CGPoint(x: origin.x, y: origin.y - r - 1))
            tri.addLine(to: CGPoint(x: origin.x + r + 1, y: origin.y + r))
            tri.addLine(to: CGPoint(x: origin.x - r - 1, y: origin.y + r))
            tri.closeSubpath()
            context.fill(tri, with: .color(.orange))
        case .intentionallySkipped:
            var slash = Path()
            slash.move(to: CGPoint(x: origin.x - r, y: origin.y + r))
            slash.addLine(to: CGPoint(x: origin.x + r, y: origin.y - r))
            context.stroke(
                slash,
                with: .color(.secondary),
                lineWidth: 1.5
            )
        }
    }

    /// Shape grammar (issue #367 RVIS-30): every marker class draws a
    /// distinct glyph so no class depends on color alone.
    private func drawGlyph(
        _ marker: RoomPlanPreviewModel.PlanMarker,
        at p: CGPoint,
        in context: inout GraphicsContext,
        color: Color
    ) {
        let r: CGFloat = 5
        switch marker.kind {
        case .door:
            // Notch: short tick plus a quarter-arc "swing".
            var tick = Path()
            tick.move(to: CGPoint(x: p.x, y: p.y))
            tick.addLine(to: CGPoint(x: p.x + 7, y: p.y))
            context.stroke(
                tick, with: .color(color), lineWidth: 2
            )
            var arc = Path()
            arc.addArc(
                center: p, radius: 7,
                startAngle: .degrees(0),
                endAngle: .degrees(70),
                clockwise: false
            )
            context.stroke(
                arc, with: .color(color), lineWidth: 1.5
            )
        case .window:
            context.stroke(
                Path(CGRect(
                    x: p.x - 5, y: p.y - 3.5, width: 10, height: 7
                )),
                with: .color(color), lineWidth: 1.8
            )
        case .opening:
            // Gap bracket: two facing ticks.
            var bracket = Path()
            bracket.move(to: CGPoint(x: p.x - 5, y: p.y - 4))
            bracket.addLine(to: CGPoint(x: p.x - 5, y: p.y + 4))
            bracket.move(to: CGPoint(x: p.x + 5, y: p.y - 4))
            bracket.addLine(to: CGPoint(x: p.x + 5, y: p.y + 4))
            context.stroke(
                bracket, with: .color(color), lineWidth: 2
            )
        case .speaker, .display:
            var tri = Path()
            tri.move(to: CGPoint(x: p.x + r + 1, y: p.y))
            tri.addLine(to: CGPoint(x: p.x - r, y: p.y - r))
            tri.addLine(to: CGPoint(x: p.x - r, y: p.y + r))
            tri.closeSubpath()
            context.fill(tri, with: .color(color))
        case .seat:
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: p.x - r, y: p.y - r, width: r * 2, height: r * 2
                )),
                with: .color(color), lineWidth: 1.8
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3
                )),
                with: .color(color)
            )
        case .screen:
            context.fill(
                Path(CGRect(
                    x: p.x - 7, y: p.y - 1.5, width: 14, height: 3
                )),
                with: .color(color)
            )
        case .projector:
            var diamond = Path()
            diamond.move(to: CGPoint(x: p.x, y: p.y - r - 1))
            diamond.addLine(to: CGPoint(x: p.x + r + 1, y: p.y))
            diamond.addLine(to: CGPoint(x: p.x, y: p.y + r + 1))
            diamond.addLine(to: CGPoint(x: p.x - r - 1, y: p.y))
            diamond.closeSubpath()
            context.stroke(
                diamond, with: .color(color), lineWidth: 1.8
            )
        case .measurement, .referencePoint:
            var cross = Path()
            cross.move(to: CGPoint(x: p.x - r, y: p.y))
            cross.addLine(to: CGPoint(x: p.x + r, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: p.y - r))
            cross.addLine(to: CGPoint(x: p.x, y: p.y + r))
            context.stroke(
                cross, with: .color(color), lineWidth: 1.6
            )
        case .annotation:
            var pin = Path()
            pin.move(to: CGPoint(x: p.x, y: p.y - r - 1))
            pin.addLine(to: CGPoint(x: p.x + r, y: p.y))
            pin.addLine(to: CGPoint(x: p.x, y: p.y + r + 1))
            pin.addLine(to: CGPoint(x: p.x - r, y: p.y))
            pin.closeSubpath()
            context.fill(pin, with: .color(color))
        case .roomFrameOrigin:
            var plus = Path()
            plus.move(to: CGPoint(x: p.x - 6, y: p.y))
            plus.addLine(to: CGPoint(x: p.x + 6, y: p.y))
            plus.move(to: CGPoint(x: p.x, y: p.y - 6))
            plus.addLine(to: CGPoint(x: p.x, y: p.y + 6))
            context.stroke(
                plus, with: .color(color), lineWidth: 2
            )
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: p.x - 9, y: p.y - 9, width: 18, height: 18
                )),
                with: .color(color), lineWidth: 1
            )
        case .roomFrameFront:
            // The front arrow is drawn by the direction pass above.
            break
        case .revisitFlag:
            // Flag: pole plus pennant — operator revisit marker (#325).
            var flag = Path()
            flag.move(to: CGPoint(x: p.x - 4, y: p.y - r - 2))
            flag.addLine(to: CGPoint(x: p.x - 4, y: p.y + r + 2))
            context.stroke(flag, with: .color(color), lineWidth: 1.6)
            var pennant = Path()
            pennant.move(to: CGPoint(x: p.x - 4, y: p.y - r - 2))
            pennant.addLine(to: CGPoint(x: p.x + r + 1, y: p.y - r + 1))
            pennant.addLine(to: CGPoint(x: p.x - 4, y: p.y - 1))
            pennant.closeSubpath()
            context.fill(pennant, with: .color(color))
        case .plannedTarget:
            // Ghost ring (issue #293): dashed outline reads as a
            // planned/reference target — design authority, never an
            // observed position. Direction ticks (planned front) are
            // drawn by the direction pass above.
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: p.x - r - 1, y: p.y - r - 1,
                    width: (r + 1) * 2, height: (r + 1) * 2
                )),
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.8, dash: [4, 3])
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3
                )),
                with: .color(color)
            )
        case .object, .genericEntity:
            context.stroke(
                Path(CGRect(
                    x: p.x - r, y: p.y - r,
                    width: r * 2, height: r * 2
                )),
                with: .color(color), lineWidth: 1.6
            )
        }
    }

    /// Connector emphasis (issue #293): the deviation status picks
    /// the stroke color; the dashed style carries "derived link",
    /// never geometry.
    private func connectorColor(
        _ status: PlanMarkerReviewStatus
    ) -> Color {
        switch status {
        case .confirmed: return .green
        case .needsAttention: return .orange
        case .intentionallySkipped: return .secondary
        case .pending, .nominal: return .secondary
        }
    }

    /// Category colors are supportive only (issue #367): kind
    /// differentiation rides on glyph shape; status uses the semantic
    /// badge, not a recolor.
    private func categoryColor(
        _ kind: RoomPlanPreviewModel.PlanMarker.Kind
    ) -> Color {
        switch kind {
        case .door: return .green
        case .window: return .blue
        case .opening: return .teal
        case .object: return .gray
        case .annotation: return .orange
        case .roomFrameOrigin: return .red
        case .roomFrameFront: return .purple
        case .speaker, .display: return .indigo
        case .seat: return .brown
        case .screen: return .cyan
        case .projector: return .mint
        case .measurement, .referencePoint: return .pink
        case .genericEntity: return .secondary
        case .revisitFlag: return .yellow
        case .plannedTarget: return .secondary
        }
    }
}

/// The stable glyph used inside the legend — a tiny Canvas drawing
/// the same grammar as the plan.
private struct LegendGlyph: View {
    let kind: RoomPlanPreviewModel.PlanMarker.Kind

    var body: some View {
        Canvas { context, size in
            let p = CGPoint(x: size.width / 2, y: size.height / 2)
            let color: Color = ReviewPlanSurface.categoryColors[kind]
                ?? .secondary
            var path = Path()
            switch kind {
            case .door:
                path.move(to: p)
                path.addLine(to: CGPoint(x: p.x + 8, y: p.y))
                path.addArc(
                    center: p, radius: 8,
                    startAngle: .degrees(0), endAngle: .degrees(70),
                    clockwise: false
                )
                context.stroke(path, with: .color(color), lineWidth: 2)
            case .window:
                context.stroke(
                    Path(CGRect(
                        x: p.x - 6, y: p.y - 4, width: 12, height: 8
                    )),
                    with: .color(color), lineWidth: 2
                )
            case .opening:
                path.move(to: CGPoint(x: p.x - 6, y: p.y - 5))
                path.addLine(to: CGPoint(x: p.x - 6, y: p.y + 5))
                path.move(to: CGPoint(x: p.x + 6, y: p.y - 5))
                path.addLine(to: CGPoint(x: p.x + 6, y: p.y + 5))
                context.stroke(path, with: .color(color), lineWidth: 2)
            case .speaker, .display:
                path.move(to: CGPoint(x: p.x + 7, y: p.y))
                path.addLine(to: CGPoint(x: p.x - 6, y: p.y - 6))
                path.addLine(to: CGPoint(x: p.x - 6, y: p.y + 6))
                path.closeSubpath()
                context.fill(path, with: .color(color))
            case .seat:
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: p.x - 6, y: p.y - 6, width: 12, height: 12
                    )),
                    with: .color(color), lineWidth: 2
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: p.x - 2, y: p.y - 2, width: 4, height: 4
                    )),
                    with: .color(color)
                )
            case .screen:
                context.fill(
                    Path(CGRect(
                        x: p.x - 8, y: p.y - 2, width: 16, height: 4
                    )),
                    with: .color(color)
                )
            case .projector, .annotation:
                path.move(to: CGPoint(x: p.x, y: p.y - 7))
                path.addLine(to: CGPoint(x: p.x + 7, y: p.y))
                path.addLine(to: CGPoint(x: p.x, y: p.y + 7))
                path.addLine(to: CGPoint(x: p.x - 7, y: p.y))
                path.closeSubpath()
                if kind == .annotation {
                    context.fill(path, with: .color(color))
                } else {
                    context.stroke(path, with: .color(color), lineWidth: 2)
                }
            case .measurement, .referencePoint:
                path.move(to: CGPoint(x: p.x - 6, y: p.y))
                path.addLine(to: CGPoint(x: p.x + 6, y: p.y))
                path.move(to: CGPoint(x: p.x, y: p.y - 6))
                path.addLine(to: CGPoint(x: p.x, y: p.y + 6))
                context.stroke(path, with: .color(color), lineWidth: 2)
            case .roomFrameOrigin:
                path.move(to: CGPoint(x: p.x - 7, y: p.y))
                path.addLine(to: CGPoint(x: p.x + 7, y: p.y))
                path.move(to: CGPoint(x: p.x, y: p.y - 7))
                path.addLine(to: CGPoint(x: p.x, y: p.y + 7))
                context.stroke(path, with: .color(color), lineWidth: 2)
            case .roomFrameFront:
                path.move(to: CGPoint(x: p.x - 6, y: p.y))
                path.addLine(to: CGPoint(x: p.x + 6, y: p.y))
                path.move(to: CGPoint(x: p.x + 6, y: p.y))
                path.addLine(to: CGPoint(x: p.x + 2, y: p.y - 4))
                path.move(to: CGPoint(x: p.x + 6, y: p.y))
                path.addLine(to: CGPoint(x: p.x + 2, y: p.y + 4))
                context.stroke(path, with: .color(color), lineWidth: 2)
            case .revisitFlag:
                path.move(to: CGPoint(x: p.x - 3, y: p.y - 6))
                path.addLine(to: CGPoint(x: p.x - 3, y: p.y + 6))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
                path.move(to: CGPoint(x: p.x - 3, y: p.y - 6))
                path.addLine(to: CGPoint(x: p.x + 5, y: p.y - 4))
                path.addLine(to: CGPoint(x: p.x - 3, y: p.y - 1))
                path.closeSubpath()
                context.fill(path, with: .color(color))
            case .plannedTarget:
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: p.x - 7, y: p.y - 7, width: 14, height: 14
                    )),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 1.8, dash: [4, 3])
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3
                    )),
                    with: .color(color)
                )
            case .object, .genericEntity:
                context.stroke(
                    Path(CGRect(
                        x: p.x - 6, y: p.y - 6, width: 12, height: 12
                    )),
                    with: .color(color), lineWidth: 2
                )
            }
        }
    }
}

public extension RoomPlanPreviewModel.PlanMarker.Kind {
    /// Legend ordering — grouped room geometry → semantic objects →
    /// review items → frame references.
    static var legendOrder: [Self] {
        [
            .door, .window, .opening,
            .speaker, .seat, .screen, .projector, .display,
            .measurement, .referencePoint, .annotation,
            .object, .genericEntity,
            .roomFrameOrigin, .roomFrameFront, .revisitFlag,
            .plannedTarget,
        ]
    }
}

fileprivate extension ReviewPlanSurface {
    /// Shared category palette for legend glyphs (issue #367).
    static let categoryColors: [RoomPlanPreviewModel.PlanMarker.Kind: Color] = [
        .door: .green, .window: .blue, .opening: .teal,
        .object: .gray, .annotation: .orange,
        .roomFrameOrigin: .red, .roomFrameFront: .purple,
        .speaker: .indigo, .display: .indigo, .seat: .brown,
        .screen: .cyan, .projector: .mint,
        .measurement: .pink, .referencePoint: .pink,
        .genericEntity: .secondary,
        .revisitFlag: .yellow, .plannedTarget: .secondary,
    ]
}
