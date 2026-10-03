import Foundation

/// World-origin-reset detector: tracks anchor identifiers across a
/// relocalization window. A relocalization that preserves the world
/// keeps at least one pre-loss anchor; a completely fresh identifier
/// set after recovery is proof the origin was rebuilt — every anchor
/// the pre-loss world named is gone. The baseline arms only on a
/// non-empty pre-loss set (absent anchors can never prove a reset),
/// so it never claims a discontinuity without evidence.
///
/// Pure state machine — platform types stay behind the bridge so the
/// detection contract is testable without an ARSession.
struct RelocalizationAnchorBaseline {
    /// Anchor identifiers from the most recent normal-tracking frame.
    private(set) var lastNormalAnchorIdentifiers: Set<UUID>?
    /// Frozen pre-loss set while `.relocalizing` is in flight.
    private(set) var baseline: Set<UUID>?

    /// Called on every frame: refreshes the pre-loss set only while
    /// tracking is normal.
    mutating func didUpdateFrame(
        trackingNormal: Bool,
        anchorIdentifiers: Set<UUID>
    ) {
        if trackingNormal {
            lastNormalAnchorIdentifiers = anchorIdentifiers
        }
    }

    /// Called when the camera reports `.relocalizing`: freezes the
    /// pre-loss set once — a later `.relocalizing` without an
    /// intervening `.normal` keeps the original baseline.
    mutating func trackingBecameRelocalizing() {
        guard baseline == nil,
              let b = lastNormalAnchorIdentifiers,
              !b.isEmpty
        else {
            return
        }
        baseline = b
    }

    /// Called when the camera reports `.normal`. Returns true exactly
    /// when a baseline existed and is disjoint from the post-recovery
    /// set — the world-origin-reset signature. The baseline always
    /// clears: whether preserved or reset, the recovery decision is
    /// made once.
    mutating func trackingBecameNormal(
        currentAnchorIdentifiers: Set<UUID>
    ) -> Bool {
        guard let b = baseline else {
            return false
        }
        baseline = nil
        return b.isDisjoint(with: currentAnchorIdentifiers)
    }
}
