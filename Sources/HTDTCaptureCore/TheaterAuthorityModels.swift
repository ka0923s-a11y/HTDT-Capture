import Foundation

/// Errors raised while constructing theater-semantic authority records.
/// Shared argument failures (empty labels, duplicate refs, non-finite
/// geometry) reuse `AnnotationModelError`; cases here are the rules that
/// are unique to the authority contract.
public enum TheaterAuthorityError: Error, Sendable, Equatable {
    case missingSourceBinding
    case invalidPatchGeometry
    case nonPositiveDimension
    case invalidObservedTimestamp
    case duplicateAuthorityRecordID
    case unresolvedObservationReference
    case unresolvedFeatureReference
    case unresolvedEntityReference
    case snapshotWithoutObservations
    /// A rack placement asserting no slot, label, facing, or evidence.
    case emptyPlacementObservation
    /// A rack placement's `host_rack_entity_id` disagrees with the
    /// item's rack membership (legacy bolph71656-ai/HTDT-Capture#402).
    case rackPlacementRackMismatch
}

public struct AuthorityRecordID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct RoomStateObservationID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct RoomStateSnapshotID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Exact, reopenable lineage to a captured surface or bounded patch.
/// A binding never synthesizes geometry: it only names the RoomPlan
/// surface/object, mesh anchor, or operator-outlined polygon that the
/// authority record is about, plus the evidence frames that support it.
public struct SurfaceRegionBinding: Codable, Sendable, Equatable {
    public let coordinateSpaceID: CoordinateSpaceID
    /// `CapturedRoom` surface identifier text (wall/opening/door).
    public let roomPlanSurfaceID: String?
    /// `CapturedRoom` object identifier text.
    public let roomPlanObjectID: String?
    /// Committed mesh anchor the patch belongs to.
    public let meshAnchorID: UUID?
    /// Mesh-anchor-local triangle indices bounding the patch. Requires
    /// `meshAnchorID`.
    public let triangleIndices: [Int]?
    /// App-assigned semantic entity identifier when the surface was
    /// produced by a capture-side semantic pass.
    public let semanticEntityID: String?
    /// World-space patch outline: empty or at least three vertices.
    public let polygonWorld: [SpatialVector3F]
    public let centroidWorld: SpatialVector3F?
    /// Unit surface normal when the host orientation is attested.
    public let normalWorld: SpatialVector3F?
    public let evidenceRefs: [String]

    public init(
        coordinateSpaceID: CoordinateSpaceID,
        roomPlanSurfaceID: String? = nil,
        roomPlanObjectID: String? = nil,
        meshAnchorID: UUID? = nil,
        triangleIndices: [Int]? = nil,
        semanticEntityID: String? = nil,
        polygonWorld: [SpatialVector3F] = [],
        centroidWorld: SpatialVector3F? = nil,
        normalWorld: SpatialVector3F? = nil,
        evidenceRefs: [String] = []
    ) throws {
        let normalizedSurface =
            SchemaOwnedText.nfc(roomPlanSurfaceID)
        let normalizedObject =
            SchemaOwnedText.nfc(roomPlanObjectID)
        let normalizedSemantic =
            SchemaOwnedText.nfc(semanticEntityID)
        for value in [
            normalizedSurface, normalizedObject, normalizedSemantic,
        ] {
            if let value, value.isEmpty {
                throw AnnotationModelError.emptyAuthorityReference
            }
        }
        if let triangleIndices {
            guard meshAnchorID != nil,
                  !triangleIndices.isEmpty,
                  triangleIndices.allSatisfy({ $0 >= 0 })
            else {
                throw TheaterAuthorityError.invalidPatchGeometry
            }
        }
        guard polygonWorld.isEmpty || polygonWorld.count >= 3 else {
            throw TheaterAuthorityError.invalidPatchGeometry
        }
        if let normalWorld {
            guard abs(normalWorld.magnitude - 1) <= 0.001 else {
                throw AnnotationModelError.invalidAxis
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }

        // At least one lineage anchor must be present so the binding is
        // reopenable against committed geometry.
        guard normalizedSurface != nil
                || normalizedObject != nil
                || meshAnchorID != nil
                || normalizedSemantic != nil
                || !polygonWorld.isEmpty
        else {
            throw TheaterAuthorityError.missingSourceBinding
        }

        self.coordinateSpaceID = coordinateSpaceID
        self.roomPlanSurfaceID = normalizedSurface
        self.roomPlanObjectID = normalizedObject
        self.meshAnchorID = meshAnchorID
        self.triangleIndices = triangleIndices
        self.semanticEntityID = normalizedSemantic
        self.polygonWorld = polygonWorld
        self.centroidWorld = centroidWorld
        self.normalWorld = normalWorld
        self.evidenceRefs = normalizedEvidence.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case coordinateSpaceID = "coordinate_space_id"
        case roomPlanSurfaceID = "roomplan_surface_id"
        case roomPlanObjectID = "roomplan_object_id"
        case meshAnchorID = "mesh_anchor_id"
        case triangleIndices = "triangle_indices"
        case semanticEntityID = "semantic_entity_id"
        case polygonWorld = "polygon_world"
        case centroidWorld = "centroid_world"
        case normalWorld = "normal_world"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            roomPlanSurfaceID: container.decodeIfPresent(
                String.self,
                forKey: .roomPlanSurfaceID
            ),
            roomPlanObjectID: container.decodeIfPresent(
                String.self,
                forKey: .roomPlanObjectID
            ),
            meshAnchorID: container.decodeIfPresent(
                UUID.self,
                forKey: .meshAnchorID
            ),
            triangleIndices: container.decodeIfPresent(
                [Int].self,
                forKey: .triangleIndices
            ),
            semanticEntityID: container.decodeIfPresent(
                String.self,
                forKey: .semanticEntityID
            ),
            polygonWorld: container.decodeIfPresent(
                [SpatialVector3F].self,
                forKey: .polygonWorld
            ) ?? [],
            centroidWorld: container.decodeIfPresent(
                SpatialVector3F.self,
                forKey: .centroidWorld
            ),
            normalWorld: container.decodeIfPresent(
                SpatialVector3F.self,
                forKey: .normalWorld
            ),
            evidenceRefs: container.decodeIfPresent(
                [String].self,
                forKey: .evidenceRefs
            ) ?? []
        )
    }
}

/// User-attested host classification for a bound surface (legacy bolph71656-ai/HTDT-Capture#218). The
/// operator attests the class; the app never guesses it.
public enum SurfaceHostClassification: String, Codable, Sendable, CaseIterable {
    case roomBoundary = "room_boundary"
    case objectSurface = "object_surface"
    case unknown
}

/// Optional treatment placement metadata carried by a surface-semantic
/// authority (legacy bolph71656-ai/HTDT-Capture#218). It describes coverage, never physics: no
/// absorption or material coefficients are synthesized here.
public struct TreatmentPlacementAuthority: Codable, Sendable, Equatable {
    public let footprintWidthMeters: Double?
    public let footprintHeightMeters: Double?
    /// Offset of the treatment plane from the host surface, in meters,
    /// when the operator explicitly attests it.
    public let surfaceOffsetMeters: Double?
    /// Declared air gap behind the treatment, in meters.
    public let airGapMeters: Double?
    public let notes: String?
    /// Exact HTDT catalog tuple when an exact treatment authority
    /// exists; nil stays user-authored-only.
    public let equipmentRef: HTDTEquipmentReference?

    public init(
        footprintWidthMeters: Double? = nil,
        footprintHeightMeters: Double? = nil,
        surfaceOffsetMeters: Double? = nil,
        airGapMeters: Double? = nil,
        notes: String? = nil,
        equipmentRef: HTDTEquipmentReference? = nil
    ) throws {
        for dimension in [
            footprintWidthMeters,
            footprintHeightMeters,
            surfaceOffsetMeters,
            airGapMeters,
        ] {
            if let dimension {
                guard dimension.isFinite, dimension >= 0 else {
                    throw TheaterAuthorityError.nonPositiveDimension
                }
            }
        }
        let normalizedNotes = SchemaOwnedText.nfc(notes)
        if let normalizedNotes, normalizedNotes.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard footprintWidthMeters != nil
                || footprintHeightMeters != nil
                || surfaceOffsetMeters != nil
                || airGapMeters != nil
                || normalizedNotes != nil
                || equipmentRef != nil
        else {
            throw TheaterAuthorityError.missingSourceBinding
        }
        self.footprintWidthMeters = footprintWidthMeters
        self.footprintHeightMeters = footprintHeightMeters
        self.surfaceOffsetMeters = surfaceOffsetMeters
        self.airGapMeters = airGapMeters
        self.notes = normalizedNotes
        self.equipmentRef = equipmentRef
    }

    private enum CodingKeys: String, CodingKey {
        case footprintWidthMeters = "footprint_width_m"
        case footprintHeightMeters = "footprint_height_m"
        case surfaceOffsetMeters = "surface_offset_m"
        case airGapMeters = "air_gap_m"
        case notes
        case equipmentRef = "equipment_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            footprintWidthMeters: container.decodeIfPresent(
                Double.self,
                forKey: .footprintWidthMeters
            ),
            footprintHeightMeters: container.decodeIfPresent(
                Double.self,
                forKey: .footprintHeightMeters
            ),
            surfaceOffsetMeters: container.decodeIfPresent(
                Double.self,
                forKey: .surfaceOffsetMeters
            ),
            airGapMeters: container.decodeIfPresent(
                Double.self,
                forKey: .airGapMeters
            ),
            notes: container.decodeIfPresent(String.self, forKey: .notes),
            equipmentRef: container.decodeIfPresent(
                HTDTEquipmentReference.self,
                forKey: .equipmentRef
            )
        )
    }
}

/// Explicit, spatially extended surface authority (legacy bolph71656-ai/HTDT-Capture#218): binds a
/// user-attested host classification — and optionally a treatment
/// footprint — to exact captured geometry. This is the promotion input
/// for HTDT `SurfaceSemanticAssignment`; it is not itself a semantic
/// surface.
public struct SurfaceSemanticAuthority: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    public let label: String?
    public let binding: SurfaceRegionBinding
    public let hostClassification: SurfaceHostClassification
    public let treatment: TreatmentPlacementAuthority?

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        label: String? = nil,
        binding: SurfaceRegionBinding,
        hostClassification: SurfaceHostClassification,
        treatment: TreatmentPlacementAuthority? = nil
    ) throws {
        let normalizedLabel = SchemaOwnedText.nfc(label)
        if let normalizedLabel, normalizedLabel.isEmpty {
            throw AnnotationModelError.emptyLabel
        }
        self.authorityID = authorityID
        self.label = normalizedLabel
        self.binding = binding
        self.hostClassification = hostClassification
        self.treatment = treatment
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case label
        case binding
        case hostClassification = "host_classification"
        case treatment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            label: container.decodeIfPresent(
                String.self,
                forKey: .label
            ),
            binding: container.decode(
                SurfaceRegionBinding.self,
                forKey: .binding
            ),
            hostClassification: container.decode(
                SurfaceHostClassification.self,
                forKey: .hostClassification
            ),
            treatment: container.decodeIfPresent(
                TreatmentPlacementAuthority.self,
                forKey: .treatment
            )
        )
    }
}

/// Where a construction/material identity claim comes from (legacy bolph71656-ai/HTDT-Capture#233).
/// The observation is a material-authoring candidate; acoustic
/// coefficient authority stays a separate downstream step.
public enum ConstructionObservationSource: String, Codable, Sendable, CaseIterable {
    case userObservation = "user_observation"
    case installerOrBuildRecord = "installer_or_build_record"
    case manufacturerReference = "manufacturer_reference"
    case catalogReference = "catalog_reference"
    case other
}

/// Common construction identities for room boundaries. `other` plus the
/// optional detail text keep the set honest: an unknown material is a
/// first-class record, never a guessed one.
public enum SurfaceConstructionKind: String, Codable, Sendable, CaseIterable {
    case gypsumDrywall = "gypsum_drywall"
    case concreteMasonry = "concrete_masonry"
    case glass
    case woodPanel = "wood_panel"
    case carpet
    case hardFloor = "hard_floor"
    case fabric
    case other
    case unknown
}

public struct SurfaceConstructionObservation: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    public let binding: SurfaceRegionBinding
    public let constructionKind: SurfaceConstructionKind
    public let materialDetail: String?
    public let source: ConstructionObservationSource

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        binding: SurfaceRegionBinding,
        constructionKind: SurfaceConstructionKind,
        materialDetail: String? = nil,
        source: ConstructionObservationSource
    ) throws {
        let normalizedDetail = SchemaOwnedText.nfc(materialDetail)
        if let normalizedDetail, normalizedDetail.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        self.authorityID = authorityID
        self.binding = binding
        self.constructionKind = constructionKind
        self.materialDetail = normalizedDetail
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case binding
        case constructionKind = "construction_kind"
        case materialDetail = "material_detail"
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            binding: container.decode(
                SurfaceRegionBinding.self,
                forKey: .binding
            ),
            constructionKind: container.decode(
                SurfaceConstructionKind.self,
                forKey: .constructionKind
            ),
            materialDetail: container.decodeIfPresent(
                String.self,
                forKey: .materialDetail
            ),
            source: container.decode(
                ConstructionObservationSource.self,
                forKey: .source
            )
        )
    }
}

/// Operator-declared geometry-reliability concern (legacy bolph71656-ai/HTDT-Capture#256). The mark is a
/// downstream caution flag, not a material classification and never a
/// geometry rewrite.
public enum ProblemSurfaceKind: String, Codable, Sendable, CaseIterable {
    case mirror
    case transparent
    case darkAbsorptive = "dark_absorptive"
    case occluded
    case other
}

public struct ProblemSurfaceObservation: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    public let binding: SurfaceRegionBinding
    public let kind: ProblemSurfaceKind
    public let notes: String?

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        binding: SurfaceRegionBinding,
        kind: ProblemSurfaceKind,
        notes: String? = nil
    ) throws {
        let normalizedNotes = SchemaOwnedText.nfc(notes)
        if let normalizedNotes, normalizedNotes.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        self.authorityID = authorityID
        self.binding = binding
        self.kind = kind
        self.notes = normalizedNotes
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case binding
        case kind
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            binding: container.decode(
                SurfaceRegionBinding.self,
                forKey: .binding
            ),
            kind: container.decode(
                ProblemSurfaceKind.self,
                forKey: .kind
            ),
            notes: container.decodeIfPresent(
                String.self,
                forKey: .notes
            )
        )
    }
}

/// Bounded theater-construction feature (legacy bolph71656-ai/HTDT-Capture#262). Candidates stay
/// derived/user-attested authoring input — they never rewrite raw
/// RoomPlan/mesh evidence.
public enum ConstructionFeatureKind: String, Codable, Sendable, CaseIterable {
    case riser
    case stage
    case soffit
    case beam
    case partialHeightWall = "partial_height_wall"
    case column
    case alcove
    case slopedCeiling = "sloped_ceiling"
    case other
}

/// Whether the classification came from the operator or was suggested
/// by the app. Distinction is preserved per record even though the
/// file-level provenance stays `user_annotation`.
public enum SemanticConfirmationSource: String, Codable, Sendable, CaseIterable {
    case userConfirmed = "user_confirmed"
    case captureAppSuggested = "capture_app_suggested"
    case importedReference = "imported_reference"
}

public struct ConstructionFeatureCandidate: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    public let binding: SurfaceRegionBinding
    public let kind: ConstructionFeatureKind
    public let confirmationSource: SemanticConfirmationSource
    public let label: String?

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        binding: SurfaceRegionBinding,
        kind: ConstructionFeatureKind,
        confirmationSource: SemanticConfirmationSource,
        label: String? = nil
    ) throws {
        let normalizedLabel = SchemaOwnedText.nfc(label)
        if let normalizedLabel, normalizedLabel.isEmpty {
            throw AnnotationModelError.emptyLabel
        }
        self.authorityID = authorityID
        self.binding = binding
        self.kind = kind
        self.confirmationSource = confirmationSource
        self.label = normalizedLabel
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case binding
        case kind
        case confirmationSource = "confirmation_source"
        case label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            binding: container.decode(
                SurfaceRegionBinding.self,
                forKey: .binding
            ),
            kind: container.decode(
                ConstructionFeatureKind.self,
                forKey: .kind
            ),
            confirmationSource: container.decode(
                SemanticConfirmationSource.self,
                forKey: .confirmationSource
            ),
            label: container.decodeIfPresent(
                String.self,
                forKey: .label
            )
        )
    }
}

/// Time-varying element whose state was observed (legacy bolph71656-ai/HTDT-Capture#264). States are
/// operator-attested; nothing is inferred from images.
public enum RoomStateKind: String, Codable, Sendable, CaseIterable {
    case curtain
    case movablePanel = "movable_panel"
    case door
    case window
    case screenMasking = "screen_masking"
    case seatPosture = "seat_posture"
    case hvac
    case airPurifier = "air_purifier"
    case lighting
    case removableElement = "removable_element"
    case other
}

public enum RoomStateValue: String, Codable, Sendable, CaseIterable {
    case open
    case closed
    case deployed
    case stowed
    case on
    case off
    case reclined
    case upright
    case present
    case absent
    case unknown
    case other
}

public struct RoomStateObservation: Codable, Sendable, Equatable {
    public let observationID: RoomStateObservationID
    public let kind: RoomStateKind
    public let state: RoomStateValue
    /// Free-text mode/detail when the closed `state` token is not
    /// enough (e.g. an HVAC fan mode). Never required.
    public let stateDetail: String?
    /// Entity the state applies to when it has one (e.g. a door or
    /// screen annotation); nil means room-wide.
    public let targetEntityID: AnnotationEntityID?
    /// Surface authority record the state applies to when it has one.
    public let targetAuthorityID: AuthorityRecordID?
    /// Coordinate space the evidence links resolve in. Required
    /// whenever `evidenceRefs` is non-empty so congruence stays
    /// provable for room-wide observations too.
    public let coordinateSpaceID: CoordinateSpaceID?
    public let observedAtUTC: String
    public let evidenceRefs: [String]

    public init(
        observationID: RoomStateObservationID = RoomStateObservationID(),
        kind: RoomStateKind,
        state: RoomStateValue,
        stateDetail: String? = nil,
        targetEntityID: AnnotationEntityID? = nil,
        targetAuthorityID: AuthorityRecordID? = nil,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        observedAtUTC: String,
        evidenceRefs: [String] = []
    ) throws {
        let normalizedDetail = SchemaOwnedText.nfc(stateDetail)
        if let normalizedDetail, normalizedDetail.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard SchemaTimestampText.isUTCTimestamp(observedAtUTC) else {
            throw TheaterAuthorityError.invalidObservedTimestamp
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        guard normalizedEvidence.isEmpty || coordinateSpaceID != nil
        else {
            throw TheaterAuthorityError.missingSourceBinding
        }
        self.observationID = observationID
        self.kind = kind
        self.state = state
        self.stateDetail = normalizedDetail
        self.targetEntityID = targetEntityID
        self.targetAuthorityID = targetAuthorityID
        self.coordinateSpaceID = coordinateSpaceID
        self.observedAtUTC = observedAtUTC
        self.evidenceRefs = normalizedEvidence.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case observationID = "observation_id"
        case kind
        case state
        case stateDetail = "state_detail"
        case targetEntityID = "target_entity_id"
        case targetAuthorityID = "target_authority_id"
        case coordinateSpaceID = "coordinate_space_id"
        case observedAtUTC = "observed_at_utc"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            observationID: container.decode(
                RoomStateObservationID.self,
                forKey: .observationID
            ),
            kind: container.decode(RoomStateKind.self, forKey: .kind),
            state: container.decode(RoomStateValue.self, forKey: .state),
            stateDetail: container.decodeIfPresent(
                String.self,
                forKey: .stateDetail
            ),
            targetEntityID: container.decodeIfPresent(
                AnnotationEntityID.self,
                forKey: .targetEntityID
            ),
            targetAuthorityID: container.decodeIfPresent(
                AuthorityRecordID.self,
                forKey: .targetAuthorityID
            ),
            coordinateSpaceID: container.decodeIfPresent(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            observedAtUTC: container.decode(
                String.self,
                forKey: .observedAtUTC
            ),
            evidenceRefs: container.decodeIfPresent(
                [String].self,
                forKey: .evidenceRefs
            ) ?? []
        )
    }
}

/// Immutable named set of operating conditions true together at capture
/// time (legacy bolph71656-ai/HTDT-Capture#264). A snapshot is a version point: a deliberate room-state
/// change produces a new snapshot, never a mutation of the prior one.
/// `stateDigest` is SHA-256 over the canonical encoding of the sorted
/// resolved observation records, so the bound set is content-addressed.
public struct RoomStateSnapshot: Codable, Sendable, Equatable {
    public let snapshotID: RoomStateSnapshotID
    public let label: String
    public let captureRevisionID: CaptureRevisionID
    public let observedAtUTC: String
    public let observationIDs: [RoomStateObservationID]
    public let campaignID: String?
    public let stateDigest: EvidenceSHA256

    public init(
        snapshotID: RoomStateSnapshotID = RoomStateSnapshotID(),
        label: String,
        captureRevisionID: CaptureRevisionID,
        observedAtUTC: String,
        observationIDs: [RoomStateObservationID],
        campaignID: String? = nil,
        stateDigest: EvidenceSHA256
    ) throws {
        let normalizedLabel = SchemaOwnedText.nfc(label)
        guard !normalizedLabel.isEmpty else {
            throw AnnotationModelError.emptyLabel
        }
        guard SchemaTimestampText.isUTCTimestamp(observedAtUTC) else {
            throw TheaterAuthorityError.invalidObservedTimestamp
        }
        guard !observationIDs.isEmpty else {
            throw TheaterAuthorityError.snapshotWithoutObservations
        }
        guard Set(observationIDs).count == observationIDs.count else {
            throw TheaterAuthorityError.unresolvedObservationReference
        }
        let normalizedCampaign = SchemaOwnedText.nfc(campaignID)
        if let normalizedCampaign, normalizedCampaign.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        self.snapshotID = snapshotID
        self.label = normalizedLabel
        self.captureRevisionID = captureRevisionID
        self.observedAtUTC = observedAtUTC
        self.observationIDs = observationIDs
        self.campaignID = normalizedCampaign
        self.stateDigest = stateDigest
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case label
        case captureRevisionID = "capture_revision_id"
        case observedAtUTC = "observed_at_utc"
        case observationIDs = "observation_ids"
        case campaignID = "campaign_id"
        case stateDigest = "state_digest"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            snapshotID: container.decode(
                RoomStateSnapshotID.self,
                forKey: .snapshotID
            ),
            label: container.decode(String.self, forKey: .label),
            captureRevisionID: container.decode(
                CaptureRevisionID.self,
                forKey: .captureRevisionID
            ),
            observedAtUTC: container.decode(
                String.self,
                forKey: .observedAtUTC
            ),
            observationIDs: container.decode(
                [RoomStateObservationID].self,
                forKey: .observationIDs
            ),
            campaignID: container.decodeIfPresent(
                String.self,
                forKey: .campaignID
            ),
            stateDigest: container.decode(
                EvidenceSHA256.self,
                forKey: .stateDigest
            )
        )
    }
}

/// Physical electronics inventory item (legacy bolph71656-ai/HTDT-Capture#281). Distinct from spatial
/// acoustic annotations: an inventory record is evidence-bound identity
/// for AV electronics, not a placement authority. `worldFromItem` is
/// present only when a physical location was actually captured.
public enum InventoryEquipmentClass: String, Codable, Sendable, CaseIterable {
    case avReceiver = "av_receiver"
    case avProcessor = "av_processor"
    case powerAmplifier = "power_amplifier"
    case dspUnit = "dsp_unit"
    case projector
    case display
    case sourceDevice = "source_device"
    case measurementInterface = "measurement_interface"
    case other
}

public struct SystemInventoryItem: Codable, Sendable, Equatable,
    Identifiable
{
    public let itemID: AuthorityRecordID
    public var id: AuthorityRecordID { itemID }
    public let equipmentClass: InventoryEquipmentClass
    public let manufacturer: String?
    public let model: String?
    /// Operator-facing label. Required: a catalog-free unit must still
    /// be addressable.
    public let userLabel: String
    /// Exact HTDT equipment-definition tuple when one exists.
    public let equipmentRef: HTDTEquipmentReference?
    /// Serial/asset text, only when the operator explicitly records it.
    public let serialNumber: String?
    /// `equipment_rack` entity hosting the unit, when known. Membership
    /// is representable independently of a captured spatial position.
    public let hostRackEntityID: AnnotationEntityID?
    public let coordinateSpaceID: CoordinateSpaceID?
    public let worldFromItem: Matrix4x4F?
    public let evidenceRefs: [String]

    public init(
        itemID: AuthorityRecordID = AuthorityRecordID(),
        equipmentClass: InventoryEquipmentClass,
        manufacturer: String? = nil,
        model: String? = nil,
        userLabel: String,
        equipmentRef: HTDTEquipmentReference? = nil,
        serialNumber: String? = nil,
        hostRackEntityID: AnnotationEntityID? = nil,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        worldFromItem: Matrix4x4F? = nil,
        evidenceRefs: [String] = []
    ) throws {
        let normalizedLabel = SchemaOwnedText.nfc(userLabel)
        guard !normalizedLabel.isEmpty else {
            throw AnnotationModelError.emptyLabel
        }
        let normalizedManufacturer =
            SchemaOwnedText.nfc(manufacturer)
        let normalizedModel = SchemaOwnedText.nfc(model)
        let normalizedSerial = SchemaOwnedText.nfc(serialNumber)
        for value in [
            normalizedManufacturer, normalizedModel, normalizedSerial,
        ] {
            if let value, value.isEmpty {
                throw AnnotationModelError.emptyAuthorityReference
            }
        }
        // A spatial pose requires the coordinate authority it is
        // expressed in, and evidence links are only congruent once a
        // space is bound.
        guard (worldFromItem == nil) == (coordinateSpaceID == nil) else {
            throw TheaterAuthorityError.missingSourceBinding
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        guard normalizedEvidence.isEmpty || coordinateSpaceID != nil
        else {
            throw TheaterAuthorityError.missingSourceBinding
        }
        self.itemID = itemID
        self.equipmentClass = equipmentClass
        self.manufacturer = normalizedManufacturer
        self.model = normalizedModel
        self.userLabel = normalizedLabel
        self.equipmentRef = equipmentRef
        self.serialNumber = normalizedSerial
        self.hostRackEntityID = hostRackEntityID
        self.coordinateSpaceID = coordinateSpaceID
        self.worldFromItem = worldFromItem
        self.evidenceRefs = normalizedEvidence.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case equipmentClass = "equipment_class"
        case manufacturer
        case model
        case userLabel = "user_label"
        case equipmentRef = "equipment_ref"
        case serialNumber = "serial_number"
        case hostRackEntityID = "host_rack_entity_id"
        case coordinateSpaceID = "coordinate_space_id"
        case worldFromItem = "T_world_from_item"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            itemID: container.decode(
                AuthorityRecordID.self,
                forKey: .itemID
            ),
            equipmentClass: container.decode(
                InventoryEquipmentClass.self,
                forKey: .equipmentClass
            ),
            manufacturer: container.decodeIfPresent(
                String.self,
                forKey: .manufacturer
            ),
            model: container.decodeIfPresent(
                String.self,
                forKey: .model
            ),
            userLabel: container.decode(
                String.self,
                forKey: .userLabel
            ),
            equipmentRef: container.decodeIfPresent(
                HTDTEquipmentReference.self,
                forKey: .equipmentRef
            ),
            serialNumber: container.decodeIfPresent(
                String.self,
                forKey: .serialNumber
            ),
            hostRackEntityID: container.decodeIfPresent(
                AnnotationEntityID.self,
                forKey: .hostRackEntityID
            ),
            coordinateSpaceID: container.decodeIfPresent(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            worldFromItem: container.decodeIfPresent(
                Matrix4x4F.self,
                forKey: .worldFromItem
            ),
            evidenceRefs: container.decodeIfPresent(
                [String].self,
                forKey: .evidenceRefs
            ) ?? []
        )
    }
}

/// Which side of a rack slot presents the unit's front panel (legacy bolph71656-ai/HTDT-Capture#402).
public enum RackFacing: String, Codable, Sendable, CaseIterable {
    case front
    case rear
    case side
    case unknown
}

/// Where one inventory unit sits inside its host rack (legacy bolph71656-ai/HTDT-Capture#402).
/// Placement is observation authority separate from the item's
/// identity: a unit keeps its model/serial when it moves slots, and
/// `SystemInventoryItem.hostRackEntityID` records membership only, so
/// ordered slot/facing authority lives here rather than overloading
/// spatial XYZ.
public struct RackPlacementObservation: Codable, Sendable, Equatable {
    public let placementID: AuthorityRecordID
    /// Inventory item this placement describes.
    public let itemID: AuthorityRecordID
    /// `equipment_rack` entity the unit occupies. Must equal the
    /// item's `hostRackEntityID` — the collection enforces it.
    public let hostRackEntityID: AnnotationEntityID
    /// 1-based rack-unit position counted from the bottom.
    public let rackUnitPosition: Int?
    /// Free slot label ("top shelf", "rear rail") when the rack has no
    /// unit numbering.
    public let shelfSlotLabel: String?
    public let facing: RackFacing?
    /// Coordinate authority any evidence refs resolve in — never a
    /// pose; spatial placement stays on the item.
    public let coordinateSpaceID: CoordinateSpaceID?
    /// Evidence refs supporting the observation (e.g. a label photo).
    public let evidenceRefs: [String]

    public init(
        placementID: AuthorityRecordID = AuthorityRecordID(),
        itemID: AuthorityRecordID,
        hostRackEntityID: AnnotationEntityID,
        rackUnitPosition: Int? = nil,
        shelfSlotLabel: String? = nil,
        facing: RackFacing? = nil,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        evidenceRefs: [String] = []
    ) throws {
        if let rackUnitPosition, rackUnitPosition < 1 {
            throw TheaterAuthorityError.nonPositiveDimension
        }
        let normalizedSlot = SchemaOwnedText.nfc(shelfSlotLabel)
        if let normalizedSlot, normalizedSlot.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AnnotationModelError.duplicateEvidenceReference
        }
        // A placement asserting nothing — no slot, label, facing, or
        // evidence — carries no observation.
        guard rackUnitPosition != nil || normalizedSlot != nil
            || facing != nil || !normalizedEvidence.isEmpty
        else {
            throw TheaterAuthorityError.emptyPlacementObservation
        }
        guard normalizedEvidence.isEmpty || coordinateSpaceID != nil
        else {
            throw TheaterAuthorityError.missingSourceBinding
        }
        self.placementID = placementID
        self.itemID = itemID
        self.hostRackEntityID = hostRackEntityID
        self.rackUnitPosition = rackUnitPosition
        self.shelfSlotLabel = normalizedSlot
        self.facing = facing
        self.coordinateSpaceID = coordinateSpaceID
        self.evidenceRefs = normalizedEvidence.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case placementID = "placement_id"
        case itemID = "item_id"
        case hostRackEntityID = "host_rack_entity_id"
        case rackUnitPosition = "rack_unit_position"
        case shelfSlotLabel = "shelf_slot_label"
        case facing
        case coordinateSpaceID = "coordinate_space_id"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            placementID: container.decode(
                AuthorityRecordID.self,
                forKey: .placementID
            ),
            itemID: container.decode(
                AuthorityRecordID.self,
                forKey: .itemID
            ),
            hostRackEntityID: container.decode(
                AnnotationEntityID.self,
                forKey: .hostRackEntityID
            ),
            rackUnitPosition: container.decodeIfPresent(
                Int.self,
                forKey: .rackUnitPosition
            ),
            shelfSlotLabel: container.decodeIfPresent(
                String.self,
                forKey: .shelfSlotLabel
            ),
            facing: container.decodeIfPresent(
                RackFacing.self,
                forKey: .facing
            ),
            coordinateSpaceID: container.decodeIfPresent(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            evidenceRefs: container.decodeIfPresent(
                [String].self,
                forKey: .evidenceRefs
            ) ?? []
        )
    }
}

public enum FurnitureCategory: String, Codable, Sendable, CaseIterable {
    case table
    case sofa
    case chairRecliner = "chair_recliner"
    case cabinetStorage = "cabinet_storage"
    case equipmentFurniture = "equipment_furniture"
    case other
    case unknown
}

public enum FurnitureRelevance: String, Codable, Sendable, CaseIterable {
    case fixedBuiltIn = "fixed_built_in"
    case movable
    case temporary
    case unknown
}

/// Operator confirmation of what a captured object actually is (legacy bolph71656-ai/HTDT-Capture#288).
/// `source` keeps an app/RoomPlan suggestion provenance-distinct from a
/// user confirmation; `.unknown` is a first-class result.
public struct FurnitureSemanticConfirmation: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    /// Annotation entity the confirmation applies to, when the object
    /// is already a staged entity.
    public let targetEntityID: AnnotationEntityID?
    /// Raw-geometry binding when the object is not an entity.
    public let binding: SurfaceRegionBinding?
    public let category: FurnitureCategory
    public let relevance: FurnitureRelevance
    public let source: SemanticConfirmationSource

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        targetEntityID: AnnotationEntityID? = nil,
        binding: SurfaceRegionBinding? = nil,
        category: FurnitureCategory,
        relevance: FurnitureRelevance,
        source: SemanticConfirmationSource
    ) throws {
        guard targetEntityID != nil || binding != nil else {
            throw TheaterAuthorityError.missingSourceBinding
        }
        self.authorityID = authorityID
        self.targetEntityID = targetEntityID
        self.binding = binding
        self.category = category
        self.relevance = relevance
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case targetEntityID = "target_entity_id"
        case binding
        case category
        case relevance
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            targetEntityID: container.decodeIfPresent(
                AnnotationEntityID.self,
                forKey: .targetEntityID
            ),
            binding: container.decodeIfPresent(
                SurfaceRegionBinding.self,
                forKey: .binding
            ),
            category: container.decode(
                FurnitureCategory.self,
                forKey: .category
            ),
            relevance: container.decode(
                FurnitureRelevance.self,
                forKey: .relevance
            ),
            source: container.decode(
                SemanticConfirmationSource.self,
                forKey: .source
            )
        )
    }
}

/// How a speaker is physically installed relative to the room boundary
/// (legacy bolph71656-ai/HTDT-Capture#280). Proximity is never promoted to mounting semantics: the record
/// exists only when the operator attests a mode.
public enum SpeakerMountingMode: String, Codable, Sendable, CaseIterable {
    case freestanding
    case standMounted = "stand_mounted"
    case onWall = "on_wall"
    case inWall = "in_wall"
    case inCeiling = "in_ceiling"
    case ceilingSurface = "ceiling_surface"
    case baffleWall = "baffle_wall"
    case other
}

public struct SpeakerInstallationAuthority: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    /// The `speaker`/`subwoofer` entity this record describes.
    public let speakerEntityID: AnnotationEntityID
    public let mountingMode: SpeakerMountingMode
    /// Exact host surface for wall/ceiling/flush mounting, composed
    /// with the surface-binding authority instead of a second surface
    /// identity system.
    public let hostSurface: SurfaceRegionBinding?
    /// Flush insertion depth when explicitly known.
    public let insertionDepthMeters: Double?
    public let hardwareNote: String?

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        speakerEntityID: AnnotationEntityID,
        mountingMode: SpeakerMountingMode,
        hostSurface: SurfaceRegionBinding? = nil,
        insertionDepthMeters: Double? = nil,
        hardwareNote: String? = nil
    ) throws {
        if let insertionDepthMeters {
            guard insertionDepthMeters.isFinite,
                  insertionDepthMeters >= 0
            else {
                throw TheaterAuthorityError.nonPositiveDimension
            }
        }
        let normalizedNote = SchemaOwnedText.nfc(hardwareNote)
        if let normalizedNote, normalizedNote.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        self.authorityID = authorityID
        self.speakerEntityID = speakerEntityID
        self.mountingMode = mountingMode
        self.hostSurface = hostSurface
        self.insertionDepthMeters = insertionDepthMeters
        self.hardwareNote = normalizedNote
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case speakerEntityID = "speaker_entity_id"
        case mountingMode = "mounting_mode"
        case hostSurface = "host_surface"
        case insertionDepthMeters = "insertion_depth_m"
        case hardwareNote = "hardware_note"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            speakerEntityID: container.decode(
                AnnotationEntityID.self,
                forKey: .speakerEntityID
            ),
            mountingMode: container.decode(
                SpeakerMountingMode.self,
                forKey: .mountingMode
            ),
            hostSurface: container.decodeIfPresent(
                SurfaceRegionBinding.self,
                forKey: .hostSurface
            ),
            insertionDepthMeters: container.decodeIfPresent(
                Double.self,
                forKey: .insertionDepthMeters
            ),
            hardwareNote: container.decodeIfPresent(
                String.self,
                forKey: .hardwareNote
            )
        )
    }
}

public enum AcousticTransparencyState: String, Codable, Sendable, CaseIterable {
    case transparent
    case opaque
    case unknown
}

public enum TransparencyAuthoritySource: String, Codable, Sendable, CaseIterable {
    case userAttestation = "user_attestation"
    case manufacturerSpecification = "manufacturer_specification"
    case equipmentCatalog = "equipment_catalog"
    case other
}

/// Projection-screen product semantics (legacy bolph71656-ai/HTDT-Capture#289): aperture vs frame,
/// attested acoustic transparency, masking state, and the
/// behind-screen speaker relation. The transparency flag is
/// installation semantics — it never fabricates transmission or
/// absorption coefficients.
public struct ProjectionScreenSemantics: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    /// The `projection_screen` entity this record describes.
    public let screenEntityID: AnnotationEntityID
    public let visibleApertureWidthMeters: Double?
    public let visibleApertureHeightMeters: Double?
    public let frameWidthMeters: Double?
    public let frameHeightMeters: Double?
    public let acousticallyTransparent: AcousticTransparencyState
    /// Provenance of the transparency claim. Required whenever the
    /// claim is not `unknown`.
    public let transparencySource: TransparencyAuthoritySource?
    /// Masking/deployed state observation under the legacy bolph71656-ai/HTDT-Capture#264 room-state
    /// model, when recorded.
    public let maskingObservationID: RoomStateObservationID?
    /// Speakers installed behind the screen, by exact entity id.
    public let behindScreenSpeakerEntityIDs: [AnnotationEntityID]

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        screenEntityID: AnnotationEntityID,
        visibleApertureWidthMeters: Double? = nil,
        visibleApertureHeightMeters: Double? = nil,
        frameWidthMeters: Double? = nil,
        frameHeightMeters: Double? = nil,
        acousticallyTransparent: AcousticTransparencyState,
        transparencySource: TransparencyAuthoritySource? = nil,
        maskingObservationID: RoomStateObservationID? = nil,
        behindScreenSpeakerEntityIDs: [AnnotationEntityID] = []
    ) throws {
        for dimension in [
            visibleApertureWidthMeters,
            visibleApertureHeightMeters,
            frameWidthMeters,
            frameHeightMeters,
        ] {
            if let dimension {
                guard dimension.isFinite, dimension > 0 else {
                    throw TheaterAuthorityError.nonPositiveDimension
                }
            }
        }
        if acousticallyTransparent == .unknown {
            // `unknown` carries no provenance claim.
        } else {
            guard transparencySource != nil else {
                throw TheaterAuthorityError.missingSourceBinding
            }
        }
        guard Set(behindScreenSpeakerEntityIDs).count
                == behindScreenSpeakerEntityIDs.count,
              !behindScreenSpeakerEntityIDs.contains(screenEntityID)
        else {
            throw TheaterAuthorityError.unresolvedEntityReference
        }
        self.authorityID = authorityID
        self.screenEntityID = screenEntityID
        self.visibleApertureWidthMeters = visibleApertureWidthMeters
        self.visibleApertureHeightMeters = visibleApertureHeightMeters
        self.frameWidthMeters = frameWidthMeters
        self.frameHeightMeters = frameHeightMeters
        self.acousticallyTransparent = acousticallyTransparent
        self.transparencySource = transparencySource
        self.maskingObservationID = maskingObservationID
        self.behindScreenSpeakerEntityIDs = behindScreenSpeakerEntityIDs
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case screenEntityID = "screen_entity_id"
        case visibleApertureWidthMeters = "visible_aperture_width_m"
        case visibleApertureHeightMeters = "visible_aperture_height_m"
        case frameWidthMeters = "frame_width_m"
        case frameHeightMeters = "frame_height_m"
        case acousticallyTransparent = "acoustically_transparent"
        case transparencySource = "transparency_source"
        case maskingObservationID = "masking_observation_id"
        case behindScreenSpeakerEntityIDs =
            "behind_screen_speaker_entity_ids"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            screenEntityID: container.decode(
                AnnotationEntityID.self,
                forKey: .screenEntityID
            ),
            visibleApertureWidthMeters: container.decodeIfPresent(
                Double.self,
                forKey: .visibleApertureWidthMeters
            ),
            visibleApertureHeightMeters: container.decodeIfPresent(
                Double.self,
                forKey: .visibleApertureHeightMeters
            ),
            frameWidthMeters: container.decodeIfPresent(
                Double.self,
                forKey: .frameWidthMeters
            ),
            frameHeightMeters: container.decodeIfPresent(
                Double.self,
                forKey: .frameHeightMeters
            ),
            acousticallyTransparent: container.decode(
                AcousticTransparencyState.self,
                forKey: .acousticallyTransparent
            ),
            transparencySource: container.decodeIfPresent(
                TransparencyAuthoritySource.self,
                forKey: .transparencySource
            ),
            maskingObservationID: container.decodeIfPresent(
                RoomStateObservationID.self,
                forKey: .maskingObservationID
            ),
            behindScreenSpeakerEntityIDs: container.decodeIfPresent(
                [AnnotationEntityID].self,
                forKey: .behindScreenSpeakerEntityIDs
            ) ?? []
        )
    }
}

/// Seat-level layout authority (legacy bolph71656-ai/HTDT-Capture#290): links a physical `seat` entity
/// to its row, riser, and the exact ear/eye reference entities used by
/// acoustic and sightline analysis. A seat may exist with no listening
/// target and a listening position with no physical seat — the link is
/// authored, never guessed.
public struct SeatLayoutAuthority: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    /// The `seat` entity this record describes.
    public let seatEntityID: AnnotationEntityID
    public let rowIdentifier: String?
    public let seatOrdinal: Int?
    /// Construction-feature candidate (kind `riser`/`stage`) hosting
    /// the seat.
    public let riserAuthorityID: AuthorityRecordID?
    /// Linked `listening_position` entity (ear point).
    public let earListeningEntityID: AnnotationEntityID?
    /// Linked `reference_point` entity (eye point).
    public let eyeReferenceEntityID: AnnotationEntityID?
    /// Explicitly measured head/obstruction envelope, when known.
    public let headObstructionHeightMeters: Double?
    public let headObstructionRadiusMeters: Double?
    public let facingOrientation: OrientationAxes?

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        seatEntityID: AnnotationEntityID,
        rowIdentifier: String? = nil,
        seatOrdinal: Int? = nil,
        riserAuthorityID: AuthorityRecordID? = nil,
        earListeningEntityID: AnnotationEntityID? = nil,
        eyeReferenceEntityID: AnnotationEntityID? = nil,
        headObstructionHeightMeters: Double? = nil,
        headObstructionRadiusMeters: Double? = nil,
        facingOrientation: OrientationAxes? = nil
    ) throws {
        let normalizedRow = SchemaOwnedText.nfc(rowIdentifier)
        if let normalizedRow, normalizedRow.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        if let seatOrdinal {
            guard seatOrdinal >= 0 else {
                throw TheaterAuthorityError.nonPositiveDimension
            }
        }
        for dimension in [
            headObstructionHeightMeters,
            headObstructionRadiusMeters,
        ] {
            if let dimension {
                guard dimension.isFinite, dimension > 0 else {
                    throw TheaterAuthorityError.nonPositiveDimension
                }
            }
        }
        self.authorityID = authorityID
        self.seatEntityID = seatEntityID
        self.rowIdentifier = normalizedRow
        self.seatOrdinal = seatOrdinal
        self.riserAuthorityID = riserAuthorityID
        self.earListeningEntityID = earListeningEntityID
        self.eyeReferenceEntityID = eyeReferenceEntityID
        self.headObstructionHeightMeters = headObstructionHeightMeters
        self.headObstructionRadiusMeters = headObstructionRadiusMeters
        self.facingOrientation = facingOrientation
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case seatEntityID = "seat_entity_id"
        case rowIdentifier = "row_identifier"
        case seatOrdinal = "seat_ordinal"
        case riserAuthorityID = "riser_authority_id"
        case earListeningEntityID = "ear_listening_entity_id"
        case eyeReferenceEntityID = "eye_reference_entity_id"
        case headObstructionHeightMeters =
            "head_obstruction_height_m"
        case headObstructionRadiusMeters =
            "head_obstruction_radius_m"
        case facingOrientation = "facing_orientation"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            seatEntityID: container.decode(
                AnnotationEntityID.self,
                forKey: .seatEntityID
            ),
            rowIdentifier: container.decodeIfPresent(
                String.self,
                forKey: .rowIdentifier
            ),
            seatOrdinal: container.decodeIfPresent(
                Int.self,
                forKey: .seatOrdinal
            ),
            riserAuthorityID: container.decodeIfPresent(
                AuthorityRecordID.self,
                forKey: .riserAuthorityID
            ),
            earListeningEntityID: container.decodeIfPresent(
                AnnotationEntityID.self,
                forKey: .earListeningEntityID
            ),
            eyeReferenceEntityID: container.decodeIfPresent(
                AnnotationEntityID.self,
                forKey: .eyeReferenceEntityID
            ),
            headObstructionHeightMeters: container.decodeIfPresent(
                Double.self,
                forKey: .headObstructionHeightMeters
            ),
            headObstructionRadiusMeters: container.decodeIfPresent(
                Double.self,
                forKey: .headObstructionRadiusMeters
            ),
            facingOrientation: container.decodeIfPresent(
                OrientationAxes.self,
                forKey: .facingOrientation
            )
        )
    }
}

/// Canonical `annotations/authorities.json` payload: every
/// theater-semantic authority record authored on top of the entity and
/// evidence base. All sections are user-attested authority; record-level
/// `confirmationSource` fields keep app-derived suggestions distinct.
public struct TheaterAuthorityCollection: Codable, Sendable, Equatable {
    public static let expectedSchema = "htdt.capture.authorities"
    public static let expectedSchemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let surfaceSemantics: [SurfaceSemanticAuthority]
    public let surfaceConstructions: [SurfaceConstructionObservation]
    public let problemSurfaces: [ProblemSurfaceObservation]
    public let constructionFeatures: [ConstructionFeatureCandidate]
    public let roomStateObservations: [RoomStateObservation]
    public let roomStateSnapshots: [RoomStateSnapshot]
    public let inventoryItems: [SystemInventoryItem]
    public let furnitureSemantics: [FurnitureSemanticConfirmation]
    public let speakerInstallations: [SpeakerInstallationAuthority]
    public let screenSemantics: [ProjectionScreenSemantics]
    public let seatLayouts: [SeatLayoutAuthority]
    /// Observed output->speaker routing claims (legacy bolph71656-ai/HTDT-Capture#316).
    public let routingVerifications: [RoutingVerificationAuthority]
    /// Field-commissioned projector lens/optics state (legacy bolph71656-ai/HTDT-Capture#335).
    public let projectorCommissionings: [ProjectorCommissioningAuthority]
    /// Attested installation-alignment assist outcomes (legacy bolph71656-ai/HTDT-Capture#346).
    public let installationAlignments: [InstallationAlignmentRecord]
    /// Rack slot/facing observations bound to inventory items (legacy bolph71656-ai/HTDT-Capture#402).
    /// Placement authority stays separate from item identity: a unit
    /// keeps its serial/model when it moves slots.
    public let rackPlacements: [RackPlacementObservation]

    /// An authority file with no records; the validating init cannot
    /// fail on empty sections.
    public static let empty = try! TheaterAuthorityCollection()

    public var isEmpty: Bool {
        surfaceSemantics.isEmpty
            && surfaceConstructions.isEmpty
            && problemSurfaces.isEmpty
            && constructionFeatures.isEmpty
            && roomStateObservations.isEmpty
            && roomStateSnapshots.isEmpty
            && inventoryItems.isEmpty
            && furnitureSemantics.isEmpty
            && speakerInstallations.isEmpty
            && screenSemantics.isEmpty
            && seatLayouts.isEmpty
            && routingVerifications.isEmpty
            && projectorCommissionings.isEmpty
            && installationAlignments.isEmpty
            && rackPlacements.isEmpty
    }

    public init(
        surfaceSemantics: [SurfaceSemanticAuthority] = [],
        surfaceConstructions: [SurfaceConstructionObservation] = [],
        problemSurfaces: [ProblemSurfaceObservation] = [],
        constructionFeatures: [ConstructionFeatureCandidate] = [],
        roomStateObservations: [RoomStateObservation] = [],
        roomStateSnapshots: [RoomStateSnapshot] = [],
        inventoryItems: [SystemInventoryItem] = [],
        furnitureSemantics: [FurnitureSemanticConfirmation] = [],
        speakerInstallations: [SpeakerInstallationAuthority] = [],
        screenSemantics: [ProjectionScreenSemantics] = [],
        seatLayouts: [SeatLayoutAuthority] = [],
        routingVerifications: [RoutingVerificationAuthority] = [],
        projectorCommissionings: [ProjectorCommissioningAuthority] = [],
        installationAlignments: [InstallationAlignmentRecord] = [],
        rackPlacements: [RackPlacementObservation] = []
    ) throws {
        // Record identifiers share one namespace and must be unique
        // across every section.
        var ids = Set<AuthorityRecordID>()
        for id in surfaceSemantics.map(\.authorityID)
            + surfaceConstructions.map(\.authorityID)
            + problemSurfaces.map(\.authorityID)
            + constructionFeatures.map(\.authorityID)
            + inventoryItems.map(\.itemID)
            + furnitureSemantics.map(\.authorityID)
            + speakerInstallations.map(\.authorityID)
            + screenSemantics.map(\.authorityID)
            + seatLayouts.map(\.authorityID)
            + routingVerifications.map(\.authorityID)
            + projectorCommissionings.map(\.authorityID)
            + installationAlignments.map(\.authorityID)
            + rackPlacements.map(\.placementID)
        {
            guard ids.insert(id).inserted else {
                throw TheaterAuthorityError.duplicateAuthorityRecordID
            }
        }

        let observationIDs = Set(
            roomStateObservations.map(\.observationID)
        )
        guard observationIDs.count == roomStateObservations.count else {
            throw TheaterAuthorityError.duplicateAuthorityRecordID
        }
        let snapshotIDs = Set(roomStateSnapshots.map(\.snapshotID))
        guard snapshotIDs.count == roomStateSnapshots.count else {
            throw TheaterAuthorityError.duplicateAuthorityRecordID
        }

        // Cross-references inside the collection must resolve so a
        // persisted file never carries dangling authority.
        let featureIDs = Dictionary(
            constructionFeatures.map { ($0.authorityID, $0.kind) },
            uniquingKeysWith: { first, _ in first }
        )
        for snapshot in roomStateSnapshots {
            for observationID in snapshot.observationIDs {
                guard observationIDs.contains(observationID) else {
                    throw TheaterAuthorityError
                        .unresolvedObservationReference
                }
            }
        }
        for observation in roomStateObservations {
            if let target = observation.targetAuthorityID {
                guard ids.contains(target) else {
                    throw TheaterAuthorityError
                        .unresolvedFeatureReference
                }
            }
        }
        for semantics in screenSemantics {
            if let masking = semantics.maskingObservationID {
                guard observationIDs.contains(masking) else {
                    throw TheaterAuthorityError
                        .unresolvedObservationReference
                }
            }
        }
        for layout in seatLayouts {
            if let riser = layout.riserAuthorityID {
                // A riser link must land on a riser/stage candidate,
                // not on arbitrary construction features.
                guard let kind = featureIDs[riser],
                      kind == .riser || kind == .stage
                else {
                    throw TheaterAuthorityError
                        .unresolvedFeatureReference
                }
            }
        }
        let routingIDs = Set(routingVerifications.map(\.authorityID))
        for routing in routingVerifications {
            if let source = routing.sourceInventoryItemID {
                guard inventoryItems.contains(where: {
                    $0.itemID == source
                }) else {
                    throw TheaterAuthorityError
                        .unresolvedFeatureReference
                }
            }
            if let supersedes = routing.supersedesRecordID {
                guard routingIDs.contains(supersedes) else {
                    throw TheaterAuthorityError
                        .unresolvedFeatureReference
                }
            }
        }
        for commissioning in projectorCommissionings {
            if let screen = commissioning.screenSemanticsAuthorityID {
                guard screenSemantics.contains(where: {
                    $0.authorityID == screen
                }) else {
                    throw TheaterAuthorityError
                        .unresolvedFeatureReference
                }
            }
        }
        let itemRacks = Dictionary(
            inventoryItems.map { ($0.itemID, $0.hostRackEntityID) },
            uniquingKeysWith: { first, _ in first }
        )
        for placement in rackPlacements {
            // A placement can only exist where its item is a member —
            // the item's `hostRackEntityID` is the membership claim,
            // the placement's the slot observation (legacy bolph71656-ai/HTDT-Capture#402).
            guard let rack = itemRacks[placement.itemID] else {
                throw TheaterAuthorityError.unresolvedFeatureReference
            }
            guard rack == placement.hostRackEntityID else {
                throw TheaterAuthorityError.rackPlacementRackMismatch
            }
        }

        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.surfaceSemantics = surfaceSemantics
        self.surfaceConstructions = surfaceConstructions
        self.problemSurfaces = problemSurfaces
        self.constructionFeatures = constructionFeatures
        self.roomStateObservations = roomStateObservations
        self.roomStateSnapshots = roomStateSnapshots
        self.inventoryItems = inventoryItems
        self.furnitureSemantics = furnitureSemantics
        self.speakerInstallations = speakerInstallations
        self.screenSemantics = screenSemantics
        self.seatLayouts = seatLayouts
        self.routingVerifications = routingVerifications
        self.projectorCommissionings = projectorCommissionings
        self.installationAlignments = installationAlignments
        self.rackPlacements = rackPlacements
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case surfaceSemantics = "surface_semantics"
        case surfaceConstructions = "surface_constructions"
        case problemSurfaces = "problem_surfaces"
        case constructionFeatures = "construction_features"
        case roomStateObservations = "room_state_observations"
        case roomStateSnapshots = "room_state_snapshots"
        case inventoryItems = "inventory_items"
        case furnitureSemantics = "furniture_semantics"
        case speakerInstallations = "speaker_installations"
        case screenSemantics = "screen_semantics"
        case seatLayouts = "seat_layouts"
        case routingVerifications = "routing_verifications"
        case projectorCommissionings = "projector_commissionings"
        case installationAlignments = "installation_alignments"
        case rackPlacements = "rack_placements"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.expectedSchema,
              schemaVersion == Self.expectedSchemaVersion
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription:
                    "Unsupported authority collection schema"
            )
        }
        try self.init(
            surfaceSemantics: container.decodeIfPresent(
                [SurfaceSemanticAuthority].self,
                forKey: .surfaceSemantics
            ) ?? [],
            surfaceConstructions: container.decodeIfPresent(
                [SurfaceConstructionObservation].self,
                forKey: .surfaceConstructions
            ) ?? [],
            problemSurfaces: container.decodeIfPresent(
                [ProblemSurfaceObservation].self,
                forKey: .problemSurfaces
            ) ?? [],
            constructionFeatures: container.decodeIfPresent(
                [ConstructionFeatureCandidate].self,
                forKey: .constructionFeatures
            ) ?? [],
            roomStateObservations: container.decodeIfPresent(
                [RoomStateObservation].self,
                forKey: .roomStateObservations
            ) ?? [],
            roomStateSnapshots: container.decodeIfPresent(
                [RoomStateSnapshot].self,
                forKey: .roomStateSnapshots
            ) ?? [],
            inventoryItems: container.decodeIfPresent(
                [SystemInventoryItem].self,
                forKey: .inventoryItems
            ) ?? [],
            furnitureSemantics: container.decodeIfPresent(
                [FurnitureSemanticConfirmation].self,
                forKey: .furnitureSemantics
            ) ?? [],
            speakerInstallations: container.decodeIfPresent(
                [SpeakerInstallationAuthority].self,
                forKey: .speakerInstallations
            ) ?? [],
            screenSemantics: container.decodeIfPresent(
                [ProjectionScreenSemantics].self,
                forKey: .screenSemantics
            ) ?? [],
            seatLayouts: container.decodeIfPresent(
                [SeatLayoutAuthority].self,
                forKey: .seatLayouts
            ) ?? [],
            routingVerifications: container.decodeIfPresent(
                [RoutingVerificationAuthority].self,
                forKey: .routingVerifications
            ) ?? [],
            projectorCommissionings: container.decodeIfPresent(
                [ProjectorCommissioningAuthority].self,
                forKey: .projectorCommissionings
            ) ?? [],
            installationAlignments: container.decodeIfPresent(
                [InstallationAlignmentRecord].self,
                forKey: .installationAlignments
            ) ?? [],
            rackPlacements: container.decodeIfPresent(
                [RackPlacementObservation].self,
                forKey: .rackPlacements
            ) ?? []
        )
    }
}

public extension TheaterAuthorityCollection {
    /// Placements bound to one inventory item, in stored order (legacy bolph71656-ai/HTDT-Capture#402).
    func rackPlacements(
        for itemID: AuthorityRecordID
    ) -> [RackPlacementObservation] {
        rackPlacements.filter { $0.itemID == itemID }
    }

    /// Upserts the item and, when given, its placement in one
    /// validating rebuild (legacy bolph71656-ai/HTDT-Capture#402): the pair is staged atomically so a
    /// placement never lands without the item it describes.
    func upsertingInventoryItem(
        _ item: SystemInventoryItem,
        placement: RackPlacementObservation? = nil
    ) throws -> TheaterAuthorityCollection {
        var items = inventoryItems
        if let index = items.firstIndex(where: {
            $0.itemID == item.itemID
        }) {
            items[index] = item
        } else {
            items.append(item)
        }
        var placements = rackPlacements
        if let placement {
            if let index = placements.firstIndex(where: {
                $0.placementID == placement.placementID
            }) {
                placements[index] = placement
            } else {
                placements.append(placement)
            }
        }
        return try TheaterAuthorityCollection(
            surfaceSemantics: surfaceSemantics,
            surfaceConstructions: surfaceConstructions,
            problemSurfaces: problemSurfaces,
            constructionFeatures: constructionFeatures,
            roomStateObservations: roomStateObservations,
            roomStateSnapshots: roomStateSnapshots,
            inventoryItems: items,
            furnitureSemantics: furnitureSemantics,
            speakerInstallations: speakerInstallations,
            screenSemantics: screenSemantics,
            seatLayouts: seatLayouts,
            routingVerifications: routingVerifications,
            projectorCommissionings: projectorCommissionings,
            installationAlignments: installationAlignments,
            rackPlacements: placements
        )
    }

    /// Removes one placement observation, keeping the item (legacy bolph71656-ai/HTDT-Capture#402).
    func removingRackPlacement(
        _ placementID: AuthorityRecordID
    ) throws -> TheaterAuthorityCollection {
        let placements = rackPlacements.filter {
            $0.placementID != placementID
        }
        guard placements.count != rackPlacements.count else {
            return self
        }
        return try TheaterAuthorityCollection(
            surfaceSemantics: surfaceSemantics,
            surfaceConstructions: surfaceConstructions,
            problemSurfaces: problemSurfaces,
            constructionFeatures: constructionFeatures,
            roomStateObservations: roomStateObservations,
            roomStateSnapshots: roomStateSnapshots,
            inventoryItems: inventoryItems,
            furnitureSemantics: furnitureSemantics,
            speakerInstallations: speakerInstallations,
            screenSemantics: screenSemantics,
            seatLayouts: seatLayouts,
            routingVerifications: routingVerifications,
            projectorCommissionings: projectorCommissionings,
            installationAlignments: installationAlignments,
            rackPlacements: placements
        )
    }

    /// Removes the item and every placement bound to it — a placement
    /// cannot outlive the unit it describes (legacy bolph71656-ai/HTDT-Capture#402). Other records
    /// still referencing the item (e.g. routing sources) refuse the
    /// delete through the validating init.
    func removingInventoryItem(
        _ itemID: AuthorityRecordID
    ) throws -> TheaterAuthorityCollection {
        let items = inventoryItems.filter { $0.itemID != itemID }
        guard items.count != inventoryItems.count else { return self }
        let placements = rackPlacements.filter {
            $0.itemID != itemID
        }
        return try TheaterAuthorityCollection(
            surfaceSemantics: surfaceSemantics,
            surfaceConstructions: surfaceConstructions,
            problemSurfaces: problemSurfaces,
            constructionFeatures: constructionFeatures,
            roomStateObservations: roomStateObservations,
            roomStateSnapshots: roomStateSnapshots,
            inventoryItems: items,
            furnitureSemantics: furnitureSemantics,
            speakerInstallations: speakerInstallations,
            screenSemantics: screenSemantics,
            seatLayouts: seatLayouts,
            routingVerifications: routingVerifications,
            projectorCommissionings: projectorCommissionings,
            installationAlignments: installationAlignments,
            rackPlacements: placements
        )
    }

    /// Conservative same-unit candidates within the staged inventory
    /// (legacy bolph71656-ai/HTDT-Capture#402 §7): an identical non-empty serial/asset text, or an
    /// identical exact catalog reference sharing the same rack or
    /// label. Detection never merges — the operator decides whether
    /// the candidate is the same physical unit.
    func inventoryDuplicateCandidates(
        for item: SystemInventoryItem
    ) -> [SystemInventoryItem] {
        inventoryItems.filter { candidate in
            guard candidate.itemID != item.itemID else { return false }
            if let serial = item.serialNumber,
               candidate.serialNumber == serial
            {
                return true
            }
            if let reference = item.equipmentRef,
               candidate.equipmentRef == reference,
               (item.hostRackEntityID != nil
                    && candidate.hostRackEntityID
                        == item.hostRackEntityID)
                    || candidate.userLabel == item.userLabel
            {
                return true
            }
            return false
        }
    }
}
