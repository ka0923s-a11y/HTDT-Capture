import Foundation

/// Which placement target class produced — or would produce — a hit
/// for the current reticle position (legacy bolph71656-ai/HTDT-Capture#214/legacy bolph71656-ai/HTDT-Capture#246).
public enum PlacementProbeTarget: String, Sendable, Equatable {
    case mesh
    case roomPlanObject = "roomplan_object"
    case existingPlaneGeometry = "existing_plane_geometry"
    case estimatedPlane = "estimated_plane"
}

public enum PlacementProbeStatus: String, Sendable, Equatable {
    /// A concrete hit is under the reticle; `target`/`positionWorld`/
    /// `distanceMeters` are populated.
    case hit
    /// The placement providers answered but nothing is under the
    /// reticle within range.
    case noHit
    /// The probe could not run (no live frame, no geometry authority).
    case unavailable
}

/// Bounded description of what a center-raycast capture would hit
/// right now. The camera-first placement UI polls this so the reticle
/// always reports the exact target class and distance before the
/// operator taps Capture (legacy bolph71656-ai/HTDT-Capture#214); the capture path uses the same
/// classification for `mesh_hit_test` / `roomplan_binding` provenance
/// (legacy bolph71656-ai/HTDT-Capture#246).
public struct AnnotationPlacementProbe: Sendable, Equatable {
    public let status: PlacementProbeStatus
    public let target: PlacementProbeTarget?
    public let distanceMeters: Float?
    public let positionWorld: Float3?
    /// Mesh anchor identity when `target == .mesh`.
    public let meshAnchorID: UUID?
    /// RoomPlan object identifier when `target == .roomPlanObject`.
    public let roomPlanObjectID: String?
    /// Category label of the bound RoomPlan object for display.
    public let roomPlanObjectCategory: String?

    public init(
        status: PlacementProbeStatus,
        target: PlacementProbeTarget? = nil,
        distanceMeters: Float? = nil,
        positionWorld: Float3? = nil,
        meshAnchorID: UUID? = nil,
        roomPlanObjectID: String? = nil,
        roomPlanObjectCategory: String? = nil
    ) {
        self.status = status
        self.target = target
        self.distanceMeters = distanceMeters
        self.positionWorld = positionWorld
        self.meshAnchorID = meshAnchorID
        self.roomPlanObjectID = roomPlanObjectID
        self.roomPlanObjectCategory = roomPlanObjectCategory
    }

    public static var unavailable: AnnotationPlacementProbe {
        AnnotationPlacementProbe(status: .unavailable)
    }

    public static var noHit: AnnotationPlacementProbe {
        AnnotationPlacementProbe(status: .noHit)
    }
}

/// Which placement authority the camera-first capture should target
/// (legacy bolph71656-ai/HTDT-Capture#246). `.automatic` resolves to the most specific geometry under
/// the reticle (RoomPlan object → mesh → plane), and the resolved class
/// is always shown before Accept so a fallback is never silent.
public enum PlacementTargetPreference: String, Sendable, Equatable, CaseIterable {
    case automatic
    case mesh
    case roomPlanObject = "roomplan_object"
    case plane
}

/// A plane-raycast hit candidate: which plane class was hit and at
/// what distance.
public struct PlaneProbeHit: Sendable, Equatable {
    public let target: PlacementProbeTarget
    public let distanceMeters: Float
    public let positionWorld: Float3

    public init(
        target: PlacementProbeTarget,
        distanceMeters: Float,
        positionWorld: Float3
    ) {
        self.target = target
        self.distanceMeters = distanceMeters
        self.positionWorld = positionWorld
    }
}

/// Candidate hits collected from the platform placement providers for
/// one reticle probe. Every candidate carries its world-space hit
/// distance so resolution is deterministic.
public struct PlacementProbeCandidates: Sendable, Equatable {
    public var meshHit: MeshRaycastHit?
    public var roomPlanHit: RoomPlanObjectHit?
    public var planeHit: PlaneProbeHit?

    public init(
        meshHit: MeshRaycastHit? = nil,
        roomPlanHit: RoomPlanObjectHit? = nil,
        planeHit: PlaneProbeHit? = nil
    ) {
        self.meshHit = meshHit
        self.roomPlanHit = roomPlanHit
        self.planeHit = planeHit
    }
}

/// Resolves which target class wins for a probe/capture. Rule set
/// (versioned with the probe type, `rulesVersion` = 1):
/// - automatic: nearest candidate wins; on a tie the more specific
///   source (roomPlanObject > mesh > plane) wins;
/// - explicit preferences only consider that class — a miss never
///   silently falls through to another class.
public enum PlacementProbeResolver {
    public static let rulesVersion = 1

    public static func resolve(
        candidates: PlacementProbeCandidates,
        preference: PlacementTargetPreference
    ) -> AnnotationPlacementProbe {
        switch preference {
        case .mesh:
            return candidates.meshHit.map {
                AnnotationPlacementProbe(
                    status: .hit,
                    target: .mesh,
                    distanceMeters: $0.distanceMeters,
                    positionWorld: $0.positionWorld,
                    meshAnchorID: $0.meshAnchorID
                )
            } ?? .noHit

        case .roomPlanObject:
            return candidates.roomPlanHit.map {
                AnnotationPlacementProbe(
                    status: .hit,
                    target: .roomPlanObject,
                    distanceMeters: $0.distanceMeters,
                    positionWorld: $0.positionWorld,
                    roomPlanObjectID: $0.object.identifier,
                    roomPlanObjectCategory: $0.object.category
                )
            } ?? .noHit

        case .plane:
            return candidates.planeHit.map {
                AnnotationPlacementProbe(
                    status: .hit,
                    target: $0.target,
                    distanceMeters: $0.distanceMeters,
                    positionWorld: $0.positionWorld
                )
            } ?? .noHit

        case .automatic:
            var contenders: [AnnotationPlacementProbe] = []
            if let meshHit = candidates.meshHit {
                contenders.append(
                    AnnotationPlacementProbe(
                        status: .hit,
                        target: .mesh,
                        distanceMeters: meshHit.distanceMeters,
                        positionWorld: meshHit.positionWorld,
                        meshAnchorID: meshHit.meshAnchorID
                    )
                )
            }
            if let roomPlanHit = candidates.roomPlanHit {
                contenders.append(
                    AnnotationPlacementProbe(
                        status: .hit,
                        target: .roomPlanObject,
                        distanceMeters: roomPlanHit.distanceMeters,
                        positionWorld: roomPlanHit.positionWorld,
                        roomPlanObjectID: roomPlanHit.object.identifier,
                        roomPlanObjectCategory:
                            roomPlanHit.object.category
                    )
                )
            }
            if let planeHit = candidates.planeHit {
                contenders.append(
                    AnnotationPlacementProbe(
                        status: .hit,
                        target: planeHit.target,
                        distanceMeters: planeHit.distanceMeters,
                        positionWorld: planeHit.positionWorld
                    )
                )
            }
            guard let winner = contenders.min(by: {
                let lhs = $0.distanceMeters ?? .greatestFiniteMagnitude
                let rhs = $1.distanceMeters ?? .greatestFiniteMagnitude
                if abs(lhs - rhs) > 0.001 {
                    return lhs < rhs
                }
                return specificity(of: $0.target)
                    > specificity(of: $1.target)
            }) else {
                return .noHit
            }
            return winner
        }
    }

    private static func specificity(
        of target: PlacementProbeTarget?
    ) -> Int {
        switch target {
        case .roomPlanObject: return 3
        case .mesh: return 2
        case .existingPlaneGeometry,
             .estimatedPlane,
             .none:
            return 1
        }
    }
}
