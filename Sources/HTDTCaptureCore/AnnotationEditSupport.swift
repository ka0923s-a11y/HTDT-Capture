import Foundation

/// Typed speaker channel-role catalog for the authoring UI (#220).
/// `ChannelRole` itself is intentionally un-opinionated; the workspace
/// presents this closed set through a localized picker and keeps a
/// free-text path only under Advanced.
extension ChannelRole {
    /// Ordered roles shown by the typed picker. Covers the standard
    /// home-theater set; a custom free-text role remains available in
    /// the advanced path for unusual layouts.
    public static var standardRoles: [ChannelRole] {
        [
            .left,
            .center,
            .right,
            .surroundLeft,
            .surroundRight,
            .surroundBackLeft,
            .surroundBackRight,
            .topFrontLeft,
            .topFrontRight,
            .topMiddleLeft,
            .topMiddleRight,
            .topRearLeft,
            .topRearRight,
            .lfe,
        ]
    }

    /// Whether the role is in the standard set — nonstandard roles are
    /// still valid, the UI just flags them as custom.
    public var isStandardRole: Bool {
        Self.standardRoles.contains(self)
    }
}

/// Type → reference-point semantics, matching
/// `ManualAuthorityBuilder.annotation` (the builder file is owned by a
/// parallel change and takes no `entityID`, so the edit path
/// replicates this small table rather than extending it).
public enum ReferencePointSemanticsCatalog {
    public static func forType(
        _ type: AnnotationEntityType
    ) -> ReferencePointSemantics {
        switch type {
        case .speaker, .subwoofer:
            return .cabinetReferencePoint
        case .display:
            return .displayCenter
        case .projectionScreen:
            return .screenCenter
        case .listeningPosition:
            return .earCenter
        case .seat:
            return .seatReferencePoint
        case .acousticTreatment, .equipmentRack, .custom,
             .referencePoint:
            return .userReferencePoint
        }
    }
}

/// Seed for editing an existing staged annotation (#245). Captures the
/// parts of `CaptureAnnotationEntity` that survive an edit so saving
/// preserves `entityID`, the coordinate-space authority, and every
/// field the operator did not touch — reopening a form never mints a
/// new identity.
public struct AnnotationEditSeed: Sendable, Equatable {
    public let entityID: AnnotationEntityID
    public let type: AnnotationEntityType
    public let label: String
    /// Position extracted from `worldFromAnnotation` — the transform
    /// column is the only editable piece of the pose.
    public let positionMeters: Float3
    /// Prior speaker yaw in degrees, derived from `orientation`.
    public let yawDegrees: Float?
    public let channelRole: ChannelRole?
    public let equipmentRef: HTDTEquipmentReference?
    /// The entity's original provenance fields, reused verbatim when
    /// the operator does not re-capture placement/orientation.
    public let originalPlacement: PlacementProvenance
    public let originalOrientation: OrientationAxes?
    public let originalTransform: Matrix4x4F

    /// New placement authority produced by a fresh capture during the
    /// edit session; nil means the original provenance is kept.
    public var replacementPlacement: AnnotationPlacementAuthority?
    /// New orientation authority produced by a fresh heading capture.
    public var replacementOrientation: AnnotationOrientationAuthority?
    /// Explicit manual override of the position (Advanced section);
    /// turns the placement method into `manual_numeric`.
    public var manualPositionOverride: Float3?

    /// Fresh seed for adding a new annotation — the resulting entity
    /// gets a new `entityID`. Used so add and edit share one assembly
    /// path (#245).
    public init(freshType type: AnnotationEntityType) {
        self.entityID = AnnotationEntityID()
        self.type = type
        self.label = ""
        self.positionMeters = Float3(0, 0, 0)
        self.yawDegrees = nil
        self.channelRole = nil
        self.equipmentRef = nil
        self.originalPlacement = try! PlacementProvenance(
            method: .manualNumeric
        )
        self.originalOrientation = nil
        self.originalTransform = .identity
    }

    public init(entity: CaptureAnnotationEntity) {
        self.entityID = entity.entityID
        self.type = entity.type
        self.label = entity.label
        self.positionMeters =
            entity.worldFromAnnotation.translationWorld
        self.yawDegrees = entity.orientation.map {
            Float(
                atan2(
                    $0.frontAxisLocal.x,
                    -$0.frontAxisLocal.z
                ) * 180 / .pi
            )
        }
        self.channelRole = entity.channelRole
        self.equipmentRef = entity.equipmentRef
        self.originalPlacement = entity.placement
        self.originalOrientation = entity.orientation
        self.originalTransform = entity.worldFromAnnotation
    }

    /// Rebuilds the entity preserving `entityID` and untouched fields.
    /// Placement uses the replacement authority when captured, a
    /// `manual_numeric` provenance when the operator typed new
    /// coordinates, and the original provenance/transform otherwise.
    public func buildEntity(
        coordinateSpaceID: CoordinateSpaceID,
        type: AnnotationEntityType,
        label: String,
        channelRole: ChannelRole?,
        equipmentRef: HTDTEquipmentReference?,
        yawDegrees: Float?,
        evidenceSelection: AnnotationEvidenceSelection
    ) throws -> CaptureAnnotationEntity {
        let placement: PlacementProvenance
        let worldFromAnnotation: Matrix4x4F
        var placementAuthority: AnnotationPlacementAuthority?
        if let replacementPlacement {
            placement = replacementPlacement.placement
            worldFromAnnotation =
                replacementPlacement.worldFromAnnotation
            placementAuthority = replacementPlacement
        } else if let manualPositionOverride {
            worldFromAnnotation = try Matrix4x4F(values: [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                manualPositionOverride.x,
                manualPositionOverride.y,
                manualPositionOverride.z,
                1,
            ])
            placement = try PlacementProvenance(
                method: .manualNumeric
            )
        } else {
            placement = originalPlacement
            worldFromAnnotation = originalTransform
        }

        let orientation: OrientationAxes?
        var orientationAuthority: AnnotationOrientationAuthority?
        if let replacementOrientation {
            orientation = replacementOrientation.orientation
            orientationAuthority = replacementOrientation
        } else if let yawDegrees {
            let radians = Double(yawDegrees) * .pi / 180
            orientation = try OrientationAxes(
                frontAxisLocal: .unit(
                    Float(sin(radians)),
                    0,
                    Float(-cos(radians))
                ),
                upAxisLocal: .unit(0, 1, 0)
            )
        } else {
            orientation = originalOrientation
        }

        var selection = evidenceSelection
        selection.replacePlacementAuthority(placementAuthority)
        selection.replaceOrientationAuthority(orientationAuthority)
        let evidenceRefs = selection.effectiveRefs

        let hasAuthority =
            placementAuthority != nil || orientationAuthority != nil
            || placement.method != .manualNumeric
        return try CaptureAnnotationEntity(
            entityID: entityID,
            type: type,
            coordinateSpaceID: coordinateSpaceID,
            worldFromAnnotation: worldFromAnnotation,
            referencePointSemantics:
                ReferencePointSemanticsCatalog.forType(type),
            label: label,
            provenanceClass: .userAnnotation,
            verificationState: hasAuthority
                ? .evidenceLinked
                : .userAttested,
            placement: placement,
            orientation: orientation,
            channelRole: channelRole,
            equipmentRef: equipmentRef,
            evidenceRefs: evidenceRefs
        )
    }
}

/// Seed for editing an existing staged measurement (#245) — preserves
/// `measurementID` so corrections update the same conceptual record.
public struct MeasurementEditSeed: Sendable, Equatable {
    public let measurementID: MeasurementID
    public let quantityType: String
    public let value: MeasurementValue
    public let unit: MeasurementUnit
    public let acquisitionMethod: MeasurementAcquisitionMethod
    public let instrument: MeasurementInstrument?
    public let statedUncertainty: Double?
    public let sourceValueText: String?
    public let evidenceRefs: [String]

    public init(measurement: CaptureMeasurement) {
        self.measurementID = measurement.measurementID
        self.quantityType = measurement.quantityType
        self.value = measurement.value
        self.unit = measurement.unit
        self.acquisitionMethod = measurement.acquisitionMethod
        self.instrument = measurement.instrument
        self.statedUncertainty = measurement.statedUncertainty
        self.sourceValueText = measurement.sourceValueText
        self.evidenceRefs = measurement.evidenceRefs
    }
}

/// Rebuilds an edited measurement preserving identity (#245). Covers
/// the scalar path `ManualAuthorityBuilder` supports — the edit form
/// never exposes endpoint-backed or derived measurements.
public enum MeasurementEditSupport {
    public static func buildEditedMeasurement(
        seed: MeasurementEditSeed,
        quantityType: String,
        value: Double,
        unit: MeasurementUnit,
        acquisitionMethod: MeasurementAcquisitionMethod,
        instrument: MeasurementInstrument?,
        statedUncertainty: Double?,
        sourceValueText: String?,
        evidenceRefs: [String]
    ) throws -> CaptureMeasurement {
        try CaptureMeasurement(
            measurementID: seed.measurementID,
            quantityType: quantityType,
            value: .scalar(value),
            unit: unit,
            acquisitionMethod: acquisitionMethod,
            instrument: instrument,
            statedUncertainty: statedUncertainty,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement,
            sourceValueText: sourceValueText,
            evidenceRefs: evidenceRefs
        )
    }
}
