import Foundation

/// iOS 27 reference-object evidence lane (#268): asset manifest,
/// mission-scoped selection, and the persisted observation document.
///
/// Authority model (from the issue contract):
///   ARKit matches asset X; the asset manifest configures X as a proxy
///   for physical object Y; the operator may bind an observation to
///   entity Z. A match is NEVER silently merged into equipment
///   identity or existing raycast/orientation/geometry evidence — it
///   lands alongside as an observation record the operator can accept.
///
/// The observation document is sensor truth: poses, lifecycle events,
/// and tracked state exactly as ARKit reported them, plus the
/// provenance echo of every `.referenceobject` artifact the session
/// was configured with. No confidence scalar is recorded — ARKit
/// does not expose one, and `isTracked` loss is modeled as a
/// lifecycle event, never as anchor removal.

// MARK: - Asset manifest

/// Stable manifest identity for a shipped `.referenceobject` artifact.
/// Unlike capture identifiers this is a human-minted slug — the same
/// `asset_id` survives retraining; only `revision` advances, so old
/// evidence is never reinterpreted against a retrained artifact.
public struct ReferenceObjectAssetID:
    RawRepresentable, Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    /// Slug form: lowercase, starts with a letter, `a-z0-9_`, <= 64
    /// chars. Keeps the id usable inside namespaced evidence refs.
    public init?(validating rawValue: String) {
        guard rawValue.range(
            of: #"^[a-z][a-z0-9_]{0,63}$"#,
            options: .regularExpression
        ) != nil,
              SchemaOwnedText.nfc(rawValue) == rawValue
        else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// Session role an asset is configured for: `detection` is the
/// stationary-object path (`detectionObjects`); `tracking` is the
/// high-frame-rate moving/handheld path (`trackingObjects`, iOS 27+).
public enum ReferenceObjectAssetRole: String, Codable, Sendable,
    Equatable
{
    case detection
    case tracking
}

/// Create ML object-tracker training mode recorded in the manifest.
public enum ReferenceObjectTrainingMode: String, Codable, Sendable,
    Equatable
{
    case standard
    case extended
}

public enum ReferenceObjectError: Error, Sendable, Equatable {
    case emptyField
    case invalidAssetID
    case invalidRevision
    case invalidDigest
    case invalidDimensions
    case invalidTimestamp
    case invalidObservationIndex
    case duplicateAssetID
    case duplicateObservationID
    case duplicateAnchorID
    case observationOverflow
    case encodedDocumentMismatch
    case unsupportedSchema
}

/// Digest/source identity of a build artifact. The manifest records
/// SHA-256 so a consumer can prove which bytes produced evidence.
public struct ReferenceObjectSourceArtifact: Codable, Sendable,
    Equatable
{
    /// Where the source artifact lives (repo-relative path or URL).
    /// Optional: an externally supplied USDZ may not have a repo URI.
    public let uri: String?
    public let sha256: String
    /// Upstream revision label of the source artifact (e.g. CAD rev).
    public let revision: String?

    public init(
        uri: String? = nil,
        sha256: String,
        revision: String? = nil
    ) throws {
        let normalizedDigest = sha256.lowercased()
        guard normalizedDigest.range(
            of: #"^[0-9a-f]{64}$"#,
            options: .regularExpression
        ) != nil else {
            throw ReferenceObjectError.invalidDigest
        }
        self.uri = uri.map { SchemaOwnedText.nfc($0) }
        self.sha256 = normalizedDigest
        self.revision = revision.map { SchemaOwnedText.nfc($0) }
    }
}

/// How the `.referenceobject` artifact was trained. A retrained asset
/// is a NEW `revision` of the same `asset_id` — never a silent
/// replacement — so historical evidence keeps pointing at the exact
/// artifact that produced it.
public struct ReferenceObjectTrainingProvenance: Codable, Sendable,
    Equatable
{
    public let createMLVersion: String?
    public let xcodeVersion: String?
    public let trainingMode: ReferenceObjectTrainingMode
    /// Free-text record of the createml viewing-angle arguments
    /// (e.g. "all", "front-top-side") — see
    /// `tools/reference_object_training/manifest.json`.
    public let viewingAngleConfig: String
    /// Identifier/path of the negative-example set used, if any.
    public let negativeExampleSetRef: String?
    /// Whether the USDZ preview payload was stripped from the shipped
    /// `.referenceobject` (REFERENCEOBJECT_STRIP_USDZ build decision).
    public let referenceObjectStripUSDZ: Bool

    public init(
        createMLVersion: String? = nil,
        xcodeVersion: String? = nil,
        trainingMode: ReferenceObjectTrainingMode,
        viewingAngleConfig: String,
        negativeExampleSetRef: String? = nil,
        referenceObjectStripUSDZ: Bool
    ) throws {
        let normalizedAngles = SchemaOwnedText.nfc(viewingAngleConfig)
        guard !normalizedAngles.isEmpty else {
            throw ReferenceObjectError.emptyField
        }
        self.createMLVersion =
            createMLVersion.map { SchemaOwnedText.nfc($0) }
        self.xcodeVersion =
            xcodeVersion.map { SchemaOwnedText.nfc($0) }
        self.trainingMode = trainingMode
        self.viewingAngleConfig = normalizedAngles
        self.negativeExampleSetRef =
            negativeExampleSetRef.map { SchemaOwnedText.nfc($0) }
        self.referenceObjectStripUSDZ = referenceObjectStripUSDZ
    }

    private enum CodingKeys: String, CodingKey {
        case createMLVersion = "createml_version"
        case xcodeVersion = "xcode_version"
        case trainingMode = "training_mode"
        case viewingAngleConfig = "viewing_angle_config"
        case negativeExampleSetRef = "negative_example_set"
        case referenceObjectStripUSDZ = "referenceobject_strip_usdz"
    }
}

/// Optional calibrated rigid transform from the recognized marker
/// (reference-object) frame into the equipment frame it stands for
/// (#268). Without it, consumers only have the marker pose.
public struct ReferenceObjectMarkerBinding: Codable, Sendable,
    Equatable
{
    /// Stable id consumers cite as `marker_to_equipment_transform_id`.
    public let transformID: String
    /// Column-major rigid `T_marker_from_equipment`.
    public let tMarkerFromEquipment: Matrix4x4F
    /// How this transform was obtained (jig, CAD alignment, ...).
    public let calibrationSource: String

    public init(
        transformID: String,
        tMarkerFromEquipment: Matrix4x4F,
        calibrationSource: String
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(transformID)
        let normalizedSource = SchemaOwnedText.nfc(calibrationSource)
        guard !normalizedID.isEmpty, !normalizedSource.isEmpty else {
            throw ReferenceObjectError.emptyField
        }
        self.transformID = normalizedID
        self.tMarkerFromEquipment = tMarkerFromEquipment
        self.calibrationSource = normalizedSource
    }

    private enum CodingKeys: String, CodingKey {
        case transformID = "transform_id"
        case tMarkerFromEquipment = "t_marker_from_equipment"
        case calibrationSource = "calibration_source"
    }
}

/// One shipped `.referenceobject` asset with full provenance.
public struct ReferenceObjectAsset: Codable, Sendable, Equatable {
    public let assetID: ReferenceObjectAssetID
    /// Manifest revision — bumped whenever the artifact is retrained
    /// or rebound. Evidence cites `asset_id` + `revision` together.
    public let revision: Int
    /// The name `ARReferenceObject.name` reports for this artifact —
    /// the runtime match key from `ARObjectAnchor` back to this entry.
    public let arkitObjectName: String
    /// File name inside the shipped object bundle directory.
    public let artifactFilename: String
    public let artifactSHA256: String
    public let sourceUSDZ: ReferenceObjectSourceArtifact
    /// Free-text declaration of the physical object this asset stands
    /// for (e.g. "HVAC sub-panel A on north wall"). This is manifest
    /// intent only — operator acceptance is still required to bind an
    /// observation to an entity.
    public let physicalBinding: String
    /// Measured object dimensions, meters.
    public let measuredDimensionsM: SpatialVector3F
    /// How the declared dimensions were obtained (calipers, CAD, ...).
    public let scaleValidationMethod: String
    public let training: ReferenceObjectTrainingProvenance
    /// Session roles this artifact is approved for.
    public let supportedRoles: [ReferenceObjectAssetRole]
    public let markerToEquipment: ReferenceObjectMarkerBinding?
    public let licenseProvenance: String

    public init(
        assetID: ReferenceObjectAssetID,
        revision: Int,
        arkitObjectName: String,
        artifactFilename: String,
        artifactSHA256: String,
        sourceUSDZ: ReferenceObjectSourceArtifact,
        physicalBinding: String,
        measuredDimensionsM: SpatialVector3F,
        scaleValidationMethod: String,
        training: ReferenceObjectTrainingProvenance,
        supportedRoles: [ReferenceObjectAssetRole],
        markerToEquipment: ReferenceObjectMarkerBinding? = nil,
        licenseProvenance: String
    ) throws {
        let normalizedName = SchemaOwnedText.nfc(arkitObjectName)
        let normalizedFilename = SchemaOwnedText.nfc(artifactFilename)
        let normalizedBinding = SchemaOwnedText.nfc(physicalBinding)
        let normalizedMethod =
            SchemaOwnedText.nfc(scaleValidationMethod)
        let normalizedLicense = SchemaOwnedText.nfc(licenseProvenance)
        guard !normalizedName.isEmpty, !normalizedFilename.isEmpty,
              !normalizedBinding.isEmpty, !normalizedMethod.isEmpty,
              !normalizedLicense.isEmpty
        else {
            throw ReferenceObjectError.emptyField
        }
        guard revision >= 1 else {
            throw ReferenceObjectError.invalidRevision
        }
        guard artifactSHA256.lowercased().range(
            of: #"^[0-9a-f]{64}$"#,
            options: .regularExpression
        ) != nil else {
            throw ReferenceObjectError.invalidDigest
        }
        let dimensions = measuredDimensionsM
        guard dimensions.x > 0, dimensions.y > 0, dimensions.z > 0
        else {
            throw ReferenceObjectError.invalidDimensions
        }
        guard !supportedRoles.isEmpty,
              Set(supportedRoles).count == supportedRoles.count
        else {
            throw ReferenceObjectError.emptyField
        }
        self.assetID = assetID
        self.revision = revision
        self.arkitObjectName = normalizedName
        self.artifactFilename = normalizedFilename
        self.artifactSHA256 = artifactSHA256.lowercased()
        self.sourceUSDZ = sourceUSDZ
        self.physicalBinding = normalizedBinding
        self.measuredDimensionsM = dimensions
        self.scaleValidationMethod = normalizedMethod
        self.training = training
        self.supportedRoles = supportedRoles
        self.markerToEquipment = markerToEquipment
        self.licenseProvenance = normalizedLicense
    }

    private enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case revision
        case arkitObjectName = "arkit_object_name"
        case artifactFilename = "artifact_filename"
        case artifactSHA256 = "artifact_sha256"
        case sourceUSDZ = "source_usdz"
        case physicalBinding = "physical_binding"
        case measuredDimensionsM = "measured_dimensions_m"
        case scaleValidationMethod = "scale_validation_method"
        case training
        case supportedRoles = "supported_roles"
        case markerToEquipment = "marker_to_equipment"
        case licenseProvenance = "license_provenance"
    }
}

/// The shipped-asset catalog document. Lives in the app bundle at
/// `ReferenceObjects/manifest.json`; it is mission INPUT, not capture
/// output — per-mission selection picks at most
/// `ReferenceObjectSelectionPolicy.maxConfiguredObjects` entries.
public struct ReferenceObjectAssetManifest: Codable, Sendable,
    Equatable
{
    public static let schema = "htdt.capture.reference-object-assets"
    public static let schemaVersion = "1.0.0"
    /// Bundle subdirectory the manifest and `.referenceobject`
    /// artifacts ship in.
    public static let bundleDirectory = "ReferenceObjects"
    public static let manifestFilename = "manifest.json"

    public let schema: String
    public let schemaVersion: String
    public let assets: [ReferenceObjectAsset]

    public init(assets: [ReferenceObjectAsset]) throws {
        guard Set(assets.map(\.assetID)).count == assets.count
        else {
            throw ReferenceObjectError.duplicateAssetID
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case assets
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
            throw ReferenceObjectError.unsupportedSchema
        }
        try self.init(
            assets: container.decode(
                [ReferenceObjectAsset].self,
                forKey: .assets
            )
        )
    }

    public func asset(for id: ReferenceObjectAssetID)
        -> ReferenceObjectAsset?
    {
        assets.first { $0.assetID == id }
    }

    /// `arkit_object_name` → asset lookup used to resolve an
    /// `ARObjectAnchor` back to manifest identity.
    public func asset(arkitObjectName: String) -> ReferenceObjectAsset?
    {
        assets.first { $0.arkitObjectName == arkitObjectName }
    }
}

// MARK: - Mission-scoped selection

/// One operator pick: this asset, used in this role for this mission.
public struct ReferenceObjectSelectionRequest: Codable, Sendable,
    Equatable
{
    public let assetID: ReferenceObjectAssetID
    public let role: ReferenceObjectAssetRole

    public init(
        assetID: ReferenceObjectAssetID,
        role: ReferenceObjectAssetRole
    ) {
        self.assetID = assetID
        self.role = role
    }

    private enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case role
    }
}

public enum ReferenceObjectRejectionReason: String, Codable, Sendable,
    Equatable
{
    case unknownAsset = "unknown_asset"
    case unsupportedRole = "unsupported_role"
    case duplicateAsset = "duplicate_asset"
    case capExceeded = "cap_exceeded"
}

/// One pick the selection policy could not honor — recorded verbatim
/// in the observation document so an absent match is explained rather
/// than silently missing.
public struct ReferenceObjectRejectedSelection: Codable, Sendable,
    Equatable
{
    public let assetID: ReferenceObjectAssetID
    public let reason: ReferenceObjectRejectionReason

    public init(
        assetID: ReferenceObjectAssetID,
        reason: ReferenceObjectRejectionReason
    ) {
        self.assetID = assetID
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case reason
    }
}

/// Resolved selection: the assets to configure (with roles) plus the
/// dropped requests. Never silently truncates — every rejection is
/// enumerated.
public struct ReferenceObjectSelectionPlan: Sendable, Equatable {
    public let selected: [ReferenceObjectSelectionRequest]
    public let rejected: [ReferenceObjectRejectedSelection]

    public init(
        selected: [ReferenceObjectSelectionRequest],
        rejected: [ReferenceObjectRejectedSelection]
    ) {
        self.selected = selected
        self.rejected = rejected
    }
}

/// Deterministic selection policy (#268): at most 10 objects may be
/// configured per session across detection+tracking combined (ARKit's
/// hard cap), each request must name a shipped asset and a role the
/// asset supports, and duplicates collapse to the first request.
public enum ReferenceObjectSelectionPolicy {
    /// ARKit's combined `detectionObjects` + `trackingObjects` limit.
    public static let maxConfiguredObjects = 10

    public static func resolve(
        requests: [ReferenceObjectSelectionRequest],
        manifest: ReferenceObjectAssetManifest
    ) -> ReferenceObjectSelectionPlan {
        var selected: [ReferenceObjectSelectionRequest] = []
        var rejected: [ReferenceObjectRejectedSelection] = []
        var seen = Set<ReferenceObjectAssetID>()

        for request in requests {
            if seen.contains(request.assetID) {
                rejected.append(
                    ReferenceObjectRejectedSelection(
                        assetID: request.assetID,
                        reason: .duplicateAsset
                    )
                )
                continue
            }
            seen.insert(request.assetID)
            guard let asset = manifest.asset(for: request.assetID)
            else {
                rejected.append(
                    ReferenceObjectRejectedSelection(
                        assetID: request.assetID,
                        reason: .unknownAsset
                    )
                )
                continue
            }
            guard asset.supportedRoles.contains(request.role) else {
                rejected.append(
                    ReferenceObjectRejectedSelection(
                        assetID: request.assetID,
                        reason: .unsupportedRole
                    )
                )
                continue
            }
            guard selected.count < Self.maxConfiguredObjects else {
                rejected.append(
                    ReferenceObjectRejectedSelection(
                        assetID: request.assetID,
                        reason: .capExceeded
                    )
                )
                continue
            }
            selected.append(request)
        }
        return ReferenceObjectSelectionPlan(
            selected: selected,
            rejected: rejected
        )
    }
}

// MARK: - Observation document

/// Which session path produced the observation — mirrors the asset's
/// configured role at match time.
public enum ReferenceObjectObservationMode: String, Codable, Sendable,
    Equatable
{
    case detection
    case tracking
}

/// What this observation record reports. `isTracked` loss is a
/// lifecycle event (`trackingLost`/`trackingResumed`), never anchor
/// removal — `removed` means ARKit dropped the anchor entirely.
public enum ReferenceObjectLifecycleEvent: String, Codable, Sendable,
    Equatable
{
    case added
    case updated
    case trackingLost = "tracking_lost"
    case trackingResumed = "tracking_resumed"
    case removed
}

public struct ReferenceObjectObservationID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// One persisted reference-object pose observation (#268). The record
/// is sensor truth: what ARKit reported, when, and in which coordinate
/// space — never an operator identity claim.
public struct ReferenceObjectPoseObservation: Codable, Sendable,
    Equatable
{
    public let observationID: ReferenceObjectObservationID
    public let captureSessionID: CaptureSessionID
    /// The coordinate space this pose is expressed in. After a
    /// recorded discontinuity the revision's bound space no longer
    /// covers new poses — the store's single-space policy applies.
    public let coordinateSpaceID: CoordinateSpaceID
    public let sessionTimestampSeconds: Double
    /// `ARObjectAnchor.identifier`.
    public let arAnchorID: UUID
    /// Manifest identity of the matched asset, resolved through
    /// `arkit_object_name`. When the match cannot be resolved to a
    /// configured asset this stays the raw object name and
    /// `referenceObjectRevision`/`referenceObjectDigestSHA256` are nil
    /// — an unresolved match is still evidence, never dropped.
    public let referenceObjectID: String
    public let referenceObjectRevision: Int?
    public let referenceObjectDigestSHA256: String?
    /// Column-major rigid `T_world_from_reference_object` —
    /// `ARObjectAnchor.transform` at the callback instant.
    public let tWorldFromReferenceObject: Matrix4x4F
    public let observationMode: ReferenceObjectObservationMode
    public let lifecycleEvent: ReferenceObjectLifecycleEvent
    /// `ARObjectAnchor.isTracked` (iOS 27+) at the callback instant.
    /// `nil` when the platform cannot report tracked state — the
    /// absence is recorded honestly rather than synthesized.
    public let isCurrentlyTracked: Bool?
    /// Retained-frame evidence ref when the platform/host kept one;
    /// `nil` when no frame is retained for this observation.
    public let sourceFrameRef: String?
    /// `marker_to_equipment.transform_id` from the matched asset's
    /// manifest entry, when it declares one.
    public let markerToEquipmentTransformID: String?

    public init(
        observationID: ReferenceObjectObservationID =
            ReferenceObjectObservationID(),
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        sessionTimestampSeconds: Double,
        arAnchorID: UUID,
        referenceObjectID: String,
        referenceObjectRevision: Int?,
        referenceObjectDigestSHA256: String?,
        tWorldFromReferenceObject: Matrix4x4F,
        observationMode: ReferenceObjectObservationMode,
        lifecycleEvent: ReferenceObjectLifecycleEvent,
        isCurrentlyTracked: Bool?,
        sourceFrameRef: String? = nil,
        markerToEquipmentTransformID: String? = nil
    ) throws {
        guard sessionTimestampSeconds.isFinite,
              sessionTimestampSeconds >= 0
        else {
            throw ReferenceObjectError.invalidTimestamp
        }
        let normalizedObjectID =
            SchemaOwnedText.nfc(referenceObjectID)
        guard !normalizedObjectID.isEmpty else {
            throw ReferenceObjectError.emptyField
        }
        if let revision = referenceObjectRevision {
            guard revision >= 1 else {
                throw ReferenceObjectError.invalidRevision
            }
        }
        if let digest = referenceObjectDigestSHA256 {
            guard digest.lowercased().range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            ) != nil else {
                throw ReferenceObjectError.invalidDigest
            }
        }
        self.observationID = observationID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.arAnchorID = arAnchorID
        self.referenceObjectID = normalizedObjectID
        self.referenceObjectRevision = referenceObjectRevision
        self.referenceObjectDigestSHA256 =
            referenceObjectDigestSHA256?.lowercased()
        self.tWorldFromReferenceObject = tWorldFromReferenceObject
        self.observationMode = observationMode
        self.lifecycleEvent = lifecycleEvent
        self.isCurrentlyTracked = isCurrentlyTracked
        self.sourceFrameRef =
            sourceFrameRef.map { SchemaOwnedText.nfc($0) }
        self.markerToEquipmentTransformID =
            markerToEquipmentTransformID.map {
                SchemaOwnedText.nfc($0)
            }
    }

    /// The namespaced evidence-ref token an entity's `evidence_refs`
    /// carries when the operator accepts this observation.
    public var evidenceRefToken: String {
        "reference_object_observation:" + observationID.description
    }

    private enum CodingKeys: String, CodingKey {
        case observationID = "observation_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case sessionTimestampSeconds = "session_timestamp_s"
        case arAnchorID = "ar_anchor_id"
        case referenceObjectID = "reference_object_id"
        case referenceObjectRevision = "reference_object_revision"
        case referenceObjectDigestSHA256 =
            "reference_object_digest_sha256"
        case tWorldFromReferenceObject =
            "t_world_from_reference_object"
        case observationMode = "observation_mode"
        case lifecycleEvent = "lifecycle_event"
        case isCurrentlyTracked = "is_currently_tracked"
        case sourceFrameRef = "source_frame_ref"
        case markerToEquipmentTransformID =
            "marker_to_equipment_transform_id"
    }

    /// `UUID`'s synthesized encoder emits uppercase; the bundle schema
    /// pins canonical lowercase v4 text like every other identifier.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(observationID, forKey: .observationID)
        try container.encode(captureSessionID, forKey: .captureSessionID)
        try container.encode(
            coordinateSpaceID,
            forKey: .coordinateSpaceID
        )
        try container.encode(
            sessionTimestampSeconds,
            forKey: .sessionTimestampSeconds
        )
        try container.encode(
            arAnchorID.uuidString.lowercased(),
            forKey: .arAnchorID
        )
        try container.encode(
            referenceObjectID,
            forKey: .referenceObjectID
        )
        try container.encodeIfPresent(
            referenceObjectRevision,
            forKey: .referenceObjectRevision
        )
        try container.encodeIfPresent(
            referenceObjectDigestSHA256,
            forKey: .referenceObjectDigestSHA256
        )
        try container.encode(
            tWorldFromReferenceObject,
            forKey: .tWorldFromReferenceObject
        )
        try container.encode(
            observationMode,
            forKey: .observationMode
        )
        try container.encode(lifecycleEvent, forKey: .lifecycleEvent)
        try container.encode(
            isCurrentlyTracked,
            forKey: .isCurrentlyTracked
        )
        try container.encodeIfPresent(
            sourceFrameRef,
            forKey: .sourceFrameRef
        )
        try container.encodeIfPresent(
            markerToEquipmentTransformID,
            forKey: .markerToEquipmentTransformID
        )
    }
}

/// What happened when the platform tried to load the artifact bytes.
public enum ReferenceObjectLoadOutcome: String, Codable, Sendable,
    Equatable
{
    case loaded
    /// File missing/unreadable — selection was honored logically but
    /// ARKit received nothing for this asset.
    case unavailable
    /// `ARReferenceObject(archiveURL:)` threw — the artifact failed
    /// ARKit's own format gate.
    case rejected
}

/// The manifest echo of one asset the session was configured with,
/// plus its load outcome. Replaying provenance into the evidence
/// document keeps the record self-contained — a consumer never has to
/// chase the app-bundle manifest to interpret a match.
public struct ReferenceObjectConfiguredAsset: Codable, Sendable,
    Equatable
{
    public let asset: ReferenceObjectAsset
    public let role: ReferenceObjectAssetRole
    public let loadOutcome: ReferenceObjectLoadOutcome
    /// Human-readable failure detail for `unavailable`/`rejected`.
    public let loadDetail: String?

    public init(
        asset: ReferenceObjectAsset,
        role: ReferenceObjectAssetRole,
        loadOutcome: ReferenceObjectLoadOutcome,
        loadDetail: String? = nil
    ) {
        self.asset = asset
        self.role = role
        self.loadOutcome = loadOutcome
        self.loadDetail = loadDetail.map { SchemaOwnedText.nfc($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case asset
        case role
        case loadOutcome = "load_outcome"
        case loadDetail = "load_detail"
    }
}

/// The selection echo persisted beside the configured assets: exactly
/// what the operator asked for, what the policy dropped and why.
public struct ReferenceObjectSelectionEcho: Codable, Sendable,
    Equatable
{
    public let requested: [ReferenceObjectSelectionRequest]
    public let dropped: [ReferenceObjectRejectedSelection]
    public let cap: Int

    public init(
        requested: [ReferenceObjectSelectionRequest],
        dropped: [ReferenceObjectRejectedSelection],
        cap: Int =
            ReferenceObjectSelectionPolicy.maxConfiguredObjects
    ) {
        self.requested = requested
        self.dropped = dropped
        self.cap = cap
    }
}

/// The persisted observation document (#268). Written incrementally
/// during scanning by `CaptureWorkingSetStore` under the same
/// canonical/`.captureAppDerived` reserved-path convention as
/// `evidence/reference-targets.json`, then restored verbatim for
/// draft recovery.
public struct ReferenceObjectObservationDocument: Codable, Sendable,
    Equatable
{
    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    /// The revision's bound coordinate space at commit time. Every
    /// observation still carries its own `coordinate_space_id`; under
    /// the single-space policy they must equal this value.
    public let coordinateSpaceID: CoordinateSpaceID
    /// `true` when the session reconfiguration was applied before the
    /// working set bound its coordinate space — the honest record
    /// that any world-origin reset ARKit performed is absorbed into
    /// the bound space, not silently preserved under a stale one.
    public let appliedBeforeCoordinateBinding: Bool
    public let selection: ReferenceObjectSelectionEcho
    public let configuredAssets: [ReferenceObjectConfiguredAsset]
    public let observations: [ReferenceObjectPoseObservation]
    /// Records dropped because the bounded buffer hit its cap —
    /// `observations.count + truncatedObservationCount` is the true
    /// event count.
    public let truncatedObservationCount: Int

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        appliedBeforeCoordinateBinding: Bool,
        selection: ReferenceObjectSelectionEcho,
        configuredAssets: [ReferenceObjectConfiguredAsset],
        observations: [ReferenceObjectPoseObservation],
        truncatedObservationCount: Int
    ) throws {
        guard Set(observations.map(\.observationID)).count
                == observations.count
        else {
            throw ReferenceObjectError.duplicateObservationID
        }
        guard truncatedObservationCount >= 0 else {
            throw ReferenceObjectError.invalidObservationIndex
        }
        self.schema = ReferenceObjectObservationPackage.schema
        self.schemaVersion =
            ReferenceObjectObservationPackage.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.appliedBeforeCoordinateBinding =
            appliedBeforeCoordinateBinding
        self.selection = selection
        self.configuredAssets = configuredAssets
        self.observations = observations
        self.truncatedObservationCount = truncatedObservationCount
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case appliedBeforeCoordinateBinding =
            "applied_before_coordinate_binding"
        case selection
        case configuredAssets = "configured_assets"
        case observations
        case truncatedObservationCount =
            "truncated_observation_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == ReferenceObjectObservationPackage.schema,
              schemaVersion
                == ReferenceObjectObservationPackage.schemaVersion
        else {
            throw ReferenceObjectError.unsupportedSchema
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
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            appliedBeforeCoordinateBinding: container.decode(
                Bool.self,
                forKey: .appliedBeforeCoordinateBinding
            ),
            selection: container.decode(
                ReferenceObjectSelectionEcho.self,
                forKey: .selection
            ),
            configuredAssets: container.decode(
                [ReferenceObjectConfiguredAsset].self,
                forKey: .configuredAssets
            ),
            observations: container.decode(
                [ReferenceObjectPoseObservation].self,
                forKey: .observations
            ),
            truncatedObservationCount: container.decode(
                Int.self,
                forKey: .truncatedObservationCount
            )
        )
    }
}

public struct ReferenceObjectObservationPackage: Sendable, Equatable {
    public static let schema =
        "htdt.capture.reference-object-observations"
    public static let schemaVersion = "1.0.0"
    public static let path =
        "evidence/reference-object-observations.json"

    public let document: ReferenceObjectObservationDocument
    public let data: Data

    public init(
        document: ReferenceObjectObservationDocument,
        data: Data
    ) {
        self.document = document
        self.data = data
    }

    /// Lineage refs for the store's declaration — the bound capture
    /// session, mirroring the reference-targets convention.
    public var sourceRefs: [String] {
        ["capture_session:" + document.captureSessionID.description]
    }
}

/// Bounded in-memory accumulator behind the store's incremental doc
/// writes (#268). ARKit fires `updated` per frame in tracking mode —
/// the buffer therefore coalesces: per anchor it keeps one mutable
/// `updated` record carrying the latest pose, plus appended records
/// only for genuine lifecycle transitions (`added`,
/// `trackingLost`/`trackingResumed` flips, `removed`). The persisted
/// document states the true event count via
/// `truncatedObservationCount` once the cap is hit.
public struct ReferenceObjectObservationBuffer: Sendable, Equatable {
    /// Hard cap on retained observation records.
    public static let recordLimit = 4096

    public private(set) var selection: ReferenceObjectSelectionEcho?
    public private(set) var configuredAssets:
        [ReferenceObjectConfiguredAsset] = []
    public private(set) var records: [ReferenceObjectPoseObservation]
        = []
    public private(set) var truncatedRecordCount = 0
    /// Index into `records` of each anchor's coalesced `updated`
    /// record, so per-frame updates rewrite in place.
    private var latestUpdateIndexByAnchor: [UUID: Int] = [:]
    /// Last reported tracked state per anchor — flips append a
    /// lifecycle record; steady-state updates coalesce.
    private var lastTrackedByAnchor: [UUID: Bool] = [:]

    public init() {}

    /// Installs the selection/configured-asset echo. Called once per
    /// revision when the session reconfiguration is applied; a second
    /// call replaces the configuration section (e.g. retry with a
    /// corrected pick) without touching recorded observations.
    public mutating func setConfiguration(
        selection: ReferenceObjectSelectionEcho,
        configuredAssets: [ReferenceObjectConfiguredAsset]
    ) {
        self.selection = selection
        self.configuredAssets = configuredAssets
    }

    /// Whether an observation exists for `anchorID`.
    public func hasObservation(for anchorID: UUID) -> Bool {
        lastTrackedByAnchor[anchorID] != nil
            || latestUpdateIndexByAnchor[anchorID] != nil
    }

    /// Latest pose record for an anchor (its `updated` record), if any.
    public func latestObservation(for anchorID: UUID)
        -> ReferenceObjectPoseObservation?
    {
        latestUpdateIndexByAnchor[anchorID].map { records[$0] }
    }

    /// All records the document should carry, ordered deterministically
    /// by session timestamp then observation id.
    public func documentObservations()
        -> [ReferenceObjectPoseObservation]
    {
        records.sorted {
            if $0.sessionTimestampSeconds
                != $1.sessionTimestampSeconds
            {
                return $0.sessionTimestampSeconds
                    < $1.sessionTimestampSeconds
            }
            return $0.observationID.description
                < $1.observationID.description
        }
    }

    /// Records one observation. `kind` is the ARKit delegate event that
    /// produced it; the buffer maps `didUpdate` onto `updated` or a
    /// tracked-flip record. Returns the record that landed in the
    /// buffer, or nil when the event coalesced/dropped.
    @discardableResult
    public mutating func record(
        _ observation: ReferenceObjectPoseObservation,
        kind: MeshAnchorLifecycleKind
    ) -> ReferenceObjectPoseObservation? {
        switch kind {
        case .added:
            guard appendIfRoom(observation) else { return nil }
            lastTrackedByAnchor[observation.arAnchorID] =
                observation.isCurrentlyTracked
            return observation
        case .updated:
            let previousTracked =
                lastTrackedByAnchor[observation.arAnchorID]
            let newTracked = observation.isCurrentlyTracked
            lastTrackedByAnchor[observation.arAnchorID] = newTracked
            // Tracked-state flip: append an explicit lifecycle record —
            // isTracked loss is evidence, not noise.
            if previousTracked != nil,
               newTracked != nil,
               previousTracked != newTracked
            {
                let flipEvent: ReferenceObjectLifecycleEvent =
                    newTracked == true
                    ? .trackingResumed : .trackingLost
                guard let flipped = try? ReferenceObjectPoseObservation(
                    observationID: observation.observationID,
                    captureSessionID: observation.captureSessionID,
                    coordinateSpaceID: observation.coordinateSpaceID,
                    sessionTimestampSeconds:
                        observation.sessionTimestampSeconds,
                    arAnchorID: observation.arAnchorID,
                    referenceObjectID: observation.referenceObjectID,
                    referenceObjectRevision:
                        observation.referenceObjectRevision,
                    referenceObjectDigestSHA256:
                        observation.referenceObjectDigestSHA256,
                    tWorldFromReferenceObject:
                        observation.tWorldFromReferenceObject,
                    observationMode: observation.observationMode,
                    lifecycleEvent: flipEvent,
                    isCurrentlyTracked: newTracked,
                    sourceFrameRef: observation.sourceFrameRef,
                    markerToEquipmentTransformID:
                        observation.markerToEquipmentTransformID
                ) else {
                    return nil
                }
                guard appendIfRoom(flipped) else { return nil }
                return flipped
            }
            // First sighting without a prior `added` callback: record
            // it as an add — the update still represents first contact.
            if latestUpdateIndexByAnchor[observation.arAnchorID] == nil,
               previousTracked == nil
            {
                guard appendIfRoom(observation) else { return nil }
                return observation
            }
            // Steady-state update: rewrite the anchor's coalesced
            // `updated` record in place.
            if let index =
                latestUpdateIndexByAnchor[observation.arAnchorID]
            {
                records[index] = observation
                return observation
            }
            guard appendIfRoom(observation) else { return nil }
            return observation
        case .removed:
            latestUpdateIndexByAnchor.removeValue(
                forKey: observation.arAnchorID
            )
            lastTrackedByAnchor.removeValue(
                forKey: observation.arAnchorID
            )
            guard appendIfRoom(observation) else { return nil }
            return observation
        }
    }

    private mutating func appendIfRoom(
        _ observation: ReferenceObjectPoseObservation
    ) -> Bool {
        guard records.count < Self.recordLimit else {
            truncatedRecordCount += 1
            return false
        }
        records.append(observation)
        if observation.lifecycleEvent == .updated {
            latestUpdateIndexByAnchor[observation.arAnchorID] =
                records.count - 1
        }
        return true
    }

    /// Rebuilds the buffer from a restored document so a reopened
    /// draft keeps appending consistently.
    public init(restoring document: ReferenceObjectObservationDocument)
    {
        self.init()
        selection = document.selection
        configuredAssets = document.configuredAssets
        truncatedRecordCount = document.truncatedObservationCount
        for record in document.observations {
            records.append(record)
            switch record.lifecycleEvent {
            case .updated:
                latestUpdateIndexByAnchor[record.arAnchorID] =
                    records.count - 1
                lastTrackedByAnchor[record.arAnchorID] =
                    record.isCurrentlyTracked
            case .added, .trackingLost, .trackingResumed:
                lastTrackedByAnchor[record.arAnchorID] =
                    record.isCurrentlyTracked
            case .removed:
                lastTrackedByAnchor.removeValue(
                    forKey: record.arAnchorID
                )
                latestUpdateIndexByAnchor.removeValue(
                    forKey: record.arAnchorID
                )
            }
        }
    }
}

public enum ReferenceObjectObservationBuilder {
    /// Canonical-encodes the document the store persists at
    /// `evidence/reference-object-observations.json`.
    public static func build(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        appliedBeforeCoordinateBinding: Bool,
        selection: ReferenceObjectSelectionEcho,
        configuredAssets: [ReferenceObjectConfiguredAsset],
        observations: [ReferenceObjectPoseObservation],
        truncatedObservationCount: Int
    ) throws -> ReferenceObjectObservationPackage {
        let document = try ReferenceObjectObservationDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            appliedBeforeCoordinateBinding:
                appliedBeforeCoordinateBinding,
            selection: selection,
            configuredAssets: configuredAssets,
            observations: observations,
            truncatedObservationCount: truncatedObservationCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard
            let decoded = try? JSONDecoder().decode(
                ReferenceObjectObservationDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw ReferenceObjectError.encodedDocumentMismatch
        }
        return ReferenceObjectObservationPackage(
            document: document,
            data: data
        )
    }

    /// Review-surface diagnostics from the committed document —
    /// advisory only, never a quality gate: failed artifact loads,
    /// dropped selection requests, truncation, and tracked-state loss
    /// counts are all observable facts a reviewer should see.
    public static func reviewDiagnostics(
        for document: ReferenceObjectObservationDocument
    ) -> [QualityDiagnostic] {
        var diagnostics: [QualityDiagnostic] = []

        for configured in document.configuredAssets
        where configured.loadOutcome != .loaded {
            diagnostics.append(
                QualityDiagnostic(
                    code: "reference_object_load_outcome",
                    severity: .warning,
                    message:
                        "Reference object \(configured.asset.assetID.rawValue) load outcome: \(configured.loadOutcome.rawValue)"
                        + (configured.loadDetail.map { " — \($0)" }
                            ?? ""),
                    evidenceRefs: [
                        "reference_object:"
                            + configured.asset.assetID.rawValue
                    ]
                )
            )
        }
        for dropped in document.selection.dropped {
            diagnostics.append(
                QualityDiagnostic(
                    code: "reference_object_selection_dropped",
                    severity: .info,
                    message:
                        "Reference object \(dropped.assetID.rawValue) selection dropped: \(dropped.reason.rawValue)",
                    evidenceRefs: [
                        "reference_object:"
                            + dropped.assetID.rawValue
                    ]
                )
            )
        }
        if document.truncatedObservationCount > 0 {
            diagnostics.append(
                QualityDiagnostic(
                    code: "reference_object_observations_truncated",
                    severity: .warning,
                    message:
                        "Reference object observations truncated: \(document.truncatedObservationCount) records beyond the bounded buffer were not persisted",
                    evidenceRefs: [
                        "path:"
                            + ReferenceObjectObservationPackage.path
                    ]
                )
            )
        }
        let lostCount = document.observations.filter {
            $0.lifecycleEvent == .trackingLost
        }.count
        if lostCount > 0 {
            diagnostics.append(
                QualityDiagnostic(
                    code: "reference_object_tracking_loss",
                    severity: .info,
                    message:
                        "Reference object tracking was lost \(lostCount) time(s) during capture; anchors were retained per ARKit policy",
                    evidenceRefs: [
                        "path:"
                            + ReferenceObjectObservationPackage.path
                    ]
                )
            )
        }
        return diagnostics
    }
}
