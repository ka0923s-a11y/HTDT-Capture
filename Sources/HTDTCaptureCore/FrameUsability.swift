import Foundation

/// Advisory frame-usability diagnostics (legacy bolph71656-ai/HTDT-Capture#274).
///
/// A retained evidence frame is structurally valid, but its visual
/// content can still be useless (nearly black, clipped/overexposed,
/// motion-smeared). The evaluator turns cheap bounded pixel statistics
/// into an advisory assessment — it never claims semantic quality and
/// never blocks retention; manual Save can force-retain with the
/// warning recorded.
public enum FrameUsabilityIssue: String, Codable, Sendable, Equatable {
    case tooDark = "too_dark"
    case overexposed
    case motionBlurSuspected = "motion_blur_suspected"
    case trackingNotNormal = "tracking_not_normal"
}

public enum FrameUsabilityStatus: String, Sendable, Equatable {
    case usable
    /// One or more soft issues; still eligible evidence.
    case suspect
    /// Clearly unusable (e.g. almost no visible content); automatic
    /// selection skips it and manual retention warns.
    case unusable
}

/// Bounded image statistics measured by the platform probe on a
/// subsampled luma grid. Values are normalized 0...1.
public struct FrameUsabilityMetrics: Codable, Sendable, Equatable {
    /// Mean luma, 0...1.
    public let meanLuminance: Double
    /// Fraction of sampled pixels at/above the clipping bound.
    public let clippedFraction: Double
    /// Fraction of sampled pixels at/below the darkness bound.
    public let darkFraction: Double
    /// Mean absolute luma gradient across the sample grid — a cheap
    /// sharpness proxy (motion blur flattens local contrast).
    public let gradientEnergy: Double
    /// EXIF exposure duration in seconds when the capture pipeline
    /// carried it; long exposures smear handheld motion. Mutable so the
    /// platform probe can attach EXIF data after pixel sampling.
    public var exposureSeconds: Double?

    public init(
        meanLuminance: Double,
        clippedFraction: Double,
        darkFraction: Double,
        gradientEnergy: Double,
        exposureSeconds: Double? = nil
    ) {
        self.meanLuminance = meanLuminance
        self.clippedFraction = clippedFraction
        self.darkFraction = darkFraction
        self.gradientEnergy = gradientEnergy
        self.exposureSeconds = exposureSeconds
    }
}

public struct FrameUsabilityAssessment: Sendable, Equatable {
    public let status: FrameUsabilityStatus
    public let issues: [FrameUsabilityIssue]
    public let policyVersion: String

    public init(
        status: FrameUsabilityStatus,
        issues: [FrameUsabilityIssue],
        policyVersion: String
    ) {
        self.status = status
        self.issues = issues
        self.policyVersion = policyVersion
    }

    public static let unknown = FrameUsabilityAssessment(
        status: .usable,
        issues: [],
        policyVersion: FrameUsabilityEvaluator.policyVersion
    )
}

public struct FrameUsabilityEvaluator: Sendable, Equatable {
    /// Versioned diagnostic identity so bundle readers understand what
    /// a usability warning measured.
    public static let policyVersion = "frame_usability_v1"

    /// Mean luma below which a frame is treated as too dark to be
    /// usable evidence (about 6% of the 0...255 range).
    public let darkMeanThreshold: Double
    /// Sampled-pixel darkness fraction at which the frame is
    /// unusable even if the mean is borderline.
    public let unusableDarkFraction: Double
    /// Clipped (near-white) fraction above which exposure is suspect.
    public let clippedFractionThreshold: Double
    /// Mean luma-gradient energy below which the image is treated as
    /// blur-suspect. Chosen so a modestly lit but sharp scene stays
    /// comfortably above it; only heavy smear falls below.
    public let blurGradientThreshold: Double
    /// EXIF exposure duration above which handheld motion blur is
    /// suspected even when the gradient proxy is marginal.
    public let longExposureSeconds: Double

    public init(
        darkMeanThreshold: Double = 0.06,
        unusableDarkFraction: Double = 0.7,
        clippedFractionThreshold: Double = 0.5,
        blurGradientThreshold: Double = 0.004,
        longExposureSeconds: Double = 0.05
    ) {
        self.darkMeanThreshold = darkMeanThreshold
        self.unusableDarkFraction = unusableDarkFraction
        self.clippedFractionThreshold = clippedFractionThreshold
        self.blurGradientThreshold = blurGradientThreshold
        self.longExposureSeconds = longExposureSeconds
    }

    /// Assess a candidate frame. `metrics` nil means the pixel probe
    /// could not read the buffer — the assessment then carries only the
    /// tracking signal and stays `usable`/`suspect` on that alone;
    /// "unmeasurable" is never reported as a pass through `.unusable`.
    public func assess(
        metrics: FrameUsabilityMetrics?,
        trackingState: TrackingQualityState?
    ) -> FrameUsabilityAssessment {
        var issues: [FrameUsabilityIssue] = []
        var hard = false

        if let metrics {
            if metrics.darkFraction >= unusableDarkFraction
                || metrics.meanLuminance <= darkMeanThreshold
            {
                issues.append(.tooDark)
                if metrics.darkFraction >= unusableDarkFraction {
                    hard = true
                }
            }
            if metrics.clippedFraction >= clippedFractionThreshold {
                issues.append(.overexposed)
            }
            let blurByGradient =
                metrics.gradientEnergy <= blurGradientThreshold
            let blurByExposure =
                (metrics.exposureSeconds ?? 0) >= longExposureSeconds
            if blurByGradient
                || (blurByExposure
                    && metrics.gradientEnergy
                        <= blurGradientThreshold * 2)
            {
                issues.append(.motionBlurSuspected)
            }
        }
        if let trackingState, trackingState != .normal {
            issues.append(.trackingNotNormal)
        }

        let status: FrameUsabilityStatus
        if hard {
            status = .unusable
        } else if issues.isEmpty {
            status = .usable
        } else {
            status = .suspect
        }
        return FrameUsabilityAssessment(
            status: status,
            issues: issues,
            policyVersion: Self.policyVersion
        )
    }
}
