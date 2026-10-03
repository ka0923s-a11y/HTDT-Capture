import Foundation

/// Plan-space overlay for the as-built verification surface
/// (issue bolph71656-ai/HTDT-Capture#293): planned HTDT targets rendered as ghost/reference
/// markers projected through the installed alignment authority,
/// observed actuals, and planned→actual deviation connectors.
///
/// The overlay exists only while an explicit alignment authority is
/// installed — without it there is no defensible way to place planned
/// coordinates in capture space, so the surface degrades to the
/// non-spatial checklist instead of guessing. Planned geometry stays
/// design authority; nothing here promotes it to observed truth.
public enum AsBuiltPlanOverlay {

    /// Review status a ghost marker carries from the item's
    /// verification state — the glyph stays the planned-target shape;
    /// the badge carries the verdict.
    public static func markerStatus(
        for state: AsBuiltItemState
    ) -> PlanMarkerReviewStatus {
        switch state {
        case .pending:
            return .pending
        case .verified:
            return .confirmed
        case .deviated, .indeterminate:
            return .needsAttention
        case .captured:
            return .nominal
        case .unavailable:
            return .intentionallySkipped
        }
    }

    /// Builds the plan model for the ghost overlay, or nil when no
    /// explicit alignment authority is installed (or the authority's
    /// transform cannot be inverted — a corrupt authority never
    /// produces a plausible-looking overlay).
    public static func model(
        items: [AsBuiltVerificationItem],
        alignment: PlanAlignmentAuthority?
    ) -> RoomPlanPreviewModel? {
        guard let alignment,
              let worldFromScene =
                try? alignment.sceneFromCapture.invertedRigid()
        else {
            return nil
        }

        var markers: [RoomPlanPreviewModel.PlanMarker] = []
        var connectors: [RoomPlanPreviewModel.PlanConnector] = []
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude

        func include(x: Double, z: Double) {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minZ = min(minZ, z)
            maxZ = max(maxZ, z)
        }

        for item in items {
            let spec = item.spec
            let plannedWorld = worldFromScene.applying(
                to: Float3(
                    spec.positionScene.x,
                    spec.positionScene.y,
                    spec.positionScene.z
                )
            )
            guard plannedWorld.isFinite else { continue }
            let px = Double(plannedWorld.x)
            let pz = Double(plannedWorld.z)
            include(x: px, z: pz)

            var dirX: Double? = nil
            var dirZ: Double? = nil
            if let orientation = spec.orientationScene {
                let front = worldFromScene.applying(
                    toDirection: Float3(
                        orientation.frontAxisLocal.x,
                        orientation.frontAxisLocal.y,
                        orientation.frontAxisLocal.z
                    )
                )
                let length = sqrt(
                    Double(front.x * front.x + front.z * front.z)
                )
                if length > 0.001 {
                    dirX = Double(front.x) / length
                    dirZ = Double(front.z) / length
                }
            }

            let status = markerStatus(for: item.state)
            markers.append(
                .init(
                    kind: .plannedTarget,
                    x: px,
                    z: pz,
                    dirX: dirX,
                    dirZ: dirZ,
                    label: spec.label ?? spec.plannedEntityID,
                    identifier:
                        "asbuilt:planned:\(spec.plannedEntityID)",
                    linkedItemID: spec.plannedEntityID,
                    selectable: true,
                    reviewStatus: status
                )
            )

            guard let observation = item.observation else { continue }
            let actual = observation.positionWorld
            let ax = Double(actual.x)
            let az = Double(actual.z)
            include(x: ax, z: az)

            var actualDirX: Double? = nil
            var actualDirZ: Double? = nil
            if let orientation = observation.orientationWorld {
                // `orientationWorld` axes are already expressed in the
                // capture world frame — the front component projects
                // straight onto the plan.
                let fx = orientation.frontAxisLocal.x
                let fz = orientation.frontAxisLocal.z
                let length = sqrt(Double(fx * fx + fz * fz))
                if length > 0.001 {
                    actualDirX = Double(fx) / length
                    actualDirZ = Double(fz) / length
                }
            }
            markers.append(
                .init(
                    kind: ReviewPlanPresentation.markerKind(
                        for: spec.entityType
                    ),
                    x: ax,
                    z: az,
                    dirX: actualDirX,
                    dirZ: actualDirZ,
                    label: spec.label ?? spec.plannedEntityID,
                    identifier:
                        "asbuilt:actual:\(spec.plannedEntityID)",
                    linkedItemID: spec.plannedEntityID,
                    selectable: true,
                    reviewStatus: .nominal
                )
            )
            connectors.append(
                .init(
                    startX: px,
                    startZ: pz,
                    endX: ax,
                    endZ: az,
                    status: status
                )
            )
        }

        guard !markers.isEmpty else { return nil }
        // Pad so edge markers are not clipped; keep a minimum span so
        // a single target still produces a usable map.
        let pad = max((maxX - minX) * 0.08, (maxZ - minZ) * 0.08, 0.5)
        return RoomPlanPreviewModel(
            minX: minX - pad,
            maxX: maxX + pad,
            minZ: minZ - pad,
            maxZ: maxZ + pad,
            walls: [],
            markers: markers,
            connectors: connectors
        )
    }
}
