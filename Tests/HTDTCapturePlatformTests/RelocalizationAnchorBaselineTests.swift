import Foundation
import Testing
@testable import HTDTCapturePlatform

/// World-origin-reset detection across relocalization: the
/// discontinuity chain only attests `broken` when anchor-identity
/// evidence proves the origin was rebuilt — preserved relocalizations
/// and anchor-less losses never claim it.
struct RelocalizationAnchorBaselineTests {

    @Test
    func preservedRelocalizationDoesNotFire() {
        var tracker = RelocalizationAnchorBaseline()
        let anchors: Set<UUID> = [UUID(), UUID(), UUID()]
        tracker.didUpdateFrame(
            trackingNormal: true,
            anchorIdentifiers: anchors
        )
        tracker.trackingBecameRelocalizing()
        // Recovery keeps one pre-loss anchor — preserved world.
        let fired = tracker.trackingBecameNormal(
            currentAnchorIdentifiers: [anchors.first!]
        )
        #expect(!fired)
    }

    @Test
    func disjointAnchorSetFiresOnce() {
        var tracker = RelocalizationAnchorBaseline()
        tracker.didUpdateFrame(
            trackingNormal: true,
            anchorIdentifiers: [UUID(), UUID()]
        )
        tracker.trackingBecameRelocalizing()
        let fired = tracker.trackingBecameNormal(
            currentAnchorIdentifiers: [UUID(), UUID()]
        )
        #expect(fired)
        // The decision is made once — a second `.normal` does not
        // re-fire even though the new world is still disjoint.
        let refired = tracker.trackingBecameNormal(
            currentAnchorIdentifiers: [UUID()]
        )
        #expect(!refired)
    }

    @Test
    func emptyPrelossSetNeverFires() {
        var tracker = RelocalizationAnchorBaseline()
        // Tracking was normal but carried no anchors — a reset can
        // never be proven from an empty set.
        tracker.didUpdateFrame(
            trackingNormal: true,
            anchorIdentifiers: []
        )
        tracker.trackingBecameRelocalizing()
        #expect(tracker.baseline == nil)
        let fired = tracker.trackingBecameNormal(
            currentAnchorIdentifiers: [UUID()]
        )
        #expect(!fired)
    }

    @Test
    func relocalizingArmsOncePerLossWindow() {
        var tracker = RelocalizationAnchorBaseline()
        let first: Set<UUID> = [UUID(), UUID()]
        tracker.didUpdateFrame(
            trackingNormal: true,
            anchorIdentifiers: first
        )
        tracker.trackingBecameRelocalizing()
        #expect(tracker.baseline == first)
        // A second `.relocalizing` without an intervening `.normal`
        // must not re-arm onto newer anchors — the baseline is the
        // world being recovered into.
        tracker.didUpdateFrame(
            trackingNormal: false,
            anchorIdentifiers: [UUID()]
        )
        tracker.trackingBecameRelocalizing()
        #expect(tracker.baseline == first)
    }

    @Test
    func nonNormalFramesDoNotRefreshBaseline() {
        var tracker = RelocalizationAnchorBaseline()
        let good: Set<UUID> = [UUID(), UUID()]
        tracker.didUpdateFrame(
            trackingNormal: true,
            anchorIdentifiers: good
        )
        // Frames while tracking is limited keep the last normal set.
        tracker.didUpdateFrame(
            trackingNormal: false,
            anchorIdentifiers: [UUID()]
        )
        tracker.trackingBecameRelocalizing()
        #expect(tracker.baseline == good)
    }

    @Test
    func normalWithoutPriorRelocalizingDoesNotFire() {
        var tracker = RelocalizationAnchorBaseline()
        tracker.didUpdateFrame(
            trackingNormal: true,
            anchorIdentifiers: [UUID()]
        )
        // `.normal` with no armed baseline reports nothing.
        let fired = tracker.trackingBecameNormal(
            currentAnchorIdentifiers: [UUID()]
        )
        #expect(!fired)
    }
}
