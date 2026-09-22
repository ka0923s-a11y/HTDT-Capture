import Foundation
import HTDTCaptureCore
import simd

#if os(iOS) && canImport(RoomPlan)
import RoomPlan

/// Derives the review-workspace projections from the committed
/// processed RoomPlan payload (`roomplan/captured-room.json`):
/// door/window/opening candidates for the opening review (#231) and a
/// platform-independent top-down plan model for the visual review
/// workspace (#213). Everything here is a pure derivation over already
/// committed bytes — nothing mutates capture authority.
/// RoomPlan exposes openings/surfaces and objects as unrelated structs;
/// the deriver only needs their spatial identity, so both conform to
/// this local shape.
private protocol RoomPlanPlanItem {
    var transform: simd_float4x4 { get }
    var dimensions: simd_float3 { get }
    var identifier: UUID { get }
}

@available(iOS 17.0, *)
extension CapturedRoom.Surface: RoomPlanPlanItem {}

@available(iOS 17.0, *)
extension CapturedRoom.Object: RoomPlanPlanItem {}

@available(iOS 17.0, *)
public enum RoomPlanReviewDeriver {
    public enum DeriverError: Error, Sendable, Equatable {
        case undecodableRoomPayload
    }

    private static func decodeRoom(
        _ processedPayload: Data
    ) throws -> CapturedRoom {
        guard let room = try? JSONDecoder().decode(
            CapturedRoom.self,
            from: processedPayload
        ) else {
            throw DeriverError.undecodableRoomPayload
        }
        return room
    }

    /// Enumerates the openings RoomPlan inferred as review candidates
    /// (issue #231). `source_ref` joins each candidate back to the
    /// originating RoomPlan object identity, so repeated enumeration is
    /// stable and merging preserves operator dispositions.
    public static func enumerateOpenings(
        processedPayload: Data
    ) throws -> [RoomOpeningCandidate] {
        let room = try decodeRoom(processedPayload)

        func candidates<O: RoomPlanPlanItem>(
            _ objects: [O],
            kind: RoomOpeningKind,
            sourceToken: String
        ) -> [RoomOpeningCandidate] {
            objects.compactMap { object in
                let translation = object.transform.columns.3
                let center = WorldPoint3D(
                    x: Double(translation.x),
                    y: Double(translation.y),
                    z: Double(translation.z)
                )
                return try? RoomOpeningCandidate(
                    kind: kind,
                    source: .roomplanInference,
                    sourceRef:
                        "roomplan:"
                        + sourceToken
                        + ":"
                        + object.identifier
                            .uuidString.lowercased(),
                    centerMeters: center,
                    widthMeters: Double(object.dimensions.x),
                    heightMeters: Double(object.dimensions.y)
                )
            }
        }

        var enumerated: [RoomOpeningCandidate] = []
        enumerated.append(
            contentsOf: candidates(room.doors, kind: .door, sourceToken: "door")
        )
        enumerated.append(
            contentsOf: candidates(
                room.windows,
                kind: .window,
                sourceToken: "window"
            )
        )
        enumerated.append(
            contentsOf: candidates(
                room.openings,
                kind: .opening,
                sourceToken: "opening"
            )
        )
        return enumerated
    }

    /// The elevation (capture-space Y, meters) of the largest
    /// detected floor surface in the processed payload, or nil when
    /// no floor exists (issue #232 field datum). This is the only
    /// ground-truth floor level a RoomPlan payload carries.
    public static func finishedFloorElevationMeters(
        processedPayload: Data
    ) -> Double? {
        guard let room = try? decodeRoom(processedPayload),
              !room.floors.isEmpty
        else {
            return nil
        }
        let largest = room.floors.max { lhs, rhs in
            lhs.dimensions.x * lhs.dimensions.z
                < rhs.dimensions.x * rhs.dimensions.z
        }
        guard let floor = largest else { return nil }
        return Double(floor.transform.columns.3.y)
    }

    /// Builds the top-down plan model (issue #213): walls as segments,
    /// openings and objects as markers, all projected onto the XZ
    /// floor plane in the capture's bound coordinate space.
    public static func planPreview(
        processedPayload: Data
    ) throws -> RoomPlanPreviewModel {
        let room = try decodeRoom(processedPayload)

        var walls: [RoomPlanPreviewModel.PlanWall] = []
        var markers: [RoomPlanPreviewModel.PlanMarker] = []
        var minX = Double.infinity
        var maxX = -Double.infinity
        var minZ = Double.infinity
        var maxZ = -Double.infinity

        func extend(x: Double, z: Double) {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minZ = min(minZ, z)
            maxZ = max(maxZ, z)
        }

        /// A surface's local +X axis in world space, projected on XZ.
        func planSegment(
            transform: simd_float4x4,
            width: Float
        ) -> RoomPlanPreviewModel.PlanWall {
            let c = transform.columns
            let cx = Double(c.3.x)
            let cz = Double(c.3.z)
            var dx = Double(c.0.x)
            var dz = Double(c.0.z)
            let len = max(hypot(dx, dz), 1e-6)
            dx /= len
            dz /= len
            let half = Double(width) / 2
            let wall = RoomPlanPreviewModel.PlanWall(
                startX: cx - dx * half,
                startZ: cz - dz * half,
                endX: cx + dx * half,
                endZ: cz + dz * half
            )
            extend(x: wall.startX, z: wall.startZ)
            extend(x: wall.endX, z: wall.endZ)
            return wall
        }

        for wall in room.walls {
            walls.append(
                planSegment(
                    transform: wall.transform,
                    width: wall.dimensions.x
                )
            )
        }

        func addMarkers<O: RoomPlanPlanItem>(
            _ objects: [O],
            kind: RoomPlanPreviewModel.PlanMarker.Kind,
            label: (O) -> String?
        ) {
            for object in objects {
                let c = object.transform.columns
                let x = Double(c.3.x)
                let z = Double(c.3.z)
                extend(x: x, z: z)
                markers.append(
                    RoomPlanPreviewModel.PlanMarker(
                        kind: kind,
                        x: x,
                        z: z,
                        dirX: Double(c.0.x),
                        dirZ: Double(c.0.z),
                        label: label(object)
                    )
                )
            }
        }

        addMarkers(room.doors, kind: .door) { _ in "door" }
        addMarkers(room.windows, kind: .window) { _ in "window" }
        addMarkers(room.openings, kind: .opening) { _ in "opening" }
        addMarkers(room.objects, kind: .object) {
            String(describing: $0.category)
        }

        guard minX.isFinite else {
            return RoomPlanPreviewModel(
                minX: 0, maxX: 0, minZ: 0, maxZ: 0,
                walls: [], markers: []
            )
        }
        return RoomPlanPreviewModel(
            minX: minX,
            maxX: maxX,
            minZ: minZ,
            maxZ: maxZ,
            walls: walls,
            markers: markers
        )
    }
}
#endif
