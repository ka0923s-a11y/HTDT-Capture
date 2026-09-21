import Foundation

/// Bounded per-capture summary of retained Scene Depth evidence (#284).
/// Built incrementally at frame-commit time so the fallback gate and
/// Review never re-decode depth payloads.
public struct DepthEvidenceSufficiency: Sendable, Equatable, Codable {
    public let framesAnalyzed: Int
    public let framesWithUsableSamples: Int
    public let totalSamples: Int
    public let validSamples: Int
    public let validFraction: Double
    public let bestFrameValidFraction: Double
    public let bestFrameSpatialCoverageFraction: Double
    public let unionSpatialCoverageFraction: Double
    public let minDepthMeters: Double?
    public let maxDepthMeters: Double?
    /// Valid samples with ARKit confidence level 0.
    public let lowConfidenceValidSamples: Int
    /// Valid samples whose frame carried no confidence map.
    public let confidenceUnobservedValidSamples: Int
    /// Valid samples with ARKit confidence level >= 1 (medium/high).
    public let confidentValidSamples: Int
    /// `confidentValidSamples / confidenceObservedValidSamples`; nil
    /// when no retained frame carried a confidence map.
    public let confidentFraction: Double?


    public init(
        framesAnalyzed: Int,
        framesWithUsableSamples: Int,
        totalSamples: Int,
        validSamples: Int,
        validFraction: Double,
        bestFrameValidFraction: Double,
        bestFrameSpatialCoverageFraction: Double,
        unionSpatialCoverageFraction: Double,
        minDepthMeters: Double?,
        maxDepthMeters: Double?,
        lowConfidenceValidSamples: Int,
        confidenceUnobservedValidSamples: Int,
        confidentValidSamples: Int,
        confidentFraction: Double?
    ) {
        self.framesAnalyzed = framesAnalyzed
        self.framesWithUsableSamples = framesWithUsableSamples
        self.totalSamples = totalSamples
        self.validSamples = validSamples
        self.validFraction = validFraction
        self.bestFrameValidFraction = bestFrameValidFraction
        self.bestFrameSpatialCoverageFraction =
            bestFrameSpatialCoverageFraction
        self.unionSpatialCoverageFraction =
            unionSpatialCoverageFraction
        self.minDepthMeters = minDepthMeters
        self.maxDepthMeters = maxDepthMeters
        self.lowConfidenceValidSamples =
            lowConfidenceValidSamples
        self.confidenceUnobservedValidSamples =
            confidenceUnobservedValidSamples
        self.confidentValidSamples = confidentValidSamples
        self.confidentFraction = confidentFraction
    }


    enum CodingKeys: String, CodingKey {
        case framesAnalyzed = "frames_analyzed"
        case framesWithUsableSamples = "frames_with_usable_samples"
        case totalSamples = "total_samples"
        case validSamples = "valid_samples"
        case validFraction = "valid_fraction"
        case bestFrameValidFraction = "best_frame_valid_fraction"
        case bestFrameSpatialCoverageFraction =
            "best_frame_spatial_coverage_fraction"
        case unionSpatialCoverageFraction =
            "union_spatial_coverage_fraction"
        case minDepthMeters = "min_depth_meters"
        case maxDepthMeters = "max_depth_meters"
        case lowConfidenceValidSamples = "low_confidence_valid_samples"
        case confidenceUnobservedValidSamples =
            "confidence_unobserved_valid_samples"
        case confidentValidSamples = "confident_valid_samples"
        case confidentFraction = "confident_fraction"
    }
}

/// Accumulates depth/confidence statistics across committed frames.
/// Spatial distribution is summarized on a fixed 4x4 occupancy grid per
/// frame; the union tracks which bins any valid frame covered.
public struct DepthSufficiencyAccumulator: Sendable, Equatable {
    public static let spatialGridSide = 4
    public static var spatialBinCount: Int {
        spatialGridSide * spatialGridSide
    }

    public private(set) var framesAnalyzed = 0
    public private(set) var framesWithUsableSamples = 0
    public private(set) var totalSamples = 0
    public private(set) var validSamples = 0
    public private(set) var lowConfidenceValidSamples = 0
    public private(set) var confidenceUnobservedValidSamples = 0
    public private(set) var confidentValidSamples = 0
    public private(set) var confidenceObservedValidSamples = 0
    public private(set) var bestFrameValidFraction = 0.0
    public private(set) var bestFrameSpatialCoverage = 0.0
    public private(set) var minDepthMeters: Float?
    public private(set) var maxDepthMeters: Float?
    private var unionBins: Set<UInt8> = []

    public init() {}

    public var isEmpty: Bool { framesAnalyzed == 0 }

    public mutating func record(
        depth: DepthMapPayload,
        confidence: ConfidenceMapPayload?
    ) {
        let count = depth.width * depth.height
        guard count > 0, depth.valuesMeters.count == count else {
            return
        }
        framesAnalyzed += 1
        totalSamples += count

        let side = Self.spatialGridSide
        var frameBins = Set<UInt8>()
        var frameValid = 0
        let confidenceAligned = confidence != nil
            && confidence!.width == depth.width
            && confidence!.height == depth.height
            && confidence!.values.count == count

        for index in 0 ..< count {
            if let mask = depth.validityMask, mask[index] == 0 {
                continue
            }
            let value = depth.valuesMeters[index]
            guard value.isFinite, value > 0 else { continue }
            frameValid += 1

            let row = min(side - 1, index / depth.width * side / depth.height)
            let column = min(
                side - 1,
                (index % depth.width) * side / depth.width
            )
            frameBins.insert(UInt8(row * side + column))

            minDepthMeters = min(minDepthMeters ?? value, value)
            maxDepthMeters = max(maxDepthMeters ?? value, value)

            if let confidence, confidenceAligned {
                confidenceObservedValidSamples += 1
                if confidence.values[index] >= 1 {
                    confidentValidSamples += 1
                } else {
                    lowConfidenceValidSamples += 1
                }
            } else {
                confidenceUnobservedValidSamples += 1
            }
        }

        if frameValid > 0 {
            framesWithUsableSamples += 1
        }
        validSamples += frameValid
        unionBins.formUnion(frameBins)
        bestFrameValidFraction = max(
            bestFrameValidFraction,
            Double(frameValid) / Double(count)
        )
        bestFrameSpatialCoverage = max(
            bestFrameSpatialCoverage,
            Double(frameBins.count) / Double(Self.spatialBinCount)
        )
    }

    public var summary: DepthEvidenceSufficiency? {
        guard framesAnalyzed > 0 else { return nil }
        return DepthEvidenceSufficiency(
            framesAnalyzed: framesAnalyzed,
            framesWithUsableSamples: framesWithUsableSamples,
            totalSamples: totalSamples,
            validSamples: validSamples,
            validFraction: Double(validSamples) / Double(totalSamples),
            bestFrameValidFraction: bestFrameValidFraction,
            bestFrameSpatialCoverageFraction: bestFrameSpatialCoverage,
            unionSpatialCoverageFraction: Double(unionBins.count)
                / Double(Self.spatialBinCount),
            minDepthMeters: minDepthMeters.map(Double.init),
            maxDepthMeters: maxDepthMeters.map(Double.init),
            lowConfidenceValidSamples: lowConfidenceValidSamples,
            confidenceUnobservedValidSamples:
                confidenceUnobservedValidSamples,
            confidentValidSamples: confidentValidSamples,
            confidentFraction: confidenceObservedValidSamples > 0
                ? Double(confidentValidSamples)
                    / Double(confidenceObservedValidSamples)
                : nil
        )
    }
}

public enum DepthSufficiencyFailure: String, Sendable, Equatable {
    case noUsableSamples = "no_usable_samples"
    case validSamplesBelowMinimum = "valid_samples_below_minimum"
    case bestFrameValidFractionBelowMinimum =
        "best_frame_valid_fraction_below_minimum"
    case spatialCoverageBelowMinimum = "spatial_coverage_below_minimum"
    case confidentFractionBelowMinimum =
        "confident_fraction_below_minimum"
    case confidenceEvidenceMissing = "confidence_evidence_missing"
}

/// Versioned sufficiency gate for the mesh-fallback path (#284). Nil on
/// a requirements value means legacy `usableDepthSampleCount > 0`
/// semantics. Thresholds are provisional pending the physical benchmark
/// program (#9); they exist to stop a single low-quality pixel from
/// satisfying the fallback, and to keep low-confidence depth from
/// counting like well-supported depth.
public struct DepthFallbackSufficiencyPolicy: Sendable, Equatable {
    public let minimumValidSamples: Int
    public let minimumBestFrameValidFraction: Double
    public let minimumBestFrameSpatialCoverageFraction: Double
    /// Fraction of confidence-observed valid samples that must be at
    /// ARKit medium confidence or higher.
    public let minimumConfidentValidFraction: Double
    public let requiresConfidenceEvidence: Bool

    public init(
        minimumValidSamples: Int = 512,
        minimumBestFrameValidFraction: Double = 0.02,
        minimumBestFrameSpatialCoverageFraction: Double = 0.5,
        minimumConfidentValidFraction: Double = 0.5,
        requiresConfidenceEvidence: Bool = true
    ) {
        self.minimumValidSamples = max(0, minimumValidSamples)
        self.minimumBestFrameValidFraction = minimumBestFrameValidFraction
        self.minimumBestFrameSpatialCoverageFraction =
            minimumBestFrameSpatialCoverageFraction
        self.minimumConfidentValidFraction = minimumConfidentValidFraction
        self.requiresConfidenceEvidence = requiresConfidenceEvidence
    }

    public func failures(
        for summary: DepthEvidenceSufficiency?
    ) -> [DepthSufficiencyFailure] {
        guard let summary else {
            return [.noUsableSamples]
        }
        var failures: [DepthSufficiencyFailure] = []
        if summary.validSamples == 0 {
            failures.append(.noUsableSamples)
            return failures
        }
        if summary.validSamples < minimumValidSamples {
            failures.append(.validSamplesBelowMinimum)
        }
        if summary.bestFrameValidFraction < minimumBestFrameValidFraction {
            failures.append(.bestFrameValidFractionBelowMinimum)
        }
        if summary.bestFrameSpatialCoverageFraction
            < minimumBestFrameSpatialCoverageFraction
        {
            failures.append(.spatialCoverageBelowMinimum)
        }
        if let confidentFraction = summary.confidentFraction {
            if confidentFraction < minimumConfidentValidFraction {
                failures.append(.confidentFractionBelowMinimum)
            }
        } else if requiresConfidenceEvidence {
            failures.append(.confidenceEvidenceMissing)
        }
        return failures
    }
}
