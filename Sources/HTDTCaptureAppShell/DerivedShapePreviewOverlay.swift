import Foundation
import SwiftUI
import HTDTCaptureCore

enum DerivedPreviewMode: String, CaseIterable, Identifiable {
    case roomPlan
    case observation
    case overlay

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .roomPlan:
            return "RoomPlan structure"
        case .observation:
            return "Observed shape"
        case .overlay:
            return "Compare"
        }
    }
}

struct DerivedShapePreviewPanel: View {
    let snapshot: DerivedShapePreviewSnapshot
    @Binding var mode: DerivedPreviewMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Geometry preview")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Derived · advisory")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Picker("Geometry preview", selection: $mode) {
                ForEach(DerivedPreviewMode.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if let decomposition = snapshot.objectDecomposition {
                decompositionSummary(decomposition)
            }

            if mode == .roomPlan {
                Text(
                    "The camera view is showing the RoomPlan semantic structure. HTDT observed geometry is hidden."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Canvas { context, size in
                    drawPreview(
                        context: &context,
                        size: size
                    )
                }
                .frame(height: 118)
                .background(
                    Color.black.opacity(0.35),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

                HStack(spacing: 10) {
                    Label(
                        primaryShapeLabel,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                    Spacer()
                    if let metrics = primaryMetrics {
                        Text(
                            String(
                                format:
                                    String(
                                        localized: "Residual %.3f · support %d%%"
                                    ),
                                metrics.normalizedResidual,
                                Int(
                                    (
                                        metrics.supportScore * 100
                                    ).rounded()
                                )
                            )
                        )
                        .monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !snapshot.disagreements.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        "Structure estimate and observed shape differ",
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                    Text(
                        "The views are separate evidence representations; neither is promoted as canonical geometry here."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var primaryProxy: DerivedShapeProxy? {
        snapshot.objectProxies.first
    }

    private var primaryMetrics: DerivedShapeFitMetrics? {
        primaryProxy?.selected?.metrics
    }

    private var primaryShapeLabel: String {
        if let decomposition = snapshot.objectDecomposition,
           decomposition.state == .unresolvedDecomposition
        {
            return String(localized: "Decomposition unresolved")
        }

        guard let primaryProxy else {
            return snapshot.wallChain == nil
                ? String(localized: "No bounded shape evidence yet")
                : String(localized: "Observed wall chain")
        }

        guard let selected = primaryProxy.selected else {
            switch primaryProxy.resolution {
            case .insufficientEvidence:
                return String(localized: "Shape unresolved")
            case .ambiguousEvidence:
                return String(localized: "Shape ambiguous")
            case .resolved:
                return String(localized: "Shape unresolved")
            }
        }

        switch selected.kind {
        case .orientedRectangle:
            return String(localized: "Oriented rectangle")
        case .circle:
            return String(localized: "Circle")
        case .ellipse:
            return String(localized: "Ellipse")
        case .polygon:
            return String(localized: "Polygon")
        }
    }

    @ViewBuilder
    private func decompositionSummary(
        _ decomposition: DerivedObjectDecomposition
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(decompositionHeadline(decomposition))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(decompositionStateLabel(decomposition.state))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(
                Array(decomposition.components.prefix(4)),
                id: \.id
            ) { component in
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(.secondary)
                    Text(
                        componentHeightLabel(
                            component,
                            total: decomposition.components.count
                        )
                    )
                    .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !decomposition.supportRelations.isEmpty {
                Text(
                    String(
                        format:
                            String(
                                localized:
                                    "%d preview-only support relation candidate(s)"
                            ),
                        decomposition.supportRelations.count
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if decomposition.reobservationAdvisory != nil {
                Label(
                    "Re-observe this region from another angle",
                    systemImage: "viewfinder"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .padding(8)
        .background(
            Color.secondary.opacity(0.10),
            in: RoundedRectangle(
                cornerRadius: 8,
                style: .continuous
            )
        )
    }

    private func decompositionHeadline(
        _ decomposition: DerivedObjectDecomposition
    ) -> String {
        switch decomposition.state {
        case .resolved:
            return String(
                format:
                    String(localized: "Observed shape candidates %d"),
                decomposition.components.count
            )
        case .possibleMultipleComponents:
            return String(
                format:
                    String(localized: "Possible shape candidates %d"),
                decomposition.components.count
            )
        case .unresolvedDecomposition:
            return String(localized: "Decomposition unresolved")
        }
    }

    private func decompositionStateLabel(
        _ state: DerivedObjectDecompositionState
    ) -> String {
        switch state {
        case .resolved:
            return String(localized: "Separated")
        case .possibleMultipleComponents:
            return String(localized: "Possible multiple components")
        case .unresolvedDecomposition:
            return String(localized: "Unresolved")
        }
    }

    private func componentHeightLabel(
        _ component: DerivedObjectComponentCandidate,
        total: Int
    ) -> String {
        let order: String
        if total == 2 {
            order = component.heightOrder == 0
                ? String(localized: "Lower")
                : String(localized: "Upper")
        } else {
            order = String(
                format: String(localized: "Layer %d"),
                component.heightOrder + 1
            )
        }

        guard let extent = component.verticalExtent else {
            return order
        }

        return String(
            format: "%@ · %.2f–%.2f m",
            order,
            extent.minY,
            extent.maxY
        )
    }

    private func drawPreview(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let points = allPreviewPoints
        guard let bounds = PreviewBounds(points: points) else {
            return
        }

        for proxy in snapshot.objectProxies {
            if let selected = proxy.selected {
                drawGeometry(
                    selected.geometry,
                    context: &context,
                    size: size,
                    bounds: bounds
                )
            } else {
                for point in proxy.observationSample.prefix(64) {
                    let mapped = bounds.map(
                        point.position,
                        into: size
                    )
                    let dot = CGRect(
                        x: mapped.x - 1.5,
                        y: mapped.y - 1.5,
                        width: 3,
                        height: 3
                    )
                    context.fill(
                        Path(ellipseIn: dot),
                        with: .color(.orange.opacity(0.8))
                    )
                }
            }
        }

        if let wallChain = snapshot.wallChain {
            let points = wallChain.vertices.map(\.position)
            drawPolyline(
                points,
                closed: wallChain.isClosed,
                context: &context,
                size: size,
                bounds: bounds,
                lineWidth: 2.2,
                dashed: true
            )
        }
    }

    private func drawGeometry(
        _ geometry: DerivedFootprintGeometry,
        context: inout GraphicsContext,
        size: CGSize,
        bounds: PreviewBounds
    ) {
        let (points, closed) = geometryPolyline(geometry)
        guard points.count >= 2 else {
            return
        }

        var path = Path()
        let first = bounds.map(points[0], into: size)
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(
                to: bounds.map(point, into: size)
            )
        }
        if closed {
            path.closeSubpath()
            context.fill(
                path,
                with: .color(.orange.opacity(0.12))
            )
        }
        context.stroke(
            path,
            with: .color(.orange),
            style: StrokeStyle(
                lineWidth: 2.4,
                lineCap: .round,
                lineJoin: .round,
                dash: [7, 4]
            )
        )
    }

    private func drawPolyline(
        _ points: [DerivedPoint2D],
        closed: Bool,
        context: inout GraphicsContext,
        size: CGSize,
        bounds: PreviewBounds,
        lineWidth: CGFloat,
        dashed: Bool
    ) {
        guard let first = points.first else {
            return
        }
        var path = Path()
        path.move(to: bounds.map(first, into: size))
        for point in points.dropFirst() {
            path.addLine(
                to: bounds.map(point, into: size)
            )
        }
        if closed {
            path.closeSubpath()
        }

        context.stroke(
            path,
            with: .color(.cyan),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: dashed ? [4, 3] : []
            )
        )

        for point in points {
            let mapped = bounds.map(point, into: size)
            let marker = CGRect(
                x: mapped.x - 2.5,
                y: mapped.y - 2.5,
                width: 5,
                height: 5
            )
            context.fill(
                Path(ellipseIn: marker),
                with: .color(.cyan)
            )
        }
    }

    private var allPreviewPoints: [DerivedPoint2D] {
        var points: [DerivedPoint2D] = []

        for proxy in snapshot.objectProxies {
            if let selected = proxy.selected {
                points.append(
                    contentsOf:
                        geometryPolyline(
                            selected.geometry
                        ).0
                )
            } else {
                points.append(
                    contentsOf:
                        proxy.observationSample.map(\.position)
                )
            }
        }

        if let wallChain = snapshot.wallChain {
            points.append(
                contentsOf:
                    wallChain.vertices.map(\.position)
            )
        }

        return points
    }

    private func geometryPolyline(
        _ geometry: DerivedFootprintGeometry
    ) -> ([DerivedPoint2D], Bool) {
        switch geometry {
        case let .orientedRectangle(rectangle):
            let halfWidth = rectangle.width / 2
            let halfDepth = rectangle.depth / 2
            let corners = [
                DerivedPoint2D(x: -halfWidth, y: -halfDepth),
                DerivedPoint2D(x: halfWidth, y: -halfDepth),
                DerivedPoint2D(x: halfWidth, y: halfDepth),
                DerivedPoint2D(x: -halfWidth, y: halfDepth),
            ]
            return (
                corners.map {
                    transformed(
                        $0,
                        center: rectangle.center,
                        heading: rectangle.headingRadians
                    )
                },
                true
            )

        case let .circle(circle):
            return (
                (0..<48).map { index in
                    let angle =
                        2 * Double.pi * Double(index) / 48
                    return DerivedPoint2D(
                        x:
                            circle.center.x
                            + circle.radius * cos(angle),
                        y:
                            circle.center.y
                            + circle.radius * sin(angle)
                    )
                },
                true
            )

        case let .ellipse(ellipse):
            return (
                (0..<48).map { index in
                    let angle =
                        2 * Double.pi * Double(index) / 48
                    let local = DerivedPoint2D(
                        x:
                            ellipse.semiMajorAxis
                            * cos(angle),
                        y:
                            ellipse.semiMinorAxis
                            * sin(angle)
                    )
                    return transformed(
                        local,
                        center: ellipse.center,
                        heading: ellipse.headingRadians
                    )
                },
                true
            )

        case let .polygon(polygon):
            return (
                polygon.vertices.map(\.position),
                true
            )
        }
    }

    private func transformed(
        _ point: DerivedPoint2D,
        center: DerivedPoint2D,
        heading: Double
    ) -> DerivedPoint2D {
        let c = cos(heading)
        let s = sin(heading)
        return DerivedPoint2D(
            x:
                center.x
                + c * point.x
                - s * point.y,
            y:
                center.y
                + s * point.x
                + c * point.y
        )
    }
}

private struct PreviewBounds {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    init?(points: [DerivedPoint2D]) {
        guard let first = points.first else {
            return nil
        }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let width = max(maxX - minX, 0.05)
        let height = max(maxY - minY, 0.05)
        let paddingX = width * 0.08
        let paddingY = height * 0.08

        self.minX = minX - paddingX
        self.maxX = maxX + paddingX
        self.minY = minY - paddingY
        self.maxY = maxY + paddingY
    }

    func map(
        _ point: DerivedPoint2D,
        into size: CGSize
    ) -> CGPoint {
        let width = max(maxX - minX, 0.001)
        let height = max(maxY - minY, 0.001)
        let scale = min(
            Double(size.width) / width,
            Double(size.height) / height
        )
        let drawnWidth = width * scale
        let drawnHeight = height * scale
        let offsetX =
            (Double(size.width) - drawnWidth) / 2
        let offsetY =
            (Double(size.height) - drawnHeight) / 2

        return CGPoint(
            x:
                offsetX
                + (point.x - minX) * scale,
            y:
                offsetY
                + (maxY - point.y) * scale
        )
    }
}
