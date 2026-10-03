import Foundation

/// One of eight principal directions around the capture start point
/// (issue bolph71656-ai/HTDT-Capture#342). Shared by the visual coverage labels, the VoiceOver
/// direction summary, and the spatial-region readout so every channel
/// names a direction identically.
public enum ScanDirectionOctant:
    String,
    Sendable,
    Equatable,
    Hashable,
    CaseIterable
{
    case front
    case frontRight
    case right
    case rearRight
    case rear
    case rearLeft
    case left
    case frontLeft

    /// Buckets an azimuth angle measured clockwise from +z (front)
    /// into 45° sectors centered on the principal directions.
    public init(azimuthRadians: Double) {
        guard azimuthRadians.isFinite else {
            self = .front
            return
        }
        let fullTurn = 2 * Double.pi
        var shifted = (azimuthRadians + Double.pi / 8)
            .truncatingRemainder(dividingBy: fullTurn)
        if shifted < 0 {
            shifted += fullTurn
        }
        let index = Int(floor(shifted / (Double.pi / 4))) % 8
        self = ScanDirectionOctant.allCases[index]
    }

    /// Buckets a direction-grid sector index. With the 12-sector grid
    /// adjacent sectors share a principal direction via rounding, so
    /// the spoken vocabulary matches the visual cell labels exactly.
    public init(sectorIndex: Int, sectorCount: Int) {
        precondition(sectorCount > 0)
        let normalized = ((sectorIndex % sectorCount) + sectorCount)
            % sectorCount
        let index = Int(
            (Double(normalized) * 8.0 / Double(sectorCount)).rounded()
        ) % 8
        self = ScanDirectionOctant.allCases[index]
    }

    /// Deterministic readout order: clockwise from front.
    var sortOrder: Int {
        ScanDirectionOctant.allCases.firstIndex(of: self) ?? 0
    }

    public var name: String {
        switch self {
        case .front: return String(localized: "front")
        case .frontRight: return String(localized: "front right")
        case .right: return String(localized: "right")
        case .rearRight: return String(localized: "rear right")
        case .rear: return String(localized: "rear")
        case .rearLeft: return String(localized: "rear left")
        case .left: return String(localized: "left")
        case .frontLeft: return String(localized: "front left")
        }
    }
}

/// Compact non-visual description of the direction-coverage grid
/// (issue bolph71656-ai/HTDT-Capture#342): one summary instead of 36 near-identical cell labels.
public struct DirectionCoverageAccessibilitySummary:
    Sendable,
    Equatable
{
    /// Missing directions grouped per band, in the grid's band order
    /// (low, level, high). Empty when every cell is observed.
    public struct BandMissing: Sendable, Equatable {
        public let band: ScanCoveragePitchBand
        /// Deduplicated principal directions, clockwise from front.
        public let octants: [ScanDirectionOctant]

        public init(
            band: ScanCoveragePitchBand,
            octants: [ScanDirectionOctant]
        ) {
            self.band = band
            self.octants = octants
        }
    }

    /// Percent of observed cells, rounded.
    public let coveragePercent: Int
    public let missingBands: [BandMissing]
    /// The same gap the visual target highlight uses — nil when no
    /// deterministic next target exists.
    public let nextTarget: ScanCoverageGap?
    /// Principal direction of `nextTarget`, for one-line readouts.
    public let nextTargetOctant: ScanDirectionOctant?

    public init(coverage: ScanCoverageSummary) {
        coveragePercent = Int(
            (coverage.coverageFraction * 100).rounded()
        )
        missingBands = [ScanCoveragePitchBand.low,
                        .level,
                        .high].compactMap { band in
            var seen = Set<ScanDirectionOctant>()
            var octants: [ScanDirectionOctant] = []
            for sector in 0..<coverage.sectorCount {
                guard !coverage.isObserved(
                    sectorIndex: sector,
                    pitchBand: band
                ) else {
                    continue
                }
                let octant = ScanDirectionOctant(
                    sectorIndex: sector,
                    sectorCount: coverage.sectorCount
                )
                if seen.insert(octant).inserted {
                    octants.append(octant)
                }
            }
            octants.sort { $0.sortOrder < $1.sortOrder }
            return octants.isEmpty
                ? nil
                : BandMissing(band: band, octants: octants)
        }
        nextTarget = coverage.recommendedGap
        nextTargetOctant = coverage.recommendedGap.map {
            ScanDirectionOctant(
                sectorIndex: $0.sectorIndex,
                sectorCount: coverage.sectorCount
            )
        }
    }
}

/// Non-visual description of the spatial coverage map (issue bolph71656-ai/HTDT-Capture#342):
/// observed/weak/unknown counts, prioritized weak regions with
/// bounded direction+distance labels, and the camera's own position.
public struct SpatialCoverageAccessibilitySummary:
    Sendable,
    Equatable
{
    /// A region rendered for spoken/readout use.
    public struct RegionDescriptor: Sendable, Equatable {
        public let key: SpatialCoverageCellKey
        /// Principal direction from the capture start point.
        public let octant: ScanDirectionOctant
        /// Distance bucket from the latest camera position.
        public let distanceBucket: SpatialCoverageDistanceBucket

        public init(
            key: SpatialCoverageCellKey,
            octant: ScanDirectionOctant,
            distanceBucket: SpatialCoverageDistanceBucket
        ) {
            self.key = key
            self.octant = octant
            self.distanceBucket = distanceBucket
        }
    }

    public let observedRegionCount: Int
    public let weakRegionCount: Int
    /// Cells inside the visible bounds with no recorded observation.
    public let unknownRegionCount: Int
    /// Weak regions not declared intentional, least-observed first,
    /// bounded for a short spoken readout.
    public let priorityWeakRegions: [RegionDescriptor]
    /// Regions the operator marked intentionally unresolved; excluded
    /// from `priorityWeakRegions` but still counted here.
    public let declaredRegionCount: Int
    /// Camera position relative to the capture start point.
    public let cameraRegion: RegionDescriptor?
    /// Direction the camera currently faces relative to start yaw.
    public let cameraHeadingOctant: ScanDirectionOctant?
    /// True while depth-only fallback observations are the only live
    /// geometric input — surfaced so a readout never implies more
    /// geometric completeness than the evidence supports.
    public let usesDepthFallback: Bool
    public let hasAnyObservation: Bool

    /// Maximum weak regions included in the prioritized readout.
    public static let maximumPrioritizedRegions = 4

    public init(
        coverage: SpatialScanCoverageSummary,
        declaredRegionKeys: Set<SpatialCoverageCellKey> = []
    ) {
        observedRegionCount = coverage.observedRegionCount
        weakRegionCount = coverage.weakRegionCount
        unknownRegionCount = coverage.displayUnknownRegionCount
        usesDepthFallback = coverage.usesDepthFallback
        hasAnyObservation = !coverage.regions.isEmpty

        var declaredCount = 0
        var candidates: [SpatialCoverageRegion] = []
        for region in coverage.regions {
            guard coverage.displayBounds?.contains(region.key) ?? true
            else {
                continue
            }
            guard region.classification == .weak else {
                continue
            }
            if declaredRegionKeys.contains(region.key) {
                declaredCount += 1
            } else {
                candidates.append(region)
            }
        }
        // Weak regions the operator intentionally left unresolved are
        // also declared — count them with the declared set so the
        // prioritized list only names actionable cells.
        for region in coverage.regions {
            guard coverage.displayBounds?.contains(region.key) ?? true,
                  region.classification == .unknown,
                  declaredRegionKeys.contains(region.key)
            else {
                continue
            }
            declaredCount += 1
        }
        declaredRegionCount = declaredCount
        priorityWeakRegions = candidates
            .sorted { lhs, rhs in
                if lhs.observationCount != rhs.observationCount {
                    return lhs.observationCount < rhs.observationCount
                }
                return lhs.key < rhs.key
            }
            .prefix(Self.maximumPrioritizedRegions)
            .map { region in
                Self.descriptor(for: region, coverage: coverage)
            }

        if let position = coverage.currentCameraPosition {
            let cellKey = SpatialCoverageCellKey(
                x: floorToIntClamped(
                    position.x / coverage.cellSizeMeters
                ),
                z: floorToIntClamped(
                    position.z / coverage.cellSizeMeters
                )
            )
            cameraRegion = RegionDescriptor(
                key: cellKey,
                octant: ScanDirectionOctant(
                    azimuthRadians: atan2(position.x, position.z)
                ),
                distanceBucket: SpatialCoverageDistanceBucket.bucket(
                    forMeters: hypot(position.x, position.z)
                )
            )
        } else {
            cameraRegion = nil
        }
        cameraHeadingOctant = coverage.currentRelativeHeadingRadians.map {
            ScanDirectionOctant(azimuthRadians: $0)
        }
    }

    static func descriptor(
        for region: SpatialCoverageRegion,
        coverage: SpatialScanCoverageSummary
    ) -> RegionDescriptor {
        let centerX = (Double(region.key.x) + 0.5)
            * coverage.cellSizeMeters
        let centerZ = (Double(region.key.z) + 0.5)
            * coverage.cellSizeMeters
        return RegionDescriptor(
            key: region.key,
            octant: ScanDirectionOctant(
                azimuthRadians: atan2(centerX, centerZ)
            ),
            distanceBucket: region.latestDistanceBucket
        )
    }
}

/// Spoken text for the coverage summaries (issue bolph71656-ai/HTDT-Capture#342). All copy
/// resolves through `Localizable.strings` (legacy bolph71656-ai/HTDT-Capture#399) — VoiceOver uses the
/// same authority as the rest of the app.
public enum ScanAccessibilityText {
    public static func directionCoverage(
        _ summary: DirectionCoverageAccessibilitySummary
    ) -> String {
        var parts = [
            String(
                format: String(
                    localized: "Direction coverage %d percent."
                ),
                summary.coveragePercent
            )
        ]
        for missing in summary.missingBands {
            let names = missing.octants
                .map(\.name)
                .joined(separator: String(localized: ", "))
            parts.append(
                String(
                    format: String(localized: "%@ missing: %@."),
                    pitchBandName(missing.band),
                    names
                )
            )
        }
        if let octant = summary.nextTargetOctant,
           let gap = summary.nextTarget
        {
            parts.append(
                String(
                    format: String(localized: "Next target: %@, %@."),
                    octant.name,
                    pitchBandName(gap.pitchBand)
                )
            )
        }
        return parts.joined(separator: " ")
    }

    public static func spatialCoverage(
        _ summary: SpatialCoverageAccessibilitySummary
    ) -> String {
        guard summary.hasAnyObservation else {
            return String(
                localized: "No spatial regions observed yet."
            )
        }
        var parts = [
            String(
                format: String(
                    localized: "Spatial coverage: %d observed, %d weak, %d unknown."
                ),
                summary.observedRegionCount,
                summary.weakRegionCount,
                summary.unknownRegionCount
            )
        ]
        if summary.declaredRegionCount > 0 {
            parts.append(
                String(
                    format: String(
                        localized: "%d marked intentional."
                    ),
                    summary.declaredRegionCount
                )
            )
        }
        if !summary.priorityWeakRegions.isEmpty {
            let labels = summary.priorityWeakRegions
                .map(regionLabel(_:))
                .joined(separator: String(localized: ", "))
            parts.append(
                String(
                    format: String(localized: "Weakest regions: %@."),
                    labels
                )
            )
        }
        if summary.usesDepthFallback {
            parts.append(
                String(
                    localized: "Observations are depth-only until mesh or room-model data resumes."
                )
            )
        }
        if let camera = summary.cameraRegion {
            let headingText = summary.cameraHeadingOctant.map {
                String(
                    format: String(localized: ", facing %@"),
                    $0.name
                )
            } ?? ""
            parts.append(
                String(
                    format: String(
                        localized: "Camera at %1$@ %2$@%3$@."
                    ),
                    camera.octant.name,
                    camera.distanceBucket.name,
                    headingText
                )
            )
        }
        return parts.joined(separator: " ")
    }

    /// Short bounded label for one region: direction + distance
    /// ("front left near").
    public static func regionLabel(
        _ descriptor:
            SpatialCoverageAccessibilitySummary.RegionDescriptor
    ) -> String {
        String(
            format: String(localized: "%1$@ %2$@"),
            descriptor.octant.name,
            descriptor.distanceBucket.name
        )
    }

    /// Band names matching the review sheet's deterministic vocabulary.
    public static func pitchBandName(
        _ band: ScanCoveragePitchBand
    ) -> String {
        switch band {
        case .low: return String(localized: "lower room")
        case .level: return String(localized: "level view")
        case .high: return String(localized: "upper room")
        }
    }
}

private extension SpatialCoverageDistanceBucket {
    var name: String {
        switch self {
        case .near: return String(localized: "near")
        case .medium: return String(localized: "medium distance")
        case .far: return String(localized: "far")
        }
    }
}
