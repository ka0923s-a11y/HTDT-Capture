import Foundation

/// Typed speaker channel-role catalog for the authoring UI (legacy bolph71656-ai/HTDT-Capture#220).
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

    /// Roles offered for a subwoofer channel (legacy bolph71656-ai/HTDT-Capture#244): typed instance
    /// tokens so multiple subs stay distinguishable; the token set is
    /// open, so custom entries remain possible under Advanced.
    public static var subwooferRoles: [ChannelRole] {
        [.lfe1, .lfe2, .lfe3, .lfe4]
    }

    /// Whether the role is in the standard set — nonstandard roles are
    /// still valid, the UI just flags them as custom.
    public var isStandardRole: Bool {
        Self.standardRoles.contains(self)
            || Self.subwooferRoles.contains(self)
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
        type.defaultReferenceSemantics
    }
}

/// Seed for editing an existing staged annotation (legacy bolph71656-ai/HTDT-Capture#245). Captures the
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
    /// Prior speaker elevation (pitch) in degrees, derived from
    /// `orientation` — positive when the front axis aims up (legacy bolph71656-ai/HTDT-Capture#228).
    public let elevationDegrees: Float?
    public let channelRole: ChannelRole?
    public let equipmentRef: HTDTEquipmentReference?
    /// Entity's logical role binding (legacy bolph71656-ai/HTDT-Capture#315); survives an edit verbatim
    /// unless the form explicitly re-binds.
    public let originalRoleBinding: SpeakerRoleBinding?
    /// The entity's original provenance fields, reused verbatim when
    /// the operator does not re-capture placement/orientation.
    public let originalPlacement: PlacementProvenance
    public let originalOrientation: OrientationAxes?
    public let originalTransform: Matrix4x4F
    /// Contract fields the form carries but does not structurally
    /// change; they pass through untouched unless the matching form
    /// control supplied a new value.
    public let originalReferencePointSemantics: ReferencePointSemantics
    public let originalReferencePoint: ReferencePointAuthority?
    public let originalPhysicalEnvelope: EntityPhysicalEnvelope?
    public let originalListeningRole: ListeningPositionRole?
    public let originalUncertainty: SpatialUncertaintyAuthority?
    /// Lifecycle keeps its original `created_at_utc`; a save stamps
    /// `updated_at_utc` via `revised(at:)` (legacy bolph71656-ai/HTDT-Capture#267).
    public let originalLifecycle: AnnotationLifecycle?
    /// Type-anchored and cross-revision authorities the form does not
    /// touch — acoustic-center offset, lineage linkage, and the
    /// operator identity binding survive an edit verbatim.
    public let originalAcousticCenter: AcousticCenterOffsetAuthority?
    public let originalLineage: AnnotationEntityLineage?
    public let originalAuthorOperatorID: OperatorProfileID?

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
    /// path (legacy bolph71656-ai/HTDT-Capture#245).
    public init(freshType type: AnnotationEntityType) {
        self.entityID = AnnotationEntityID()
        self.type = type
        self.label = ""
        self.positionMeters = Float3(0, 0, 0)
        self.yawDegrees = nil
        self.elevationDegrees = nil
        self.channelRole = nil
        self.equipmentRef = nil
        self.originalRoleBinding = nil
        self.originalPlacement = try! PlacementProvenance(
            method: .manualNumeric
        )
        self.originalOrientation = nil
        self.originalTransform = .identity
        self.originalReferencePointSemantics =
            type.defaultReferenceSemantics
        self.originalReferencePoint = nil
        self.originalPhysicalEnvelope = nil
        self.originalListeningRole = nil
        self.originalUncertainty = nil
        self.originalLifecycle = nil
        self.originalAcousticCenter = nil
        self.originalLineage = nil
        self.originalAuthorOperatorID = nil
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
        self.elevationDegrees = entity.orientation.map {
            Float(
                asin(
                    max(-1, min(1, Double($0.frontAxisLocal.y)))
                ) * 180 / .pi
            )
        }
        self.channelRole = entity.channelRole
        self.equipmentRef = entity.equipmentRef
        self.originalRoleBinding = entity.roleBinding
        self.originalPlacement = entity.placement
        self.originalOrientation = entity.orientation
        self.originalTransform = entity.worldFromAnnotation
        self.originalReferencePointSemantics =
            entity.referencePointSemantics
        self.originalReferencePoint = entity.referencePoint
        self.originalPhysicalEnvelope = entity.physicalEnvelope
        self.originalListeningRole = entity.listeningRole
        self.originalUncertainty = entity.uncertainty
        self.originalLifecycle = entity.lifecycle
        self.originalAcousticCenter = entity.acousticCenter
        self.originalLineage = entity.lineage
        self.originalAuthorOperatorID = entity.authorOperatorID
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
        roleBinding: SpeakerRoleBinding? = nil,
        equipmentRef: HTDTEquipmentReference?,
        yawDegrees: Float?,
        speakerElevationDegrees: Float? = nil,
        /// Explicit aim removal (legacy bolph71656-ai/HTDT-Capture#228): an edit that clears the yaw
        /// field drops a previously recorded speaker aim rather than
        /// preserving it. Untouched fields never reach here.
        speakerAimRemoved: Bool = false,
        orientationYawDegrees: Float? = nil,
        listeningRole: ListeningPositionRole? = nil,
        referencePointSemantics: ReferencePointSemantics? = nil,
        referencePointConstruction: ReferencePointConstruction? = nil,
        referencePointOffset: SpatialVector3F? = nil,
        physicalEnvelope: EntityPhysicalEnvelope? = nil,
        evidenceSelection: AnnotationEvidenceSelection
    ) throws -> CaptureAnnotationEntity {
        let placement: PlacementProvenance
        var transform: Matrix4x4F
        var placementAuthority: AnnotationPlacementAuthority?
        if let replacementPlacement {
            placement = replacementPlacement.placement
            transform = replacementPlacement.worldFromAnnotation
            placementAuthority = replacementPlacement
        } else if let manualPositionOverride {
            transform = try Matrix4x4F(values: [
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
            transform = originalTransform
        }

        // A fresh evidence-captured placement must say how the
        // semantic point was constructed — the contract is
        // fail-closed here (legacy bolph71656-ai/HTDT-Capture#291). For a roomplan object binding the
        // point is a direct placement, not a surface hit.
        let referencePoint: ReferencePointAuthority?
        if placementAuthority != nil {
            guard let referencePointConstruction else {
                throw ManualAuthorityBuilderError
                    .referencePointConstructionRequired
            }
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
            referencePoint = try ReferencePointAuthority(
                construction: referencePointConstruction,
                offsetMeters:
                    referencePointConstruction == .offsetFromSurface
                    ? referencePointOffset
                    : nil,
                sourceEvidenceRefs:
                    referencePointConstruction
                        == .surfaceHitConfirmed
                        || referencePointConstruction
                            == .offsetFromSurface
                    ? placement.sourceEvidenceRefs
                    : []
            )
        } else if let original = originalReferencePoint,
                  Self.construction(
                      original.construction,
                      isCompatibleWith: placement.method
                  )
        {
            referencePoint = original
        } else {
            referencePoint = nil
        }

        // The contract requires a typed listening role on authored
        // listening positions (legacy bolph71656-ai/HTDT-Capture#243) and channel roles on both
        // speakers and subwoofers (legacy bolph71656-ai/HTDT-Capture#244); roles are rejected outright
        // on types that cannot carry them.
        if type == .listeningPosition, listeningRole == nil {
            throw ManualAuthorityBuilderError.listeningRoleRequired
        }
        if type == .subwoofer, channelRole == nil {
            throw ManualAuthorityBuilderError
                .invalidSubwooferChannelRole
        }
        guard type == .speaker || type == .subwoofer
                || channelRole == nil
        else {
            throw AnnotationModelError.invalidAuthorityComponent
        }
        // A logical role binding only makes sense on a physical
        // loudspeaker (legacy bolph71656-ai/HTDT-Capture#315).
        guard type == .speaker || type == .subwoofer
                || roleBinding == nil
        else {
            throw AnnotationModelError.incompatibleRoleBinding
        }

        let semantics = referencePointSemantics
            ?? (type == self.type
                ? originalReferencePointSemantics
                : type.defaultReferenceSemantics)
        if let allowed = type.allowedReferenceSemantics,
           !allowed.contains(semantics)
        {
            throw AnnotationModelError.invalidReferencePointSemantics
        }

        let requestedOrientation =
            replacementOrientation != nil || yawDegrees != nil
            || speakerElevationDegrees != nil
            || orientationYawDegrees != nil
        if requestedOrientation,
           !type.supportsOrientationAuthority
        {
            throw ManualAuthorityBuilderError
                .orientationNotSupportedForType
        }

        let orientation: OrientationAxes?
        var orientationAuthority: AnnotationOrientationAuthority?
        if let replacementOrientation {
            orientation = replacementOrientation.orientation
            orientationAuthority = replacementOrientation
        } else if let yawDegrees {
            // Speaker aim (legacy bolph71656-ai/HTDT-Capture#228): azimuth plus optional elevation — at
            // 0° elevation the axes equal the historical yaw-only aim.
            orientation = try ManualAuthorityBuilder
                .speakerOrientationAxes(
                    azimuthDegrees: Double(yawDegrees),
                    elevationDegrees:
                        speakerElevationDegrees.map(Double.init)
                )
        } else if speakerElevationDegrees != nil {
            throw ManualAuthorityBuilderError.invalidSpeakerElevation
        } else if let orientationYawDegrees {
            let radians = Double(orientationYawDegrees) * .pi / 180
            orientation = try OrientationAxes(
                frontAxisLocal: .unit(
                    Float(sin(radians)),
                    0,
                    Float(-cos(radians))
                ),
                upAxisLocal: .unit(0, 1, 0)
            )
        } else {
            // A type that cannot carry orientation semantics drops a
            // stale captured body orientation on save; a cleared
            // speaker aim is an explicit removal (legacy bolph71656-ai/HTDT-Capture#228), not a keep.
            orientation = type.supportsOrientationAuthority
                && !speakerAimRemoved
                ? originalOrientation
                : nil
        }

        var selection = evidenceSelection
        selection.replacePlacementAuthority(placementAuthority)
        selection.replaceOrientationAuthority(orientationAuthority)
        let evidenceRefs = selection.effectiveRefs

        let hasAuthority =
            placementAuthority != nil || orientationAuthority != nil
            || placement.method != .manualNumeric

        // Per-component authority, mirroring
        // `ManualAuthorityBuilder.annotation` (legacy bolph71656-ai/HTDT-Capture#263): preserved
        // evidence-linked placements still count as evidence-linked
        // even though no fresh authority object exists this session.
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
                    || placement.method != .manualNumeric
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
            equipment: try equipmentRef.map { ref in
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
                || listeningRole != nil || roleBinding != nil)
                ? AnnotationComponentAuthority(state: .userAttested)
                : nil
        )

        let now = BundleTimestamp.utcString(from: Date())
        let lifecycle = try originalLifecycle?.revised(at: now)
            ?? AnnotationLifecycle(createdAtUTC: now)

        return try CaptureAnnotationEntity(
            entityID: entityID,
            type: type,
            coordinateSpaceID: coordinateSpaceID,
            worldFromAnnotation: transform,
            referencePointSemantics: semantics,
            label: label,
            provenanceClass: .userAnnotation,
            verificationState: hasAuthority
                ? .evidenceLinked
                : .userAttested,
            placement: placement,
            orientation: orientation,
            channelRole: channelRole,
            roleBinding: roleBinding,
            acousticCenter: type == self.type
                ? originalAcousticCenter
                : nil,
            equipmentRef: equipmentRef,
            evidenceRefs: evidenceRefs,
            physicalEnvelope: type == self.type
                ? (physicalEnvelope ?? originalPhysicalEnvelope)
                : physicalEnvelope,
            listeningRole: type == .listeningPosition
                ? (listeningRole ?? originalListeningRole)
                : nil,
            uncertainty: originalUncertainty,
            authority: authority,
            lifecycle: lifecycle,
            referencePoint: referencePoint,
            lineage: originalLineage,
            authorOperatorID: originalAuthorOperatorID
        )
    }

    /// Matches the entity contract: surface-aware constructions only
    /// apply to surface-derived placement methods (legacy bolph71656-ai/HTDT-Capture#291).
    private static func construction(
        _ construction: ReferencePointConstruction,
        isCompatibleWith method: PlacementMethod
    ) -> Bool {
        let surfaceDerived =
            method == .raycast || method == .meshHitTest
        switch construction {
        case .surfaceHitConfirmed, .offsetFromSurface:
            return surfaceDerived
        case .directPlacement:
            return !surfaceDerived
        case .importedReference:
            return true
        }
    }
}

/// Seed for editing an existing staged measurement (legacy bolph71656-ai/HTDT-Capture#245) — preserves
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
    /// Fields the scalar edit form does not touch; they describe what
    /// was measured (endpoints, spatial authority, lineage, operator
    /// identity) and therefore survive an edit verbatim.
    public let originalCoordinateSpaceID: CoordinateSpaceID?
    public let originalEndpointRefs: [String]
    public let originalObservedAtUTC: String?
    public let originalSourceAuthority: MeasurementSourceAuthority?
    public let originalUncertainty: MeasurementUncertainty?
    public let originalLineage: MeasurementLineage?
    public let originalInstrumentAuthority:
        MeasurementInstrumentReference?
    public let originalAuthorOperatorID: OperatorProfileID?

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
        self.originalCoordinateSpaceID =
            measurement.coordinateSpaceID
        self.originalEndpointRefs = measurement.endpointRefs
        self.originalObservedAtUTC = measurement.observedAtUTC
        self.originalSourceAuthority = measurement.sourceAuthority
        self.originalUncertainty = measurement.uncertainty
        self.originalLineage = measurement.lineage
        self.originalInstrumentAuthority =
            measurement.instrumentAuthority
        self.originalAuthorOperatorID =
            measurement.authorOperatorID
    }
}

/// Rebuilds an edited measurement preserving identity (legacy bolph71656-ai/HTDT-Capture#245). Covers
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
        guard let scopedQuantityType =
            OpenTokenPolicy.scopedForAuthoring(
                quantityType,
                vocabulary: .measurementQuantity
            )
        else {
            throw MeasurementModelError.unscopedCustomQuantity
        }
        // A re-authored value is a new user attestation — the
        // derivation record is intentionally not carried (the result
        // is no longer computed), while endpoint/spatial authority,
        // lineage, instrument authority, and operator binding describe
        // what was measured rather than how and therefore survive.
        let uncertainty: MeasurementUncertainty?
        if let original = seed.originalUncertainty,
           (original.unit?.dimension ?? unit.dimension) == unit.dimension,
           statedUncertainty == nil
            || statedUncertainty == original.value
        {
            uncertainty = original
        } else {
            uncertainty = nil
        }
        return try CaptureMeasurement(
            measurementID: seed.measurementID,
            quantityType: scopedQuantityType,
            value: .scalar(value),
            unit: unit,
            coordinateSpaceID: seed.originalEndpointRefs.isEmpty
                ? nil
                : seed.originalCoordinateSpaceID,
            endpointRefs: seed.originalEndpointRefs,
            acquisitionMethod: acquisitionMethod,
            instrument: instrument,
            statedUncertainty: statedUncertainty,
            observedAtUTC: seed.originalObservedAtUTC,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement,
            sourceValueText: sourceValueText,
            sourceAuthority:
                acquisitionMethod == .manufacturerSpecification
                ? seed.originalSourceAuthority
                : nil,
            uncertainty: uncertainty,
            lineage: seed.originalLineage,
            instrumentAuthority: seed.originalInstrumentAuthority,
            authorOperatorID: seed.originalAuthorOperatorID,
            evidenceRefs: evidenceRefs
        )
    }
}
