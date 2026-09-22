import Foundation

public struct DerivedShapeTemporalFusionConfiguration:
    Sendable,
    Equatable
{
    public let maximumFrameCount: Int
    public let maximumAgeSeconds: Double
    public let voxelSizeMeters: Double
    public let maximumPointCount: Int
    public let maximumObservationCenterShiftMeters: Double?

    public init(
        maximumFrameCount: Int = 5,
        maximumAgeSeconds: Double = 8.0,
        voxelSizeMeters: Double = 0.05,
        maximumPointCount: Int = 768,
        maximumObservationCenterShiftMeters: Double? = nil
    ) {
        precondition(maximumFrameCount > 0)
        precondition(
            maximumAgeSeconds.isFinite
                && maximumAgeSeconds >= 0
        )
        precondition(
            voxelSizeMeters.isFinite
                && voxelSizeMeters > 0
        )
        precondition(maximumPointCount > 0)
        precondition(
            maximumObservationCenterShiftMeters == nil
                || (
                    maximumObservationCenterShiftMeters!.isFinite
                    && maximumObservationCenterShiftMeters! > 0
                )
        )

        self.maximumFrameCount = maximumFrameCount
        self.maximumAgeSeconds = maximumAgeSeconds
        self.voxelSizeMeters = voxelSizeMeters
        self.maximumPointCount = maximumPointCount
        self.maximumObservationCenterShiftMeters =
            maximumObservationCenterShiftMeters
    }

    public static let livePreview =
        DerivedShapeTemporalFusionConfiguration()
}

/// Bounded multi-view accumulator for advisory derived geometry.
///
/// This is intentionally not capture authority. It only fuses already-derived
/// observation points that share one exact coordinate-space authority. The
/// tracker resets rather than combining points across a coordinate-space
/// change.
public struct DerivedShapeTemporalFusionTracker: Sendable {
    private struct Frame: Sendable {
        let timestampSeconds: Double
        let observation: DerivedShapeObservation
    }

    private struct VoxelKey: Hashable, Comparable, Sendable {
        let x: Int
        let y: Int
        let z: Int
        let hasVertical: Bool

        static func < (lhs: VoxelKey, rhs: VoxelKey) -> Bool {
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            if lhs.z != rhs.z { return lhs.z < rhs.z }
            if lhs.hasVertical != rhs.hasVertical {
                return lhs.hasVertical && !rhs.hasVertical
            }
            return lhs.y < rhs.y
        }
    }

    public let configuration: DerivedShapeTemporalFusionConfiguration

    private var coordinateSpaceID: CoordinateSpaceID?
    private var targetCenterAnchor: DerivedPoint2D?
    private var frames: [Frame] = []

    public init(
        configuration: DerivedShapeTemporalFusionConfiguration =
            .livePreview
    ) {
        self.configuration = configuration
    }

    public mutating func reset() {
        coordinateSpaceID = nil
        targetCenterAnchor = nil
        frames.removeAll(keepingCapacity: false)
    }

    @discardableResult
    public mutating func record(
        _ observation: DerivedShapeObservation?,
        timestampSeconds: Double
    ) -> DerivedShapeObservation? {
        let timestamp =
            timestampSeconds.isFinite
            ? timestampSeconds
            : (
                observation?.observationEndSeconds
                ?? observation?.observationStartSeconds
                ?? frames.last?.timestampSeconds
                ?? 0
            )

        if let observation {
            if coordinateSpaceID != nil,
               coordinateSpaceID != observation.coordinateSpaceID
            {
                reset()
            }

            let newCenter = observationCenter(observation)

            if let maximumShift =
                configuration.maximumObservationCenterShiftMeters,
               let anchor = targetCenterAnchor,
               let newCenter,
               hypot(
                    anchor.x - newCenter.x,
                    anchor.y - newCenter.y
               ) > maximumShift
            {
                // Live object observations are intentionally single-target.
                // The acceptance reference is the window's anchor center,
                // not the previous frame: a chain of sub-threshold steps
                // (A -> B -> C -> D) must not walk the fused target onto
                // adjacent furniture. Panning from one piece of furniture
                // to another must not fuse both silhouettes into one
                // bogus polygon. Reset only the derived preview
                // accumulator; canonical capture evidence is unaffected.
                reset()
            }

            coordinateSpaceID = observation.coordinateSpaceID
            if targetCenterAnchor == nil {
                // The first center-bearing observation of the window pins
                // the target lock. The anchor does not move as later
                // frames arrive, so acceptance is bounded by total
                // distance from the target rather than by step-to-step
                // distance from the previous frame.
                targetCenterAnchor = newCenter
            }
            frames.append(
                Frame(
                    timestampSeconds: timestamp,
                    observation: observation
                )
            )
        }

        prune(referenceTimestampSeconds: timestamp)
        return fusedObservation()
    }

    public func fusedObservation() -> DerivedShapeObservation? {
        guard let coordinateSpaceID,
              !frames.isEmpty
        else {
            return nil
        }

        var voxels: [VoxelKey: DerivedObservationPoint] = [:]
        var minimumStart: Double?
        var maximumEnd: Double?

        for frame in frames {
            if let start = frame.observation.observationStartSeconds,
               start.isFinite
            {
                minimumStart = minimumStart.map {
                    min($0, start)
                } ?? start
            }
            if let end = frame.observation.observationEndSeconds,
               end.isFinite
            {
                maximumEnd = maximumEnd.map {
                    max($0, end)
                } ?? end
            }

            for point in frame.observation.points
            where point.position.x.isFinite
                && point.position.y.isFinite
            {
                let key = voxelKey(point)
                // Frames are stored oldest -> newest. Overwriting preserves
                // the newest sample for one bounded world-space voxel.
                voxels[key] = point
            }
        }

        guard !voxels.isEmpty else {
            return nil
        }

        let ordered = voxels
            .sorted { $0.key < $1.key }
            .map(\.value)
        let bounded = boundedSample(
            ordered,
            maximum: configuration.maximumPointCount
        )

        return DerivedShapeObservation(
            coordinateSpaceID: coordinateSpaceID,
            points: bounded,
            sourceEvidenceRefs:
                Array(Set(bounded.map(\.evidenceRef))).sorted(),
            observationStartSeconds: minimumStart,
            observationEndSeconds: maximumEnd
        )
    }

    private func observationCenter(
        _ observation: DerivedShapeObservation
    ) -> DerivedPoint2D? {
        let points = observation.points.filter {
            $0.position.x.isFinite
                && $0.position.y.isFinite
        }
        guard !points.isEmpty else {
            return nil
        }

        // Median center is deliberately robust to sparse depth outliers.
        // It tracks the observed furniture target in world space without
        // allowing a few floor/wall samples to drag the target lock.
        let xs = points.map { $0.position.x }.sorted()
        let ys = points.map { $0.position.y }.sorted()

        func median(_ values: [Double]) -> Double {
            let middle = values.count / 2
            if values.count.isMultiple(of: 2) {
                return (values[middle - 1] + values[middle]) / 2
            }
            return values[middle]
        }

        return DerivedPoint2D(
            x: median(xs),
            y: median(ys)
        )
    }

    private mutating func prune(
        referenceTimestampSeconds: Double
    ) {
        if configuration.maximumAgeSeconds > 0,
           referenceTimestampSeconds.isFinite
        {
            let cutoff =
                referenceTimestampSeconds
                - configuration.maximumAgeSeconds
            frames.removeAll {
                $0.timestampSeconds.isFinite
                    && $0.timestampSeconds < cutoff
            }
        }

        if frames.count > configuration.maximumFrameCount {
            frames.removeFirst(
                frames.count - configuration.maximumFrameCount
            )
        }

        if frames.isEmpty {
            coordinateSpaceID = nil
            targetCenterAnchor = nil
        }
    }

    private func voxelKey(
        _ point: DerivedObservationPoint
    ) -> VoxelKey {
        let voxel = configuration.voxelSizeMeters
        if let vertical = point.verticalPositionMeters,
           vertical.isFinite
        {
            return VoxelKey(
                x: floorToIntClamped(point.position.x / voxel),
                y: floorToIntClamped(vertical / voxel),
                z: floorToIntClamped(point.position.y / voxel),
                hasVertical: true
            )
        }

        return VoxelKey(
            x: floorToIntClamped(point.position.x / voxel),
            y: 0,
            z: floorToIntClamped(point.position.y / voxel),
            hasVertical: false
        )
    }

    private func boundedSample(
        _ points: [DerivedObservationPoint],
        maximum: Int
    ) -> [DerivedObservationPoint] {
        guard points.count > maximum else {
            return points
        }

        let stride = Double(points.count) / Double(maximum)
        return (0..<maximum).map {
            points[Int(Double($0) * stride)]
        }
    }
}
