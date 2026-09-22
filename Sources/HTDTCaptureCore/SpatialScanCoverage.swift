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

    /// Buckets a camera-relative distance in meters: <1.5 m near,
    /// <3.5 m medium, otherwise far. Shared by the tracker and the
    /// accessibility summary so a spoken label names the same bucket
    /// the map does.
    public static func bucket(
        forMeters meters: Double
    ) -> SpatialCoverageDistanceBucket {
        if meters < 1.5 {
            return .near
        }
        if meters < 3.5 {
            return .medium
        }
        return .far
    }
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
    /// Azimuth-only view-angle diversity (#329): bits index the 8
    /// horizontal view sectors the cell was observed from. The vertical
    /// camera-height axis is tracked separately in
    /// `elevationBucketMask` and in the vertical voxel layer — a
    /// horizontal orbit alone can never claim 3D diversity.
    public let viewAngleBucketMask: UInt16
    /// Vertical viewpoint diversity observed for this cell: bits index
    /// `SpatialCoverageElevationBucket` (camera below / level / above
    /// the observed points). Additive to `viewAngleBucketMask`; both are
    /// set only for normal-tracking observations.
    public let elevationBucketMask: UInt8
    public let latestDistanceBucket: SpatialCoverageDistanceBucket
    public let depthObservationCount: Int
    public let meshSupportCount: Int
    public let classification: SpatialCoverageClassification

    public var viewAngleDiversityCount: Int {
        viewAngleBucketMask.nonzeroBitCount
    }

    /// Number of distinct vertical viewpoint bands observed (1-3).
    public var elevationDiversityCount: Int {
        elevationBucketMask.nonzeroBitCount
    }
}

/// Vertical viewpoint of the camera relative to an observed surface
/// point (issue #329): whether the camera looked up at, across at, or
/// down at the point. Combined with the 8 azimuth buckets it yields the
/// 3D viewpoint-diversity mask used by the voxel layer.
public enum SpatialCoverageElevationBucket: Int, Sendable, Equatable {
    /// The camera was materially below the point (e.g. ceiling).
    case cameraBelow = 0
    /// The point was near camera height.
    case level = 1
    /// The camera was materially above the point (e.g. floor).
    case cameraAbove = 2
}

/// Key of one bounded 3D coverage voxel (issue #329): the same
/// start-relative X/Z cell grid as the 2D layer plus a coarse
/// start-relative vertical band, so floor-level and ceiling-level
/// evidence at the same X/Z never share a single classification.
public struct SpatialCoverageVoxelKey:
    Sendable,
    Hashable,
    Comparable
{
    public let x: Int
    public let z: Int
    /// `floor((point.y - referenceOrigin.y) / verticalCellSizeMeters)`.
    public let yBand: Int

    public init(x: Int, z: Int, yBand: Int) {
        self.x = x
        self.z = z
        self.yBand = yBand
    }

    public static func < (
        lhs: SpatialCoverageVoxelKey,
        rhs: SpatialCoverageVoxelKey
    ) -> Bool {
        if lhs.z != rhs.z {
            return lhs.z < rhs.z
        }
        if lhs.x != rhs.x {
            return lhs.x < rhs.x
        }
        return lhs.yBand < rhs.yBand
    }
}

/// One bounded 3D coverage voxel (issue #329). `viewpointBucketMask3D`
/// is azimuth*elevation diverse (8 x 3 bins), so a horizontal orbit
/// alone accumulates azimuth diversity without elevation diversity.
public struct SpatialCoverageVoxel: Sendable, Equatable {
    public let key: SpatialCoverageVoxelKey
    public let observationCount: Int
    public let normalTrackingObservationCount: Int
    public let limitedTrackingObservationCount: Int
    public let lastObservedTimestampSeconds: Double
    /// 24-bin viewpoint mask: bit index = azimuthBucket * 3 +
    /// elevationBucket. Three azimuth groups at one elevation still
    /// count as only one vertical viewpoint.
    public let viewpointBucketMask3D: UInt32
    public let latestDistanceBucket: SpatialCoverageDistanceBucket
    public let depthObservationCount: Int
    public let meshSupportCount: Int
    public let classification: SpatialCoverageClassification
    /// True when at least one observation saw this voxel materially
    /// above or below the camera — i.e. the voxel is height-offset, so
    /// `observed` additionally requires elevation diversity.
    public let elevationSensitive: Bool

    /// Distinct horizontal view sectors observed (1-8).
    public var azimuthDiversityCount: Int {
        var count = 0
        for azimuth in 0 ..< 8
        where (viewpointBucketMask3D >> (azimuth * 3)) & 0b111 != 0 {
            count += 1
        }
        return count
    }

    /// Distinct elevation buckets observed (1-3), counted across all
    /// azimuth groups — bit index is `azimuthBucket * 3 +
    /// elevationBucket`, so each elevation bucket's column mask is the
    /// 8-azimuth pattern `0x00249249` shifted by its bucket index.
    public var elevationDiversityCount: Int {
        var count = 0
        for elevation in 0 ..< 3 {
            if viewpointBucketMask3D
                & (UInt32(0x0024_9249) << elevation) != 0
            {
                count += 1
            }
        }
        return count
    }
}

/// Display-level vertical bands (issue #329). Bands partition the
/// observed start-relative vertical extent into five fixed strata so a
/// cell can carry an upper-band gap independently of its floor-level
/// coverage. Band boundaries are derived from the observed y-band
/// range, not from a hard-coded device or room height.
public enum SpatialVerticalDisplayBand: String, Sendable, Equatable, CaseIterable {
    case lowest
    case lower
    case middle
    case upper
    case highest
}

/// Per-band voxel statistics over the whole observed region set.
public struct SpatialVerticalBandSummary: Sendable, Equatable {
    public let band: SpatialVerticalDisplayBand
    public let voxelCount: Int
    public let observedCount: Int
    public let weakCount: Int

    public init(
        band: SpatialVerticalDisplayBand,
        voxelCount: Int,
        observedCount: Int,
        weakCount: Int
    ) {
        self.band = band
        self.voxelCount = voxelCount
        self.observedCount = observedCount
        self.weakCount = weakCount
    }
}

/// Summary of the additive bounded 3D coverage layer (issue #329).
/// Voxels share the 2D layer's start-relative X/Z grid; the y-band axis
/// is quantized relative to the scan-start camera height. Bounded to
/// `maxVoxelCount` by the tracker's own oldest-first eviction —
/// independent of the 2D `maxRegionCount`/`evictOldestRegion` policy
/// so in-flight coverage-budget work (#336) stays orthogonal.
public struct SpatialVerticalCoverageSummary: Sendable, Equatable {
    public let verticalCellSizeMeters: Double
    public let maxVoxelCount: Int
    /// Observed y-band extent, lowest through highest populated band.
    public let observedYBandMin: Int?
    public let observedYBandMax: Int?
    public let voxels: [SpatialCoverageVoxel]
    public let displayBands: [SpatialVerticalBandSummary]

    public init(
        verticalCellSizeMeters: Double,
        maxVoxelCount: Int,
        observedYBandMin: Int?,
        observedYBandMax: Int?,
        voxels: [SpatialCoverageVoxel],
        displayBands: [SpatialVerticalBandSummary]
    ) {
        self.verticalCellSizeMeters = verticalCellSizeMeters
        self.maxVoxelCount = maxVoxelCount
        self.observedYBandMin = observedYBandMin
        self.observedYBandMax = observedYBandMax
        self.voxels = voxels
        self.displayBands = displayBands
    }

    public static let empty = SpatialVerticalCoverageSummary(
        verticalCellSizeMeters: 0.6,
        maxVoxelCount: 0,
        observedYBandMin: nil,
        observedYBandMax: nil,
        voxels: [],
        displayBands: []
    )

    public var voxelCount: Int {
        voxels.count
    }

    public var observedVoxelCount: Int {
        voxels.filter { $0.classification == .observed }.count
    }

    public var weakVoxelCount: Int {
        voxels.filter { $0.classification == .weak }.count
    }

    public func voxel(
        at key: SpatialCoverageVoxelKey
    ) -> SpatialCoverageVoxel? {
        voxels.first(where: { $0.key == key })
    }

    /// Maps a voxel y-band onto its display stratum, or nil when no
    /// voxels have been observed yet.
    public func displayBand(
        forYBand yBand: Int
    ) -> SpatialVerticalDisplayBand? {
        guard let observedYBandMin, let observedYBandMax else {
            return nil
        }
        let span = observedYBandMax - observedYBandMin + 1
        guard span > 0 else { return nil }
        let bandCount = SpatialVerticalDisplayBand.allCases.count
        let offset = yBand - observedYBandMin
        let index = min(
            bandCount - 1,
            max(0, offset * bandCount / span)
        )
        return SpatialVerticalDisplayBand.allCases[index]
    }

    /// The weakest classification of a cell's voxels inside one display
    /// band: unknown when the band has no voxels at that X/Z, weak when
    /// any voxel is weak, observed only when every populated voxel
    /// there is observed.
    public func bandClassification(
        _ band: SpatialVerticalDisplayBand,
        at cellKey: SpatialCoverageCellKey
    ) -> SpatialCoverageClassification {
        var sawWeak = false
        var sawAny = false
        for voxel in voxels
        where voxel.key.x == cellKey.x
            && voxel.key.z == cellKey.z
        {
            guard displayBand(forYBand: voxel.key.yBand) == band
            else {
                continue
            }
            sawAny = true
            if voxel.classification != .observed {
                sawWeak = true
            }
        }
        if !sawAny {
            return .unknown
        }
        return sawWeak ? .weak : .observed
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
    /// Additive 3D-aware layer (issue #329): a bounded voxel map on the
    /// same start-relative X/Z grid plus a coarse vertical band, so a
    /// cell's `observed` floor-level classification can no longer hide
    /// an unobserved ceiling at the same X/Z.
    public let vertical: SpatialVerticalCoverageSummary
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
        vertical: SpatialVerticalCoverageSummary = .empty,
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
        self.vertical = vertical
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

    /// The start-relative coverage cell containing a world-space point,
    /// or nil before the reference pose exists. Vertical position does
    /// not affect the returned key — use `voxelKey(forWorldPoint:)` for
    /// the 3D layer.
    public func cellKey(
        forWorldPoint point: SpatialCoveragePoint3D
    ) -> SpatialCoverageCellKey? {
        guard let referenceOriginWorld,
              let referenceYawRadians,
              point.isFinite
        else {
            return nil
        }
        let relative = Self.relativePoint(
            point,
            origin: referenceOriginWorld,
            referenceYawRadians: referenceYawRadians
        )
        return Self.cellKey(
            for: relative,
            cellSizeMeters: cellSizeMeters
        )
    }

    /// The start-relative voxel key containing a world-space point, or
    /// nil before the reference pose exists (#329).
    public func voxelKey(
        forWorldPoint point: SpatialCoveragePoint3D
    ) -> SpatialCoverageVoxelKey? {
        guard let cell = cellKey(forWorldPoint: point),
              let referenceOriginWorld
        else {
            return nil
        }
        return SpatialCoverageVoxelKey(
            x: cell.x,
            z: cell.z,
            yBand: SpatialScanCoverageTracker.yBand(
                for: point.y - referenceOriginWorld.y,
                verticalCellSizeMeters:
                    vertical.verticalCellSizeMeters
            )
        )
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
            x: floorToIntClamped(point.x / cellSizeMeters),
            z: floorToIntClamped(point.z / cellSizeMeters)
        )
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
    /// Vertical quantization of the 3D layer, in meters of
    /// start-relative Y. Coarse on purpose: bands answer "was this
    /// height range observed", not surface reconstruction (#329).
    public let verticalCellSizeMeters: Double
    /// Bound on the additive voxel layer — independent of
    /// `maxRegionCount` and enforced by the layer's own oldest-first
    /// eviction so the 2D budget/eviction policy stays untouched.
    public let maxVoxelCount: Int
    /// Minimum distinct elevation buckets a height-offset voxel needs
    /// before it can classify `observed`; a horizontal orbit alone can
    /// never satisfy this for ceiling/floor geometry.
    public let minimumElevationBucketsForElevatedVoxels: Int
    /// Elevation angle at which a camera-to-point offset counts as a
    /// non-level viewpoint (~20 degrees).
    public let elevationLevelThresholdRadians: Double

    private struct StoredRegion: Sendable {
        var observationCount = 0
        var normalTrackingObservationCount = 0
        var limitedTrackingObservationCount = 0
        var lastObservedTimestampSeconds = 0.0
        var viewAngleBucketMask: UInt16 = 0
        var elevationBucketMask: UInt8 = 0
        var latestDistanceBucket: SpatialCoverageDistanceBucket = .far
        var depthObservationCount = 0
        var meshSupportCount = 0
    }

    private struct StoredVoxel: Sendable {
        var observationCount = 0
        var normalTrackingObservationCount = 0
        var limitedTrackingObservationCount = 0
        var lastObservedTimestampSeconds = 0.0
        var viewpointBucketMask3D: UInt32 = 0
        var latestDistanceBucket: SpatialCoverageDistanceBucket = .far
        var depthObservationCount = 0
        var meshSupportCount = 0
    }

    private var referenceOriginWorld: SpatialCoveragePoint3D?
    private var referenceYawRadians: Double?
    private var currentCameraPosition: SpatialCoveragePoint2D?
    private var currentCameraYWorld: Double?
    private var currentRelativeHeadingRadians: Double?
    private var latestTrackingState: TrackingQualityState?
    private var latestHasSceneDepth = false
    private var latestMeshAvailability: MeshAvailabilityDiagnostic = .unavailable
    private var regions: [SpatialCoverageCellKey: StoredRegion] = [:]
    private var voxels: [SpatialCoverageVoxelKey: StoredVoxel] = [:]
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
        displayRadiusCells: Int = 6,
        verticalCellSizeMeters: Double = 0.6,
        maxVoxelCount: Int = 768,
        minimumElevationBucketsForElevatedVoxels: Int = 2,
        elevationLevelThresholdRadians: Double = 0.35
    ) {
        precondition(cellSizeMeters.isFinite && cellSizeMeters > 0)
        precondition(maxRegionCount > 0)
        precondition(minimumNormalObservations > 0)
        precondition(minimumViewAngleBuckets > 0)
        precondition(minimumViewAngleBuckets <= 8)
        precondition(displayRadiusCells >= 0)
        precondition(
            verticalCellSizeMeters.isFinite
                && verticalCellSizeMeters > 0
        )
        precondition(maxVoxelCount > 0)
        precondition(
            minimumElevationBucketsForElevatedVoxels > 0
                && minimumElevationBucketsForElevatedVoxels <= 3
        )
        precondition(
            elevationLevelThresholdRadians.isFinite
                && elevationLevelThresholdRadians >= 0
        )

        self.cellSizeMeters = cellSizeMeters
        self.maxRegionCount = maxRegionCount
        self.minimumNormalObservations = minimumNormalObservations
        self.minimumViewAngleBuckets = minimumViewAngleBuckets
        self.displayRadiusCells = displayRadiusCells
        self.verticalCellSizeMeters = verticalCellSizeMeters
        self.maxVoxelCount = maxVoxelCount
        self.minimumElevationBucketsForElevatedVoxels =
            minimumElevationBucketsForElevatedVoxels
        self.elevationLevelThresholdRadians =
            elevationLevelThresholdRadians
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
        currentCameraYWorld = sample.cameraPositionWorld.y
        currentRelativeHeadingRadians = Self.normalizeSignedRadians(
            sample.cameraYawRadians - referenceYawRadians
        )

        guard sample.trackingState != .unavailable else {
            return summary()
        }

        var sampleKeys: Set<SpatialCoverageCellKey> = []
        var sampleVoxelKeys: Set<SpatialCoverageVoxelKey> = []
        let cameraRelativeY = cameraRelativeYAxis(
            sample.cameraPositionWorld,
            origin: referenceOriginWorld
        )

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
            let relativeY = point.y - referenceOriginWorld.y

            let dx = cameraRelative.x - relative.x
            let dz = cameraRelative.z - relative.z
            let dy = cameraRelativeY - relativeY
            let horizontalDistance = hypot(dx, dz)
            let elevationBucket = Self.elevationBucket(
                elevationRadians: atan2(dy, horizontalDistance),
                levelThresholdRadians:
                    elevationLevelThresholdRadians
            )
            let viewAngleBucket = Self.viewAngleBucket(atan2(dx, dz))

            if sampleKeys.insert(key).inserted {
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

                region.latestDistanceBucket =
                    Self.distanceBucket(horizontalDistance)

                switch sample.trackingState {
                case .normal:
                    region.normalTrackingObservationCount += 1
                    region.viewAngleBucketMask |=
                        UInt16(1) << viewAngleBucket
                    region.elevationBucketMask |=
                        UInt8(1) << elevationBucket.rawValue
                case .limited:
                    region.limitedTrackingObservationCount += 1
                case .unavailable:
                    break
                }

                regions[key] = region
                peakRegionCount = max(peakRegionCount, regions.count)
            }

            // #329: the additive 3D layer keys the same point by
            // (cell x, cell z, start-relative y-band) so vertical gaps
            // cannot hide inside a 2D "observed" cell. Eviction is the
            // layer's own oldest-first policy, independent of
            // `evictOldestRegion`/`maxRegionCount`.
            let voxelKey = SpatialCoverageVoxelKey(
                x: key.x,
                z: key.z,
                yBand: Self.yBand(
                    for: relativeY,
                    verticalCellSizeMeters: verticalCellSizeMeters
                )
            )
            guard sampleVoxelKeys.insert(voxelKey).inserted else {
                continue
            }

            if voxels[voxelKey] == nil,
               voxels.count >= maxVoxelCount
            {
                evictOldestVoxel()
            }

            var voxel = voxels[voxelKey] ?? StoredVoxel()
            voxel.observationCount += 1
            voxel.lastObservedTimestampSeconds =
                sample.sessionTimestampSeconds

            switch sample.surfaceEvidenceSource {
            case .mesh:
                voxel.meshSupportCount += 1
            case .sceneDepth:
                voxel.depthObservationCount += 1
            case .none:
                break
            }

            voxel.latestDistanceBucket =
                Self.distanceBucket(horizontalDistance)

            switch sample.trackingState {
            case .normal:
                voxel.normalTrackingObservationCount += 1
                voxel.viewpointBucketMask3D |=
                    UInt32(1) << (viewAngleBucket * 3
                        + elevationBucket.rawValue)
            case .limited:
                voxel.limitedTrackingObservationCount += 1
            case .unavailable:
                break
            }

            voxels[voxelKey] = voxel
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
                elevationBucketMask: stored.elevationBucketMask,
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
            vertical: verticalSummary(),
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

    private func verticalSummary() -> SpatialVerticalCoverageSummary {
        let publicVoxels = voxels.map { key, stored in
            let mask = stored.viewpointBucketMask3D
            return SpatialCoverageVoxel(
                key: key,
                observationCount: stored.observationCount,
                normalTrackingObservationCount:
                    stored.normalTrackingObservationCount,
                limitedTrackingObservationCount:
                    stored.limitedTrackingObservationCount,
                lastObservedTimestampSeconds:
                    stored.lastObservedTimestampSeconds,
                viewpointBucketMask3D: mask,
                latestDistanceBucket: stored.latestDistanceBucket,
                depthObservationCount: stored.depthObservationCount,
                meshSupportCount: stored.meshSupportCount,
                classification: voxelClassification(stored),
                elevationSensitive:
                    Self.elevationSensitive(mask: mask)
            )
        }
        .sorted { $0.key < $1.key }

        let yBands = publicVoxels.map(\.key.yBand)
        let observedMin = yBands.min()
        let observedMax = yBands.max()

        var bands: [SpatialVerticalBandSummary] = []
        if let observedMin, let observedMax {
            for band in SpatialVerticalDisplayBand.allCases {
                let inBand = publicVoxels.filter { voxel in
                    Self.displayBand(
                        forYBand: voxel.key.yBand,
                        minYBand: observedMin,
                        maxYBand: observedMax
                    ) == band
                }
                bands.append(
                    SpatialVerticalBandSummary(
                        band: band,
                        voxelCount: inBand.count,
                        observedCount: inBand.filter {
                            $0.classification == .observed
                        }.count,
                        weakCount: inBand.filter {
                            $0.classification == .weak
                        }.count
                    )
                )
            }
        }

        return SpatialVerticalCoverageSummary(
            verticalCellSizeMeters: verticalCellSizeMeters,
            maxVoxelCount: maxVoxelCount,
            observedYBandMin: observedMin,
            observedYBandMax: observedMax,
            voxels: publicVoxels,
            displayBands: bands
        )
    }

    /// Maps a populated y-band onto its display stratum. Kept in lock
    /// step with `SpatialVerticalCoverageSummary.displayBand(forYBand:)`.
    static func displayBand(
        forYBand yBand: Int,
        minYBand: Int,
        maxYBand: Int
    ) -> SpatialVerticalDisplayBand? {
        let span = maxYBand - minYBand + 1
        guard span > 0 else { return nil }
        let bandCount = SpatialVerticalDisplayBand.allCases.count
        let index = min(
            bandCount - 1,
            max(0, (yBand - minYBand) * bandCount / span)
        )
        return SpatialVerticalDisplayBand.allCases[index]
    }

    /// A voxel is `observed` on the same evidence/diversity thresholds
    /// as a 2D region, plus one 3D rule: when the voxel is
    /// height-offset (seen from materially above or below), a
    /// horizontal orbit alone is not "multi-view" — at least
    /// `minimumElevationBucketsForElevatedVoxels` distinct elevation
    /// buckets are required so a ceiling patch cannot be claimed fully
    /// observed from a single camera height.
    private func voxelClassification(
        _ voxel: StoredVoxel
    ) -> SpatialCoverageClassification {
        var azimuthDiversity = 0
        var elevationDiversity = 0
        for azimuth in 0 ..< 8
        where (voxel.viewpointBucketMask3D >> (azimuth * 3))
            & 0b111 != 0
        {
            azimuthDiversity += 1
        }
        elevationDiversity = Self.elevationDiversityCount(
            mask: voxel.viewpointBucketMask3D
        )

        let geometricSupportCount =
            voxel.meshSupportCount
            + voxel.depthObservationCount

        let multiViewSatisfied =
            azimuthDiversity >= minimumViewAngleBuckets
            && (
                elevationDiversity
                    >= minimumElevationBucketsForElevatedVoxels
                || !Self.elevationSensitive(
                    mask: voxel.viewpointBucketMask3D
                )
            )

        if voxel.normalTrackingObservationCount
                >= minimumNormalObservations,
           multiViewSatisfied,
           geometricSupportCount >= minimumNormalObservations
        {
            return .observed
        }

        if voxel.observationCount > 0 || voxel.meshSupportCount > 0 {
            return .weak
        }

        return .unknown
    }

    /// Bits of the level-elevation row across all 8 azimuth groups.
    private static let levelElevationMask: UInt32 = 0x0049_2492

    static func elevationSensitive(mask: UInt32) -> Bool {
        mask & ~levelElevationMask != 0
    }

    /// Distinct elevation buckets across all 8 azimuth groups — the
    /// elevation-e column mask is `0x00249249 << e`.
    static func elevationDiversityCount(mask: UInt32) -> Int {
        var count = 0
        for elevation in 0 ..< 3 {
            if mask & (UInt32(0x0024_9249) << elevation) != 0 {
                count += 1
            }
        }
        return count
    }

    /// `floor`-quantized vertical band for a start-relative height.
    static func yBand(
        for relativeY: Double,
        verticalCellSizeMeters: Double
    ) -> Int {
        floorToIntClamped(relativeY / verticalCellSizeMeters)
    }

    static func elevationBucket(
        elevationRadians: Double,
        levelThresholdRadians: Double
    ) -> SpatialCoverageElevationBucket {
        if elevationRadians > levelThresholdRadians {
            return .cameraAbove
        }
        if elevationRadians < -levelThresholdRadians {
            return .cameraBelow
        }
        return .level
    }

    private func cameraRelativeYAxis(
        _ cameraWorld: SpatialCoveragePoint3D,
        origin: SpatialCoveragePoint3D
    ) -> Double {
        cameraWorld.y - origin.y
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

        // Cell keys saturate at `Int.min`/`Int.max` under
        // `floorToIntClamped`; expand the display window without
        // overflowing so an extreme key still renders a degenerate
        // bounds rather than trapping.
        let clamped = min(
            Int.max - displayRadiusCells,
            max(Int.min + displayRadiusCells, center.x)
        )
        let clampedZ = min(
            Int.max - displayRadiusCells,
            max(Int.min + displayRadiusCells, center.z)
        )
        return SpatialCoverageBounds(
            minX: clamped - displayRadiusCells,
            maxX: clamped + displayRadiusCells,
            minZ: clampedZ - displayRadiusCells,
            maxZ: clampedZ + displayRadiusCells
        )
    }

    /// Oldest-first eviction for the additive voxel layer (#329). Kept
    /// separate from `evictOldestRegion` so the 2D budget policy
    /// (including in-flight #336 changes) is untouched.
    private mutating func evictOldestVoxel() {
        guard let oldestKey = voxels.min(by: { lhs, rhs in
            if lhs.value.lastObservedTimestampSeconds
                != rhs.value.lastObservedTimestampSeconds
            {
                return lhs.value.lastObservedTimestampSeconds
                    < rhs.value.lastObservedTimestampSeconds
            }
            return lhs.key < rhs.key
        })?.key else {
            return
        }
        voxels[oldestKey] = nil
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
            x: floorToIntClamped(point.x / cellSizeMeters),
            z: floorToIntClamped(point.z / cellSizeMeters)
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
        SpatialCoverageDistanceBucket.bucket(forMeters: meters)
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
