import Foundation

/// Bounded automatic evidence-keyframe selection policy (#216).
///
/// During an active scan the host periodically offers the tracker a
/// compact `AutomaticKeyframeSample`. A candidate is retained only when
/// tracking is normal, it is usable evidence, it satisfies the
/// minimum interval, and it is spatially novel (translation, heading
/// change, or a coverage cell no retained frame has observed yet).
/// Retention is hard-bounded per capture by both frame count and an
/// estimated byte budget; manual `Save evidence` bypasses this tracker
/// entirely and is never deduplicated or discarded by it.
///
/// `policyVersion` identifies the selection behavior so a retained
/// automatic frame can be attributed to an understandable policy.
public struct AutomaticKeyframeConfiguration: Sendable, Equatable {
    public var maximumRetainedFrames: Int
    public var minimumIntervalSeconds: Double
    public var minimumTranslationMeters: Double
    public var minimumRotationRadians: Double
    /// Total estimated retained bytes (pixel + depth payloads) beyond
    /// which automatic selection stops.
    public var maximumRetainedBytes: Int
    /// Frames without scene depth are still useful, but strictly
    /// limited so a degraded-depth run cannot spend the whole budget.
    public var maximumNoDepthFrames: Int
    public var policyVersion: String

    public init(
        maximumRetainedFrames: Int = 6,
        minimumIntervalSeconds: Double = 12,
        minimumTranslationMeters: Double = 0.75,
        minimumRotationRadians: Double = .pi / 3,
        maximumRetainedBytes: Int = 128 * 1024 * 1024,
        maximumNoDepthFrames: Int = 2,
        policyVersion: String = "auto_keyframe_v1"
    ) {
        precondition(maximumRetainedFrames > 0)
        precondition(minimumIntervalSeconds > 0)
        precondition(minimumTranslationMeters > 0)
        precondition(minimumRotationRadians > 0)
        precondition(maximumRetainedBytes > 0)
        precondition(maximumNoDepthFrames >= 0)
        precondition(!policyVersion.isEmpty)
        self.maximumRetainedFrames = maximumRetainedFrames
        self.minimumIntervalSeconds = minimumIntervalSeconds
        self.minimumTranslationMeters = minimumTranslationMeters
        self.minimumRotationRadians = minimumRotationRadians
        self.maximumRetainedBytes = maximumRetainedBytes
        self.maximumNoDepthFrames = maximumNoDepthFrames
        self.policyVersion = policyVersion
    }

    public static var standard: AutomaticKeyframeConfiguration {
        AutomaticKeyframeConfiguration()
    }
}

public enum AutomaticKeyframeDecision: String, Sendable, Equatable {
    case retain
    case skippedTrackingNotNormal
    case skippedUnusable
    case skippedInterval
    case skippedDuplicate
    case skippedBudgetFrames
    case skippedBudgetBytes
    case skippedNoDepthAllowance
    case skippedNoPosition
}

/// One bounded observation offered to the selector. `cameraPosition`
/// carries world X/Z; `yawRadians` the world-space heading; both come
/// from the same sample authority as the coverage loop.
public struct AutomaticKeyframeSample: Sendable, Equatable {
    public let timestampSeconds: Double
    public let cameraX: Double?
    public let cameraZ: Double?
    public let yawRadians: Double?
    public let trackingState: TrackingQualityState
    public let hasSceneDepth: Bool
    /// Result of the frame-usability check for the candidate frame;
    /// nil when no usability probe ran for this tick.
    public let usabilityStatus: FrameUsabilityStatus?
    /// Estimated bytes the frame package would persist (pixel + depth
    /// + preview), when the caller can provide it; else nil.
    public let estimatedBytes: Int?

    public init(
        timestampSeconds: Double,
        cameraX: Double? = nil,
        cameraZ: Double? = nil,
        yawRadians: Double? = nil,
        trackingState: TrackingQualityState,
        hasSceneDepth: Bool,
        usabilityStatus: FrameUsabilityStatus? = nil,
        estimatedBytes: Int? = nil
    ) {
        self.timestampSeconds = timestampSeconds
        self.cameraX = cameraX
        self.cameraZ = cameraZ
        self.yawRadians = yawRadians
        self.trackingState = trackingState
        self.hasSceneDepth = hasSceneDepth
        self.usabilityStatus = usabilityStatus
        self.estimatedBytes = estimatedBytes
    }
}

public struct AutomaticKeyframeTracker: Sendable, Equatable {
    public private(set) var retainedCount: Int
    public private(set) var retainedNoDepthCount: Int
    public private(set) var retainedByteEstimate: Int
    private var retainedAnchors: [AutomaticKeyframeAnchor]
    private var lastConsideredTimestamp: Double?
    public let configuration: AutomaticKeyframeConfiguration

    public init(
        configuration: AutomaticKeyframeConfiguration = .standard
    ) {
        self.configuration = configuration
        retainedCount = 0
        retainedNoDepthCount = 0
        retainedByteEstimate = 0
        retainedAnchors = []
        lastConsideredTimestamp = nil
    }

    public var policyVersion: String {
        configuration.policyVersion
    }

    /// Evaluate a candidate. Retention is recorded only through
    /// `markRetained` so a capture attempt that later fails does not
    /// consume novelty/budget.
    public func evaluate(
        _ sample: AutomaticKeyframeSample
    ) -> AutomaticKeyframeDecision {
        guard sample.trackingState == .normal else {
            return .skippedTrackingNotNormal
        }
        if sample.usabilityStatus == .unusable {
            return .skippedUnusable
        }
        if let last = lastConsideredTimestamp,
           sample.timestampSeconds - last
                < configuration.minimumIntervalSeconds
        {
            return .skippedInterval
        }
        guard let x = sample.cameraX, let z = sample.cameraZ else {
            return .skippedNoPosition
        }
        guard retainedCount < configuration.maximumRetainedFrames else {
            return .skippedBudgetFrames
        }
        if !sample.hasSceneDepth,
           retainedNoDepthCount >= configuration.maximumNoDepthFrames
        {
            return .skippedNoDepthAllowance
        }
        if let estimatedBytes = sample.estimatedBytes,
           retainedByteEstimate + estimatedBytes
                > configuration.maximumRetainedBytes
        {
            return .skippedBudgetBytes
        }

        for anchor in retainedAnchors {
            let translation = hypot(x - anchor.x, z - anchor.z)
            if translation >= configuration.minimumTranslationMeters {
                continue
            }
            if let yaw = sample.yawRadians,
               let anchorYaw = anchor.yawRadians
            {
                let delta = abs(
                    Self.angularDelta(yaw, anchorYaw)
                )
                if delta >= configuration.minimumRotationRadians {
                    continue
                }
            }
            // Close in translation and heading to a retained frame:
            // the candidate adds no spatial novelty.
            return .skippedDuplicate
        }

        return .retain
    }

    /// Record that the candidate was durably retained. The host calls
    /// this only after the frame package commit path accepted the
    /// evidence. `actualBytes` reconciles the byte budget with the
    /// persisted payload size when the host knows it; the estimator's
    /// `estimatedBytes` is used otherwise.
    public mutating func markRetained(
        _ sample: AutomaticKeyframeSample,
        actualBytes: Int? = nil
    ) {
        lastConsideredTimestamp = sample.timestampSeconds
        if let x = sample.cameraX, let z = sample.cameraZ {
            retainedAnchors.append(
                AutomaticKeyframeAnchor(
                    x: x,
                    z: z,
                    yawRadians: sample.yawRadians
                )
            )
        }
        retainedCount += 1
        if !sample.hasSceneDepth {
            retainedNoDepthCount += 1
        }
        retainedByteEstimate +=
            actualBytes ?? sample.estimatedBytes ?? 0
    }

    /// Shortest angle between two headings in radians, in `(-π, π]`.
    static func angularDelta(_ a: Double, _ b: Double) -> Double {
        var delta = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta <= -.pi {
            delta += 2 * .pi
        }
        return delta
    }
}

private struct AutomaticKeyframeAnchor: Sendable, Equatable {
    let x: Double
    let z: Double
    let yawRadians: Double?
}
