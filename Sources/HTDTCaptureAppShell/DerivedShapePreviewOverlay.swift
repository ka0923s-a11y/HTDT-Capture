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

                if let supportAnalysis = snapshot.supportAnalysis {
                    HStack(spacing: 8) {
                        Label(
                            supportSummaryLabel(supportAnalysis),
                            systemImage: "cube.transparent"
                        )
                        Spacer()
                        Text(lowerVolumeLabel(supportAnalysis))
                    }
                    .font(.caption2)
                    .foregroundStyle(.cyan)

                    if let advisory = supportAnalysis.advisories.first {
                        Label(
                            advisoryLabel(advisory.kind),
                            systemImage: "viewfinder"
                        )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    }
                }
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

    private func supportSummaryLabel(
        _ analysis: DerivedSupportAnalysis
    ) -> String {
        switch analysis.resolution {
        case .separatedSupports:
            return String(
                format:
                    String(localized: "%d observed supports"),
                analysis.supports.count
            )
        case .solidToFloor:
            return String(localized: "Observed body reaches floor")
        case .floatingBodyUnresolved:
            return String(localized: "Lower support unresolved")
        case .insufficientHeightEvidence:
            return String(localized: "Height evidence insufficient")
        }
    }

    private func lowerVolumeLabel(
        _ analysis: DerivedSupportAnalysis
    ) -> String {
        switch analysis.lowerVolumeState {
        case .sparseObservedSupports:
            return String(localized: "Open lower volume")
        case .solidToFloor:
            return String(localized: "Solid to floor")
        case .unresolved:
            return String(localized: "Unresolved")
        }
    }

    private func advisoryLabel(
        _ kind: DerivedSupportAdvisoryKind
    ) -> String {
        switch kind {
        case .observeLowerFurniture:
            return String(localized: "Show the lower part of the furniture")
        case .observeLowerFurnitureFromAnotherAngle:
            return String(localized: "Show the lower part from another angle")
        }
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

        if let supportAnalysis = snapshot.supportAnalysis {
            drawSupportElements(
                supportAnalysis.supports,
                context: &context,
                size: size,
                bounds: bounds
            )
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

    private func drawSupportElements(
        _ supports: [DerivedSupportElement],
        context: inout GraphicsContext,
        size: CGSize,
        bounds: PreviewBounds
    ) {
        for support in supports {
            let center = bounds.map(support.center, into: size)
            let edge = bounds.map(
                DerivedPoint2D(
                    x: support.center.x + support.footprintRadius,
                    y: support.center.y
                ),
                into: size
            )
            let radius = max(
                CGFloat(3),
                min(CGFloat(14), abs(edge.x - center.x))
            )
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let path = Path(ellipseIn: rect)
            let uncertain = support.resolution == .uncertain
            context.fill(
                path,
                with: .color(
                    .cyan.opacity(uncertain ? 0.08 : 0.18)
                )
            )
            context.stroke(
                path,
                with: .color(
                    .cyan.opacity(uncertain ? 0.65 : 0.95)
                ),
                style: StrokeStyle(
                    lineWidth: uncertain ? 1.2 : 2.0,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: uncertain ? [3, 3] : []
                )
            )
        }
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

        if let supportAnalysis = snapshot.supportAnalysis {
            for support in supportAnalysis.supports {
                points.append(support.center)
                points.append(
                    DerivedPoint2D(
                        x: support.center.x + support.footprintRadius,
                        y: support.center.y
                    )
                )
                points.append(
                    DerivedPoint2D(
                        x: support.center.x - support.footprintRadius,
                        y: support.center.y
                    )
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
