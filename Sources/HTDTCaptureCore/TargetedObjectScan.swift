import Foundation

/// Operator-targeted "Scan this object" re-observation pass (#250).
///
/// The operator picks the important object; the tracker holds a bounded
/// target authority (centroid + extent radius measured from the fused
/// derived-shape observation at selection time) and turns the orbit
/// into view-angle buckets around the target. Guidance stays
/// object-specific (orbit toward the least-observed side, hold, step
/// back) instead of generic room coverage, and completion/timeout are
/// bounded. The tracker never fabricates geometry: it only reports how
/// well the target region was re-observed; the fused candidate remains
/// advisory as before.
public struct ScanTargetAnchor: Sendable, Equatable {
    /// World-space centroid of the operator-selected target.
    public let x: Double
    public let y: Double
    public let z: Double
    /// Horizontal half-extent used as the orbit radius baseline.
    public let radiusMeters: Double

    public init(x: Double, y: Double, z: Double, radiusMeters: Double) {
        precondition(radiusMeters.isFinite && radiusMeters > 0)
        self.x = x
        self.y = y
        self.z = z
        self.radiusMeters = radiusMeters
    }
}

public enum TargetScanGuidance: Sendable, Equatable {
    /// Move around the target; `clockwise` picks the orbit direction
    /// toward the least-observed side.
    case orbit(clockwise: Bool)
    /// Step back: the camera is too close to keep the whole target in
    /// useful view.
    case retreat
    /// Approach: the camera is so far that surface detail is weak.
    case approach
    /// Keep observing from here.
    case hold
}

public struct TargetScanStatus: Sendable, Equatable {
    /// Fraction of view-angle buckets around the target observed at
    /// normal tracking, 0...1.
    public let angularCoverageFraction: Double
    /// Number of distinct view-angle buckets observed.
    public let observedBucketCount: Int
    public let totalBucketCount: Int
    /// True once the bounded pass finished: required buckets observed
    /// or the duration budget elapsed with partial coverage retained.
    public let isComplete: Bool
    /// The pass exceeded its duration budget without completing.
    public let expired: Bool
    /// The camera left the target neighborhood entirely — the pass
    /// auto-pauses rather than following the operator away.
    public let outOfRange: Bool
    public let guidance: TargetScanGuidance

    public init(
        angularCoverageFraction: Double,
        observedBucketCount: Int,
        totalBucketCount: Int,
        isComplete: Bool,
        expired: Bool,
        outOfRange: Bool,
        guidance: TargetScanGuidance
    ) {
        self.angularCoverageFraction = angularCoverageFraction
        self.observedBucketCount = observedBucketCount
        self.totalBucketCount = totalBucketCount
        self.isComplete = isComplete
        self.expired = expired
        self.outOfRange = outOfRange
        self.guidance = guidance
    }
}

public struct TargetedObjectScanTracker: Sendable, Equatable {
    /// View-angle buckets around the target (N = 8 gives 45° sectors).
    public let bucketCount: Int
    /// Buckets required for the pass to complete.
    public let requiredBucketCount: Int
    /// Maximum duration of the pass; expiry keeps partial progress
    /// instead of trapping the operator.
    public let maximumDurationSeconds: Double
    /// Distance (m) beyond which the pass is treated as out of range.
    public let maximumRangeMeters: Double
    /// Distance (m) below which guidance asks the operator to step back
    /// so the whole target stays in view.
    public let minimumRangeMeters: Double
    /// Minimum normal-tracking camera dwell per bucket.
    public let minimumBucketDwellSeconds: Double

    public let target: ScanTargetAnchor
    public private(set) var startTimestampSeconds: Double?
    private var bucketDwellSeconds: [Double]
    private var lastTimestampSeconds: Double?

    public init(
        target: ScanTargetAnchor,
        bucketCount: Int = 8,
        requiredBucketCount: Int = 5,
        maximumDurationSeconds: Double = 120,
        maximumRangeMeters: Double = 6,
        minimumRangeMeters: Double = 0.5,
        minimumBucketDwellSeconds: Double = 0.6
    ) {
        precondition(bucketCount >= 4)
        precondition(requiredBucketCount > 0)
        precondition(requiredBucketCount <= bucketCount)
        precondition(maximumDurationSeconds > 0)
        precondition(maximumRangeMeters > minimumRangeMeters)
        self.target = target
        self.bucketCount = bucketCount
        self.requiredBucketCount = requiredBucketCount
        self.maximumDurationSeconds = maximumDurationSeconds
        self.maximumRangeMeters = maximumRangeMeters
        self.minimumRangeMeters = minimumRangeMeters
        self.minimumBucketDwellSeconds = minimumBucketDwellSeconds
        bucketDwellSeconds = Array(
            repeating: 0,
            count: bucketCount
        )
    }

    /// Record one sample. Only normal-tracking samples inside the
    /// target range accumulate bucket dwell.
    public mutating func record(
        cameraX: Double,
        cameraZ: Double,
        timestampSeconds: Double,
        trackingState: TrackingQualityState
    ) -> TargetScanStatus {
        if startTimestampSeconds == nil {
            startTimestampSeconds = timestampSeconds
        }
        let elapsed = max(
            0,
            timestampSeconds - (startTimestampSeconds ?? timestampSeconds)
        )
        let expired = elapsed >= maximumDurationSeconds

        let dx = cameraX - target.x
        let dz = cameraZ - target.z
        let distance = hypot(dx, dz)
        // A non-finite camera/target delta reports out-of-range rather
        // than reaching `Int(normalized)` in `bucketIndex` below.
        let outOfRange = distance.isFinite
            ? distance > maximumRangeMeters
            : true

        if trackingState == .normal, !outOfRange,
           let last = lastTimestampSeconds
        {
            let dt = max(0, timestampSeconds - last)
            let bucket = bucketIndex(dx: dx, dz: dz)
            bucketDwellSeconds[bucket] += dt
        }
        lastTimestampSeconds = timestampSeconds

        let observed = bucketDwellSeconds.filter {
            $0 >= minimumBucketDwellSeconds
        }.count
        let complete =
            observed >= requiredBucketCount || expired

        return TargetScanStatus(
            angularCoverageFraction:
                Double(observed) / Double(bucketCount),
            observedBucketCount: observed,
            totalBucketCount: bucketCount,
            isComplete: complete,
            expired: expired,
            outOfRange: outOfRange,
            guidance: guidance(
                distance: distance,
                dx: dx,
                dz: dz
            )
        )
    }

    public var observedBucketCount: Int {
        bucketDwellSeconds.filter {
            $0 >= minimumBucketDwellSeconds
        }.count
    }

    private func guidance(
        distance: Double,
        dx: Double,
        dz: Double
    ) -> TargetScanGuidance {
        if distance < minimumRangeMeters {
            return .retreat
        }
        if distance > maximumRangeMeters * 0.8 {
            return .approach
        }
        guard let weakest = leastObservedBucket() else {
            return .hold
        }
        let currentAngle = atan2(dz, dx)
        let weakestCenter =
            (Double(weakest) + 0.5) / Double(bucketCount)
                * 2 * .pi - .pi
        var delta = weakestCenter - currentAngle
        delta = delta.truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta < -.pi {
            delta += 2 * .pi
        }
        if abs(delta) < .pi / Double(bucketCount) / 2 {
            return .hold
        }
        // Positive delta means the weakest region is counterclockwise
        // from the camera — moving clockwise keeps the orbit tightest.
        return .orbit(clockwise: delta > 0)
    }

    private func leastObservedBucket() -> Int? {
        bucketDwellSeconds.enumerated().min {
            $0.element < $1.element
        }?.offset
    }

    private func bucketIndex(dx: Double, dz: Double) -> Int {
        let angle = atan2(dz, dx)
        let normalized =
            (angle + .pi) / (2 * .pi) * Double(bucketCount)
        return min(bucketCount - 1, max(0, Int(normalized)))
    }
}
