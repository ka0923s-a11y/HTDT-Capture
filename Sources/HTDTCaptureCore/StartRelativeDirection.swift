import Foundation

/// Direction-reference convention shared by every coverage/guidance
/// surface (#343).
///
/// The scan's reference yaw is the operator's facing direction at the
/// first normally-tracking frame — an arbitrary start heading, never
/// an authoritative room "Front". All compass, coverage-map, and
/// end-review direction labels are therefore expressed relative to
/// the start direction. A confirmed room reference frame (#232) is
/// the only permitted room-relative authority, and UI may present
/// room-relative labels only where that exact reference relationship
/// exists; persisted advisories record `convention` so a reader knows
/// which frame the labels were rendered in.
public enum StartRelativeDirection {
    /// Persisted direction-reference convention identifier written
    /// into advisory summaries (`direction_reference`).
    public static let convention = "start_relative"

    /// Eight-way semantic bucket of a start-relative bearing.
    /// `ahead` is the start direction itself; `behind` is 180° from
    /// it — deliberately never "Front"/"Rear" (#343).
    public enum Octant: String, Sendable, Equatable, CaseIterable {
        case ahead
        case aheadRight = "ahead_right"
        case right
        case behindRight = "behind_right"
        case behind
        case behindLeft = "behind_left"
        case left
        case aheadLeft = "ahead_left"
    }

    /// Buckets a start-relative angle into an octant. `radians` is a
    /// wrapped angle in `[-π, π]` measured by `atan2(x, z)` in the
    /// scan's start-relative frame: 0 = ahead of start, positive =
    /// toward the right. Buckets are 45°-wide, centered on each
    /// cardinal/intercardinal.
    public static func octant(
        forRelativeAngleRadians radians: Double
    ) -> Octant {
        let wrapped = (radians
            .truncatingRemainder(dividingBy: 2 * .pi) + 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)
        let step = Int(((wrapped / (2 * .pi)) * 8).rounded()) % 8
        switch step {
        case 0: return .ahead
        case 1: return .aheadRight
        case 2: return .right
        case 3: return .behindRight
        case 4: return .behind
        case 5: return .behindLeft
        case 6: return .left
        default: return .aheadLeft
        }
    }

    /// Whole degrees clockwise from the start direction that a
    /// `sectorCount`-wide coverage sector index represents
    /// (sector 0 = start direction).
    public static func sectorOffsetDegrees(
        sectorIndex: Int,
        sectorCount: Int
    ) -> Int {
        guard sectorCount > 0 else {
            return 0
        }
        let wrapped = ((sectorIndex % sectorCount) + sectorCount)
            % sectorCount
        return wrapped * 360 / sectorCount
    }

    /// The shortest signed offset of a sector from the start
    /// direction: positive = right of start, negative = left,
    /// magnitude in whole degrees ≤ 180.
    public static func sectorSignedDegrees(
        sectorIndex: Int,
        sectorCount: Int
    ) -> Int {
        let offset = sectorOffsetDegrees(
            sectorIndex: sectorIndex,
            sectorCount: sectorCount
        )
        return offset <= 180 ? offset : offset - 360
    }
}
