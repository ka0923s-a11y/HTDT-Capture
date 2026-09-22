import Foundation

/// Bounded record of RoomPlan coaching/instruction transitions (#260).
/// Only transitions are retained — repeated identical instructions merge
/// into one transition with a count, so per-frame coaching cannot grow
/// the history.
public struct RoomPlanGuidanceObservation: Sendable, Equatable {
    public let instruction: String
    public let sessionTimestampSeconds: Double

    public init(
        instruction: String,
        sessionTimestampSeconds: Double
    ) {
        self.instruction = instruction
        self.sessionTimestampSeconds =
            sessionTimestampSeconds
    }

}

public struct RoomPlanGuidanceTracker: Sendable, Equatable {
    public static let transitionLimit = 128

    public private(set) var transitions: [RoomPlanGuidanceTransition] = []
    public private(set) var truncated = false
    private var lastInstruction: String?

    public init() {}

    public mutating func record(_ observation: RoomPlanGuidanceObservation) {
        guard observation.sessionTimestampSeconds.isFinite else { return }
        if observation.instruction == lastInstruction,
           var last = transitions.last
        {
            last = RoomPlanGuidanceTransition(
                instruction: last.instruction,
                firstSessionTimestampSeconds: last.firstSessionTimestampSeconds,
                lastSessionTimestampSeconds: observation
                    .sessionTimestampSeconds,
                count: last.count + 1
            )
            transitions[transitions.count - 1] = last
            return
        }
        lastInstruction = observation.instruction
        guard transitions.count < Self.transitionLimit else {
            truncated = true
            return
        }
        transitions.append(
            RoomPlanGuidanceTransition(
                instruction: observation.instruction,
                firstSessionTimestampSeconds:
                    observation.sessionTimestampSeconds,
                lastSessionTimestampSeconds:
                    observation.sessionTimestampSeconds,
                count: 1
            )
        )
    }

    /// The instruction currently shown by the framework, if any has been
    /// recorded since the last transition reset.
    public var currentInstruction: String? {
        lastInstruction
    }

    public func history() -> RoomPlanGuidanceHistory {
        RoomPlanGuidanceHistory(
            source: .roomPlanDelegate,
            transitions: transitions,
            truncated: truncated
        )
    }
}

public enum RoomPlanGuidanceSource: String, Sendable, Equatable, Codable {
    case roomPlanDelegate = "roomplan_delegate"
    case unavailable
}

public struct RoomPlanGuidanceTransition: Sendable, Equatable, Codable {
    public let instruction: String
    public let firstSessionTimestampSeconds: Double
    public let lastSessionTimestampSeconds: Double
    public let count: Int


    public init(
        instruction: String,
        firstSessionTimestampSeconds: Double,
        lastSessionTimestampSeconds: Double,
        count: Int
    ) {
        self.instruction = instruction
        self.firstSessionTimestampSeconds =
            firstSessionTimestampSeconds
        self.lastSessionTimestampSeconds =
            lastSessionTimestampSeconds
        self.count = count
    }


    enum CodingKeys: String, CodingKey {
        case instruction
        case firstSessionTimestampSeconds = "first_ts"
        case lastSessionTimestampSeconds = "last_ts"
        case count
    }
}

public struct RoomPlanGuidanceHistory: Sendable, Equatable, Codable {
    public let source: RoomPlanGuidanceSource
    public let transitions: [RoomPlanGuidanceTransition]
    public let truncated: Bool


    public init(
        source: RoomPlanGuidanceSource,
        transitions: [RoomPlanGuidanceTransition],
        truncated: Bool
    ) {
        self.source = source
        self.transitions = transitions
        self.truncated = truncated
    }


    enum CodingKeys: String, CodingKey {
        case source
        case transitions
        case truncated
    }
}

/// Mesh anchor lifecycle diagnostics (#268). Events are bounded: at most
/// `uniqueAnchorLimit` distinct anchors and `eventLimit` total events are
/// retained; beyond that only aggregate counters advance so the summary
/// stays deterministic.
public enum MeshAnchorLifecycleKind: String, Sendable, Equatable, Codable {
    case added
    case updated
    case removed
}

public struct MeshAnchorLifecycleTracker: Sendable, Equatable {
    public static let uniqueAnchorLimit = 512
    public static let eventLimit = 8192

    public private(set) var addedCount = 0
    public private(set) var updatedCount = 0
    public private(set) var removedCount = 0
    public private(set) var uniqueAnchorLimitExceeded = false
    public private(set) var eventLimitReached = false
    public private(set) var lastUpdateTimestampSeconds: Double?
    private var updateCounts: [UUID: Int] = [:]
    private var activeAnchors: Set<UUID> = []

    public init() {}

    public mutating func record(
        _ kind: MeshAnchorLifecycleKind,
        anchorID: UUID,
        sessionTimestampSeconds: Double
    ) {
        guard sessionTimestampSeconds.isFinite else { return }
        let totalEvents = addedCount + updatedCount + removedCount
        guard totalEvents < Self.eventLimit else {
            eventLimitReached = true
            return
        }

        switch kind {
        case .added:
            addedCount += 1
            activeAnchors.insert(anchorID)
            if updateCounts[anchorID] == nil {
                if updateCounts.count >= Self.uniqueAnchorLimit {
                    uniqueAnchorLimitExceeded = true
                } else {
                    updateCounts[anchorID] = 0
                }
            }
        case .updated:
            updatedCount += 1
            lastUpdateTimestampSeconds = sessionTimestampSeconds
            if updateCounts[anchorID] == nil {
                if updateCounts.count >= Self.uniqueAnchorLimit {
                    uniqueAnchorLimitExceeded = true
                } else {
                    updateCounts[anchorID] = 0
                }
            }
            if let count = updateCounts[anchorID] {
                updateCounts[anchorID] = count + 1
            }
        case .removed:
            removedCount += 1
            activeAnchors.remove(anchorID)
        }
    }

    public func summary(
        endSessionTimestampSeconds: Double?
    ) -> MeshAnchorLifecycleSummary {
        var once = 0
        var twoToFour = 0
        var fivePlus = 0
        var neverUpdated = 0
        for (_, count) in updateCounts {
            switch count {
            case 0: neverUpdated += 1
            case 1: once += 1
            case 2 ... 4: twoToFour += 1
            default: fivePlus += 1
            }
        }
        var secondsSinceLastUpdate: Double?
        if let endSessionTimestampSeconds,
           let lastUpdateTimestampSeconds
        {
            secondsSinceLastUpdate = max(
                0,
                endSessionTimestampSeconds - lastUpdateTimestampSeconds
            )
        }
        return MeshAnchorLifecycleSummary(
            addedCount: addedCount,
            updatedCount: updatedCount,
            removedCount: removedCount,
            uniqueAnchorsObserved: updateCounts.count,
            finalActiveAnchors: activeAnchors.count,
            anchorsUpdatedOnceCount: once,
            anchorsUpdatedTwoToFourCount: twoToFour,
            anchorsUpdatedFiveOrMoreCount: fivePlus,
            anchorsNeverUpdatedCount: neverUpdated,
            secondsSinceLastUpdate: secondsSinceLastUpdate,
            truncated: uniqueAnchorLimitExceeded || eventLimitReached
        )
    }
}

public struct MeshAnchorLifecycleSummary: Sendable, Equatable, Codable {
    public let addedCount: Int
    public let updatedCount: Int
    public let removedCount: Int
    public let uniqueAnchorsObserved: Int
    public let finalActiveAnchors: Int
    public let anchorsUpdatedOnceCount: Int
    public let anchorsUpdatedTwoToFourCount: Int
    public let anchorsUpdatedFiveOrMoreCount: Int
    public let anchorsNeverUpdatedCount: Int
    public let secondsSinceLastUpdate: Double?
    public let truncated: Bool


    public init(
        addedCount: Int,
        updatedCount: Int,
        removedCount: Int,
        uniqueAnchorsObserved: Int,
        finalActiveAnchors: Int,
        anchorsUpdatedOnceCount: Int,
        anchorsUpdatedTwoToFourCount: Int,
        anchorsUpdatedFiveOrMoreCount: Int,
        anchorsNeverUpdatedCount: Int,
        secondsSinceLastUpdate: Double?,
        truncated: Bool
    ) {
        self.addedCount = addedCount
        self.updatedCount = updatedCount
        self.removedCount = removedCount
        self.uniqueAnchorsObserved = uniqueAnchorsObserved
        self.finalActiveAnchors = finalActiveAnchors
        self.anchorsUpdatedOnceCount = anchorsUpdatedOnceCount
        self.anchorsUpdatedTwoToFourCount =
            anchorsUpdatedTwoToFourCount
        self.anchorsUpdatedFiveOrMoreCount =
            anchorsUpdatedFiveOrMoreCount
        self.anchorsNeverUpdatedCount = anchorsNeverUpdatedCount
        self.secondsSinceLastUpdate = secondsSinceLastUpdate
        self.truncated = truncated
    }


    enum CodingKeys: String, CodingKey {
        case addedCount = "added_count"
        case updatedCount = "updated_count"
        case removedCount = "removed_count"
        case uniqueAnchorsObserved = "unique_anchors_observed"
        case finalActiveAnchors = "final_active_anchors"
        case anchorsUpdatedOnceCount = "anchors_updated_once_count"
        case anchorsUpdatedTwoToFourCount = "anchors_updated_2_4_count"
        case anchorsUpdatedFiveOrMoreCount = "anchors_updated_5plus_count"
        case anchorsNeverUpdatedCount = "anchors_never_updated_count"
        case secondsSinceLastUpdate = "seconds_since_last_update"
        case truncated
    }
}

/// The advisory coverage/guidance context captured at the accepted End
/// boundary (#223). Built from the ephemeral trackers right before the
/// RoomPlan session stops so the finalized bundle retains what the HUD
/// showed.
public struct CaptureEndCoverageSummary: Sendable, Equatable, Codable {
    public let algorithm: String
    public let algorithmVersion: String
    public let endSessionTimestampSeconds: Double?
    public let sectorCount: Int
    public let minimumSamplesPerCell: Int
    public let cellSampleCounts: [Int]
    public let coverageFraction: Double
    public let pitchBandFractions: [String: Double]
    public let weakCells: [String]
    public let latestTrackingState: TrackingQualityState?
    public let latestTrackingReason: String?
    public let latestMeshAnchorCount: Int
    public let latestHasSceneDepth: Bool
    public let spatialCellSizeMeters: Double
    public let observedRegionCount: Int
    public let weakRegionCount: Int
    public let displayUnknownRegionCount: Int
    public let usesDepthFallback: Bool
    public let meshAvailabilityState: String
    public let weakRegionKeys: [String]
    public let geometryEvidenceMode: String
    public let movementCapability: String
    public let guidanceCompletedAttempts: Int
    public let guidanceMaximumAttempts: Int
    public let actionableWeakRegionCount: Int
    public let saturatedWeakRegionCount: Int
    public let guidanceComplete: Bool
    /// Why `guidanceComplete` fired (issue #296): a
    /// `ScanGuidanceCompletionSource` raw value. Optional so payloads
    /// persisted before the source was tracked still decode; nil means
    /// "recorded by an older schema", never "observed".
    public let guidanceCompletionSource: String?
    // Optional scope/convention markers added for #336/#343/#347.
    // Optionals keep `htdt.capture.advisory` v1.0.0 payloads written
    // before these fields existed decodable.
    /// Retained weak regions outside the operator's final display
    /// window (#347): the global-vs-local split is explicit so the
    /// summary cannot be misread as viewport-scoped.
    public let remoteWeakRegionCount: Int?
    /// Live spatial coverage region budget that was configured (#336).
    public let spatialMaxRegionCount: Int?
    /// Peak retained region count observed during the scan (#336).
    public let spatialPeakRegionCount: Int?
    /// Number of retained regions dropped by the capacity budget
    /// (#336); nil/zero means nothing was forgotten.
    public let spatialRegionEvictionCount: Int?
    /// True when the spatial coverage map was saturated at End (#336).
    public let spatialCapacitySaturated: Bool?
    /// Direction-reference convention the coverage labels were
    /// rendered in (#343): `start_relative` means sectors/regions are
    /// named relative to the operator's arbitrary start heading, never
    /// a room authority.
    public let directionReference: String?


    public init(
        algorithm: String,
        algorithmVersion: String,
        endSessionTimestampSeconds: Double?,
        sectorCount: Int,
        minimumSamplesPerCell: Int,
        cellSampleCounts: [Int],
        coverageFraction: Double,
        pitchBandFractions: [String: Double],
        weakCells: [String],
        latestTrackingState: TrackingQualityState?,
        latestTrackingReason: String?,
        latestMeshAnchorCount: Int,
        latestHasSceneDepth: Bool,
        spatialCellSizeMeters: Double,
        observedRegionCount: Int,
        weakRegionCount: Int,
        displayUnknownRegionCount: Int,
        usesDepthFallback: Bool,
        meshAvailabilityState: String,
        weakRegionKeys: [String],
        geometryEvidenceMode: String,
        movementCapability: String,
        guidanceCompletedAttempts: Int,
        guidanceMaximumAttempts: Int,
        actionableWeakRegionCount: Int,
        saturatedWeakRegionCount: Int,
        guidanceComplete: Bool,
        guidanceCompletionSource: String? = nil
        guidanceComplete: Bool,
        remoteWeakRegionCount: Int? = nil,
        spatialMaxRegionCount: Int? = nil,
        spatialPeakRegionCount: Int? = nil,
        spatialRegionEvictionCount: Int? = nil,
        spatialCapacitySaturated: Bool? = nil,
        directionReference: String? = nil
    ) {
        self.algorithm = algorithm
        self.algorithmVersion = algorithmVersion
        self.endSessionTimestampSeconds =
            endSessionTimestampSeconds
        self.sectorCount = sectorCount
        self.minimumSamplesPerCell = minimumSamplesPerCell
        self.cellSampleCounts = cellSampleCounts
        self.coverageFraction = coverageFraction
        self.pitchBandFractions = pitchBandFractions
        self.weakCells = weakCells
        self.latestTrackingState = latestTrackingState
        self.latestTrackingReason = latestTrackingReason
        self.latestMeshAnchorCount = latestMeshAnchorCount
        self.latestHasSceneDepth = latestHasSceneDepth
        self.spatialCellSizeMeters = spatialCellSizeMeters
        self.observedRegionCount = observedRegionCount
        self.weakRegionCount = weakRegionCount
        self.displayUnknownRegionCount =
            displayUnknownRegionCount
        self.usesDepthFallback = usesDepthFallback
        self.meshAvailabilityState = meshAvailabilityState
        self.weakRegionKeys = weakRegionKeys
        self.geometryEvidenceMode = geometryEvidenceMode
        self.movementCapability = movementCapability
        self.guidanceCompletedAttempts = guidanceCompletedAttempts
        self.guidanceMaximumAttempts = guidanceMaximumAttempts
        self.actionableWeakRegionCount =
            actionableWeakRegionCount
        self.saturatedWeakRegionCount =
            saturatedWeakRegionCount
        self.guidanceComplete = guidanceComplete
        self.guidanceCompletionSource = guidanceCompletionSource
        self.remoteWeakRegionCount = remoteWeakRegionCount
        self.spatialMaxRegionCount = spatialMaxRegionCount
        self.spatialPeakRegionCount = spatialPeakRegionCount
        self.spatialRegionEvictionCount =
            spatialRegionEvictionCount
        self.spatialCapacitySaturated = spatialCapacitySaturated
        self.directionReference = directionReference
    }


    enum CodingKeys: String, CodingKey {
        case algorithm
        case algorithmVersion = "algorithm_version"
        case endSessionTimestampSeconds = "end_session_timestamp_seconds"
        case sectorCount = "sector_count"
        case minimumSamplesPerCell = "minimum_samples_per_cell"
        case cellSampleCounts = "cell_sample_counts"
        case coverageFraction = "coverage_fraction"
        case pitchBandFractions = "pitch_band_fractions"
        case weakCells = "weak_cells"
        case latestTrackingState = "latest_tracking_state"
        case latestTrackingReason = "latest_tracking_reason"
        case latestMeshAnchorCount = "latest_mesh_anchor_count"
        case latestHasSceneDepth = "latest_has_scene_depth"
        case spatialCellSizeMeters = "spatial_cell_size_meters"
        case observedRegionCount = "observed_region_count"
        case weakRegionCount = "weak_region_count"
        case displayUnknownRegionCount = "display_unknown_region_count"
        case usesDepthFallback = "uses_depth_fallback"
        case meshAvailabilityState = "mesh_availability_state"
        case weakRegionKeys = "weak_region_keys"
        case geometryEvidenceMode = "geometry_evidence_mode"
        case movementCapability = "movement_capability"
        case guidanceCompletedAttempts = "guidance_completed_attempts"
        case guidanceMaximumAttempts = "guidance_maximum_attempts"
        case actionableWeakRegionCount = "actionable_weak_region_count"
        case saturatedWeakRegionCount = "saturated_weak_region_count"
        case guidanceComplete = "guidance_complete"
        case guidanceCompletionSource = "guidance_completion_source"
        case remoteWeakRegionCount = "remote_weak_region_count"
        case spatialMaxRegionCount = "spatial_max_region_count"
        case spatialPeakRegionCount = "spatial_peak_region_count"
        case spatialRegionEvictionCount = "spatial_region_eviction_count"
        case spatialCapacitySaturated = "spatial_capacity_saturated"
        case directionReference = "direction_reference"
    }
}

/// Built at the accepted End boundary and handed to the working-set
/// store so seal can persist it. All sections are optional so a partial
/// advisory context still produces a valid payload.
public struct CaptureAdvisoryReport: Sendable, Equatable, Codable {
    public static let schema = "htdt.capture.advisory"
    public static let schemaVersion = "1.0.0"
    public static let payloadPath = "quality/capture-advisory.json"

    public let schema: String
    public let schemaVersion: String
    public let captureSessionID: CaptureSessionID
    public let generatedAtUTC: String
    /// Advisory-only marker: the payload must never be read as canonical
    /// geometry/truth authority.
    public let authority: String
    public let endCoverage: CaptureEndCoverageSummary?
    public let taskCompleteness: CaptureTaskCompletenessReport?
    public let roomPlanGuidance: RoomPlanGuidanceHistory?
    public let meshLifecycle: MeshAnchorLifecycleSummary?
    public let depthSufficiency: DepthEvidenceSufficiency?
    public let conflicts: CaptureConflictReport?
    public let geometryConsistency: RoomPlanMeshConsistencyReport?

    public init(
        captureSessionID: CaptureSessionID,
        generatedAtUTC: String,
        endCoverage: CaptureEndCoverageSummary? = nil,
        taskCompleteness: CaptureTaskCompletenessReport? = nil,
        roomPlanGuidance: RoomPlanGuidanceHistory? = nil,
        meshLifecycle: MeshAnchorLifecycleSummary? = nil,
        depthSufficiency: DepthEvidenceSufficiency? = nil,
        conflicts: CaptureConflictReport? = nil,
        geometryConsistency: RoomPlanMeshConsistencyReport? = nil
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureSessionID = captureSessionID
        self.generatedAtUTC = generatedAtUTC
        self.authority = "capture_app_derived"
        self.endCoverage = endCoverage
        self.taskCompleteness = taskCompleteness
        self.roomPlanGuidance = roomPlanGuidance
        self.meshLifecycle = meshLifecycle
        self.depthSufficiency = depthSufficiency
        self.conflicts = conflicts
        self.geometryConsistency = geometryConsistency
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureSessionID = "capture_session_id"
        case generatedAtUTC = "generated_at_utc"
        case authority
        case endCoverage = "end_coverage"
        case taskCompleteness = "task_completeness"
        case roomPlanGuidance = "roomplan_guidance"
        case meshLifecycle = "mesh_lifecycle"
        case depthSufficiency = "depth_sufficiency"
        case conflicts
        case geometryConsistency = "geometry_consistency"
    }
}
