import Foundation

public enum MeshAvailabilityState: String, Sendable, Equatable {
    case unavailable
    case enabledNoAnchors
    case anchorsObserved
}

public struct MeshAvailabilityDiagnostic: Sendable, Equatable {
    public let sceneReconstructionSupported: Bool
    public let sceneReconstructionEnabled: Bool
    public let activeMeshAnchorCount: Int
    public let activeConfigurationName: String?
    public let configurationMismatchSuspected: Bool

    public init(
        sceneReconstructionSupported: Bool,
        sceneReconstructionEnabled: Bool,
        activeMeshAnchorCount: Int,
        activeConfigurationName: String? = nil,
        configurationMismatchSuspected: Bool = false
    ) {
        self.sceneReconstructionSupported = sceneReconstructionSupported
        self.sceneReconstructionEnabled = sceneReconstructionEnabled
        self.activeMeshAnchorCount = max(0, activeMeshAnchorCount)
        self.activeConfigurationName = activeConfigurationName
        self.configurationMismatchSuspected = configurationMismatchSuspected
    }

    public var state: MeshAvailabilityState {
        if activeMeshAnchorCount > 0 {
            return .anchorsObserved
        }

        guard sceneReconstructionSupported,
              sceneReconstructionEnabled
        else {
            return .unavailable
        }

        return .enabledNoAnchors
    }

    public static let unavailable = MeshAvailabilityDiagnostic(
        sceneReconstructionSupported: false,
        sceneReconstructionEnabled: false,
        activeMeshAnchorCount: 0
    )
}

public struct SpatialCoveragePoint3D: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

public struct SpatialCoveragePoint2D: Sendable, Equatable {
    public let x: Double
    public let z: Double

    public init(x: Double, z: Double) {
        self.x = x
        self.z = z
    }
}

public enum SpatialCoverageDistanceBucket: String, Sendable, Equatable {
    case near
    case medium
    case far
}

public enum SpatialCoverageClassification: String, Sendable, Equatable {
    case unknown
    case weak
    case observed
}

public enum SpatialCoverageEvidenceSource: String, Sendable, Equatable {
    case none
    case mesh
    case sceneDepth = "scene_depth"
}

public struct SpatialCoverageCellKey:
    Sendable,
    Hashable,
    Comparable
{
    public let x: Int
    public let z: Int

    public init(x: Int, z: Int) {
        self.x = x
        self.z = z
    }

    public static func < (
        lhs: SpatialCoverageCellKey,
        rhs: SpatialCoverageCellKey
    ) -> Bool {
        if lhs.z != rhs.z {
            return lhs.z < rhs.z
        }
        return lhs.x < rhs.x
    }
}

public struct SpatialCoverageBounds: Sendable, Equatable {
    public let minX: Int
    public let maxX: Int
    public let minZ: Int
    public let maxZ: Int

    public init(
        minX: Int,
        maxX: Int,
        minZ: Int,
        maxZ: Int
    ) {
        precondition(minX <= maxX)
        precondition(minZ <= maxZ)
        self.minX = minX
        self.maxX = maxX
        self.minZ = minZ
        self.maxZ = maxZ
    }

    public var columnCount: Int {
        maxX - minX + 1
    }

    public var rowCount: Int {
        maxZ - minZ + 1
    }

    public var cellCount: Int {
        columnCount * rowCount
    }

    public func contains(_ key: SpatialCoverageCellKey) -> Bool {
        key.x >= minX
        && key.x <= maxX
        && key.z >= minZ
        && key.z <= maxZ
    }
}

/// Bounded diagnostics describing how the spatial coverage grid has
/// used its live region budget (#336). Eviction is never silent: the
/// counters and timestamps here are published in the live summary, the
/// end-review surface, and the persisted end-coverage advisory so a
/// saturated grid can always be distinguished from a fully observed
/// one.
public struct SpatialCoverageCapacityDiagnostics: Sendable, Equatable {
    /// The configured hard bound on retained regions.
    public let maxRegionCount: Int
    /// Largest number of regions retained at once this scan.
    public let peakRegionCount: Int
    /// Total region entries ever inserted into the bounded map,
    /// including keys later evicted. Exceeds `peakRegionCount` once the
    /// budget has evicted at least one region.
    public let regionEntryCount: Int
    /// Number of regions dropped to make room for new cells.
    public let evictionCount: Int
    /// Session timestamp of the first eviction, when any occurred.
    public let firstEvictionTimestampSeconds: Double?
    /// Session timestamp of the most recent eviction, when any
    /// occurred.
    public let lastEvictionTimestampSeconds: Double?
    /// True while the bounded map is at capacity, meaning the next new
    /// cell observation drops a retained region.
    public let isSaturated: Bool

    public init(
        maxRegionCount: Int,
        peakRegionCount: Int,
        regionEntryCount: Int,
        evictionCount: Int,
        firstEvictionTimestampSeconds: Double?,
        lastEvictionTimestampSeconds: Double?,
        isSaturated: Bool
    ) {
        self.maxRegionCount = maxRegionCount
        self.peakRegionCount = peakRegionCount
        self.regionEntryCount = regionEntryCount
        self.evictionCount = evictionCount
        self.firstEvictionTimestampSeconds =
            firstEvictionTimestampSeconds
        self.lastEvictionTimestampSeconds =
            lastEvictionTimestampSeconds
        self.isSaturated = isSaturated
    }

    public static func none(
        maxRegionCount: Int
    ) -> SpatialCoverageCapacityDiagnostics {
        SpatialCoverageCapacityDiagnostics(
            maxRegionCount: maxRegionCount,
            peakRegionCount: 0,
            regionEntryCount: 0,
            evictionCount: 0,
            firstEvictionTimestampSeconds: nil,
            lastEvictionTimestampSeconds: nil,
            isSaturated: false
        )
    }
}

public struct SpatialCoverageRegion: Sendable, Equatable {
    public let key: SpatialCoverageCellKey
    public let observationCount: Int
    public let normalTrackingObservationCount: Int
    public let limitedTrackingObservationCount: Int
    public let lastObservedTimestampSeconds: Double
    public let viewAngleBucketMask: UInt16
    public let latestDistanceBucket: SpatialCoverageDistanceBucket
    public let depthObservationCount: Int
    public let meshSupportCount: Int
    public let classification: SpatialCoverageClassification

    public var viewAngleDiversityCount: Int {
        viewAngleBucketMask.nonzeroBitCount
    }
}

public struct SpatialCoverageSample: Sendable {
    public let sessionTimestampSeconds: Double
    public let cameraPositionWorld: SpatialCoveragePoint3D
    public let cameraYawRadians: Double
    public let trackingState: TrackingQualityState
    public let hasSceneDepth: Bool
    public let meshAvailability: MeshAvailabilityDiagnostic
    public let surfaceEvidenceSource: SpatialCoverageEvidenceSource
    public let surfacePointsWorld: [SpatialCoveragePoint3D]

    public init(
        sessionTimestampSeconds: Double,
        cameraPositionWorld: SpatialCoveragePoint3D,
        cameraYawRadians: Double,
        trackingState: TrackingQualityState,
        hasSceneDepth: Bool,
        meshAvailability: MeshAvailabilityDiagnostic,
        surfaceEvidenceSource: SpatialCoverageEvidenceSource = .mesh,
        surfacePointsWorld: [SpatialCoveragePoint3D]
    ) {
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.cameraPositionWorld = cameraPositionWorld
        self.cameraYawRadians = cameraYawRadians
        self.trackingState = trackingState
        self.hasSceneDepth = hasSceneDepth
        self.meshAvailability = meshAvailability
        self.surfaceEvidenceSource = surfaceEvidenceSource
        self.surfacePointsWorld = surfacePointsWorld
    }
}

public struct SpatialScanCoverageSummary: Sendable, Equatable {
    public let cellSizeMeters: Double
    public let maxRegionCount: Int
    public let referenceOriginWorld: SpatialCoveragePoint3D?
    public let referenceYawRadians: Double?
    public let currentCameraPosition: SpatialCoveragePoint2D?
    public let currentRelativeHeadingRadians: Double?
    public let latestTrackingState: TrackingQualityState?
    public let latestHasSceneDepth: Bool
    public let meshAvailability: MeshAvailabilityDiagnostic
    public let regions: [SpatialCoverageRegion]
    public let displayBounds: SpatialCoverageBounds?
    /// Live region-budget usage (#336); never silent when the bounded
    /// grid has dropped previously observed cells.
    public let capacity: SpatialCoverageCapacityDiagnostics
    /// Bounded recency list of cell keys dropped by capacity eviction
    /// (#336). Lets consumers distinguish `unknown` cells that were
    /// never observed from cells previously observed but no longer
    /// retained inside the live budget.
    public let recentlyEvictedKeys: Set<SpatialCoverageCellKey>

    public init(
        cellSizeMeters: Double,
        maxRegionCount: Int,
        referenceOriginWorld: SpatialCoveragePoint3D?,
        referenceYawRadians: Double?,
        currentCameraPosition: SpatialCoveragePoint2D?,
        currentRelativeHeadingRadians: Double?,
        latestTrackingState: TrackingQualityState?,
        latestHasSceneDepth: Bool,
        meshAvailability: MeshAvailabilityDiagnostic,
        regions: [SpatialCoverageRegion],
        displayBounds: SpatialCoverageBounds?,
        capacity: SpatialCoverageCapacityDiagnostics? = nil,
        recentlyEvictedKeys: Set<SpatialCoverageCellKey> = []
    ) {
        self.cellSizeMeters = cellSizeMeters
        self.maxRegionCount = maxRegionCount
        self.referenceOriginWorld = referenceOriginWorld
        self.referenceYawRadians = referenceYawRadians
        self.currentCameraPosition = currentCameraPosition
        self.currentRelativeHeadingRadians = currentRelativeHeadingRadians
        self.latestTrackingState = latestTrackingState
        self.latestHasSceneDepth = latestHasSceneDepth
        self.meshAvailability = meshAvailability
        self.regions = regions
        self.displayBounds = displayBounds
        self.capacity = capacity
            ?? SpatialCoverageCapacityDiagnostics(
                maxRegionCount: maxRegionCount,
                peakRegionCount: regions.count,
                regionEntryCount: regions.count,
                evictionCount: 0,
                firstEvictionTimestampSeconds: nil,
                lastEvictionTimestampSeconds: nil,
                isSaturated: regions.count >= maxRegionCount
            )
        self.recentlyEvictedKeys = recentlyEvictedKeys
    }

    public static let empty = SpatialScanCoverageSummary(
        cellSizeMeters: 0.5,
        maxRegionCount: SpatialScanCoverageTracker
            .defaultMaxRegionCount,
        referenceOriginWorld: nil,
        referenceYawRadians: nil,
        currentCameraPosition: nil,
        currentRelativeHeadingRadians: nil,
        latestTrackingState: nil,
        latestHasSceneDepth: false,
        meshAvailability: .unavailable,
        regions: [],
        displayBounds: nil
    )

    public var observedRegionCount: Int {
        regions.filter { $0.classification == .observed }.count
    }

    public var weakRegionCount: Int {
        regions.filter { $0.classification == .weak }.count
    }

    public var knownRegionCount: Int {
        regions.count
    }

    public var usesDepthFallback: Bool {
        meshAvailability.state != .anchorsObserved
            && regions.contains { $0.depthObservationCount > 0 }
    }

    public var displayUnknownRegionCount: Int {
        guard let displayBounds else {
            return 0
        }

        let knownInDisplay = regions.reduce(into: 0) { count, region in
            if displayBounds.contains(region.key) {
                count += 1
            }
        }
        return max(0, displayBounds.cellCount - knownInDisplay)
    }

    public func classification(
        at key: SpatialCoverageCellKey
    ) -> SpatialCoverageClassification {
        regions.first(where: { $0.key == key })?.classification
            ?? .unknown
    }

    /// Whether a cell currently classified `unknown` (not retained) was
    /// previously observed and later dropped by the capacity budget
    /// (#336). A retained region is never reported evicted: the recency
    /// list drops the key the moment a fresh observation re-enters.
    public func wasRecentlyEvicted(
        at key: SpatialCoverageCellKey
    ) -> Bool {
        recentlyEvictedKeys.contains(key)
            && classification(at: key) == .unknown
    }

    public func region(
        at key: SpatialCoverageCellKey
    ) -> SpatialCoverageRegion? {
        regions.first(where: { $0.key == key })
    }
}

public struct SpatialScanCoverageTracker: Sendable {
    /// Default live region budget (#336). The legacy 256-cell budget
    /// silently forgot completed regions in an ordinary room once its
    /// 0.5 m grid covered more than ~64 m² of distinct surface cells;
    /// the default now covers a large multi-room path while staying
    /// deterministically bounded. A capture strategy/profile may still
    /// choose a different budget through the initializer.
    public static let defaultMaxRegionCount = 2048

    public let cellSizeMeters: Double
    public let maxRegionCount: Int
    public let minimumNormalObservations: Int
    public let minimumViewAngleBuckets: Int
    public let displayRadiusCells: Int

    private struct StoredRegion: Sendable {
        var observationCount = 0
        var normalTrackingObservationCount = 0
        var limitedTrackingObservationCount = 0
        var lastObservedTimestampSeconds = 0.0
        var viewAngleBucketMask: UInt16 = 0
        var latestDistanceBucket: SpatialCoverageDistanceBucket = .far
        var depthObservationCount = 0
        var meshSupportCount = 0
    }

    private var referenceOriginWorld: SpatialCoveragePoint3D?
    private var referenceYawRadians: Double?
    private var currentCameraPosition: SpatialCoveragePoint2D?
    private var currentRelativeHeadingRadians: Double?
    private var latestTrackingState: TrackingQualityState?
    private var latestHasSceneDepth = false
    private var latestMeshAvailability: MeshAvailabilityDiagnostic = .unavailable
    private var regions: [SpatialCoverageCellKey: StoredRegion] = [:]
    // #336 capacity diagnostics: bounded counters so eviction is
    // observable, and a bounded recency list of dropped keys so an
    // `unknown` cell can be distinguished from a previously observed
    // one the budget dropped. The recency list is capped at
    // `maxRegionCount` entries, so retention memory stays proportional
    // to the configured budget.
    private var peakRegionCount = 0
    private var regionEntryCount = 0
    private var evictionCount = 0
    private var firstEvictionTimestampSeconds: Double?
    private var lastEvictionTimestampSeconds: Double?
    private var recentlyEvictedKeys: [SpatialCoverageCellKey] = []
    private var recentlyEvictedKeySet: Set<SpatialCoverageCellKey> = []

    public init(
        cellSizeMeters: Double = 0.5,
        maxRegionCount: Int = Self.defaultMaxRegionCount,
        minimumNormalObservations: Int = 3,
        minimumViewAngleBuckets: Int = 2,
        displayRadiusCells: Int = 6
    ) {
        precondition(cellSizeMeters.isFinite && cellSizeMeters > 0)
        precondition(maxRegionCount > 0)
        precondition(minimumNormalObservations > 0)
        precondition(minimumViewAngleBuckets > 0)
        precondition(minimumViewAngleBuckets <= 8)
        precondition(displayRadiusCells >= 0)

        self.cellSizeMeters = cellSizeMeters
        self.maxRegionCount = maxRegionCount
        self.minimumNormalObservations = minimumNormalObservations
        self.minimumViewAngleBuckets = minimumViewAngleBuckets
        self.displayRadiusCells = displayRadiusCells
    }

    @discardableResult
    public mutating func record(
        _ sample: SpatialCoverageSample
    ) -> SpatialScanCoverageSummary {
        latestTrackingState = sample.trackingState
        latestHasSceneDepth = sample.hasSceneDepth
        latestMeshAvailability = sample.meshAvailability

        guard sample.cameraPositionWorld.isFinite,
              sample.cameraYawRadians.isFinite
        else {
            return summary()
        }

        if referenceOriginWorld == nil,
           sample.trackingState == .normal
        {
            referenceOriginWorld = sample.cameraPositionWorld
            referenceYawRadians = sample.cameraYawRadians
        }

        guard let referenceOriginWorld,
              let referenceYawRadians
        else {
            return summary()
        }

        let cameraRelative = Self.relativePoint(
            sample.cameraPositionWorld,
            origin: referenceOriginWorld,
            referenceYawRadians: referenceYawRadians
        )
        currentCameraPosition = cameraRelative
        currentRelativeHeadingRadians = Self.normalizeSignedRadians(
            sample.cameraYawRadians - referenceYawRadians
        )

        guard sample.trackingState != .unavailable else {
            return summary()
        }

        var sampleKeys: Set<SpatialCoverageCellKey> = []

        for point in sample.surfacePointsWorld where point.isFinite {
            let relative = Self.relativePoint(
                point,
                origin: referenceOriginWorld,
                referenceYawRadians: referenceYawRadians
            )
            let key = Self.cellKey(
                for: relative,
                cellSizeMeters: cellSizeMeters
            )

            guard sampleKeys.insert(key).inserted else {
                continue
            }

            if regions[key] == nil,
               regions.count >= maxRegionCount
            {
                evictLowestValueRegion(
                    atTimestampSeconds:
                        sample.sessionTimestampSeconds
                )
            }

            if regions[key] == nil {
                regionEntryCount += 1
                if recentlyEvictedKeySet.remove(key) != nil {
                    // A re-observed cell is no longer a forgotten one.
                    recentlyEvictedKeys.removeAll { $0 == key }
                }
            }

            var region = regions[key] ?? StoredRegion()
            region.observationCount += 1
            region.lastObservedTimestampSeconds =
                sample.sessionTimestampSeconds

            switch sample.surfaceEvidenceSource {
            case .mesh:
                region.meshSupportCount += 1
            case .sceneDepth:
                region.depthObservationCount += 1
            case .none:
                break
            }

            let dx = cameraRelative.x - relative.x
            let dz = cameraRelative.z - relative.z
            region.latestDistanceBucket =
                Self.distanceBucket(hypot(dx, dz))

            switch sample.trackingState {
            case .normal:
                region.normalTrackingObservationCount += 1
                let bucket = Self.viewAngleBucket(atan2(dx, dz))
                region.viewAngleBucketMask |= UInt16(1) << bucket
            case .limited:
                region.limitedTrackingObservationCount += 1
            case .unavailable:
                break
            }

            regions[key] = region
            peakRegionCount = max(peakRegionCount, regions.count)
        }

        return summary()
    }

    public func summary() -> SpatialScanCoverageSummary {
        let publicRegions = regions.map { key, stored in
            SpatialCoverageRegion(
                key: key,
                observationCount: stored.observationCount,
                normalTrackingObservationCount:
                    stored.normalTrackingObservationCount,
                limitedTrackingObservationCount:
                    stored.limitedTrackingObservationCount,
                lastObservedTimestampSeconds:
                    stored.lastObservedTimestampSeconds,
                viewAngleBucketMask: stored.viewAngleBucketMask,
                latestDistanceBucket: stored.latestDistanceBucket,
                depthObservationCount: stored.depthObservationCount,
                meshSupportCount: stored.meshSupportCount,
                classification: classification(stored)
            )
        }
        .sorted { $0.key < $1.key }

        return SpatialScanCoverageSummary(
            cellSizeMeters: cellSizeMeters,
            maxRegionCount: maxRegionCount,
            referenceOriginWorld: referenceOriginWorld,
            referenceYawRadians: referenceYawRadians,
            currentCameraPosition: currentCameraPosition,
            currentRelativeHeadingRadians: currentRelativeHeadingRadians,
            latestTrackingState: latestTrackingState,
            latestHasSceneDepth: latestHasSceneDepth,
            meshAvailability: latestMeshAvailability,
            regions: publicRegions,
            displayBounds: displayBounds(),
            capacity: SpatialCoverageCapacityDiagnostics(
                maxRegionCount: maxRegionCount,
                peakRegionCount: peakRegionCount,
                regionEntryCount: regionEntryCount,
                evictionCount: evictionCount,
                firstEvictionTimestampSeconds:
                    firstEvictionTimestampSeconds,
                lastEvictionTimestampSeconds:
                    lastEvictionTimestampSeconds,
                isSaturated: regions.count >= maxRegionCount
            ),
            recentlyEvictedKeys: recentlyEvictedKeySet
        )
    }

    private func classification(
        _ region: StoredRegion
    ) -> SpatialCoverageClassification {
        let angleDiversity = region.viewAngleBucketMask.nonzeroBitCount

        // Each recorded observation contributes to exactly one modality
        // counter (mesh anchors or discrete scene depth). Both modalities
        // are acceptable geometric evidence for this advisory
        // classification, so promotion counts valid observation
        // occasions across a source transition rather than discarding the
        // earlier modality's evidence. The per-modality counters remain
        // stored/emitted separately for diagnostics.
        let geometricSupportCount =
            region.meshSupportCount
            + region.depthObservationCount

        if region.normalTrackingObservationCount
                >= minimumNormalObservations,
           angleDiversity >= minimumViewAngleBuckets,
           geometricSupportCount >= minimumNormalObservations
        {
            return .observed
        }

        if region.observationCount > 0 || region.meshSupportCount > 0 {
            return .weak
        }

        return .unknown
    }

    private func displayBounds() -> SpatialCoverageBounds? {
        let center: SpatialCoverageCellKey

        if let currentCameraPosition {
            center = Self.cellKey(
                for: currentCameraPosition,
                cellSizeMeters: cellSizeMeters
            )
        } else if let first = regions.keys.sorted().first {
            center = first
        } else {
            return nil
        }

        return SpatialCoverageBounds(
            minX: center.x - displayRadiusCells,
            maxX: center.x + displayRadiusCells,
            minZ: center.z - displayRadiusCells,
            maxZ: center.z + displayRadiusCells
        )
    }

    /// Capacity eviction (#336) is value-aware and recorded: low-
    /// information regions (weak/transient) are dropped before a
    /// high-confidence `observed` region, and only among the same tier
    /// does the stalest last-observation lose. The dropped key joins a
    /// bounded recency list so consumers can distinguish it from a
    /// never-observed `unknown` cell.
    private mutating func evictLowestValueRegion(
        atTimestampSeconds timestamp: Double
    ) {
        func evictionTier(
            _ region: StoredRegion
        ) -> Int {
            switch classification(region) {
            case .observed:
                return 1
            case .weak, .unknown:
                return 0
            }
        }

        guard let candidate = regions.min(by: { lhs, rhs in
            let lhsTier = evictionTier(lhs.value)
            let rhsTier = evictionTier(rhs.value)
            if lhsTier != rhsTier {
                return lhsTier < rhsTier
            }
            if lhs.value.lastObservedTimestampSeconds
                != rhs.value.lastObservedTimestampSeconds
            {
                return lhs.value.lastObservedTimestampSeconds
                    < rhs.value.lastObservedTimestampSeconds
            }
            return lhs.key < rhs.key
        }) else {
            return
        }

        regions.removeValue(forKey: candidate.key)
        evictionCount += 1
        if firstEvictionTimestampSeconds == nil {
            firstEvictionTimestampSeconds = timestamp
        }
        lastEvictionTimestampSeconds = timestamp

        if !recentlyEvictedKeySet.insert(candidate.key).inserted {
            recentlyEvictedKeys.removeAll { $0 == candidate.key }
        }
        recentlyEvictedKeys.append(candidate.key)
        if recentlyEvictedKeys.count > maxRegionCount {
            let stale = recentlyEvictedKeys.removeFirst()
            recentlyEvictedKeySet.remove(stale)
        }
    }

    private static func relativePoint(
        _ point: SpatialCoveragePoint3D,
        origin: SpatialCoveragePoint3D,
        referenceYawRadians: Double
    ) -> SpatialCoveragePoint2D {
        let dx = point.x - origin.x
        let dz = point.z - origin.z
        let cosine = cos(referenceYawRadians)
        let sine = sin(referenceYawRadians)

        return SpatialCoveragePoint2D(
            x: dx * cosine + dz * sine,
            z: dx * sine - dz * cosine
        )
    }

    private static func cellKey(
        for point: SpatialCoveragePoint2D,
        cellSizeMeters: Double
    ) -> SpatialCoverageCellKey {
        SpatialCoverageCellKey(
            x: Int(floor(point.x / cellSizeMeters)),
            z: Int(floor(point.z / cellSizeMeters))
        )
    }

    private static func viewAngleBucket(_ radians: Double) -> Int {
        let normalized = normalizePositiveRadians(
            radians + Double.pi / 8
        )
        return Int(
            floor(normalized / (Double.pi / 4))
        ) % 8
    }

    private static func distanceBucket(
        _ meters: Double
    ) -> SpatialCoverageDistanceBucket {
        if meters < 1.5 {
            return .near
        }
        if meters < 3.5 {
            return .medium
        }
        return .far
    }

    private static func normalizeSignedRadians(
        _ value: Double
    ) -> Double {
        let fullTurn = 2 * Double.pi
        var normalized = value.truncatingRemainder(
            dividingBy: fullTurn
        )
        if normalized <= -Double.pi {
            normalized += fullTurn
        } else if normalized > Double.pi {
            normalized -= fullTurn
        }
        return normalized
    }

    private static func normalizePositiveRadians(
        _ value: Double
    ) -> Double {
        let fullTurn = 2 * Double.pi
        let remainder = value.truncatingRemainder(
            dividingBy: fullTurn
        )
        return remainder >= 0
            ? remainder
            : remainder + fullTurn
    }
}

public actor SpatialScanCoverageAggregator {
    private var tracker: SpatialScanCoverageTracker

    public init(
        tracker: SpatialScanCoverageTracker =
            SpatialScanCoverageTracker()
    ) {
        self.tracker = tracker
    }

    public func record(
        _ sample: SpatialCoverageSample
    ) -> SpatialScanCoverageSummary {
        tracker.record(sample)
    }

    public func summary() -> SpatialScanCoverageSummary {
        tracker.summary()
    }

    public func reset(
        tracker: SpatialScanCoverageTracker =
            SpatialScanCoverageTracker()
    ) -> SpatialScanCoverageSummary {
        self.tracker = tracker
        return tracker.summary()
    }
}
