import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(Vision)
import ARKit
import simd
import Vision

/// Bounded camera-source preflight on the shared AR session (issue
/// #277): selects ONE stable ordinary camera frame, runs Vision's
/// `DetectLensSmudgeRequest` off the AR callback path, and returns the
/// honest outcome for the Core advisory assessment.
///
/// Never runs per-frame, never on the AR delegate queue, and skips
/// rather than blocks when no stable sample arrives promptly.
public enum CameraSourcePreflight {
    /// The one stable frame sample the preflight needs. The pixel
    /// buffer is retained only for the single bounded Vision analysis
    /// — it is `@unchecked Sendable` because CVPixelBuffer has no
    /// concurrency annotation, and the buffer is never mutated.
    public struct StableFrameSample: @unchecked Sendable {
        public let pixelBuffer: CVPixelBuffer
        public let ambientIntensityLumens: Double?
        public let timestampSeconds: Double
    }

    /// Wait for a stable ordinary frame on `session`: tracking must be
    /// `.normal` and the camera must not drift more than `policy`'s
    /// position budget across two polls separated by `settleSeconds`.
    /// Returns nil when the budget expires — callers treat nil as
    /// "check skipped", never as a pass or fail.
    /// `ARSession` is not `Sendable`, so the poll is `@MainActor` —
    /// `currentFrame` reads are microsecond and `Task.sleep` suspends,
    /// so the UI is never blocked; the session is never sent across
    /// isolation boundaries.
    @MainActor
    public static func acquireStableFrameSample(
        session: ARSession,
        policy: CameraSourcePreflightPolicy,
        settleSeconds: Double = 0.4,
        pollIntervalNanoseconds: UInt64 = 150_000_000
    ) async -> StableFrameSample? {
        let deadline = Date().addingTimeInterval(
            policy.stableFrameMaxWaitSeconds
        )
        var lastPosition: SIMD3<Float>?
        var lastTimestamp: Double?

        while Date() < deadline {
            try? await Task.sleep(
                nanoseconds: pollIntervalNanoseconds
            )
            guard !Task.isCancelled else { return nil }
            guard let frame = session.currentFrame,
                  frame.camera.trackingState == .normal
            else {
                lastPosition = nil
                lastTimestamp = nil
                continue
            }
            let position = SIMD3<Float>(
                frame.camera.transform.columns.3.x,
                frame.camera.transform.columns.3.y,
                frame.camera.transform.columns.3.z
            )
            guard let previous = lastPosition,
                  let previousTimestamp = lastTimestamp,
                  frame.timestamp - previousTimestamp >= settleSeconds
            else {
                lastPosition = position
                lastTimestamp = frame.timestamp
                continue
            }
            let drift = simd_distance(position, previous)
            guard Double(drift)
                    <= policy.stableFrameMaxPositionDeltaMeters
            else {
                lastPosition = position
                lastTimestamp = frame.timestamp
                continue
            }
            return StableFrameSample(
                pixelBuffer: frame.capturedImage,
                ambientIntensityLumens: frame.lightEstimate.map {
                    Double($0.ambientIntensity)
                },
                timestampSeconds: frame.timestamp
            )
        }
        return nil
    }

    /// Run `DetectLensSmudgeRequest` on the sampled pixel buffer.
    /// Returns the observation confidence (0...1) or nil when Vision
    /// produced no observation — the caller records nil honestly.
    public static func smudgeConfidence(
        of pixelBuffer: CVPixelBuffer
    ) async -> Double? {
        // DetectLensSmudgeRequest is iOS 26+; below it the check is
        // skipped honestly (nil = smudge unknown). The #267 baseline
        // rebases to iOS 27, where this guard is a no-op.
        guard #available(iOS 26.0, *) else {
            return nil
        }
        // The caller is the bounded preflight task — never the AR
        // delegate queue — and `perform` is async, so the Vision work
        // suspends without blocking the session's frame path.
        let request = DetectLensSmudgeRequest()
        guard let observation = try? await request.perform(
            on: pixelBuffer
        ) else {
            return nil
        }
        return Double(observation.confidence)
    }
}
#endif
