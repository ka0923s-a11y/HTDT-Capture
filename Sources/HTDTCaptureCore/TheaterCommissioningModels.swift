import Foundation

/// The theater-semantic record kinds a mission/task plan can request
/// (legacy bolph71656-ai/HTDT-Capture#359) and that the authority workspace groups under (legacy bolph71656-ai/HTDT-Capture#357). Covers
/// every section of `TheaterAuthorityCollection`; the wire value is the
/// exact token a task plan's `semantic_kind` field carries.
public enum SemanticTaskKind: String, Codable, Sendable, CaseIterable {
    case surfaceSemantics = "surface_semantics"
    case surfaceConstruction = "surface_construction"
    case problemSurface = "problem_surface"
    case constructionFeature = "construction_feature"
    case roomStateObservation = "room_state_observation"
    case roomStateSnapshot = "room_state_snapshot"
    case inventoryItem = "inventory_item"
    case furnitureSemantics = "furniture_semantics"
    case speakerInstallation = "speaker_installation"
    case screenSemantics = "screen_semantics"
    case seatLayout = "seat_layout"
    case routingVerification = "routing_verification"
    case projectorCommissioning = "projector_commissioning"
    case installationAlignment = "installation_alignment"
}

/// Flat, human-facing identity of one authority record: the exact id,
/// the semantic kind a task plan can request, an optional exact subtype
/// token within the kind, and the primary entity the record describes
/// when the kind binds one. Task-plan fulfillment matching (legacy bolph71656-ai/HTDT-Capture#359) and
/// the workspace record list (legacy bolph71656-ai/HTDT-Capture#357) both consume this shape.
public struct AuthorityRecordDescriptor: Sendable, Equatable,
    Identifiable
{
    public let recordID: AuthorityRecordID
    public let kind: SemanticTaskKind
    /// Exact subtype token within the kind — e.g. an inventory item's
    /// `equipment_class`, a room-state observation's `kind`, a speaker
    /// installation's `mounting_mode`. A task plan's `expected_subtype`
    /// must match this value byte-for-byte when specified.
    public let subtype: String?
    /// Primary annotation entity the record describes, when the kind
    /// binds one; nil for room-wide or multi-entity records.
    public let targetEntityID: AnnotationEntityID?
    /// Plan-side target identity the record was authored against, when
    /// the record kind carries one (alignment records).
    public let targetPlannedRef: String?
    /// Short human-facing title for list rendering — a label, channel
    /// name, or bound entity reference. Never a synthesized claim.
    public let title: String
    /// Secondary human-facing detail (state, subtype, or role text).
    public let detail: String?

    public var id: AuthorityRecordID { recordID }

    public init(
        recordID: AuthorityRecordID,
        kind: SemanticTaskKind,
        subtype: String? = nil,
        targetEntityID: AnnotationEntityID? = nil,
        targetPlannedRef: String? = nil,
        title: String,
        detail: String? = nil
    ) {
        self.recordID = recordID
        self.kind = kind
        self.subtype = subtype
        self.targetEntityID = targetEntityID
        self.targetPlannedRef = targetPlannedRef
        self.title = title
        self.detail = detail
    }
}

public extension TheaterAuthorityCollection {
    /// Every staged record as a flat, human-sortable descriptor list.
    /// Ordering is stable: records appear section by section in
    /// declaration order, in their stored order within each section.
    var recordDescriptors: [AuthorityRecordDescriptor] {
        var descriptors: [AuthorityRecordDescriptor] = []
        descriptors += surfaceSemantics.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .surfaceSemantics,
                subtype: record.hostClassification.rawValue,
                title: record.label
                    ?? record.binding.roomPlanSurfaceID
                    ?? record.binding.semanticEntityID
                    ?? record.authorityID.description,
                detail: record.hostClassification.rawValue
            )
        }
        descriptors += surfaceConstructions.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .surfaceConstruction,
                subtype: record.constructionKind.rawValue,
                title: record.binding.roomPlanSurfaceID
                    ?? record.binding.semanticEntityID
                    ?? record.authorityID.description,
                detail: record.constructionKind.rawValue
            )
        }
        descriptors += problemSurfaces.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .problemSurface,
                subtype: record.kind.rawValue,
                title: record.binding.roomPlanSurfaceID
                    ?? record.binding.semanticEntityID
                    ?? record.authorityID.description,
                detail: record.kind.rawValue
            )
        }
        descriptors += constructionFeatures.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .constructionFeature,
                subtype: record.kind.rawValue,
                title: record.label
                    ?? record.binding.roomPlanSurfaceID
                    ?? record.authorityID.description,
                detail: record.kind.rawValue
            )
        }
        descriptors += roomStateObservations.map { record in
            AuthorityRecordDescriptor(
                recordID: AuthorityRecordID(
                    rawValue: record.observationID.rawValue
                ),
                kind: .roomStateObservation,
                subtype: record.kind.rawValue,
                targetEntityID: record.targetEntityID,
                title: record.kind.rawValue,
                detail: record.state.rawValue
            )
        }
        descriptors += roomStateSnapshots.map { record in
            AuthorityRecordDescriptor(
                recordID: AuthorityRecordID(
                    rawValue: record.snapshotID.rawValue
                ),
                kind: .roomStateSnapshot,
                title: record.label,
                detail: "\(record.observationIDs.count) observations"
            )
        }
        descriptors += inventoryItems.map { record in
            AuthorityRecordDescriptor(
                recordID: record.itemID,
                kind: .inventoryItem,
                subtype: record.equipmentClass.rawValue,
                targetEntityID: record.hostRackEntityID,
                title: record.userLabel,
                detail: record.equipmentClass.rawValue
            )
        }
        descriptors += furnitureSemantics.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .furnitureSemantics,
                subtype: record.category.rawValue,
                targetEntityID: record.targetEntityID,
                title: record.category.rawValue,
                detail: record.relevance.rawValue
            )
        }
        descriptors += speakerInstallations.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .speakerInstallation,
                subtype: record.mountingMode.rawValue,
                targetEntityID: record.speakerEntityID,
                title: record.speakerEntityID.description,
                detail: record.mountingMode.rawValue
            )
        }
        descriptors += screenSemantics.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .screenSemantics,
                subtype: record.acousticallyTransparent.rawValue,
                targetEntityID: record.screenEntityID,
                title: record.screenEntityID.description,
                detail: record.acousticallyTransparent.rawValue
            )
        }
        descriptors += seatLayouts.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .seatLayout,
                subtype: record.rowIdentifier,
                targetEntityID: record.seatEntityID,
                title: record.seatEntityID.description,
                detail: record.rowIdentifier
            )
        }
        descriptors += routingVerifications.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .routingVerification,
                subtype: record.bandScope.rawValue,
                title: record.channelRole?.rawValue
                    ?? record.outputLabel
                    ?? record.authorityID.description,
                detail: record.verificationState.rawValue
            )
        }
        descriptors += projectorCommissionings.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .projectorCommissioning,
                targetEntityID: record.projectorEntityID,
                title: record.projectorEntityID.description,
                detail: record.observedAtUTC
            )
        }
        descriptors += installationAlignments.map { record in
            AuthorityRecordDescriptor(
                recordID: record.authorityID,
                kind: .installationAlignment,
                targetEntityID: record.finalEntityID,
                targetPlannedRef: record.targetPlannedEntityID,
                title: record.targetPlannedEntityID,
                detail: record.precisionSufficiency.rawValue
            )
        }
        return descriptors
    }
}

// MARK: - Routing / physical-source verification (legacy bolph71656-ai/HTDT-Capture#316)

/// Frequency band a routing claim covers. Bass-managed channels carry
/// low-frequency energy to a subwoofer path that a full-range claim
/// would misrepresent; the record must state which band it attests.
public enum RoutingBandScope: String, Codable, Sendable, CaseIterable {
    /// The output drives the named speaker(s) across the whole band.
    case fullRange = "full_range"
    /// The output drives the speaker's upper band directly (the
    /// speaker still receives bass-managed content elsewhere).
    case highBandDirect = "high_band_direct"
    /// The output is the low-band path for a bass-managed speaker.
    case lowBandBassManaged = "low_band_bass_managed"
    /// The operator cannot attest which band the output covers.
    case unknown
}

/// State of one logical-output -> physical-speaker claim (legacy bolph71656-ai/HTDT-Capture#316).
/// `verified` and `conflicting` are distinct operator-attested results;
/// `manualLabel` is a label only, `unknown` a first-class result.
public enum RoutingVerificationState: String, Codable, Sendable,
    CaseIterable
{
    case verified
    case manualLabel = "manual_label"
    case unknown
    case conflicting
}

/// How the routing claim was established. A cable label is evidence,
/// never verification by itself; `verified` requires a method that
/// exercises the signal path (`listened_test_signal`,
/// `measured_signal_path`) or explicit operator attestation.
public enum RoutingVerificationMethod: String, Codable, Sendable,
    CaseIterable
{
    case userAttestation = "user_attestation"
    case cableLabelEvidence = "cable_label_evidence"
    case listenedTestSignal = "listened_test_signal"
    case measuredSignalPath = "measured_signal_path"
    case other
}

/// Typed authority recording which logical output channel actually
/// drives which installed speaker entity/entities (legacy bolph71656-ai/HTDT-Capture#316). Planned
/// topology (`expectedChannelRoles` in the task plan, speaker layout
/// plans) stays a separate authority — this record only ever carries
/// the observed/attested routing, and Capture never changes AVR or DSP
/// settings.
///
/// `supersedesRecordID` is how a changed device configuration revises a
/// routing observation explicitly: the old record stays and the new one
/// names it, so HTDT can see the supersession chain.
public struct RoutingVerificationAuthority: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    /// Expected logical/output role when the plan defines one
    /// (`L`, `LFE1`, ...). At least one of `channelRole`/`outputLabel`
    /// must be present so the claim is addressable.
    public let channelRole: ChannelRole?
    /// Physical output label as printed on the equipment
    /// ("Front R Pre-Out", "Amp ch 3") — free text, operator-entered.
    public let outputLabel: String?
    /// Inventory item (`av_receiver`/`av_processor`/`power_amplifier`/
    /// `dsp_unit`) the output physically belongs to, when recorded.
    public let sourceInventoryItemID: AuthorityRecordID?
    public let bandScope: RoutingBandScope
    /// The exact installed speaker entities this output drives. A
    /// logical input may drive multiple physical sources (parallel
    /// subs, bi-amp), so this is a non-empty set, never a single id.
    public let speakerEntityIDs: [AnnotationEntityID]
    public let verificationState: RoutingVerificationState
    /// Required for every state except `unknown`.
    public let verificationMethod: RoutingVerificationMethod?
    /// Device/configuration context reference shared with the legacy bolph71656-ai/HTDT-Capture#301
    /// session context (e.g. an AVR configuration hash or free-text
    /// "AVR preset A"), so a stale config can be seen to invalidate
    /// the observation.
    public let deviceContextRef: String?
    public let observedAtUTC: String
    public let coordinateSpaceID: CoordinateSpaceID?
    public let evidenceRefs: [String]
    /// Earlier routing record this observation explicitly revises.
    public let supersedesRecordID: AuthorityRecordID?
    public let notes: String?

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        channelRole: ChannelRole? = nil,
        outputLabel: String? = nil,
        sourceInventoryItemID: AuthorityRecordID? = nil,
        bandScope: RoutingBandScope,
        speakerEntityIDs: [AnnotationEntityID],
        verificationState: RoutingVerificationState,
        verificationMethod: RoutingVerificationMethod? = nil,
        deviceContextRef: String? = nil,
        observedAtUTC: String,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        evidenceRefs: [String] = [],
        supersedesRecordID: AuthorityRecordID? = nil,
        notes: String? = nil
    ) throws {
        let normalizedLabel = SchemaOwnedText.nfc(outputLabel)
        if let normalizedLabel, normalizedLabel.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard channelRole != nil || normalizedLabel != nil else {
            throw TheaterAuthorityError.missingSourceBinding
        }
        guard !speakerEntityIDs.isEmpty,
              Set(speakerEntityIDs).count == speakerEntityIDs.count
        else {
            throw TheaterAuthorityError.unresolvedEntityReference
        }
        if verificationState == .unknown {
            // `unknown` is a valid attestation result; no method needed.
        } else {
            guard verificationMethod != nil else {
                throw TheaterAuthorityError.missingSourceBinding
            }
        }
        if verificationState == .verified,
           verificationMethod == .cableLabelEvidence
        {
            // A printed label never verifies the live signal path.
            throw TheaterAuthorityError.missingSourceBinding
        }
        let normalizedContext = SchemaOwnedText.nfc(deviceContextRef)
        if let normalizedContext, normalizedContext.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        let normalizedNotes = SchemaOwnedText.nfc(notes)
        if let normalizedNotes, normalizedNotes.isEmpty {
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
        guard supersedesRecordID != authorityID else {
            throw TheaterAuthorityError.unresolvedEntityReference
        }
        self.authorityID = authorityID
        self.channelRole = channelRole
        self.outputLabel = normalizedLabel
        self.sourceInventoryItemID = sourceInventoryItemID
        self.bandScope = bandScope
        self.speakerEntityIDs = speakerEntityIDs
        self.verificationState = verificationState
        self.verificationMethod = verificationMethod
        self.deviceContextRef = normalizedContext
        self.observedAtUTC = observedAtUTC
        self.coordinateSpaceID = coordinateSpaceID
        self.evidenceRefs = normalizedEvidence.sorted()
        self.supersedesRecordID = supersedesRecordID
        self.notes = normalizedNotes
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case channelRole = "channel_role"
        case outputLabel = "output_label"
        case sourceInventoryItemID = "source_inventory_item_id"
        case bandScope = "band_scope"
        case speakerEntityIDs = "speaker_entity_ids"
        case verificationState = "verification_state"
        case verificationMethod = "verification_method"
        case deviceContextRef = "device_context_ref"
        case observedAtUTC = "observed_at_utc"
        case coordinateSpaceID = "coordinate_space_id"
        case evidenceRefs = "evidence_refs"
        case supersedesRecordID = "supersedes_record_id"
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            channelRole: container.decodeIfPresent(
                ChannelRole.self,
                forKey: .channelRole
            ),
            outputLabel: container.decodeIfPresent(
                String.self,
                forKey: .outputLabel
            ),
            sourceInventoryItemID: container.decodeIfPresent(
                AuthorityRecordID.self,
                forKey: .sourceInventoryItemID
            ),
            bandScope: container.decode(
                RoutingBandScope.self,
                forKey: .bandScope
            ),
            speakerEntityIDs: container.decode(
                [AnnotationEntityID].self,
                forKey: .speakerEntityIDs
            ),
            verificationState: container.decode(
                RoutingVerificationState.self,
                forKey: .verificationState
            ),
            verificationMethod: container.decodeIfPresent(
                RoutingVerificationMethod.self,
                forKey: .verificationMethod
            ),
            deviceContextRef: container.decodeIfPresent(
                String.self,
                forKey: .deviceContextRef
            ),
            observedAtUTC: container.decode(
                String.self,
                forKey: .observedAtUTC
            ),
            coordinateSpaceID: container.decodeIfPresent(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            evidenceRefs: container.decodeIfPresent(
                [String].self,
                forKey: .evidenceRefs
            ) ?? [],
            supersedesRecordID: container.decodeIfPresent(
                AuthorityRecordID.self,
                forKey: .supersedesRecordID
            ),
            notes: container.decodeIfPresent(
                String.self,
                forKey: .notes
            )
        )
    }
}

// MARK: - Projector commissioning (legacy bolph71656-ai/HTDT-Capture#335)

/// Whether a projector lens/optics value was attested in the field or
/// explicitly recorded as not known. `unknown` is a first-class answer —
/// a planned value never silently becomes the installed one.
public enum SettingObservationState: String, Codable, Sendable,
    CaseIterable
{
    case attested
    case unknown
}

/// One lens/optics setting observation: either an attested value
/// (text such as a preset name, or a numeric value) or an explicit
/// `unknown`. An attested entry must carry at least one value; an
/// `unknown` entry must carry none.
public struct AttestedSettingValue: Codable, Sendable, Equatable {
    public let state: SettingObservationState
    /// Verbatim value text — preset name, lens-shift scale marking,
    /// throw-distance measurement note.
    public let textValue: String?
    /// Numeric value when the setting is scalar (meters, ratio,
    /// percent as labeled).
    public let numericValue: Double?

    public init(
        state: SettingObservationState,
        textValue: String? = nil,
        numericValue: Double? = nil
    ) throws {
        let normalizedText = SchemaOwnedText.nfc(textValue)
        if let normalizedText, normalizedText.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        if let numericValue {
            guard numericValue.isFinite else {
                throw TheaterAuthorityError.nonPositiveDimension
            }
        }
        switch state {
        case .attested:
            guard normalizedText != nil || numericValue != nil else {
                throw TheaterAuthorityError.missingSourceBinding
            }
        case .unknown:
            guard normalizedText == nil, numericValue == nil else {
                throw TheaterAuthorityError.invalidPatchGeometry
            }
        }
        self.state = state
        self.textValue = normalizedText
        self.numericValue = numericValue
    }

    /// Convenience for an explicitly-unknown observation.
    public static var unknown: AttestedSettingValue {
        try! AttestedSettingValue(state: .unknown)
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case textValue = "text_value"
        case numericValue = "numeric_value"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            state: container.decode(
                SettingObservationState.self,
                forKey: .state
            ),
            textValue: container.decodeIfPresent(
                String.self,
                forKey: .textValue
            ),
            numericValue: container.decodeIfPresent(
                Double.self,
                forKey: .numericValue
            )
        )
    }
}

/// How the projector is physically mounted/oriented in the install.
public enum ProjectorMountOrientation: String, Codable, Sendable,
    CaseIterable
{
    case tabletopFront = "tabletop_front"
    case ceilingFront = "ceiling_front"
    case tabletopRear = "tabletop_rear"
    case ceilingRear = "ceiling_rear"
    case other
    case unknown
}

/// Whether focus was checked at commissioning time.
public enum ProjectorFocusState: String, Codable, Sendable, CaseIterable {
    case verified
    case unverified
    case unknown
}

/// Field-commissioned state of one projector install (legacy bolph71656-ai/HTDT-Capture#335): which
/// lens/reference point is the optical authority (distinct from the
/// cabinet center), throw distance with explicit endpoint semantics,
/// lens shift/zoom/memory-preset state, optical axis, and the evidence
/// each claim rests on. Nothing here is a manufacturer capability —
/// capability data stays with the HTDT equipment authority (legacy bolph71656-ai/HTDT-Capture#415);
/// this record carries only what was observed in the field.
public struct ProjectorCommissioningAuthority: Codable, Sendable,
    Equatable
{
    public let authorityID: AuthorityRecordID
    /// The `projector` entity this record describes (cabinet pose).
    public let projectorEntityID: AnnotationEntityID
    /// Separate entity carrying `projector_lens_center` reference
    /// semantics, when the lens center was captured as its own point.
    public let lensCenterEntityID: AnnotationEntityID?
    /// Attested throw distance (meters in `numeric_value`) or
    /// `unknown`. Never seeded from the plan.
    public let throwObservation: AttestedSettingValue?
    /// Exact throw-measurement endpoints — e.g.
    /// "lens_center_to_screen_aperture". Required when
    /// `throwObservation` is present so the distance is interpretable.
    public let throwEndpointSemantics: String?
    public let zoom: AttestedSettingValue?
    public let lensShiftHorizontal: AttestedSettingValue?
    public let lensShiftVertical: AttestedSettingValue?
    public let lensMemoryPreset: AttestedSettingValue?
    public let mountOrientation: ProjectorMountOrientation?
    public let focusState: ProjectorFocusState?
    /// Attested optical axis direction in world space (front/up), when
    /// the operator aimed and captured it.
    public let opticalAxis: OrientationAxes?
    /// Free-text alignment/keystone note; never a geometry rewrite.
    public let imageAlignmentNote: String?
    /// Plan-side reference the commissioning answers to (e.g. a
    /// planned projector spec id). Identifies intent only — planned
    /// values stay plan-side.
    public let plannedSpecRef: String?
    /// Device/configuration context shared with legacy bolph71656-ai/HTDT-Capture#301 (e.g. projector
    /// settings profile), as with routing records.
    public let deviceContextRef: String?
    /// The `ProjectionScreenSemantics` record the projected image
    /// lands on, composing aperture/masking authority (legacy bolph71656-ai/HTDT-Capture#289) with
    /// this observation.
    public let screenSemanticsAuthorityID: AuthorityRecordID?
    public let observedAtUTC: String
    public let coordinateSpaceID: CoordinateSpaceID?
    public let evidenceRefs: [String]

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        projectorEntityID: AnnotationEntityID,
        lensCenterEntityID: AnnotationEntityID? = nil,
        throwObservation: AttestedSettingValue? = nil,
        throwEndpointSemantics: String? = nil,
        zoom: AttestedSettingValue? = nil,
        lensShiftHorizontal: AttestedSettingValue? = nil,
        lensShiftVertical: AttestedSettingValue? = nil,
        lensMemoryPreset: AttestedSettingValue? = nil,
        mountOrientation: ProjectorMountOrientation? = nil,
        focusState: ProjectorFocusState? = nil,
        opticalAxis: OrientationAxes? = nil,
        imageAlignmentNote: String? = nil,
        plannedSpecRef: String? = nil,
        deviceContextRef: String? = nil,
        screenSemanticsAuthorityID: AuthorityRecordID? = nil,
        observedAtUTC: String,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        evidenceRefs: [String] = []
    ) throws {
        guard lensCenterEntityID != projectorEntityID else {
            throw TheaterAuthorityError.unresolvedEntityReference
        }
        let normalizedEndpoints =
            SchemaOwnedText.nfc(throwEndpointSemantics)
        if let normalizedEndpoints, normalizedEndpoints.isEmpty {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard (throwObservation == nil) == (normalizedEndpoints == nil)
        else {
            throw TheaterAuthorityError.missingSourceBinding
        }
        for text in [
            SchemaOwnedText.nfc(imageAlignmentNote),
            SchemaOwnedText.nfc(plannedSpecRef),
            SchemaOwnedText.nfc(deviceContextRef),
        ] {
            if let text, text.isEmpty {
                throw AnnotationModelError.emptyAuthorityReference
            }
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
        self.authorityID = authorityID
        self.projectorEntityID = projectorEntityID
        self.lensCenterEntityID = lensCenterEntityID
        self.throwObservation = throwObservation
        self.throwEndpointSemantics = normalizedEndpoints
        self.zoom = zoom
        self.lensShiftHorizontal = lensShiftHorizontal
        self.lensShiftVertical = lensShiftVertical
        self.lensMemoryPreset = lensMemoryPreset
        self.mountOrientation = mountOrientation
        self.focusState = focusState
        self.opticalAxis = opticalAxis
        self.imageAlignmentNote = SchemaOwnedText.nfc(imageAlignmentNote)
        self.plannedSpecRef = SchemaOwnedText.nfc(plannedSpecRef)
        self.deviceContextRef = SchemaOwnedText.nfc(deviceContextRef)
        self.screenSemanticsAuthorityID = screenSemanticsAuthorityID
        self.observedAtUTC = observedAtUTC
        self.coordinateSpaceID = coordinateSpaceID
        self.evidenceRefs = normalizedEvidence.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case projectorEntityID = "projector_entity_id"
        case lensCenterEntityID = "lens_center_entity_id"
        case throwObservation = "throw_observation"
        case throwEndpointSemantics = "throw_endpoint_semantics"
        case zoom
        case lensShiftHorizontal = "lens_shift_horizontal"
        case lensShiftVertical = "lens_shift_vertical"
        case lensMemoryPreset = "lens_memory_preset"
        case mountOrientation = "mount_orientation"
        case focusState = "focus_state"
        case opticalAxis = "optical_axis"
        case imageAlignmentNote = "image_alignment_note"
        case plannedSpecRef = "planned_spec_ref"
        case deviceContextRef = "device_context_ref"
        case screenSemanticsAuthorityID =
            "screen_semantics_authority_id"
        case observedAtUTC = "observed_at_utc"
        case coordinateSpaceID = "coordinate_space_id"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            projectorEntityID: container.decode(
                AnnotationEntityID.self,
                forKey: .projectorEntityID
            ),
            lensCenterEntityID: container.decodeIfPresent(
                AnnotationEntityID.self,
                forKey: .lensCenterEntityID
            ),
            throwObservation: container.decodeIfPresent(
                AttestedSettingValue.self,
                forKey: .throwObservation
            ),
            throwEndpointSemantics: container.decodeIfPresent(
                String.self,
                forKey: .throwEndpointSemantics
            ),
            zoom: container.decodeIfPresent(
                AttestedSettingValue.self,
                forKey: .zoom
            ),
            lensShiftHorizontal: container.decodeIfPresent(
                AttestedSettingValue.self,
                forKey: .lensShiftHorizontal
            ),
            lensShiftVertical: container.decodeIfPresent(
                AttestedSettingValue.self,
                forKey: .lensShiftVertical
            ),
            lensMemoryPreset: container.decodeIfPresent(
                AttestedSettingValue.self,
                forKey: .lensMemoryPreset
            ),
            mountOrientation: container.decodeIfPresent(
                ProjectorMountOrientation.self,
                forKey: .mountOrientation
            ),
            focusState: container.decodeIfPresent(
                ProjectorFocusState.self,
                forKey: .focusState
            ),
            opticalAxis: container.decodeIfPresent(
                OrientationAxes.self,
                forKey: .opticalAxis
            ),
            imageAlignmentNote: container.decodeIfPresent(
                String.self,
                forKey: .imageAlignmentNote
            ),
            plannedSpecRef: container.decodeIfPresent(
                String.self,
                forKey: .plannedSpecRef
            ),
            deviceContextRef: container.decodeIfPresent(
                String.self,
                forKey: .deviceContextRef
            ),
            screenSemanticsAuthorityID: container.decodeIfPresent(
                AuthorityRecordID.self,
                forKey: .screenSemanticsAuthorityID
            ),
            observedAtUTC: container.decode(
                String.self,
                forKey: .observedAtUTC
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

// MARK: - Installation alignment assist (legacy bolph71656-ai/HTDT-Capture#346)

/// How the assist guided the operator. `spatial_delta` is only possible
/// under a proven plan alignment authority (legacy bolph71656-ai/HTDT-Capture#232/legacy bolph71656-ai/HTDT-Capture#227/legacy bolph71656-ai/HTDT-Capture#293); without
/// one the assistant degrades to `textual_instructions` and never
/// fabricates metric guidance.
public enum AlignmentGuidanceMode: String, Codable, Sendable,
    CaseIterable
{
    case spatialDelta = "spatial_delta"
    case textualInstructions = "textual_instructions"
}

/// Whether the live guidance could claim sufficient precision to place
/// against the design target. `insufficient` and `unknown` are both
/// first-class results — the assistant declares its limit instead of
/// faking a number.
public enum PrecisionSufficiency: String, Codable, Sendable,
    CaseIterable
{
    case sufficient
    case insufficient
    case unknown
}

/// One attested outcome of the installation-alignment assist (legacy bolph71656-ai/HTDT-Capture#346):
/// which exact planned target was aimed at, how guidance ran, whether
/// it could claim sufficient precision, the final independently
/// captured entity, and the deviation reported against the plan.
///
/// Authority separation is explicit: the plan's design target lives in
/// `targetPlannedEntityID`, the live guidance estimate lived only in
/// the assist UI, the final as-built is the `finalEntityID` entity
/// captured under `coordinateSpaceID`, and `reportedDeviation` is the
/// verification result. A spatial deviation is only recordable when an
/// alignment authority was proven (`guidanceMode == .spatialDelta` with
/// `alignment` present).
public struct InstallationAlignmentRecord: Codable, Sendable, Equatable {
    public let authorityID: AuthorityRecordID
    /// Exact planned-entity identity from the design target list
    /// (matches `PlannedAsBuiltSpec.plannedEntityID`).
    public let targetPlannedEntityID: String
    public let targetEntityType: AnnotationEntityType
    /// Entity the design aims at (e.g. the MLP/listening position
    /// entity) — only recordable when the design explicitly defines
    /// one.
    public let aimAtEntityID: AnnotationEntityID?
    public let guidanceMode: AlignmentGuidanceMode
    /// The proven `captureWorld -> scene` alignment the guidance ran
    /// under. Required for `spatialDelta`; absent for textual guidance.
    public let alignment: PlanAlignmentAuthority?
    public let precisionSufficiency: PrecisionSufficiency
    /// The entity committed as the final as-built — independently
    /// observed, never the plan value.
    public let finalEntityID: AnnotationEntityID
    /// Deviation of the final entity from the planned pose under the
    /// alignment, when computed.
    public let reportedDeviation: AsBuiltDeviation?
    public let observedAtUTC: String
    public let coordinateSpaceID: CoordinateSpaceID
    public let evidenceRefs: [String]

    public init(
        authorityID: AuthorityRecordID = AuthorityRecordID(),
        targetPlannedEntityID: String,
        targetEntityType: AnnotationEntityType,
        aimAtEntityID: AnnotationEntityID? = nil,
        guidanceMode: AlignmentGuidanceMode,
        alignment: PlanAlignmentAuthority? = nil,
        precisionSufficiency: PrecisionSufficiency,
        finalEntityID: AnnotationEntityID,
        reportedDeviation: AsBuiltDeviation? = nil,
        observedAtUTC: String,
        coordinateSpaceID: CoordinateSpaceID,
        evidenceRefs: [String] = []
    ) throws {
        let normalizedTarget = SchemaOwnedText.nfc(targetPlannedEntityID)
        guard !normalizedTarget.isEmpty else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard aimAtEntityID != finalEntityID else {
            throw TheaterAuthorityError.unresolvedEntityReference
        }
        switch guidanceMode {
        case .spatialDelta:
            guard alignment != nil else {
                throw TheaterAuthorityError.missingSourceBinding
            }
        case .textualInstructions:
            break
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
        self.authorityID = authorityID
        self.targetPlannedEntityID = normalizedTarget
        self.targetEntityType = targetEntityType
        self.aimAtEntityID = aimAtEntityID
        self.guidanceMode = guidanceMode
        self.alignment = alignment
        self.precisionSufficiency = precisionSufficiency
        self.finalEntityID = finalEntityID
        self.reportedDeviation = reportedDeviation
        self.observedAtUTC = observedAtUTC
        self.coordinateSpaceID = coordinateSpaceID
        self.evidenceRefs = normalizedEvidence.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case targetPlannedEntityID = "target_planned_entity_id"
        case targetEntityType = "target_entity_type"
        case aimAtEntityID = "aim_at_entity_id"
        case guidanceMode = "guidance_mode"
        case alignment
        case precisionSufficiency = "precision_sufficiency"
        case finalEntityID = "final_entity_id"
        case reportedDeviation = "reported_deviation"
        case observedAtUTC = "observed_at_utc"
        case coordinateSpaceID = "coordinate_space_id"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            authorityID: container.decode(
                AuthorityRecordID.self,
                forKey: .authorityID
            ),
            targetPlannedEntityID: container.decode(
                String.self,
                forKey: .targetPlannedEntityID
            ),
            targetEntityType: container.decode(
                AnnotationEntityType.self,
                forKey: .targetEntityType
            ),
            aimAtEntityID: container.decodeIfPresent(
                AnnotationEntityID.self,
                forKey: .aimAtEntityID
            ),
            guidanceMode: container.decode(
                AlignmentGuidanceMode.self,
                forKey: .guidanceMode
            ),
            alignment: container.decodeIfPresent(
                PlanAlignmentAuthority.self,
                forKey: .alignment
            ),
            precisionSufficiency: container.decode(
                PrecisionSufficiency.self,
                forKey: .precisionSufficiency
            ),
            finalEntityID: container.decode(
                AnnotationEntityID.self,
                forKey: .finalEntityID
            ),
            reportedDeviation: container.decodeIfPresent(
                AsBuiltDeviation.self,
                forKey: .reportedDeviation
            ),
            observedAtUTC: container.decode(
                String.self,
                forKey: .observedAtUTC
            ),
            coordinateSpaceID: container.decode(
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
