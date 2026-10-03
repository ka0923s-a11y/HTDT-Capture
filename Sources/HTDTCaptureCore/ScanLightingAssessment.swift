import Foundation

/// Lighting condition for AR acquisition guidance (legacy bolph71656-ai/HTDT-Capture#283).
///
/// Home-theater rooms are commonly operated dark; visual tracking and
/// evidence frames still need light even though LiDAR depth does not.
/// This assessment is advisory — it never gates canonical quality — it
/// only lets the product tell "the room is too dark" apart from a
/// generic tracking failure.
public enum ScanLightingStatus: String, Sendable, Equatable {
    /// No ambient-light reading is available (non-ARKit surface or a
    /// frame without a light estimate); never claim a lighting problem.
    case unknown
    case adequate
    case lowLight
}

public struct ScanLightingPolicy: Sendable, Equatable {
    /// Ambient intensity (lumens) below which the scene is treated as
    /// too dark for reliable visual acquisition. A dim living room is
    /// typically a few hundred lumens; the threshold deliberately sits
    /// well below that so only genuinely dark rooms trigger.
    public let lowLightThresholdLumens: Double

    public init(lowLightThresholdLumens: Double = 100) {
        precondition(lowLightThresholdLumens > 0)
        self.lowLightThresholdLumens = lowLightThresholdLumens
    }

    public func assess(
        ambientIntensityLumens: Double?,
        trackingState: TrackingQualityState?,
        trackingReason: String?
    ) -> ScanLightingStatus {
        guard let ambientIntensityLumens,
              ambientIntensityLumens.isFinite,
              ambientIntensityLumens >= 0
        else {
            return .unknown
        }
        guard ambientIntensityLumens < lowLightThresholdLumens else {
            return .adequate
        }
        return .lowLight
    }

    /// Whether live guidance should surface the low-light recovery
    /// message: either the light estimate alone is clearly low, or a
    /// low estimate coincides with degraded tracking (the case where a
    /// generic "move slowly" prompt would mislead).
    public func shouldSurfaceLowLightGuidance(
        status: ScanLightingStatus,
        trackingState: TrackingQualityState?
    ) -> Bool {
        status == .lowLight
    }
}
