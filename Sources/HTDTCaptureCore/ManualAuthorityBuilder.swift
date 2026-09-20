import Foundation

public enum ManualAuthorityBuilderError:
    Error,
    Sendable,
    Equatable
{
    case invalidPosition
    case invalidSpeakerYaw
    case invalidSpeakerChannelRole
}

public struct AnnotationPlacementAuthority:
    Sendable,
    Equatable
{
    public let worldFromAnnotation: Matrix4x4F
    public let placement: PlacementProvenance
    public let evidenceRefs: [String]

    public init(
        worldFromAnnotation: Matrix4x4F,
        placement: PlacementProvenance,
        evidenceRefs: [String]
    ) throws {
        guard Set(evidenceRefs).count == evidenceRefs.count else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        self.worldFromAnnotation = worldFromAnnotation
        self.placement = placement
        self.evidenceRefs = evidenceRefs.sorted()
    }
}

public enum ManualAuthorityBuilder {
    public static func annotation(
        type: AnnotationEntityType,
        label: String,
        xMeters: Double,
        yMeters: Double,
        zMeters: Double,
        coordinateSpaceID: CoordinateSpaceID,
        speakerChannelRole: String? = nil,
        speakerYawDegrees: Double? = nil,
        equipmentReference: HTDTEquipmentReference? = nil,
        evidenceRefs: [String] = [],
        placementAuthority: AnnotationPlacementAuthority? = nil
    ) throws -> CaptureAnnotationEntity {
        guard xMeters.isFinite,
              yMeters.isFinite,
              zMeters.isFinite
        else {
            throw ManualAuthorityBuilderError.invalidPosition
        }

        let manualTransform = try Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            Float(xMeters),
            Float(yMeters),
            Float(zMeters),
            1,
        ])
        let transform =
            placementAuthority?.worldFromAnnotation
            ?? manualTransform
        let placement: PlacementProvenance
        if let placementAuthority {
            placement = placementAuthority.placement
        } else {
            placement = try PlacementProvenance(
                method: .manualNumeric
            )
        }
        let mergedEvidenceRefs = Array(
            Set(
                evidenceRefs
                    + (placementAuthority?.evidenceRefs ?? [])
            )
        ).sorted()

        let semantics: ReferencePointSemantics
        switch type {
        case .speaker, .subwoofer:
            semantics = .cabinetReferencePoint
        case .display:
            semantics = .displayCenter
        case .projectionScreen:
            semantics = .screenCenter
        case .listeningPosition:
            semantics = .earCenter
        case .seat:
            semantics = .seatReferencePoint
        case .referencePoint:
            semantics = .userReferencePoint
        case .acousticTreatment, .equipmentRack, .custom:
            semantics = .userReferencePoint
        }

        var orientation: OrientationAxes?
        var channelRole: ChannelRole?
        if type == .speaker {
            guard let speakerYawDegrees,
                  speakerYawDegrees.isFinite
            else {
                throw ManualAuthorityBuilderError.invalidSpeakerYaw
            }
            let roleText = speakerChannelRole?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            guard let parsedRole = ChannelRole(rawValue: roleText) else {
                throw ManualAuthorityBuilderError
                    .invalidSpeakerChannelRole
            }

            let radians = speakerYawDegrees
                * Double.pi / 180.0
            let front = try SpatialVector3F.unit(
                Float(sin(radians)),
                0,
                Float(-cos(radians))
            )
            orientation = try OrientationAxes(
                frontAxisLocal: front,
                upAxisLocal: .unit(0, 1, 0)
            )
            channelRole = parsedRole
        }

        return try CaptureAnnotationEntity(
            type: type,
            coordinateSpaceID: coordinateSpaceID,
            worldFromAnnotation: transform,
            referencePointSemantics: semantics,
            label: label,
            provenanceClass: .userAnnotation,
            verificationState:
                placementAuthority == nil
                ? .userAttested
                : .evidenceLinked,
            placement: placement,
            orientation: orientation,
            channelRole: channelRole,
            equipmentRef: equipmentReference,
            evidenceRefs: mergedEvidenceRefs
        )
    }

    public static func scalarMeasurement(
        quantityType: String,
        value: Double,
        unit: MeasurementUnit,
        acquisitionMethod: MeasurementAcquisitionMethod,
        instrument: MeasurementInstrument? = nil,
        statedUncertainty: Double? = nil,
        sourceValueText: String? = nil,
        evidenceRefs: [String] = []
    ) throws -> CaptureMeasurement {
        try CaptureMeasurement(
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
