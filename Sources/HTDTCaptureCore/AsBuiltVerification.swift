import Foundation

/// How the `captureWorld -> planned scene` alignment was established
/// (issue #293). An explicit authority is required — "looks close
/// enough" is never an alignment.
public enum PlanAlignmentMechanism: String, Codable, Sendable,
    Equatable
{
    /// The plan scene frame is anchored on a capture reference frame
    /// (e.g. the room's declared origin).
    case roomReferenceFrame = "room_reference_frame"
    /// Alignment was solved against a captured reference/fiducial
    /// target (issue #227).
    case referenceTarget = "reference_target"
    /// Alignment was entered from an explicit surveyed transform.
    case manualSurvey = "manual_survey"
}

/// Per-item verification outcome (issue #293).
public enum AsBuiltItemState: String, Codable, Sendable, Equatable {
    /// Planned item has no captured observation yet.
    case pending
    /// Actual position captured; deviation evaluated under the plan's
    /// tolerance policy and within tolerance.
    case verified
    /// Actual position captured; deviation exceeds the plan's
    /// tolerance policy.
    case deviated
    /// Actual position captured; no tolerance policy applies, so the
    /// deviation is reported without a pass/fail verdict.
    case captured
    /// Operator marked the item unavailable (e.g. location blocked).
    case unavailable
}

public enum AsBuiltVerificationError: Error, Sendable, Equatable {
    case emptyField
    case invalidTransform
    case invalidTolerance
    case unknownPlannedEntity
    case duplicatePlannedEntity
    case duplicateEvidenceReference
    /// Spatial verification is impossible without an explicit
    /// alignment authority — the session falls back to the
    /// non-spatial checklist instead.
    case alignmentRequired
    case invalidResidualValue
    case encodedDocumentMismatch
}

/// One planned speaker/screen/projector position imported from HTDT.
/// Coordinates live in the plan's own scene frame; they are never
/// treated as capture-space truth.
public struct PlannedAsBuiltSpec: Codable, Sendable, Equatable {
    public let plannedEntityID: String
    public let entityType: AnnotationEntityType
    public let channelRole: ChannelRole?
    public let label: String?
    /// Planned position in the plan scene frame, meters.
    public let positionScene: SpatialVector3F
    /// Planned front/up axes in the scene frame, when the plan
    /// specifies orientation.
    public let orientationScene: OrientationAxes?
    /// Optional per-item positional tolerance in meters; evaluated
    /// only when a versioned policy applies it.
    public let toleranceMeters: Double?

    public init(
        plannedEntityID: String,
        entityType: AnnotationEntityType,
        channelRole: ChannelRole? = nil,
        label: String? = nil,
        positionScene: SpatialVector3F,
        orientationScene: OrientationAxes? = nil,
        toleranceMeters: Double? = nil
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(plannedEntityID)
        guard !normalizedID.isEmpty else {
            throw AsBuiltVerificationError.emptyField
        }
        if let toleranceMeters {
            guard toleranceMeters.isFinite,
                  toleranceMeters >= 0
            else {
                throw AsBuiltVerificationError.invalidTolerance
            }
        }
        self.plannedEntityID = normalizedID
        self.entityType = entityType
        self.channelRole = channelRole
        self.label = SchemaOwnedText.nfc(label)
        self.positionScene = positionScene
        self.orientationScene = orientationScene
        self.toleranceMeters = toleranceMeters
    }

    private enum CodingKeys: String, CodingKey {
        case plannedEntityID = "planned_entity_id"
        case entityType = "entity_type"
        case channelRole = "channel_role"
        case label
        case positionScene = "position_scene"
        case orientationScene = "orientation_scene"
        case toleranceMeters = "tolerance_m"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            plannedEntityID: container.decode(
                String.self,
                forKey: .plannedEntityID
            ),
            entityType: container.decode(
                AnnotationEntityType.self,
                forKey: .entityType
            ),
            channelRole: container.decodeIfPresent(
                ChannelRole.self,
                forKey: .channelRole
            ),
            label: container.decodeIfPresent(
                String.self,
                forKey: .label
            ),
            positionScene: container.decode(
                SpatialVector3F.self,
                forKey: .positionScene
            ),
            orientationScene: container.decodeIfPresent(
                OrientationAxes.self,
                forKey: .orientationScene
            ),
            toleranceMeters: container.decodeIfPresent(
                Double.self,
                forKey: .toleranceMeters
            )
        )
    }
}

/// The explicit `captureWorld -> planned scene` alignment authority
/// (issue #293): which mechanism established it, the rigid transform
/// itself, and the evidence it rests on. Ghost overlay is only shown
/// while a valid authority is installed.
public struct PlanAlignmentAuthority: Codable, Sendable, Equatable {
    public let mechanism: PlanAlignmentMechanism
    /// Scene-from-capture-world rigid transform.
    public let sceneFromCapture: Matrix4x4F
    /// Authority citation — e.g. "reference_target:<uuid>",
    /// "room_reference_frame", or a survey document ref.
    public let authorityRef: String
    public let evidenceRefs: [String]
    public let establishedAtUTC: String

    public init(
        mechanism: PlanAlignmentMechanism,
        sceneFromCapture: Matrix4x4F,
        authorityRef: String,
        evidenceRefs: [String] = [],
        establishedAtUTC: String
    ) throws {
        let normalizedRef = SchemaOwnedText.nfc(authorityRef)
        guard !normalizedRef.isEmpty else {
            throw AsBuiltVerificationError.emptyField
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AsBuiltVerificationError.emptyField
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AsBuiltVerificationError.duplicateEvidenceReference
        }
        guard SchemaTimestampText.isUTCTimestamp(establishedAtUTC)
        else {
            throw AsBuiltVerificationError.invalidTransform
        }
        self.mechanism = mechanism
        self.sceneFromCapture = sceneFromCapture
        self.authorityRef = normalizedRef
        self.evidenceRefs = normalizedEvidence
        self.establishedAtUTC = establishedAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case mechanism
        case sceneFromCapture = "scene_from_capture"
        case authorityRef = "authority_ref"
        case evidenceRefs = "evidence_refs"
        case establishedAtUTC = "established_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            mechanism: container.decode(
                PlanAlignmentMechanism.self,
                forKey: .mechanism
            ),
            sceneFromCapture: container.decode(
                Matrix4x4F.self,
                forKey: .sceneFromCapture
            ),
            authorityRef: container.decode(
                String.self,
                forKey: .authorityRef
            ),
            evidenceRefs: container.decode(
                [String].self,
                forKey: .evidenceRefs
            ),
            establishedAtUTC: container.decode(
                String.self,
                forKey: .establishedAtUTC
            )
        )
    }
}

/// An independently captured actual position for one planned item —
/// observed truth, never the planned value (issue #293).
public struct AsBuiltObservation: Codable, Sendable, Equatable {
    public let plannedEntityID: String
    /// Observed world-space position in the bound coordinate space.
    public let positionWorld: SpatialVector3F
    public let orientationWorld: OrientationAxes?
    public let coordinateSpaceID: CoordinateSpaceID
    public let placement: PlacementProvenance?
    public let observedAtUTC: String?
    public let evidenceRefs: [String]

    public init(
        plannedEntityID: String,
        positionWorld: SpatialVector3F,
        orientationWorld: OrientationAxes? = nil,
        coordinateSpaceID: CoordinateSpaceID,
        placement: PlacementProvenance? = nil,
        observedAtUTC: String? = nil,
        evidenceRefs: [String] = []
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(plannedEntityID)
        guard !normalizedID.isEmpty else {
            throw AsBuiltVerificationError.emptyField
        }
        if let observedAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(observedAtUTC)
            else {
                throw AsBuiltVerificationError.invalidTransform
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw AsBuiltVerificationError.emptyField
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw AsBuiltVerificationError.duplicateEvidenceReference
        }
        self.plannedEntityID = normalizedID
        self.positionWorld = positionWorld
        self.orientationWorld = orientationWorld
        self.coordinateSpaceID = coordinateSpaceID
        self.placement = placement
        self.observedAtUTC = observedAtUTC
        self.evidenceRefs = normalizedEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case plannedEntityID = "planned_entity_id"
        case positionWorld = "position_world"
        case orientationWorld = "orientation_world"
        case coordinateSpaceID = "coordinate_space_id"
        case placement
        case observedAtUTC = "observed_at"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            plannedEntityID: container.decode(
                String.self,
                forKey: .plannedEntityID
            ),
            positionWorld: container.decode(
                SpatialVector3F.self,
                forKey: .positionWorld
            ),
            orientationWorld: container.decodeIfPresent(
                OrientationAxes.self,
                forKey: .orientationWorld
            ),
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            placement: container.decodeIfPresent(
                PlacementProvenance.self,
                forKey: .placement
            ),
            observedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .observedAtUTC
            ),
            evidenceRefs: container.decode(
                [String].self,
                forKey: .evidenceRefs
            )
        )
    }
}

/// Computed deviation of one observed position from its plan —
/// always expressed in the plan scene frame via the alignment
/// authority.
public struct AsBuiltDeviation: Codable, Sendable, Equatable {
    /// observed(scene) - planned(scene), meters.
    public let translationScene: SpatialVector3F
    public let distanceMeters: Double
    /// Heading delta between planned and observed front axes,
    /// radians, when both orientations are known.
    public let headingDeltaRadians: Double?

    public init(
        translationScene: SpatialVector3F,
        distanceMeters: Double,
        headingDeltaRadians: Double? = nil
    ) throws {
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            throw AsBuiltVerificationError.invalidResidualValue
        }
        if let headingDeltaRadians {
            guard headingDeltaRadians.isFinite else {
                throw AsBuiltVerificationError.invalidResidualValue
            }
        }
        self.translationScene = translationScene
        self.distanceMeters = distanceMeters
        self.headingDeltaRadians = headingDeltaRadians
    }

    private enum CodingKeys: String, CodingKey {
        case translationScene = "translation_scene"
        case distanceMeters = "distance_m"
        case headingDeltaRadians = "heading_delta_rad"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            translationScene: container.decode(
                SpatialVector3F.self,
                forKey: .translationScene
            ),
            distanceMeters: container.decode(
                Double.self,
                forKey: .distanceMeters
            ),
            headingDeltaRadians: container.decodeIfPresent(
                Double.self,
                forKey: .headingDeltaRadians
            )
        )
    }
}

/// One planned item plus its verification state in the persisted
/// document.
public struct AsBuiltVerificationItem: Codable, Sendable, Equatable {
    public let spec: PlannedAsBuiltSpec
    public let state: AsBuiltItemState
    public let observation: AsBuiltObservation?
    public let deviation: AsBuiltDeviation?

    public init(
        spec: PlannedAsBuiltSpec,
        state: AsBuiltItemState,
        observation: AsBuiltObservation? = nil,
        deviation: AsBuiltDeviation? = nil
    ) throws {
        if state == .pending || state == .unavailable {
            guard observation == nil, deviation == nil else {
                throw AsBuiltVerificationError.invalidResidualValue
            }
        }
        self.spec = spec
        self.state = state
        self.observation = observation
        self.deviation = deviation
    }

    private enum CodingKeys: String, CodingKey {
        case spec
        case state
        case observation
        case deviation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            spec: container.decode(
                PlannedAsBuiltSpec.self,
                forKey: .spec
            ),
            state: container.decode(
                AsBuiltItemState.self,
                forKey: .state
            ),
            observation: container.decodeIfPresent(
                AsBuiltObservation.self,
                forKey: .observation
            ),
            deviation: container.decodeIfPresent(
                AsBuiltDeviation.self,
                forKey: .deviation
            )
        )
    }
}

/// The persisted as-built verification document at
/// `verification/as-built.json` (issue #293). Planned and observed
/// authorities stay distinct: the plan spec is immutable input, the
/// observation is the captured actual, the deviation is computed
/// through the explicit alignment authority only.
public struct AsBuiltVerificationDocument: Codable, Sendable,
    Equatable
{
    public static let schema = "htdt.capture.as-built-verification"
    public static let schemaVersion = "1.0.0"
    public static let path = "verification/as-built.json"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    /// Immutable identity of the imported plan this verifies.
    public let planID: String
    public let planVersion: String
    public let planSHA256: EvidenceSHA256
    /// Versioned tolerance policy under which deviations were
    /// evaluated; nil when the plan supplied no policy.
    public let tolerancePolicyRef: String?
    /// Present only while an explicit alignment authority is
    /// established; without it the document degrades to checklist.
    public let alignment: PlanAlignmentAuthority?
    public let items: [AsBuiltVerificationItem]

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        planID: String,
        planVersion: String,
        planSHA256: EvidenceSHA256,
        tolerancePolicyRef: String?,
        alignment: PlanAlignmentAuthority?,
        items: [AsBuiltVerificationItem]
    ) throws {
        guard Set(items.map(\.spec.plannedEntityID)).count
                == items.count
        else {
            throw AsBuiltVerificationError.duplicatePlannedEntity
        }
        let normalizedPolicy = SchemaOwnedText.nfc(tolerancePolicyRef)
        if let normalizedPolicy, normalizedPolicy.isEmpty {
            throw AsBuiltVerificationError.emptyField
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.planID = planID
        self.planVersion = planVersion
        self.planSHA256 = planSHA256
        self.tolerancePolicyRef = normalizedPolicy
        self.alignment = alignment
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case planID = "plan_id"
        case planVersion = "plan_version"
        case planSHA256 = "plan_sha256"
        case tolerancePolicyRef = "tolerance_policy_ref"
        case alignment
        case items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.schema,
              schemaVersion == Self.schemaVersion
        else {
            throw AsBuiltVerificationError.encodedDocumentMismatch
        }
        try self.init(
            captureRevisionID: container.decode(
                CaptureRevisionID.self,
                forKey: .captureRevisionID
            ),
            captureSessionID: container.decode(
                CaptureSessionID.self,
                forKey: .captureSessionID
            ),
            planID: container.decode(String.self, forKey: .planID),
            planVersion: container.decode(
                String.self,
                forKey: .planVersion
            ),
            planSHA256: container.decode(
                EvidenceSHA256.self,
                forKey: .planSHA256
            ),
            tolerancePolicyRef: container.decodeIfPresent(
                String.self,
                forKey: .tolerancePolicyRef
            ),
            alignment: container.decodeIfPresent(
                PlanAlignmentAuthority.self,
                forKey: .alignment
            ),
            items: container.decode(
                [AsBuiltVerificationItem].self,
                forKey: .items
            )
        )
    }
}

/// Live as-built verification session (issue #293). Without an
/// explicit alignment authority the session still records captured
/// actuals and operator marks — but spatially evaluated states and
/// the ghost overlay stay unavailable, and the persisted document
/// degrades to the non-spatial checklist.
public struct AsBuiltVerificationSession: Sendable, Equatable {
    public let planID: String
    public let planVersion: String
    public let planSHA256: EvidenceSHA256
    /// Versioned tolerance policy reference, when the plan carries
    /// one. Deviation pass/fail is only produced under this policy.
    public let tolerancePolicyRef: String?
    public let coordinateSpaceID: CoordinateSpaceID

    public private(set) var specs: [PlannedAsBuiltSpec]
    public private(set) var alignment: PlanAlignmentAuthority?
    private var observations: [String: AsBuiltObservation]
    private var unavailableIDs: Set<String>

    public init(
        planID: String,
        planVersion: String,
        planSHA256: EvidenceSHA256,
        tolerancePolicyRef: String? = nil,
        coordinateSpaceID: CoordinateSpaceID,
        specs: [PlannedAsBuiltSpec]
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(planID)
        let normalizedVersion = SchemaOwnedText.nfc(planVersion)
        guard !normalizedID.isEmpty, !normalizedVersion.isEmpty else {
            throw AsBuiltVerificationError.emptyField
        }
        guard Set(specs.map(\.plannedEntityID)).count == specs.count
        else {
            throw AsBuiltVerificationError.duplicatePlannedEntity
        }
        self.planID = normalizedID
        self.planVersion = normalizedVersion
        self.planSHA256 = planSHA256
        self.tolerancePolicyRef =
            SchemaOwnedText.nfc(tolerancePolicyRef)
        self.coordinateSpaceID = coordinateSpaceID
        self.specs = specs
        self.alignment = nil
        self.observations = [:]
        self.unavailableIDs = []
    }

    /// Whether the ghost overlay may be shown — only while an
    /// explicit alignment authority is installed.
    public var ghostOverlayEnabled: Bool {
        alignment != nil
    }

    /// Installs the explicit alignment authority. Only mechanisms in
    /// `PlanAlignmentMechanism` are admissible — the call site must
    /// construct the authority, so "looks close enough" cannot
    /// produce one.
    public mutating func installAlignment(
        _ authority: PlanAlignmentAuthority
    ) {
        alignment = authority
    }

    public mutating func clearAlignment() {
        alignment = nil
    }

    /// Records an independently captured actual position for one
    /// planned item.
    public mutating func recordActual(
        _ observation: AsBuiltObservation
    ) throws {
        guard specs.contains(where: {
            $0.plannedEntityID == observation.plannedEntityID
        }) else {
            throw AsBuiltVerificationError.unknownPlannedEntity
        }
        guard observation.coordinateSpaceID == coordinateSpaceID
        else {
            throw AsBuiltVerificationError.invalidTransform
        }
        observations[observation.plannedEntityID] = observation
        unavailableIDs.remove(observation.plannedEntityID)
    }

    /// Operator mark: the planned location could not be captured.
    public mutating func markUnavailable(
        _ plannedEntityID: String
    ) throws {
        guard specs.contains(where: {
            $0.plannedEntityID == plannedEntityID
        }) else {
            throw AsBuiltVerificationError.unknownPlannedEntity
        }
        unavailableIDs.insert(plannedEntityID)
    }

    /// Per-item deviation and state. Spatial evaluation requires the
    /// alignment authority; without it captured items report
    /// `.captured` only when the caller explicitly tolerates the
    /// non-spatial checklist — `deviation` throws instead.
    public func items() throws -> [AsBuiltVerificationItem] {
        try specs.map { spec in
            try item(for: spec)
        }
    }

    public func item(
        for spec: PlannedAsBuiltSpec
    ) throws -> AsBuiltVerificationItem {
        if unavailableIDs.contains(spec.plannedEntityID) {
            return try AsBuiltVerificationItem(
                spec: spec,
                state: .unavailable
            )
        }
        guard let observation =
                observations[spec.plannedEntityID]
        else {
            return try AsBuiltVerificationItem(
                spec: spec,
                state: .pending
            )
        }
        guard let alignment else {
            // Checklist fallback: the observation is recorded but no
            // spatial verdict exists without an alignment authority.
            return try AsBuiltVerificationItem(
                spec: spec,
                state: .captured,
                observation: observation
            )
        }
        let deviation = try Self.deviation(
            spec: spec,
            observation: observation,
            sceneFromCapture: alignment.sceneFromCapture
        )
        let state: AsBuiltItemState
        if tolerancePolicyRef != nil,
           let tolerance = spec.toleranceMeters
        {
            state = deviation.distanceMeters <= tolerance
                ? .verified
                : .deviated
        } else {
            state = .captured
        }
        return try AsBuiltVerificationItem(
            spec: spec,
            state: state,
            observation: observation,
            deviation: deviation
        )
    }

    /// The deviation of an observed world position through the
    /// alignment transform, in the plan scene frame.
    public static func deviation(
        spec: PlannedAsBuiltSpec,
        observation: AsBuiltObservation,
        sceneFromCapture: Matrix4x4F
    ) throws -> AsBuiltDeviation {
        let observedScene = sceneFromCapture.applying(
            to: Float3(
                observation.positionWorld.x,
                observation.positionWorld.y,
                observation.positionWorld.z
            )
        )
        let planned = spec.positionScene
        let dx = observedScene.x - planned.x
        let dy = observedScene.y - planned.y
        let dz = observedScene.z - planned.z
        let distance = (dx * dx + dy * dy + dz * dz).squareRoot()

        var headingDelta: Double? = nil
        if let plannedOrientation = spec.orientationScene,
           let observedOrientation = observation.orientationWorld
        {
            let observedFront = sceneFromCapture.applyingDirection(
                to: Float3(
                    observedOrientation.frontAxisLocal.x,
                    observedOrientation.frontAxisLocal.y,
                    observedOrientation.frontAxisLocal.z
                )
            )
            let plannedFront = plannedOrientation.frontAxisLocal
            let dotProduct = Double(
                observedFront.x * plannedFront.x
                    + observedFront.y * plannedFront.y
                    + observedFront.z * plannedFront.z
            )
            headingDelta = acos(
                min(1, max(-1, dotProduct))
            )
        }
        return try AsBuiltDeviation(
            translationScene: try SpatialVector3F(
                observedScene.x,
                observedScene.y,
                observedScene.z
            ),
            distanceMeters: Double(distance),
            headingDeltaRadians: headingDelta
        )
    }

    /// Builds the persisted verification document for the working set.
    public func document(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID
    ) throws -> AsBuiltVerificationDocument {
        try AsBuiltVerificationDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            planID: planID,
            planVersion: planVersion,
            planSHA256: planSHA256,
            tolerancePolicyRef: tolerancePolicyRef,
            alignment: alignment,
            items: items()
        )
    }

    /// Encoded payload for the supplemental-document store path.
    public func package(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID
    ) throws -> Data {
        let document = try document(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard
            let decoded = try? JSONDecoder().decode(
                AsBuiltVerificationDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw AsBuiltVerificationError.encodedDocumentMismatch
        }
        return data
    }
}

public extension Matrix4x4F {
    /// Applies only the rotation basis to a direction vector.
    func applyingDirection(to vector: Float3) -> Float3 {
        Float3(
            values[0] * vector.x + values[4] * vector.y
                + values[8] * vector.z,
            values[1] * vector.x + values[5] * vector.y
                + values[9] * vector.z,
            values[2] * vector.x + values[6] * vector.y
                + values[10] * vector.z
        )
    }
}
