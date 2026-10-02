import Foundation

/// Accepted-geometry 3D review surface (issue #408): the platform-
/// neutral scene model behind the `[Plan] [3D]` review toggle. The
/// scene composes only *accepted/persisted* sources — mesh anchor
/// snapshots, RoomPlan surfaces/objects, derived-shape candidates,
/// committed entities and measurements — and hands a renderer
/// (SceneKit on iOS) elements, layers, and camera presets.
///
/// This is a review + selection surface, deliberately not a CAD
/// tool: elements are inspectable and pickable (accepted-geometry
/// selection feeds `PostScanGeometryAuthoringSession`), never
/// editable. LOD (derived candidates) never substitutes captured
/// evidence — the mesh anchors are always present in the model.
public enum GeometrySceneLayer: String, Sendable, CaseIterable {
    /// Canonical captured geometry: mesh anchors and RoomPlan
    /// surfaces/objects — what the capture actually observed.
    case capturedEvidence = "captured_evidence"
    /// Derived shape candidates — interpreted geometry, visually
    /// secondary, never replaces captured evidence.
    case derivedCandidate = "derived_candidate"
    /// Semantic authority: committed annotation entities and their
    /// direction indicators.
    case semanticAuthority = "semantic_authority"
}

/// What an element is — the renderer styles within a layer on this
/// (mesh translucent, RoomPlan surfaces solid, entities marked).
public enum GeometrySceneElementKind: String, Sendable {
    case meshAnchor = "mesh_anchor"
    case roomPlanSurface = "roomplan_surface"
    case roomPlanObject = "roomplan_object"
    case derivedCandidate = "derived_candidate"
    case entity
    case measurement
}

/// One selectable/inspectable element of the accepted-geometry
/// scene.
public struct GeometrySceneElement:
    Sendable, Equatable, Identifiable
{
    /// Stable element id (`mesh:<uuid>`, `roomplan:<id>`,
    /// `derived:<uuid>`, `entity:<id>`, `measurement:<id>`).
    public let elementID: String
    public let layer: GeometrySceneLayer
    public let kind: GeometrySceneElementKind
    public let label: String
    public let centerWorld: Float3
    /// Axis-aligned world extents (meters) when known.
    public let extentsWorld: Float3?
    /// Object-space → world transform for surface/object/entity
    /// elements.
    public let worldFromElement: Matrix4x4F?
    /// Lineage back to the accepted source — the fields
    /// `GeometrySelection` binds.
    public let sourceMeshAnchorID: UUID?
    public let sourceRoomPlanObjectID: String?
    public let sourceDerivedCandidateID: DerivedGeometryCandidateID?
    public let sourceEntityID: AnnotationEntityID?

    public init(
        elementID: String,
        layer: GeometrySceneLayer,
        kind: GeometrySceneElementKind,
        label: String,
        centerWorld: Float3,
        extentsWorld: Float3? = nil,
        worldFromElement: Matrix4x4F? = nil,
        sourceMeshAnchorID: UUID? = nil,
        sourceRoomPlanObjectID: String? = nil,
        sourceDerivedCandidateID: DerivedGeometryCandidateID? = nil,
        sourceEntityID: AnnotationEntityID? = nil
    ) {
        self.elementID = elementID
        self.layer = layer
        self.kind = kind
        self.label = label
        self.centerWorld = centerWorld
        self.extentsWorld = extentsWorld
        self.worldFromElement = worldFromElement
        self.sourceMeshAnchorID = sourceMeshAnchorID
        self.sourceRoomPlanObjectID = sourceRoomPlanObjectID
        self.sourceDerivedCandidateID = sourceDerivedCandidateID
        self.sourceEntityID = sourceEntityID
    }

    public var id: String { elementID }

    /// Accepted-geometry sources are pickable — entity/measurement
    /// overlays are inspect-only (issue #408 §10: selection writes
    /// a `GeometrySelection` against accepted geometry only).
    public var isSelectable: Bool {
        switch kind {
        case .meshAnchor, .roomPlanSurface, .roomPlanObject,
             .derivedCandidate:
            return true
        case .entity, .measurement:
            return false
        }
    }
}

/// A direction arrow in the scene (issue #408 §12): speaker
/// orientation and measurement direction render with their full 3D
/// vector — a horizontal-only arrow is flagged so legacy data never
/// silently reads as level.
public struct DirectionalIndicator:
    Sendable, Equatable, Identifiable
{
    public let indicatorID: String
    /// World-space arrow base.
    public let baseWorld: Float3
    /// World-space unit direction, or nil when no direction exists.
    public let directionWorld: Float3?
    /// True when the direction carries a vertical component;
    /// `verticalDropped` records a legacy horizontal-only source so
    /// the renderer can mark it instead of pretending levelness.
    public let verticalDropped: Bool
    public let label: String?
    /// `entity:<id>` / `measurement:<id>` owner token.
    public let ownerToken: String

    public init(
        indicatorID: String,
        baseWorld: Float3,
        directionWorld: Float3?,
        verticalDropped: Bool,
        label: String? = nil,
        ownerToken: String
    ) {
        self.indicatorID = indicatorID
        self.baseWorld = baseWorld
        self.directionWorld = directionWorld
        self.verticalDropped = verticalDropped
        self.label = label
        self.ownerToken = ownerToken
    }

    public var id: String { indicatorID }
}

// MARK: - Camera

/// Camera presets (issue #408 §9): named views plus fit/focus.
public enum GeometryCameraPreset: Sendable, Equatable, Hashable {
    /// Free orbit at a readable diagonal angle (the default).
    case orbit
    /// Elevation view toward the room front (looking down -Z).
    case frontElevation
    /// Elevation view from the room's right side (looking down -X).
    case sideElevation
    /// Plan view straight down (matches the 2D plan's XZ space).
    case topPlan
    /// Fit every element in view.
    case fitRoom
    /// Orbit around one element.
    case focusElement(String)
}

/// Resolved camera transform (world space, capture coordinates:
/// +Y up).
public struct GeometryCameraSpec: Sendable, Equatable {
    public let positionWorld: Float3
    public let lookAtWorld: Float3
    public let upWorld: Float3
    /// Vertical field of view in degrees.
    public let fieldOfViewDegrees: Float

    public init(
        positionWorld: Float3,
        lookAtWorld: Float3,
        upWorld: Float3 = Float3(0, 1, 0),
        fieldOfViewDegrees: Float = 60
    ) {
        self.positionWorld = positionWorld
        self.lookAtWorld = lookAtWorld
        self.upWorld = upWorld
        self.fieldOfViewDegrees = fieldOfViewDegrees
    }
}

// MARK: - The scene model

/// The accepted-geometry scene for one workspace (issue #408).
/// `meshSnapshots` carry the real vertex/index data — elements only
/// hold identity + bounds so the model stays cheap and the renderer
/// decides tessellation LOD (never replacing evidence).
public struct AcceptedGeometrySceneModel: Sendable, Equatable {
    /// The coordinate space every element resolves in.
    public let coordinateSpaceID: CoordinateSpaceID?
    public let elements: [GeometrySceneElement]
    public let directionIndicators: [DirectionalIndicator]
    /// Mesh snapshots keyed by anchor id — the renderer's captured
    /// evidence payload.
    public let meshSnapshots: [UUID: MeshAnchorSnapshot]
    /// Derived candidates keyed by id — contour/points payload.
    public let derivedCandidates:
        [DerivedGeometryCandidateID: DerivedGeometryCandidateRecord]
    /// Combined scene bounds (min/max world corners); nil when empty.
    public let boundsMin: Float3?
    public let boundsMax: Float3?

    public init(
        coordinateSpaceID: CoordinateSpaceID?,
        meshSnapshots: [MeshAnchorSnapshot],
        roomPlanObjects: [RoomPlanBindableObject],
        derivedCandidates: [DerivedGeometryCandidateRecord],
        entities: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement]
    ) {
        self.coordinateSpaceID = coordinateSpaceID
        var elements: [GeometrySceneElement] = []
        var snapshotMap: [UUID: MeshAnchorSnapshot] = [:]
        var candidateMap:
            [DerivedGeometryCandidateID:
                DerivedGeometryCandidateRecord] = [:]
        var indicators: [DirectionalIndicator] = []

        var minCorner: Float3?
        var maxCorner: Float3?
        func extend(_ p: Float3) {
            guard p.isFinite else { return }
            if var lo = minCorner, var hi = maxCorner {
                lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y)
                lo.z = min(lo.z, p.z)
                hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y)
                hi.z = max(hi.z, p.z)
                minCorner = lo; maxCorner = hi
            } else {
                minCorner = p; maxCorner = p
            }
        }

        for snapshot in meshSnapshots {
            snapshotMap[snapshot.anchorID] = snapshot
            let geometry = snapshot.geometry
            var lo = Float3(
                Float.greatestFiniteMagnitude,
                Float.greatestFiniteMagnitude,
                Float.greatestFiniteMagnitude
            )
            var hi = Float3(
                -Float.greatestFiniteMagnitude,
                -Float.greatestFiniteMagnitude,
                -Float.greatestFiniteMagnitude
            )
            var hasVertex = false
            for local in geometry.vertices {
                let world = snapshot.worldFromAnchor.applying(to: local)
                guard world.isFinite else { continue }
                hasVertex = true
                lo.x = min(lo.x, world.x); lo.y = min(lo.y, world.y)
                lo.z = min(lo.z, world.z)
                hi.x = max(hi.x, world.x); hi.y = max(hi.y, world.y)
                hi.z = max(hi.z, world.z)
            }
            guard hasVertex else { continue }
            let center = Float3(
                (lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2
            )
            let extents = Float3(
                hi.x - lo.x, hi.y - lo.y, hi.z - lo.z
            )
            extend(lo); extend(hi)
            elements.append(
                GeometrySceneElement(
                    elementID: "mesh:"
                        + snapshot.anchorID.uuidString.lowercased(),
                    layer: .capturedEvidence,
                    kind: .meshAnchor,
                    label: "Mesh region",
                    centerWorld: center,
                    extentsWorld: extents,
                    worldFromElement: snapshot.worldFromAnchor,
                    sourceMeshAnchorID: snapshot.anchorID
                )
            )
        }

        for object in roomPlanObjects {
            let center = object.worldFromObject.translationWorld
            extend(center)
            elements.append(
                GeometrySceneElement(
                    elementID: "roomplan:" + object.identifier,
                    layer: .capturedEvidence,
                    kind: object.isSurface
                        ? .roomPlanSurface : .roomPlanObject,
                    label: object.category,
                    centerWorld: center,
                    extentsWorld: object.dimensionsMeters,
                    worldFromElement: object.worldFromObject,
                    sourceRoomPlanObjectID: object.identifier
                )
            )
        }

        for candidate in derivedCandidates {
            candidateMap[candidate.candidateID] = candidate
            // Contour points are plan-space (x = X, y = Z); a
            // vertical offset lets resolved shapes float where
            // evidence saw them.
            var lo = Float3(
                Float.greatestFiniteMagnitude, 0,
                Float.greatestFiniteMagnitude
            )
            var hi = Float3(
                -Float.greatestFiniteMagnitude, 0,
                -Float.greatestFiniteMagnitude
            )
            var hasPoint = false
            for point in candidate.contourPoints {
                let x = Float(point.position.x)
                let z = Float(point.position.y)
                let y = Float(point.verticalPositionMeters ?? 0)
                guard x.isFinite, y.isFinite, z.isFinite else {
                    continue
                }
                hasPoint = true
                lo.x = min(lo.x, x); lo.y = min(lo.y, y)
                lo.z = min(lo.z, z)
                hi.x = max(hi.x, x); hi.y = max(hi.y, y)
                hi.z = max(hi.z, z)
            }
            guard hasPoint else { continue }
            let center = Float3(
                (lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2
            )
            extend(lo); extend(hi)
            elements.append(
                GeometrySceneElement(
                    elementID: "derived:"
                        + candidate.candidateID.description,
                    layer: .derivedCandidate,
                    kind: .derivedCandidate,
                    label: candidate.shapeKind?.rawValue
                        ?? "candidate",
                    centerWorld: center,
                    extentsWorld: Float3(
                        hi.x - lo.x, hi.y - lo.y, hi.z - lo.z
                    ),
                    sourceDerivedCandidateID: candidate.candidateID
                )
            )
        }

        for entity in entities {
            let transform = entity.worldFromAnnotation
            let center = transform.translationWorld
            extend(center)
            elements.append(
                GeometrySceneElement(
                    elementID: "entity:"
                        + entity.entityID.description,
                    layer: .semanticAuthority,
                    kind: .entity,
                    label: entity.label,
                    centerWorld: center,
                    worldFromElement: transform,
                    sourceEntityID: entity.entityID
                )
            )
            // Direction arrows carry the real 3D vector; a
            // horizontal-only source is flagged, never silently
            // leveled (issue #408 §12).
            if let orientation = entity.orientation {
                let frontWorld = transform.applying(
                    toDirection: Float3(
                        orientation.frontAxisLocal.x,
                        orientation.frontAxisLocal.y,
                        orientation.frontAxisLocal.z
                    )
                )
                let magnitude = (
                    frontWorld.x * frontWorld.x
                        + frontWorld.y * frontWorld.y
                        + frontWorld.z * frontWorld.z
                ).squareRoot()
                if magnitude > 0.001 {
                    let unit = Float3(
                        frontWorld.x / magnitude,
                        frontWorld.y / magnitude,
                        frontWorld.z / magnitude
                    )
                    indicators.append(
                        DirectionalIndicator(
                            indicatorID: "dir:"
                                + entity.entityID.description,
                            baseWorld: center,
                            directionWorld: unit,
                            verticalDropped: abs(unit.y) < 0.02,
                            label: entity.label,
                            ownerToken: "entity:"
                                + entity.entityID.description
                        )
                    )
                }
            }
        }

        for measurement in measurements {
            // Measurements expose endpoint refs, not world points —
            // the scene lists them for inspectability at the room
            // centroid when the renderer has nothing to place.
            guard let lo = minCorner, let hi = maxCorner else {
                continue
            }
            let boundsCenter = Float3(
                (lo.x + hi.x) * 0.5,
                (lo.y + hi.y) * 0.5,
                (lo.z + hi.z) * 0.5
            )
            elements.append(
                GeometrySceneElement(
                    elementID: "measurement:"
                        + measurement.measurementID.description,
                    layer: .semanticAuthority,
                    kind: .measurement,
                    label: measurement.quantityType,
                    centerWorld: boundsCenter
                )
            )
        }

        self.elements = elements
        self.directionIndicators = indicators
        self.meshSnapshots = snapshotMap
        self.derivedCandidates = candidateMap
        self.boundsMin = minCorner
        self.boundsMax = maxCorner
    }

    /// Resolve a camera preset against the current content
    /// (issue #408 §9). Falls back to a readable default for the
    /// empty scene.
    public func cameraSpec(
        for preset: GeometryCameraPreset
    ) -> GeometryCameraSpec {
        let lo = boundsMin ?? Float3(-2, 0, -2)
        let hi = boundsMax ?? Float3(2, 2, 2)
        let center = Float3(
            (lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2
        )
        let size = Float3(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
        let diagonal = max(
            (size.x * size.x + size.y * size.y + size.z * size.z)
                .squareRoot(),
            0.5
        )
        let fitDistance = diagonal * 0.9 + 1.0
        let floorY = lo.y

        switch preset {
        case .orbit:
            return GeometryCameraSpec(
                positionWorld: Float3(
                    center.x + fitDistance * 0.65,
                    floorY + max(size.y, 1.2) + fitDistance * 0.45,
                    center.z + fitDistance * 0.65
                ),
                lookAtWorld: center
            )
        case .frontElevation:
            return GeometryCameraSpec(
                positionWorld: Float3(
                    center.x,
                    floorY + min(max(size.y * 0.6, 1.4), 3.0),
                    center.z + fitDistance
                ),
                lookAtWorld: Float3(
                    center.x, center.y, center.z - size.z / 2
                )
            )
        case .sideElevation:
            return GeometryCameraSpec(
                positionWorld: Float3(
                    center.x + fitDistance,
                    floorY + min(max(size.y * 0.6, 1.4), 3.0),
                    center.z
                ),
                lookAtWorld: Float3(
                    center.x - size.x / 2, center.y, center.z
                )
            )
        case .topPlan:
            return GeometryCameraSpec(
                positionWorld: Float3(
                    center.x, hi.y + fitDistance, center.z
                ),
                lookAtWorld: center,
                // -Z forward reads as the 2D plan's "up".
                upWorld: Float3(0, 0, -1)
            )
        case .fitRoom:
            return cameraSpec(for: .orbit)
        case .focusElement(let elementID):
            guard let element = elements.first(where: {
                $0.elementID == elementID
            }) else {
                return cameraSpec(for: .orbit)
            }
            let ext = element.extentsWorld ?? Float3(1, 1, 1)
            let radius = max(
                (ext.x * ext.x + ext.y * ext.y + ext.z * ext.z)
                    .squareRoot() * 1.6,
                0.8
            )
            let c = element.centerWorld
            return GeometryCameraSpec(
                positionWorld: Float3(
                    c.x + radius, c.y + radius * 0.7, c.z + radius
                ),
                lookAtWorld: c
            )
        }
    }
}
