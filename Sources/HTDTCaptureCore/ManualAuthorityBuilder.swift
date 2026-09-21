import Foundation

public enum ManualAuthorityBuilderError:
    Error,
    Sendable,
    Equatable
{
    case invalidPosition
    case invalidSpeakerYaw
    case invalidSpeakerChannelRole
    case orientationOnlyForSpeaker
    case derivedAcquisitionNotUserAttestable
    /// An evidence-captured authority is expressed in a different
    /// coordinate space than the annotation it would support (issue
    /// #199).
    case authorityCoordinateSpaceMismatch
}

public struct AnnotationPlacementAuthority:
    Sendable,
    Equatable
{
    public let worldFromAnnotation: Matrix4x4F
    public let placement: PlacementProvenance
    /// The coordinate space the captured transform and its evidence
    /// refs are expressed in. Evidence-linked authority must be bound
    /// to the referenced frame's coordinate space (issue #199).
    public let coordinateSpaceID: CoordinateSpaceID
    public let evidenceRefs: [String]

    public init(
        worldFromAnnotation: Matrix4x4F,
        placement: PlacementProvenance,
        coordinateSpaceID: CoordinateSpaceID,
        evidenceRefs: [String]
    ) throws {
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        // An evidence-backed placement authority must carry the evidence
        // it claims; the plain manual path uses a nil authority instead.
        guard !normalizedEvidence.isEmpty
                || placement.hasSourceReference
        else {
            throw AnnotationModelError.missingEvidenceLink
        }
        self.worldFromAnnotation = worldFromAnnotation
        self.placement = placement
        self.coordinateSpaceID = coordinateSpaceID
        self.evidenceRefs = normalizedEvidence.sorted()
    }
}

public struct AnnotationOrientationAuthority:
    Sendable,
    Equatable
{
    public let orientation: OrientationAxes
    /// The coordinate space the captured orientation and its evidence
    /// refs are expressed in (issue #199).
    public let coordinateSpaceID: CoordinateSpaceID
    public let evidenceRefs: [String]

    public init(
        orientation: OrientationAxes,
        coordinateSpaceID: CoordinateSpaceID,
        evidenceRefs: [String]
    ) throws {
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        // An evidence-backed orientation authority must carry the
        // evidence it claims; the plain manual path uses nil instead.
        guard !normalizedEvidence.isEmpty else {
            throw AnnotationModelError.missingEvidenceLink
        }
        self.orientation = orientation
        self.coordinateSpaceID = coordinateSpaceID
        self.evidenceRefs = normalizedEvidence.sorted()
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
        placementAuthority: AnnotationPlacementAuthority? = nil,
        orientationAuthority: AnnotationOrientationAuthority? = nil
    ) throws -> CaptureAnnotationEntity {
        guard xMeters.isFinite,
              yMeters.isFinite,
              zMeters.isFinite
        else {
            throw ManualAuthorityBuilderError.invalidPosition
        }

        // Evidence-captured authorities are bound to the coordinate
        // space of the frame they were captured from (issue #199).
        // Applying one to an annotation in a different space would make
        // the linked evidence geometrically non-comparable; only an
        // explicit transform/alignment authority could bridge spaces,
        // and none exists in v1 — manifest membership of both space IDs
        // is never sufficient.
        if let placementAuthority,
           placementAuthority.coordinateSpaceID != coordinateSpaceID
        {
            throw ManualAuthorityBuilderError
                .authorityCoordinateSpaceMismatch
        }
        if let orientationAuthority,
           orientationAuthority.coordinateSpaceID != coordinateSpaceID
        {
            throw ManualAuthorityBuilderError
                .authorityCoordinateSpaceMismatch
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
                    + (orientationAuthority?.evidenceRefs ?? [])
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

        if type != .speaker, orientationAuthority != nil {
            throw ManualAuthorityBuilderError.orientationOnlyForSpeaker
        }

        var orientation: OrientationAxes?
        var channelRole: ChannelRole?
        if type == .speaker {
            let roleText = speakerChannelRole?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            guard let parsedRole = ChannelRole(rawValue: roleText) else {
                throw ManualAuthorityBuilderError
                    .invalidSpeakerChannelRole
            }

            if let orientationAuthority {
                orientation = orientationAuthority.orientation
            } else {
                guard let speakerYawDegrees,
                      speakerYawDegrees.isFinite
                else {
                    throw ManualAuthorityBuilderError.invalidSpeakerYaw
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
            }
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
                    && orientationAuthority == nil
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
        // The manual builder always writes a user-attested record, so a
        // derived acquisition method would be a contradictory provenance
        // claim. Derived values must use their own evidence path.
        switch acquisitionMethod {
        case .lidarDerived, .roomPlanDerived:
            throw ManualAuthorityBuilderError
                .derivedAcquisitionNotUserAttestable
        case .tapeMeasure, .laserDistanceMeter,
             .manufacturerSpecification, .other:
            break
        }
        return try CaptureMeasurement(
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
