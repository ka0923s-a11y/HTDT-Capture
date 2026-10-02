import Foundation
import SwiftUI
import HTDTCaptureCore
#if os(iOS)
import SceneKit
#endif

/// The accepted-geometry 3D review surface (issue #408). Everything
/// rendered is committed, persisted evidence — mesh anchor payloads,
/// RoomPlan surfaces/objects, derived candidates, committed entities —
/// layered by provenance (capture vs derived vs semantic authority)
/// so a reader can always tell evidence from inference. It is a
/// review/authoring aid, not a second CAD application: camera presets
/// and element selection, never free-form modeling.
///
/// The view is read-only over the bundle — it never mutates
/// authorities. Selection exposes the same element the spatial
/// survey binds to; "Pick again" in the authoring flow means
/// re-capturing the scan epoch, which the sealed-checksum banner in
/// the workspace surfaces when geometry changed after commitment.
public struct AcceptedGeometrySceneView: View {
    public let scene: AcceptedGeometrySceneModel
    /// Read-only is the review contract (#408 §16); authoring hosts
    /// still get selection + focus for bound-element inspection.
    public let readOnly: Bool
    @State private var preset: GeometryCameraPreset = .fitRoom
    @State private var selectedElementID: String?
    @State private var elementsExpanded = true

    public init(
        scene: AcceptedGeometrySceneModel,
        readOnly: Bool = true
    ) {
        self.scene = scene
        self.readOnly = readOnly
    }

    private var selectedElement: GeometrySceneElement? {
        scene.elements.first { $0.elementID == selectedElementID }
    }

    /// Caption describing what the selected camera preset shows —
    /// segmented controls carry no per-option detail, so the choice
    /// is explained under the picker instead.
    private var presetCaption: String {
        switch preset {
        case .orbit:
            return String(localized:
                "Orbit freely around the room at a readable diagonal angle.")
        case .frontElevation:
            return String(localized:
                "Flat elevation view looking toward the room front.")
        case .sideElevation:
            return String(localized:
                "Flat elevation view looking in from the room's right side.")
        case .topPlan:
            return String(localized:
                "Straight-down plan view matching the 2D layout.")
        case .fitRoom:
            return String(localized:
                "Frames every captured element in view at once.")
        case .focusElement:
            return String(localized:
                "Orbits around the element selected in the list.")
        }
    }

    public var body: some View {
        VStack(spacing: 8) {
            if scene.elements.isEmpty {
                Text("No spatial geometry is stored in this capture")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
            } else {
                Picker("Camera", selection: $preset) {
                    Text("Orbit").tag(GeometryCameraPreset.orbit)
                    Text("Front")
                        .tag(GeometryCameraPreset.frontElevation)
                    Text("Side")
                        .tag(GeometryCameraPreset.sideElevation)
                    Text("Top").tag(GeometryCameraPreset.topPlan)
                    Text("Fit").tag(GeometryCameraPreset.fitRoom)
                    if selectedElement != nil {
                        Text("Focus").tag(
                            GeometryCameraPreset.focusElement(
                                selectedElementID ?? ""
                            )
                        )
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(presetCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if os(iOS)
                GeometrySceneRepresentable(
                    scene: scene,
                    preset: preset,
                    selectedElementID: $selectedElementID
                )
                .frame(minHeight: 300)
                .clipShape(
                    RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("3D room geometry")
                .accessibilityHint(
                    "Use the elements list for the same content without 3D interaction"
                )
                #else
                // macOS verification target: the list below is the
                // full equivalent — the SceneKit surface is iOS-only
                // (#408: the package must still compile off-device).
                Text(
                    "3D preview is available on iOS — the elements list carries the same geometry"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                #endif

                if let element = selectedElement {
                    sceneSelectionCard(element)
                }

                layerLegend
            }

            // #408: the accessible equivalent — every rendered element
            // as a list, so VoiceOver and non-3D contexts see exactly
            // what the scene shows.
            DisclosureGroup(
                isExpanded: $elementsExpanded
            ) {
                ForEach(scene.elements) { element in
                    Button {
                        selectedElementID = element.elementID
                        if element.isSelectable {
                            preset = .focusElement(
                                element.elementID
                            )
                        }
                    } label: {
                        elementRow(element)
                    }
                    .disabled(!element.isSelectable)
                }
            } label: {
                Text(
                    "Scene elements (\(scene.elements.count))"
                )
                .font(.caption)
            }
        }
    }

    /// The layer visual language (#408 §7): captured evidence,
    /// derived candidates and semantic authority never share a color
    /// so a boundary pulled from RoomPlan can never be mistaken for
    /// an operator's committed entity.
    private var layerLegend: some View {
        HStack(spacing: 12) {
            legendChip("Captured", role: .capturedEvidence)
            legendChip("Derived", role: .derivedCandidate)
            legendChip("Authority", role: .semanticAuthority)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendChip(
        _ label: String,
        role: GeometrySceneLayer
    ) -> some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: "square.fill")
                .foregroundStyle(
                    GeometryScenePresentation.layerColor(role)
                )
        }
    }

    private func elementRow(
        _ element: GeometrySceneElement
    ) -> some View {
        HStack {
            Image(
                systemName: GeometryScenePresentation
                    .kindSymbol(element.kind)
            )
            .foregroundStyle(
                GeometryScenePresentation.layerColor(
                    element.layer
                )
            )
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(element.label)
                    .font(.caption)
                Text(
                    GeometryScenePresentation.kindName(
                        element.kind
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if element.elementID == selectedElementID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
    }

    /// Selection detail (#408 §9): identity + provenance of the
    /// picked element. Re-anchoring after the epoch changed is an
    /// authoring decision — read-only review only ever inspects.
    private func sceneSelectionCard(
        _ element: GeometrySceneElement
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(element.label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(
                    GeometryScenePresentation.layerName(
                        element.layer
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    GeometryScenePresentation.layerColor(
                        element.layer
                    )
                )
            }
            Text(element.elementID)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            if !readOnly {
                Text(
                    "Geometry committed under a different epoch must be re-picked in the annotation workspace — this surface never rewrites authority bindings."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
    }
}

/// Shared colors/symbols/names for the layer visual language so the
/// 3D nodes, legend, and accessible list can never disagree.
public enum GeometryScenePresentation {
    public static func layerColor(
        _ layer: GeometrySceneLayer
    ) -> Color {
        switch layer {
        case .capturedEvidence:
            return Color(red: 0.45, green: 0.55, blue: 0.65)
        case .derivedCandidate:
            return Color(red: 0.6, green: 0.45, blue: 0.8)
        case .semanticAuthority:
            return Color(red: 0.85, green: 0.55, blue: 0.2)
        }
    }

    public static func layerName(
        _ layer: GeometrySceneLayer
    ) -> String {
        switch layer {
        case .capturedEvidence:
            return String(localized: "Captured evidence")
        case .derivedCandidate:
            return String(localized: "Derived candidate")
        case .semanticAuthority:
            return String(localized: "Committed authority")
        }
    }

    public static func kindName(
        _ kind: GeometrySceneElementKind
    ) -> String {
        switch kind {
        case .meshAnchor:
            return String(localized: "Mesh region")
        case .roomPlanSurface:
            return String(localized: "RoomPlan surface")
        case .roomPlanObject:
            return String(localized: "RoomPlan object")
        case .derivedCandidate:
            return String(localized: "Derived geometry")
        case .entity:
            return String(localized: "Committed entity")
        case .measurement:
            return String(localized: "Measurement")
        }
    }

    public static func kindSymbol(
        _ kind: GeometrySceneElementKind
    ) -> String {
        switch kind {
        case .meshAnchor:
            return "squareshape.split.3x3"
        case .roomPlanSurface:
            return "square.split.bottomrightquarter"
        case .roomPlanObject:
            return "cube"
        case .derivedCandidate:
            return "cube.transparent"
        case .entity:
            return "tag"
        case .measurement:
            return "ruler"
        }
    }
}

#if os(iOS)
/// SceneKit-backed 3D surface (#408 §4): native orbit/pinch/pan via
/// `allowsCameraControl`, tap-to-select wired to the committed
/// element list, and named camera presets. Every node maps back to
/// its `GeometrySceneElement` — LOD/impostors would lie about
/// evidence, so geometry is rendered verbatim.
struct GeometrySceneRepresentable: UIViewRepresentable {
    let scene: AcceptedGeometrySceneModel
    let preset: GeometryCameraPreset
    @Binding var selectedElementID: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        buildScene(into: view, coordinator: context.coordinator)
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        applyCamera(to: view)
        return view
    }

    func updateUIView(
        _ view: SCNView,
        context: Context
    ) {
        if context.coordinator.builtSignature
            != sceneSignature
        {
            buildScene(into: view, coordinator: context.coordinator)
        }
        if context.coordinator.lastPreset != preset {
            context.coordinator.lastPreset = preset
            applyCamera(to: view)
        }
        applySelection(to: view)
    }

    /// Node identity → element lookup; the model is value-typed, so
    /// a stale scene tree is rebuilt rather than diffed.
    private var sceneSignature: Int {
        var hasher = Hasher()
        hasher.combine(scene.elements.count)
        for element in scene.elements {
            hasher.combine(element.elementID)
        }
        hasher.combine(scene.directionIndicators.count)
        return hasher.finalize()
    }

    private func buildScene(
        into view: SCNView,
        coordinator: Coordinator
    ) {
        let scnScene = SCNScene()
        coordinator.elementLookup = Dictionary(
            uniqueKeysWithValues: scene.elements.map {
                ($0.elementID, $0)
            }
        )
        coordinator.builtSignature = sceneSignature

        for element in scene.elements {
            let node = makeNode(for: element)
            node.name = element.elementID
            scnScene.rootNode.addChildNode(node)
        }
        for indicator in scene.directionIndicators {
            let node = makeIndicatorNode(indicator)
            node.name = "indicator:" + indicator.indicatorID
            scnScene.rootNode.addChildNode(node)
        }

        // Reference floor grid at the lowest bound — orientation cue
        // only, deliberately not an evidence node.
        if let min = scene.boundsMin {
            let maxBound = scene.boundsMax ?? min
            let extent = max(
                maxBound.x - min.x, maxBound.z - min.z, 1
            )
            let floor = SCNNode(
                geometry: SCNPlane(
                    width: CGFloat(extent),
                    height: CGFloat(extent)
                )
            )
            floor.geometry?.firstMaterial?.diffuse.contents =
                UIColor.systemGray6
            floor.geometry?.firstMaterial?.isDoubleSided = true
            floor.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            floor.position = SCNVector3(
                (min.x + maxBound.x) / 2,
                min.y - 0.001,
                (min.z + maxBound.z) / 2
            )
            floor.name = "_floor_grid"
            scnScene.rootNode.addChildNode(floor)
        }

        view.scene = scnScene
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.name = "_camera"
        scnScene.rootNode.addChildNode(camera)
        view.pointOfView = camera
    }

    private func applyCamera(to view: SCNView) {
        guard let camera = view.scene?.rootNode
            .childNode(withName: "_camera", recursively: false)
        else {
            return
        }
        let spec = resolvedCameraSpec()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        camera.position = SCNVector3(
            spec.positionWorld.x,
            spec.positionWorld.y,
            spec.positionWorld.z
        )
        camera.look(
            at: SCNVector3(
                spec.lookAtWorld.x,
                spec.lookAtWorld.y,
                spec.lookAtWorld.z
            ),
            up: SCNVector3(
                spec.upWorld.x,
                spec.upWorld.y,
                spec.upWorld.z
            ),
            localFront: SCNVector3(0, 0, -1)
        )
        camera.camera?.fieldOfView = CGFloat(
            spec.fieldOfViewDegrees
        )
        SCNTransaction.commit()
    }

    private func resolvedCameraSpec() -> GeometryCameraSpec {
        scene.cameraSpec(for: preset)
    }

    private func applySelection(to view: SCNView) {
        guard let root = view.scene?.rootNode else { return }
        root.enumerateChildNodes { node, _ in
            guard let name = node.name,
                  !name.hasPrefix("_")
            else {
                return
            }
            node.geometry?.materials.forEach { material in
                material.emission.contents =
                    name == selectedElementID
                        ? UIColor.systemOrange
                        : UIColor.black
            }
        }
    }

    private func makeNode(
        for element: GeometrySceneElement
    ) -> SCNNode {
        switch element.kind {
        case .meshAnchor:
            return meshNode(element)
        case .roomPlanSurface, .roomPlanObject:
            return boxNode(element, opacity: 0.75)
        case .derivedCandidate:
            return derivedCandidateNode(element)
        case .entity:
            let sphere = SCNNode(
                geometry: SCNSphere(radius: 0.06)
            )
            sphere.geometry?.firstMaterial?.diffuse.contents =
                color(for: element.layer)
            sphere.position = scnVector(element.centerWorld)
            return sphere
        case .measurement:
            let dot = SCNNode(
                geometry: SCNSphere(radius: 0.035)
            )
            dot.geometry?.firstMaterial?.diffuse.contents =
                UIColor.systemGreen
            dot.position = scnVector(element.centerWorld)
            return dot
        }
    }

    private func meshNode(
        _ element: GeometrySceneElement
    ) -> SCNNode {
        guard let anchorID = element.sourceMeshAnchorID,
              let snapshot = scene.meshSnapshots[anchorID]
        else {
            return boxNode(element, opacity: 0.2)
        }
        let geometry = snapshot.geometry
        let vertexSource = SCNGeometrySource(
            vertices: geometry.vertices.map {
                SCNVector3($0.x, $0.y, $0.z)
            }
        )
        var sources = [vertexSource]
        if let normals = geometry.normals {
            sources.append(
                SCNGeometrySource(
                    normals: normals.map {
                        SCNVector3($0.x, $0.y, $0.z)
                    }
                )
            )
        }
        let indexData = Data(
            bytes: geometry.triangleIndices,
            count: geometry.triangleIndices.count
                * MemoryLayout<UInt32>.size
        )
        let indices = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: geometry.triangleIndices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let scnGeometry = SCNGeometry(
            sources: sources,
            elements: [indices]
        )
        let material = SCNMaterial()
        material.diffuse.contents = color(for: element.layer)
        material.isDoubleSided = true
        material.transparency = 0.55
        material.lightingModel = .constant
        scnGeometry.materials = [material]
        let node = SCNNode(geometry: scnGeometry)
        // Vertices are anchor-local; the node's transform carries
        // them into world space (#408 — accepted pose only).
        let m = snapshot.worldFromAnchor.values
        node.transform = SCNMatrix4(
            m11: m[0], m12: m[1],
            m13: m[2], m14: m[3],
            m21: m[4], m22: m[5],
            m23: m[6], m24: m[7],
            m31: m[8], m32: m[9],
            m33: m[10], m34: m[11],
            m41: m[12], m42: m[13],
            m43: m[14], m44: m[15]
        )
        return node
    }

    /// Resolved candidates render their fitted footprint as a flat
    /// outline floating at the contour's median height; unresolved
    /// ones show the raw contour point set — a translucent box would
    /// claim a volume the fit never produced.
    private func derivedCandidateNode(
        _ element: GeometrySceneElement
    ) -> SCNNode {
        guard let candidateID = element.sourceDerivedCandidateID,
              let record = scene.derivedCandidates[candidateID]
        else {
            return boxNode(element, opacity: 0.3)
        }

        let heights = record.contourPoints
            .compactMap(\.verticalPositionMeters)
            .sorted()
        let medianY = Float(
            heights.isEmpty
                ? Double(element.centerWorld.y)
                : heights[heights.count / 2]
        )

        if let geometry = record.geometry {
            let loop = planLoop(for: geometry)
            if loop.count >= 2 {
                let node = SCNNode(
                    geometry: loopGeometry(
                        loop.map {
                            SCNVector3(
                                Float($0.x), medianY, Float($0.y)
                            )
                        },
                        closed: record.resolution == .resolved
                    )
                )
                node.geometry?.firstMaterial?.diffuse.contents =
                    color(for: element.layer)
                return node
            }
        }

        // Unresolved (or degenerate geometry): show the observed
        // contour itself as a point cloud.
        let vertices = record.contourPoints.map {
            SCNVector3(
                Float($0.position.x),
                Float($0.verticalPositionMeters ?? Double(medianY)),
                Float($0.position.y)
            )
        }
        guard !vertices.isEmpty else {
            return boxNode(element, opacity: 0.3)
        }
        let node = SCNNode(
            geometry: pointGeometry(vertices)
        )
        node.geometry?.firstMaterial?.diffuse.contents =
            color(for: element.layer)
        return node
    }

    /// Fitted footprint → plan-space outline (x = world X, y = world
    /// Z), in the order the segments should be drawn.
    private func planLoop(
        for geometry: DerivedFootprintGeometry
    ) -> [DerivedPoint2D] {
        switch geometry {
        case .polygon(let polygon):
            return polygon.vertices.map(\.position)
        case .orientedRectangle(let rectangle):
            let c = cos(rectangle.headingRadians)
            let s = sin(rectangle.headingRadians)
            let hw = rectangle.width / 2
            let hd = rectangle.depth / 2
            return [
                (hw, hd), (-hw, hd), (-hw, -hd), (hw, -hd),
            ].map { u, v in
                DerivedPoint2D(
                    x: rectangle.center.x + c * u - s * v,
                    y: rectangle.center.y + s * u + c * v
                )
            }
        case .circle(let circle):
            return (0..<24).map { index in
                let angle =
                    Double(index) * 2 * .pi / 24
                return DerivedPoint2D(
                    x: circle.center.x
                        + circle.radius * cos(angle),
                    y: circle.center.y
                        + circle.radius * sin(angle)
                )
            }
        case .ellipse(let ellipse):
            let c = cos(ellipse.headingRadians)
            let s = sin(ellipse.headingRadians)
            return (0..<24).map { index in
                let angle =
                    Double(index) * 2 * .pi / 24
                let u = ellipse.semiMajorAxis * cos(angle)
                let v = ellipse.semiMinorAxis * sin(angle)
                return DerivedPoint2D(
                    x: ellipse.center.x + c * u - s * v,
                    y: ellipse.center.y + s * u + c * v
                )
            }
        }
    }

    private func loopGeometry(
        _ vertices: [SCNVector3],
        closed: Bool
    ) -> SCNGeometry {
        var indices: [UInt32] = []
        let segments = closed
            ? vertices.count
            : vertices.count - 1
        for index in 0..<max(segments, 0) {
            indices.append(UInt32(index))
            indices.append(
                UInt32((index + 1) % vertices.count)
            )
        }
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let indexData = Data(
            bytes: indices,
            count: indices.count * MemoryLayout<UInt32>.size
        )
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: indices.count / 2,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geometry = SCNGeometry(
            sources: [vertexSource],
            elements: [element]
        )
        geometry.firstMaterial?.lightingModel = .constant
        return geometry
    }

    private func pointGeometry(
        _ vertices: [SCNVector3]
    ) -> SCNGeometry {
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: 0
        )
        element.pointSize = 6
        let geometry = SCNGeometry(
            sources: [vertexSource],
            elements: [element]
        )
        geometry.firstMaterial?.lightingModel = .constant
        return geometry
    }

    private func boxNode(
        _ element: GeometrySceneElement,
        opacity: CGFloat
    ) -> SCNNode {
        let extents = element.extentsWorld
            ?? Float3(0.3, 0.3, 0.3)
        let box = SCNBox(
            width: CGFloat(max(extents.x, 0.01)),
            height: CGFloat(max(extents.y, 0.01)),
            length: CGFloat(max(extents.z, 0.01)),
            chamferRadius: 0
        )
        box.firstMaterial?.diffuse.contents =
            color(for: element.layer)
        box.firstMaterial?.transparency = opacity
        let node = SCNNode(geometry: box)
        if let transform = element.worldFromElement {
            let m = transform.values
            node.transform = SCNMatrix4(
                m11: m[0], m12: m[1],
                m13: m[2], m14: m[3],
                m21: m[4], m22: m[5],
                m23: m[6], m24: m[7],
                m31: m[8], m32: m[9],
                m33: m[10], m34: m[11],
                m41: m[12], m42: m[13],
                m43: m[14], m44: m[15]
            )
        } else {
            node.position = scnVector(element.centerWorld)
        }
        return node
    }

    /// Direction arrows (#408 §11): full 3D vectors — a horizontal-
    /// only legacy export renders thin + desaturated and the label
    /// carries the flag, never silently projected flat.
    private func makeIndicatorNode(
        _ indicator: DirectionalIndicator
    ) -> SCNNode {
        let direction = indicator.directionWorld
            ?? Float3(1, 0, 0)
        let length = sqrt(
            direction.x * direction.x
                + direction.y * direction.y
                + direction.z * direction.z
        )
        let normalized = length > 0.001
            ? Float3(
                direction.x / length,
                direction.y / length,
                direction.z / length
            )
            : Float3(1, 0, 0)
        let arrowLength: Float = 0.45
        let shaft = SCNNode(
            geometry: SCNCylinder(
                radius: CGFloat(
                    indicator.verticalDropped ? 0.006 : 0.012
                ),
                height: CGFloat(arrowLength)
            )
        )
        let materialColor: UIColor = indicator.verticalDropped
            ? UIColor.systemOrange.withAlphaComponent(0.45)
            : UIColor.systemOrange
        shaft.geometry?.firstMaterial?.diffuse.contents =
            materialColor
        // Cylinder runs +Y; rotate +Y onto the direction.
        let axis = Float3(0, 1, 0).cross(normalized)
        let axisLength = sqrt(
            axis.x * axis.x + axis.y * axis.y + axis.z * axis.z
        )
        let cosAngle = Float3(0, 1, 0).dot(normalized)
        if axisLength > 0.001 {
            let angle = acos(max(-1, min(1, cosAngle)))
            shaft.rotation = SCNVector4(
                axis.x / axisLength,
                axis.y / axisLength,
                axis.z / axisLength,
                angle
            )
        } else if cosAngle < 0 {
            shaft.rotation = SCNVector4(1, 0, 0, Float.pi)
        }
        shaft.position = SCNVector3(
            indicator.baseWorld.x
                + normalized.x * arrowLength / 2,
            indicator.baseWorld.y
                + normalized.y * arrowLength / 2,
            indicator.baseWorld.z
                + normalized.z * arrowLength / 2
        )
        return shaft
    }

    private func scnVector(_ p: Float3) -> SCNVector3 {
        SCNVector3(p.x, p.y, p.z)
    }

    private func color(
        for layer: GeometrySceneLayer
    ) -> UIColor {
        switch layer {
        case .capturedEvidence:
            return UIColor(
                red: 0.45, green: 0.55, blue: 0.65, alpha: 1
            )
        case .derivedCandidate:
            return UIColor(
                red: 0.6, green: 0.45, blue: 0.8, alpha: 1
            )
        case .semanticAuthority:
            return UIColor(
                red: 0.85, green: 0.55, blue: 0.2, alpha: 1
            )
        }
    }

    final class Coordinator: NSObject {
        var parent: GeometrySceneRepresentable
        var lastPreset: GeometryCameraPreset?
        var builtSignature = 0
        var elementLookup: [String: GeometrySceneElement] = [:]

        init(_ parent: GeometrySceneRepresentable) {
            self.parent = parent
            self.lastPreset = parent.preset
        }

        @MainActor
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else {
                return
            }
            let hits = view.hitTest(
                gesture.location(in: view),
                options: nil
            )
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name,
                       let element = elementLookup[name]
                    {
                        parent.selectedElementID =
                            element.elementID
                        return
                    }
                    node = current.parent
                }
            }
            parent.selectedElementID = nil
        }
    }
}
#endif
