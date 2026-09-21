import Foundation

public enum ManualAuthorityBuilderError:
    Error,
    Sendable,
    Equatable
{
    case invalidPosition
    case invalidSpeakerYaw
    case invalidSpeakerElevation
    case invalidSpeakerChannelRole
    case invalidSubwooferChannelRole
    case invalidOrientationYaw
    /// Orientation authority (captured or yaw-entered) is only
    /// supported on types with body/plane semantics — see
    /// `AnnotationEntityType.supportsOrientationAuthority`.
    case orientationNotSupportedForType
    /// A typed `listening_role` is required when authoring a
    /// listening position (#243); legacy records may lack one, new
    /// authoring cannot.
    case listeningRoleRequired
    /// Any evidence-captured placement authority must be paired with
    /// an explicit `referencePointConstruction` — a raycast hit can
    /// never silently claim a semantic point like `ear_center`
    /// (#291).
    case referencePointConstructionRequired
    /// A non-nil acoustic center is only defined for loudspeaker
    /// entities (speaker/subwoofer) and only through an explicit
    /// offset authority — never inferred (issue #234).
    case acousticCenterRequiresLoudspeaker
    case derivedAcquisitionNotUserAttestable
    /// An evidence-captured authority is expressed in a different
    /// coordinate space than the annotation it would support (issue
    /// #199).
    case authorityCoordinateSpaceMismatch
    /// No point-direction capture is available in this environment
    /// (e.g. no live ARSession); used by default closures only.
    case pointDirectionUnavailable
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
        speakerElevationDegrees: Double? = nil,
        acousticCenter: AcousticCenterOffsetAuthority? = nil,
        subwooferChannelRole: String? = nil,
        orientationYawDegrees: Double? = nil,
        listeningRole: ListeningPositionRole? = nil,
        referencePointSemantics: ReferencePointSemantics? = nil,
        referencePointConstruction: ReferencePointConstruction? = nil,
        referencePointOffset: SpatialVector3F? = nil,
        physicalEnvelope: EntityPhysicalEnvelope? = nil,
        uncertainty: SpatialUncertaintyAuthority? = nil,
        equipmentReference: HTDTEquipmentReference? = nil,
        evidenceRefs: [String] = [],
        placementAuthority: AnnotationPlacementAuthority? = nil,
        orientationAuthority: AnnotationOrientationAuthority? = nil,
        createdAt: Date = Date(),
        observedAtUTC: String? = nil,
        sourceCreatedAtUTC: String? = nil,
        supersedesEntityID: AnnotationEntityID? = nil
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

        // Equipment-reference compatibility is enforced below the UI
        // (#237): an exact catalog tuple can only be attached to an
        // annotation type the catalog's authority version actually
        // covers — a cryptographically-correct tuple on the wrong
        // entity kind is still meaningless authority.
        if let equipmentReference {
            switch HTDTEquipmentCompatibility.check(
                reference: equipmentReference,
                entityType: type
            ) {
            case .compatible:
                break
            case .unknownAuthorityVersion:
                throw AnnotationModelError.unknownEquipmentAuthority
            case .incompatible, .noReference:
                throw AnnotationModelError
                    .incompatibleEquipmentReference
            }
        }

        // Reference semantics describe the point actually authored,
        // not merely the entity type (#291). The caller may select a
        // type-appropriate token; the default remains the type's
        // convention.
        let semantics =
            referencePointSemantics ?? type.defaultReferenceSemantics
        if let allowed = type.allowedReferenceSemantics,
           !allowed.contains(semantics)
        {
            throw AnnotationModelError.invalidReferencePointSemantics
        }

        // Reference-point construction is fail-closed (#291): any
        // evidence-captured placement must be paired with an explicit
        // construction record so a surface hit can never silently
        // claim a semantic point.
        if placementAuthority != nil,
           referencePointConstruction == nil
        {
            throw ManualAuthorityBuilderError
                .referencePointConstructionRequired
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
        var transform =
            placementAuthority?.worldFromAnnotation
            ?? manualTransform

        // `offset_from_surface` constructs the free-space semantic
        // point by applying an explicit world-frame offset to the
        // captured surface hit (#291).
        if referencePointConstruction == .offsetFromSurface {
            guard let referencePointOffset else {
                throw AnnotationModelError
                    .invalidReferencePointAuthority
            }
            var values = transform.values
            values[12] += referencePointOffset.x
            values[13] += referencePointOffset.y
            values[14] += referencePointOffset.z
            transform = try Matrix4x4F(values: values)
        }

        let placement: PlacementProvenance
        if let placementAuthority {
            placement = placementAuthority.placement
        } else {
            placement = try PlacementProvenance(
                method: .manualNumeric
            )
        }

        let referencePoint: ReferencePointAuthority?
        if let referencePointConstruction {
            // The supporting evidence for a surface-derived
            // construction is the surface evidence itself.
            let constructionEvidence =
                referencePointConstruction == .surfaceHitConfirmed
                    || referencePointConstruction == .offsetFromSurface
                ? placement.sourceEvidenceRefs
                : []
            referencePoint = try ReferencePointAuthority(
                construction: referencePointConstruction,
                offsetMeters:
                    referencePointConstruction == .offsetFromSurface
                    ? referencePointOffset
                    : nil,
                sourceEvidenceRefs: constructionEvidence
            )
        } else {
            referencePoint = nil
        }

        let mergedEvidenceRefs = Array(
            Set(
                evidenceRefs
                    + (placementAuthority?.evidenceRefs ?? [])
                    + (orientationAuthority?.evidenceRefs ?? [])
            )
        ).sorted()

        // Orientation authority is supported on any type with
        // body/plane semantics (#230, #244); pure point authorities
        // (listening position, reference point) reject it.
        if orientationAuthority != nil || orientationYawDegrees != nil {
            guard type.supportsOrientationAuthority else {
                throw ManualAuthorityBuilderError
                    .orientationNotSupportedForType
            }
        }
        if acousticCenter != nil,
           type != .speaker, type != .subwoofer
        {
            throw ManualAuthorityBuilderError
                .acousticCenterRequiresLoudspeaker
        }

        var orientation: OrientationAxes?
        if let orientationAuthority {
            orientation = orientationAuthority.orientation
        } else if let orientationYawDegrees {
            guard orientationYawDegrees.isFinite else {
                throw ManualAuthorityBuilderError.invalidOrientationYaw
            }
            orientation = try Self.yawOrientation(
                degrees: orientationYawDegrees
            )
        } else if type == .speaker {
            orientation = try Self.speakerOrientationAxes(
                azimuthDegrees: speakerYawDegrees,
                elevationDegrees: speakerElevationDegrees
            )
        }

        var channelRole: ChannelRole?
        switch type {
        case .speaker:
            let roleText = speakerChannelRole?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            guard let parsedRole = ChannelRole(rawValue: roleText)
            else {
                throw ManualAuthorityBuilderError
                    .invalidSpeakerChannelRole
            }
            channelRole = parsedRole
        case .subwoofer:
            // Subwoofer topology (#244): every sub carries a typed
            // channel/instance role so multiple subs are
            // distinguishable without label parsing. The token set is
            // open (LFE1/LFE2/... or custom) — no AVR convention is
            // forced.
            guard speakerElevationDegrees == nil else {
                throw ManualAuthorityBuilderError
                    .invalidSpeakerElevation
            }
            let roleText = subwooferChannelRole?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            guard let parsedRole = ChannelRole(rawValue: roleText)
            else {
                throw ManualAuthorityBuilderError
                    .invalidSubwooferChannelRole
            }
            channelRole = parsedRole
        default:
            guard speakerChannelRole == nil,
                  subwooferChannelRole == nil,
                  speakerElevationDegrees == nil
            else {
                throw AnnotationModelError.invalidAuthorityComponent
            }
        }

        // Typed listening-position role (#243): required for new
        // authored records so the primary MLP is machine-readable.
        if type == .listeningPosition, listeningRole == nil {
            throw ManualAuthorityBuilderError.listeningRoleRequired
        }

        // Component-level authority (#263): the aggregate
        // `verification_state` stays the legacy summary; `authority`
        // records which components are actually evidence-backed so a
        // mixed record never overstates itself.
        let placementEvidence = Array(
            Set(
                placement.sourceEvidenceRefs
                    + (placementAuthority?.evidenceRefs ?? [])
            )
        ).sorted()
        let placementSource =
            placement.sourceSemanticEntityID
                ?? placement.sourceMeshAnchorID?
                    .uuidString.lowercased()
                ?? placement.sourceRoomPlanObjectID
        let authority = try AnnotationAuthorityComponents(
            placement: AnnotationComponentAuthority(
                state: placementAuthority != nil
                    ? .evidenceLinked
                    : .userAttested,
                evidenceRefs: placementEvidence,
                sourceRef: placementSource
            ),
            orientation: try orientation.map { _ in
                try AnnotationComponentAuthority(
                    state: orientationAuthority != nil
                        ? .evidenceLinked
                        : .userAttested,
                    evidenceRefs:
                        orientationAuthority?.evidenceRefs ?? []
                )
            },
            equipment: try equipmentReference.map { ref in
                try AnnotationComponentAuthority(
                    state: .userAttested,
                    sourceRef:
                        "equipment:" + ref.equipmentID
                            + "@" + ref.equipmentVersion
                )
            },
            referencePoint: try referencePoint.map { point in
                try AnnotationComponentAuthority(
                    state: point.sourceEvidenceRefs.isEmpty
                        ? .userAttested
                        : .evidenceLinked,
                    evidenceRefs: point.sourceEvidenceRefs
                )
            },
            semanticRole: try (channelRole != nil
                || listeningRole != nil)
                ? AnnotationComponentAuthority(state: .userAttested)
                : nil
        )

        // Lifecycle metadata (#267): creation time is always stamped;
        // observation/source times are recorded only when supplied —
        // never fabricated for manual or imported records.
        let lifecycle = try AnnotationLifecycle(
            createdAtUTC: BundleTimestamp.utcString(from: createdAt),
            observedAtUTC: observedAtUTC,
            sourceCreatedAtUTC: sourceCreatedAtUTC,
            supersedesEntityID: supersedesEntityID
        )

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
            acousticCenter: acousticCenter,
            equipmentRef: equipmentReference,
            evidenceRefs: mergedEvidenceRefs,
            physicalEnvelope: physicalEnvelope,
            listeningRole: listeningRole,
            uncertainty: uncertainty,
            authority: authority,
            lifecycle: lifecycle,
            referencePoint: referencePoint
        )
    }

    /// Yaw-only body orientation: front = (sin θ, 0, −cos θ), up = +Y.
    private static func yawOrientation(
        degrees: Double
    ) throws -> OrientationAxes {
        let radians = degrees * Double.pi / 180.0
        let front = try SpatialVector3F.unit(
            Float(sin(radians)),
            0,
            Float(-cos(radians))
        )
        return try OrientationAxes(
            frontAxisLocal: front,
            upAxisLocal: .unit(0, 1, 0)
        )
    }

    /// Speaker front/up axes from an azimuth + optional elevation (#228).
    /// Azimuth follows the existing convention: 0° faces −Z, +90° faces
    /// +X. Elevation pitches about the azimuth's right axis, positive up;
    /// at 0° elevation the result is the historical yaw-only aim.
    public static func speakerOrientationAxes(
        azimuthDegrees: Double?,
        elevationDegrees: Double? = nil
    ) throws -> OrientationAxes {
        guard let azimuthDegrees, azimuthDegrees.isFinite else {
            throw ManualAuthorityBuilderError.invalidSpeakerYaw
        }
        let elevation = elevationDegrees ?? 0
        guard elevation.isFinite else {
            throw ManualAuthorityBuilderError.invalidSpeakerElevation
        }
        let yaw = azimuthDegrees * Double.pi / 180.0
        let pitch = elevation * Double.pi / 180.0
        let front = try SpatialVector3F.unit(
            Float(sin(yaw) * cos(pitch)),
            Float(sin(pitch)),
            Float(-cos(yaw) * cos(pitch))
        )
        let up = try SpatialVector3F.unit(
            Float(-sin(yaw) * sin(pitch)),
            Float(cos(pitch)),
            Float(cos(yaw) * sin(pitch))
        )
        return try OrientationAxes(
            frontAxisLocal: front,
            upAxisLocal: up
        )
    }

    /// The full user-attested measurement authority (issues #215,
    /// #238, #253, #275): scalar or vector values, endpoint refs bound
    /// to resolvable spatial authorities, observation time, instrument
    /// calibration metadata, and manufacturer-specification source
    /// identity. Every record this builder emits is
    /// `user_attested_measurement`; derived values go through
    /// `DerivedMeasurementBuilder` instead.
    public static func measurement(
        quantityType: String,
        value: MeasurementValue,
        unit: MeasurementUnit,
        acquisitionMethod: MeasurementAcquisitionMethod,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        endpointRefs: [String] = [],
        instrument: MeasurementInstrument? = nil,
        statedUncertainty: Double? = nil,
        observedAtUTC: String? = nil,
        sourceValueText: String? = nil,
        sourceAuthority: MeasurementSourceAuthority? = nil,
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
             .manufacturerSpecification, .externalInstrument, .other:
            break
        }
        try MeasurementQuantityRegistry.validate(
            quantityType: quantityType,
            value: value,
            unit: unit,
            endpointCount: endpointRefs.count
        )
        return try CaptureMeasurement(
            quantityType: quantityType,
            value: value,
            unit: unit,
            coordinateSpaceID: coordinateSpaceID,
            endpointRefs: endpointRefs,
            acquisitionMethod: acquisitionMethod,
            instrument: instrument,
            statedUncertainty: statedUncertainty,
            observedAtUTC: observedAtUTC,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement,
            sourceValueText: sourceValueText,
            sourceAuthority: sourceAuthority,
            evidenceRefs: evidenceRefs
        )
    }

    public static func scalarMeasurement(
        quantityType: String,
        value: Double,
        unit: MeasurementUnit,
        acquisitionMethod: MeasurementAcquisitionMethod,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        endpointRefs: [String] = [],
        instrument: MeasurementInstrument? = nil,
        statedUncertainty: Double? = nil,
        observedAtUTC: String? = nil,
        sourceValueText: String? = nil,
        sourceAuthority: MeasurementSourceAuthority? = nil,
        evidenceRefs: [String] = []
    ) throws -> CaptureMeasurement {
        try measurement(
            quantityType: quantityType,
            value: .scalar(value),
            unit: unit,
            acquisitionMethod: acquisitionMethod,
            coordinateSpaceID: coordinateSpaceID,
            endpointRefs: endpointRefs,
            instrument: instrument,
            statedUncertainty: statedUncertainty,
            observedAtUTC: observedAtUTC,
            sourceValueText: sourceValueText,
            sourceAuthority: sourceAuthority,
            evidenceRefs: evidenceRefs
        )
    }
}
