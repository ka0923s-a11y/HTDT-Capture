import Foundation

public enum CaptureConflictStatus: String, Sendable, Equatable, Codable {
    /// Analysis ran against committed authorities; `conflicts` may be
    /// empty, which still means "checked and none found".
    case analyzed
    /// A required input collection was unavailable so the analysis
    /// could not run; an empty `conflicts` list here must NOT be read
    /// as "no conflicts" (#229).
    case unavailable
}

public enum CaptureConflictKind: String, Sendable, Equatable, Codable {
    case sameQuantityValueDisagreement =
        "same_quantity_value_disagreement"
    case roomPlanDimensionDisagreement =
        "roomplan_dimension_disagreement"
    case annotationOrientationMissing =
        "annotation_orientation_missing"
    case endpointBindingMissing = "endpoint_binding_missing"
}

public struct CaptureConflictCandidate: Sendable, Equatable, Codable {
    public let recordRef: String
    public let quantityType: String?
    public let valueText: String
    public let unit: String?
    public let acquisitionMethod: String?
    public let statedUncertaintyMeters: Double?
    public let provenanceClass: String


    public init(
        recordRef: String,
        quantityType: String?,
        valueText: String,
        unit: String?,
        acquisitionMethod: String?,
        statedUncertaintyMeters: Double?,
        provenanceClass: String
    ) {
        self.recordRef = recordRef
        self.quantityType = quantityType
        self.valueText = valueText
        self.unit = unit
        self.acquisitionMethod = acquisitionMethod
        self.statedUncertaintyMeters = statedUncertaintyMeters
        self.provenanceClass = provenanceClass
    }


    enum CodingKeys: String, CodingKey {
        case recordRef = "record_ref"
        case quantityType = "quantity_type"
        case valueText = "value_text"
        case unit
        case acquisitionMethod = "acquisition_method"
        case statedUncertaintyMeters = "stated_uncertainty_meters"
        case provenanceClass = "provenance_class"
    }
}

public struct CaptureConflict: Sendable, Equatable, Codable {
    public let kind: CaptureConflictKind
    /// Stable semantic key for the conflicted quantity/entity — e.g. the
    /// quantity type plus sorted endpoint refs — never a localized
    /// string.
    public let subject: String
    public let detail: String
    public let candidates: [CaptureConflictCandidate]


    public init(
        kind: CaptureConflictKind,
        subject: String,
        detail: String,
        candidates: [CaptureConflictCandidate]
    ) {
        self.kind = kind
        self.subject = subject
        self.detail = detail
        self.candidates = candidates
    }


    enum CodingKeys: String, CodingKey {
        case kind
        case subject
        case detail
        case candidates
    }
}

public struct CaptureConflictReport: Sendable, Equatable, Codable {
    public let status: CaptureConflictStatus
    public let toleranceMeters: Double
    public let conflicts: [CaptureConflict]


    public init(
        status: CaptureConflictStatus,
        toleranceMeters: Double,
        conflicts: [CaptureConflict]
    ) {
        self.status = status
        self.toleranceMeters = toleranceMeters
        self.conflicts = conflicts
    }


    enum CodingKeys: String, CodingKey {
        case status
        case toleranceMeters = "tolerance_meters"
        case conflicts
    }
}

/// Advisory conflict/reconciliation analyzer (#229). Never mutates or
/// ranks records: conflicting candidates stay independently preserved
/// and are reported side by side with their provenance.
public enum CaptureConflictAnalyzer {
    /// Measurements disagreeing beyond this distance are surfaced as
    /// conflicts (or beyond combined stated uncertainty, whichever is
    /// larger). Advisory only — a versioned policy may promote it later.
    public static let advisoryDisagreementToleranceMeters = 0.05

    /// RoomPlan dimension axes bind to common operator quantity names.
    static let roomPlanDimensionBindings: [(axis: String, names: Set<String>)] = [
        ("x", ["room_width"]),
        ("y", ["room_height"]),
        ("z", ["room_length", "room_depth"]),
    ]

    static func roomPlanDimension(
        axis: String,
        on dimensions: CapturedRoomDimensionsSummary
    ) -> Double {
        switch axis {
        case "x": dimensions.xMeters
        case "y": dimensions.yMeters
        default: dimensions.zMeters
        }
    }

    public static func analyze(
        measurements: [CaptureMeasurement]?,
        annotations: [CaptureAnnotationEntity]?,
        roomMetadata: CapturedRoomMetadataDocument?,
        toleranceMeters: Double =
            advisoryDisagreementToleranceMeters
    ) -> CaptureConflictReport {
        guard let measurements, let annotations else {
            return CaptureConflictReport(
                status: .unavailable,
                toleranceMeters: toleranceMeters,
                conflicts: []
            )
        }
        var conflicts: [CaptureConflict] = []

        conflicts += sameQuantityConflicts(
            measurements: measurements,
            toleranceMeters: toleranceMeters
        )
        if let dimensions = roomMetadata?.summary?.dimensionsMeters {
            conflicts += roomPlanDimensionConflicts(
                measurements: measurements,
                dimensions: dimensions,
                toleranceMeters: toleranceMeters
            )
        }
        conflicts += orientationConflicts(annotations: annotations)
        conflicts += endpointBindingConflicts(measurements: measurements)

        conflicts.sort {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.subject < $1.subject
        }
        return CaptureConflictReport(
            status: .analyzed,
            toleranceMeters: toleranceMeters,
            conflicts: conflicts
        )
    }

    private static func sameQuantityConflicts(
        measurements: [CaptureMeasurement],
        toleranceMeters: Double
    ) -> [CaptureConflict] {
        var groups: [String: [CaptureMeasurement]] = [:]
        for measurement in measurements {
            let key = measurement.quantityType + "|"
                + measurement.endpointRefs.sorted().joined(separator: ",")
            groups[key, default: []].append(measurement)
        }
        var conflicts: [CaptureConflict] = []
        for (key, group) in groups where group.count > 1 {
            var scalars: [(CaptureMeasurement, Double)] = []
            for measurement in group {
                guard case let .scalar(value) = measurement.value,
                      value.isFinite
                else { continue }
                scalars.append((measurement, value))
            }
            guard scalars.count > 1 else { continue }
            let values = scalars.map(\.1)
            let spread = values.max()! - values.min()!
            let combinedUncertainty = scalars
                .compactMap(\.0.statedUncertainty)
                .sorted()
                .suffix(2)
                .reduce(0, +)
            guard spread > max(toleranceMeters, combinedUncertainty)
            else { continue }
            conflicts.append(
                CaptureConflict(
                    kind: .sameQuantityValueDisagreement,
                    subject: key,
                    detail: "\(scalars.count) measurements spread \(spread)",
                    candidates: scalars.map {
                        candidate(for: $0.0)
                    }
                )
            )
        }
        return conflicts
    }

    private static func roomPlanDimensionConflicts(
        measurements: [CaptureMeasurement],
        dimensions: CapturedRoomDimensionsSummary,
        toleranceMeters: Double
    ) -> [CaptureConflict] {
        var conflicts: [CaptureConflict] = []
        for binding in roomPlanDimensionBindings {
            let roomPlanValue = roomPlanDimension(
                axis: binding.axis, on: dimensions)
            for measurement in measurements
            where binding.names.contains(measurement.quantityType) {
                guard case let .scalar(value) = measurement.value,
                      value.isFinite,
                      abs(value - roomPlanValue) > max(
                          toleranceMeters,
                          measurement.statedUncertainty ?? 0
                      )
                else { continue }
                conflicts.append(
                    CaptureConflict(
                        kind: .roomPlanDimensionDisagreement,
                        subject:
                            "roomplan_dimension_\(binding.axis)|\(measurement.quantityType)",
                        detail: "user-attested \(value) vs RoomPlan \(roomPlanValue)",
                        candidates: [
                            candidate(for: measurement),
                            CaptureConflictCandidate(
                                recordRef:
                                    "path:roomplan/captured-room-metadata.json",
                                quantityType: binding.axis,
                                valueText: String(roomPlanValue),
                                unit: MeasurementUnit.meter.rawValue,
                                acquisitionMethod: "roomplan_derived",
                                statedUncertaintyMeters: nil,
                                provenanceClass:
                                    "apple_roomplan_inference"
                            ),
                        ]
                    )
                )
            }
        }
        return conflicts
    }

    private static func orientationConflicts(
        annotations: [CaptureAnnotationEntity]
    ) -> [CaptureConflict] {
        annotations.compactMap { entity in
            guard entity.type == .speaker || entity.type == .display,
                  entity.orientation == nil
            else { return nil }
            return CaptureConflict(
                kind: .annotationOrientationMissing,
                subject: "annotation:\(entity.entityID.description)",
                detail:
                    "\(entity.type.rawValue) annotation lacks orientation axes",
                candidates: [
                    CaptureConflictCandidate(
                        recordRef:
                            "annotation:\(entity.entityID.description)",
                        quantityType: nil,
                        valueText: entity.label,
                        unit: nil,
                        acquisitionMethod: nil,
                        statedUncertaintyMeters: nil,
                        provenanceClass: entity.provenanceClass.rawValue
                    ),
                ]
            )
        }
    }

    private static func endpointBindingConflicts(
        measurements: [CaptureMeasurement]
    ) -> [CaptureConflict] {
        measurements.compactMap { measurement in
            guard measurement.endpointRefs.isEmpty else { return nil }
            return CaptureConflict(
                kind: .endpointBindingMissing,
                subject:
                    "measurement:\(measurement.measurementID.description)",
                detail:
                    "measurement carries no endpoint/evidence binding",
                candidates: [candidate(for: measurement)]
            )
        }
    }

    private static func candidate(
        for measurement: CaptureMeasurement
    ) -> CaptureConflictCandidate {
        let valueText: String
        switch measurement.value {
        case let .scalar(value):
            valueText = String(value)
        case let .vector3(x, y, z):
            valueText = "[\(x),\(y),\(z)]"
        }
        return CaptureConflictCandidate(
            recordRef: "measurement:\(measurement.measurementID.description)",
            quantityType: measurement.quantityType,
            valueText: valueText,
            unit: measurement.unit.rawValue,
            acquisitionMethod: measurement.acquisitionMethod.rawValue,
            statedUncertaintyMeters: measurement.statedUncertainty,
            provenanceClass: measurement.provenanceClass.rawValue
        )
    }
}
