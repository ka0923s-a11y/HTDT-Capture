import Foundation

/// One of eight principal directions around the capture start point
/// (issue #342). Shared by the visual coverage labels, the VoiceOver
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

    public func name(language: ScanMotionGuidanceLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .front: return "front"
            case .frontRight: return "front right"
            case .right: return "right"
            case .rearRight: return "rear right"
            case .rear: return "rear"
            case .rearLeft: return "rear left"
            case .left: return "left"
            case .frontLeft: return "front left"
            }
        case .japanese:
            switch self {
            case .front: return "前方"
            case .frontRight: return "右前方"
            case .right: return "右"
            case .rearRight: return "右後方"
            case .rear: return "後方"
            case .rearLeft: return "左後方"
            case .left: return "左"
            case .frontLeft: return "左前方"
            }
        }
    }
}

/// Compact non-visual description of the direction-coverage grid
/// (issue #342): one summary instead of 36 near-identical cell labels.
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

/// Non-visual description of the spatial coverage map (issue #342):
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
                x: Int(floor(position.x / coverage.cellSizeMeters)),
                z: Int(floor(position.z / coverage.cellSizeMeters))
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

/// Deterministic en/ja spoken text for the coverage summaries
/// (issue #342). Shares `ScanMotionGuidanceLanguage` so announcements
/// and on-screen values come from one vocabulary.
public enum ScanAccessibilityText {
    public static func directionCoverage(
        _ summary: DirectionCoverageAccessibilitySummary,
        language: ScanMotionGuidanceLanguage
    ) -> String {
        switch language {
        case .english:
            var parts = [
                "Direction coverage \(summary.coveragePercent) percent."
            ]
            for missing in summary.missingBands {
                let names = missing.octants
                    .map { $0.name(language: language) }
                    .joined(separator: ", ")
                parts.append(
                    "\(pitchBandName(missing.band, language: language)) missing: \(names)."
                )
            }
            if let octant = summary.nextTargetOctant,
               let gap = summary.nextTarget
            {
                parts.append(
                    "Next target: \(octant.name(language: language)), \(pitchBandName(gap.pitchBand, language: language))."
                )
            }
            return parts.joined(separator: " ")
        case .japanese:
            var parts = [
                "方向カバレッジ \(summary.coveragePercent)%。"
            ]
            for missing in summary.missingBands {
                let names = missing.octants
                    .map { $0.name(language: language) }
                    .joined(separator: "、")
                parts.append(
                    "\(pitchBandName(missing.band, language: language))が未走査：\(names)。"
                )
            }
            if let octant = summary.nextTargetOctant,
               let gap = summary.nextTarget
            {
                parts.append(
                    "次の目標：\(octant.name(language: language))（\(pitchBandName(gap.pitchBand, language: language))）。"
                )
            }
            return parts.joined(separator: " ")
        }
    }

    public static func spatialCoverage(
        _ summary: SpatialCoverageAccessibilitySummary,
        language: ScanMotionGuidanceLanguage
    ) -> String {
        switch language {
        case .english:
            guard summary.hasAnyObservation else {
                return "No spatial regions observed yet."
            }
            var parts = [
                "Spatial coverage: \(summary.observedRegionCount) observed, \(summary.weakRegionCount) weak, \(summary.unknownRegionCount) unknown."
            ]
            if summary.declaredRegionCount > 0 {
                parts.append(
                    "\(summary.declaredRegionCount) marked intentional."
                )
            }
            if !summary.priorityWeakRegions.isEmpty {
                let labels = summary.priorityWeakRegions
                    .map { regionLabel($0, language: language) }
                    .joined(separator: ", ")
                parts.append("Weakest regions: \(labels).")
            }
            if summary.usesDepthFallback {
                parts.append(
                    "Observations are depth-only until mesh or room-model data resumes."
                )
            }
            if let camera = summary.cameraRegion {
                var cameraText =
                    "Camera at \(camera.octant.name(language: language)) \(camera.distanceBucket.name(language: language))"
                if let heading = summary.cameraHeadingOctant {
                    cameraText +=
                        ", facing \(heading.name(language: language))"
                }
                parts.append(cameraText + ".")
            }
            return parts.joined(separator: " ")
        case .japanese:
            guard summary.hasAnyObservation else {
                return "まだ空間領域は観測されていません。"
            }
            var parts = [
                "空間カバレッジ：観測済み\(summary.observedRegionCount)、弱い領域\(summary.weakRegionCount)、未観測\(summary.unknownRegionCount)。"
            ]
            if summary.declaredRegionCount > 0 {
                parts.append(
                    "意図的として宣言済み\(summary.declaredRegionCount)。"
                )
            }
            if !summary.priorityWeakRegions.isEmpty {
                let labels = summary.priorityWeakRegions
                    .map { regionLabel($0, language: language) }
                    .joined(separator: "、")
                parts.append("最も弱い領域：\(labels)。")
            }
            if summary.usesDepthFallback {
                parts.append(
                    "メッシュまたはルームモデルが再開するまでは深度のみの観測です。"
                )
            }
            if let camera = summary.cameraRegion {
                var cameraText =
                    "現在位置：\(camera.octant.name(language: language))（\(camera.distanceBucket.name(language: language))）"
                if let heading = summary.cameraHeadingOctant {
                    cameraText +=
                        "、向き：\(heading.name(language: language))"
                }
                parts.append(cameraText + "。")
            }
            return parts.joined(separator: " ")
        }
    }

    /// Short bounded label for one region: direction + distance
    /// ("front left near").
    public static func regionLabel(
        _ descriptor:
            SpatialCoverageAccessibilitySummary.RegionDescriptor,
        language: ScanMotionGuidanceLanguage
    ) -> String {
        let direction = descriptor.octant.name(language: language)
        let distance = descriptor.distanceBucket
            .name(language: language)
        switch language {
        case .english:
            return "\(direction) \(distance)"
        case .japanese:
            return "\(direction)（\(distance)）"
        }
    }

    /// Band names matching the review sheet's deterministic vocabulary.
    public static func pitchBandName(
        _ band: ScanCoveragePitchBand,
        language: ScanMotionGuidanceLanguage
    ) -> String {
        switch (language, band) {
        case (.english, .low): return "lower room"
        case (.english, .level): return "level view"
        case (.english, .high): return "upper room"
        case (.japanese, .low): return "下部"
        case (.japanese, .level): return "水平"
        case (.japanese, .high): return "上部"
        }
    }
}

private extension SpatialCoverageDistanceBucket {
    func name(language: ScanMotionGuidanceLanguage) -> String {
        switch (language, self) {
        case (.english, .near): return "near"
        case (.english, .medium): return "medium distance"
        case (.english, .far): return "far"
        case (.japanese, .near): return "近距離"
        case (.japanese, .medium): return "中距離"
        case (.japanese, .far): return "遠距離"
        }
    }
}
