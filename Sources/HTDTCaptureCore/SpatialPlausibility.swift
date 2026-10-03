import Foundation

/// Advisory spatial-plausibility context for Review (legacy bolph71656-ai/HTDT-Capture#247). Built from
/// accepted persisted geometry only — mesh-anchor world bounds decoded
/// from `mesh/geometry/*.meshbin` plus `mesh/anchors.json` transforms,
/// and the captured-room dimension summary. Every field is optional so
/// missing geometry reports "analysis unavailable" instead of a false
/// pass.
public struct SpatialPlausibilityContext: Sendable, Equatable {
    /// Per-anchor world-space bounds of committed mesh geometry.
    /// Empty when no usable mesh evidence exists.
    public var meshBounds: [SpatialAxisBounds]
    /// Lowest observed mesh vertex height — a broad floor reference.
    public var floorYMeters: Float?
    /// RoomPlan content extents, when the captured room was processed.
    public var roomDimensionsMeters: CapturedRoomDimensionsSummary?

    public init(
        meshBounds: [SpatialAxisBounds] = [],
        floorYMeters: Float? = nil,
        roomDimensionsMeters: CapturedRoomDimensionsSummary? = nil
    ) {
        self.meshBounds = meshBounds
        self.floorYMeters = floorYMeters
        self.roomDimensionsMeters = roomDimensionsMeters
    }

    /// Whether any accepted geometry authority is available at all;
    /// when false the evaluator reports `unavailable` rather than
    /// manufacturing a pass.
    public var hasGeometryAuthority: Bool {
        !meshBounds.isEmpty || roomDimensionsMeters != nil
    }

    /// Merged world bounds of all mesh evidence.
    public var combinedBounds: SpatialAxisBounds? {
        guard var bounds = meshBounds.first else {
            return nil
        }
        for bound in meshBounds.dropFirst() {
            bounds = bounds.union(bound)
        }
        return bounds
    }
}

/// Versioned advisory thresholds. The version is persisted in each
/// finding so downstream consumers can tell which rule set flagged an
/// annotation; raising a threshold later never rewrites stored verdicts.
public struct SpatialPlausibilityThresholds: Sendable, Equatable {
    public static let current = SpatialPlausibilityThresholds()

    /// Rule set identifier recorded on every finding.
    public let rulesVersion: String = "1.0.0"
    /// How far outside the union of mesh bounds a point may sit before
    /// being flagged.
    public var outsideBoundsMarginMeters: Float = 1.5
    /// Distance to the nearest accepted surface bound beyond which a
    /// point is considered detached from all observed geometry.
    public var farFromSurfaceMeters: Float = 4.0
    /// Tolerance below the observed floor reference.
    public var belowFloorMarginMeters: Float = 0.15
    /// Headroom above the room-content height (floor + dimensions_y)
    /// before a point is flagged.
    public var aboveRoomMarginMeters: Float = 0.75
    /// Positions closer than this are reported as accidental duplicates.
    public var duplicateDistanceMeters: Float = 0.05

    public init() {}
}

public enum SpatialPlausibilityRule: String, Codable, Sendable {
    /// Point sits beyond every accepted surface bound plus margin.
    case outsideRoomExtent = "outside_room_extent"
    /// Point is below the observed floor reference.
    case belowFloor = "below_floor"
    /// Point is above floor + room-content height plus margin.
    case aboveRoomExtent = "above_room_extent"
    /// Point is far from all accepted geometry.
    case farFromSurfaces = "far_from_surfaces"
    /// Another entity occupies effectively the same position.
    case duplicatePosition = "duplicate_position"
}

/// One advisory plausibility diagnostic linked to its annotation.
/// Diagnostics never mutate records — the operator inspects and either
/// corrects the annotation or keeps it.
public struct SpatialPlausibilityFinding:
    Codable, Sendable, Equatable, Identifiable
{
    public let rule: SpatialPlausibilityRule
    public let rulesVersion: String
    public let entityID: AnnotationEntityID
    public let entityLabel: String
    /// Human-readable measured detail (e.g. actual distance/height).
    /// Plain language; localized presentation lives in the UI layer.
    public let detail: String

    public var id: String {
        rule.rawValue + ":" + entityID.rawValue.uuidString
    }

    public init(
        rule: SpatialPlausibilityRule,
        rulesVersion: String,
        entityID: AnnotationEntityID,
        entityLabel: String,
        detail: String
    ) {
        self.rule = rule
        self.rulesVersion = rulesVersion
        self.entityID = entityID
        self.entityLabel = entityLabel
        self.detail = detail
    }
}

/// Advisory evaluator for annotation plausibility against accepted
/// room geometry (legacy bolph71656-ai/HTDT-Capture#247). Emits `SpatialPlausibilityFinding`s only;
/// annotations are never moved or rewritten.
public enum SpatialPlausibilityEvaluator {
    /// Evaluates `annotations` against `context`. Returns nil when no
    /// geometry authority exists ("analysis unavailable") — callers
    /// must not treat nil as a pass.
    public static func evaluate(
        annotations: [CaptureAnnotationEntity],
        context: SpatialPlausibilityContext,
        thresholds: SpatialPlausibilityThresholds = .current
    ) -> [SpatialPlausibilityFinding]? {
        guard context.hasGeometryAuthority else {
            return nil
        }

        var findings: [SpatialPlausibilityFinding] = []
        let version = thresholds.rulesVersion
        let combinedBounds = context.combinedBounds
        let positions: [(entity: CaptureAnnotationEntity, p: Float3)] =
            annotations.map {
                ($0, $0.worldFromAnnotation.translationWorld)
            }

        for (entity, position) in positions {
            if let combinedBounds,
               !combinedBounds.contains(
                   position,
                   margin: thresholds.outsideBoundsMarginMeters
               )
            {
                let outside = combinedBounds.distanceOutside(position)
                findings.append(
                    SpatialPlausibilityFinding(
                        rule: .outsideRoomExtent,
                        rulesVersion: version,
                        entityID: entity.entityID,
                        entityLabel: entity.label,
                        detail:
                            "point lies "
                            + String(format: "%.2f", outside)
                            + " m outside every scanned surface bound"
                    )
                )
            }

            if let floorY = context.floorYMeters {
                if position.y
                    < floorY - thresholds.belowFloorMarginMeters
                {
                    findings.append(
                        SpatialPlausibilityFinding(
                            rule: .belowFloor,
                            rulesVersion: version,
                            entityID: entity.entityID,
                            entityLabel: entity.label,
                            detail:
                                "point lies "
                                + String(
                                    format: "%.2f",
                                    floorY - position.y
                                )
                                + " m below the scanned floor reference"
                        )
                    )
                }
                if let dimensions = context.roomDimensionsMeters,
                   position.y
                       > floorY + Float(dimensions.yMeters)
                           + thresholds.aboveRoomMarginMeters
                {
                    findings.append(
                        SpatialPlausibilityFinding(
                            rule: .aboveRoomExtent,
                            rulesVersion: version,
                            entityID: entity.entityID,
                            entityLabel: entity.label,
                            detail:
                                "point lies above the scanned room's "
                                + "vertical extent"
                        )
                    )
                }
            }

            if !context.meshBounds.isEmpty {
                let nearest = context.meshBounds.map {
                    $0.distanceOutside(position)
                }.min() ?? .greatestFiniteMagnitude
                if nearest > thresholds.farFromSurfaceMeters {
                    findings.append(
                        SpatialPlausibilityFinding(
                            rule: .farFromSurfaces,
                            rulesVersion: version,
                            entityID: entity.entityID,
                            entityLabel: entity.label,
                            detail:
                                "nearest observed geometry is "
                                + String(format: "%.2f", nearest)
                                + " m away"
                        )
                    )
                }
            }
        }

        for (index, lhs) in positions.enumerated() {
            for rhs in positions.dropFirst(index + 1) {
                let distance = (lhs.p - rhs.p).length
                guard distance < thresholds.duplicateDistanceMeters
                else {
                    continue
                }
                let detail =
                    "same position as “" + rhs.entity.label + "”"
                findings.append(
                    SpatialPlausibilityFinding(
                        rule: .duplicatePosition,
                        rulesVersion: version,
                        entityID: lhs.entity.entityID,
                        entityLabel: lhs.entity.label,
                        detail: detail
                    )
                )
                findings.append(
                    SpatialPlausibilityFinding(
                        rule: .duplicatePosition,
                        rulesVersion: version,
                        entityID: rhs.entity.entityID,
                        entityLabel: rhs.entity.label,
                        detail:
                            "same position as “" + lhs.entity.label + "”"
                    )
                )
            }
        }

        return findings
    }
}
