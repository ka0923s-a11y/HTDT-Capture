import Foundation

/// The field-authority commit surface (issues #300/#301/#310/#314/
/// #324/#331): the five derived documents this family introduces, plus
/// the binary asset payloads field-evidence records own, staged for a
/// single atomic `CaptureWorkingSetStore` commit. Every member is
/// optional — a commit only replaces the documents it carries, so
/// earlier committed documents the caller did not touch stay byte-for
/// -byte identical.
public struct FieldAuthorityBundle: Sendable, Equatable {
    public let operators: OperatorProfilePackage?
    public let fieldEvidence: FieldEvidencePackage?
    public let instruments: InstrumentProfilePackage?
    public let settings: InstalledSettingsPackage?
    public let wiring: AsBuiltWiringPackage?
    /// #227: fiducial/reference-target capture document — declared
    /// targets plus their evidence-linked observations.
    public let referenceTargets: ReferenceTargetCapturePackage?
    /// Binary assets (captured close-ups / imported files) to write —
    /// write-once; an already-declared identical path is a no-op.
    public let assetWrites: [FieldEvidenceAssetPayload]
    /// Binary assets to remove — identity-checked: removal happens
    /// only when the file on disk still matches `data` byte-for-byte.
    public let assetRemovals: [FieldEvidenceAssetPayload]

    public init(
        operators: OperatorProfilePackage? = nil,
        fieldEvidence: FieldEvidencePackage? = nil,
        instruments: InstrumentProfilePackage? = nil,
        settings: InstalledSettingsPackage? = nil,
        wiring: AsBuiltWiringPackage? = nil,
        referenceTargets: ReferenceTargetCapturePackage? = nil,
        assetWrites: [FieldEvidenceAssetPayload] = [],
        assetRemovals: [FieldEvidenceAssetPayload] = []
    ) {
        self.operators = operators
        self.fieldEvidence = fieldEvidence
        self.instruments = instruments
        self.settings = settings
        self.wiring = wiring
        self.referenceTargets = referenceTargets
        self.assetWrites = assetWrites
        self.assetRemovals = assetRemovals
    }

    public var isEmpty: Bool {
        operators == nil && fieldEvidence == nil && instruments == nil
            && settings == nil && wiring == nil
            && referenceTargets == nil && assetWrites.isEmpty
            && assetRemovals.isEmpty
    }
}

/// Effective field-authority documents for cross-validation — each the
/// staged package's document, or the previously committed document
/// when the commit does not carry it.
struct EffectiveFieldAuthorityDocuments {
    var operators: OperatorProfileDocument?
    var fieldEvidence: FieldEvidenceDocument?
    var instruments: InstrumentProfileDocument?
    var settings: InstalledSettingsDocument?
    var wiring: AsBuiltWiringDocument?
}

/// Cross-document binding validation for the field-authority family.
/// Every binding ref on a committed document resolves against the
/// *effective* committed state (staged doc else previously persisted),
/// so a commit cannot reference a record that only exists in its own
/// unstaged preview and cannot break references the unchanged docs
/// still rely on.
enum FieldAuthorityBindingValidator {

    static func validate(
        bundle: FieldAuthorityBundle,
        effective: EffectiveFieldAuthorityDocuments,
        entityIDs: Set<AnnotationEntityID>,
        measurementIDs: Set<MeasurementID>,
        inventoryItemIDs: Set<AuthorityRecordID>,
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        declaredPaths: Set<String>,
        coordinateSpaceIDs: Set<CoordinateSpaceID>
    ) throws {
        // Digests are recomputed at document init; re-verifying here
        // makes the store the second line of defence for any decoder
        // path that bypassed document construction.
        if let instruments = effective.instruments {
            for instrument in instruments.instruments {
                guard instrument.verifyDigest() else {
                    throw FieldAuthorityModelError.unboundReference(
                        "profile_sha256"
                    )
                }
            }
        }

        let operatorIDs = Set(
            effective.operators?.operators.map(\.operatorID) ?? []
        )
        let instrumentIDs = Set(
            effective.instruments?.instruments.map(\.instrumentID)
                ?? []
        )
        let wiringRouteIDs = Set(
            effective.wiring?.routes.map(\.routeID) ?? []
        )
        let observationIDs = Set(
            effective.settings?.observations.map(\.observationID) ?? []
        )
        let evidenceIDs = Set(
            effective.fieldEvidence?.records.map(\.evidenceID) ?? []
        )
        let assetPaths = declaredPaths.union(
            bundle.assetWrites.map(\.path)
        ).subtracting(bundle.assetRemovals.map(\.path))

        func requireOperator(_ id: OperatorProfileID?) throws {
            guard let id else { return }
            guard operatorIDs.contains(id) else {
                throw FieldAuthorityModelError
                    .unboundReference(id.description)
            }
        }

        func resolveTargetRef(_ ref: String) throws {
            if let id = parseID(ref, "entity:") {
                guard entityIDs.contains(
                    AnnotationEntityID(rawValue: id)
                ) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "measurement:") {
                guard measurementIDs.contains(
                    MeasurementID(rawValue: id)
                ) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "inventory_item:") {
                guard inventoryItemIDs.contains(
                    AuthorityRecordID(rawValue: id)
                ) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "capture_revision:") {
                guard id == captureRevisionID.rawValue else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "capture_session:") {
                guard id == captureSessionID.rawValue else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "wiring_route:") {
                guard wiringRouteIDs.contains(
                    WiringRouteID(rawValue: id)
                ) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "settings_observation:") {
                guard observationIDs.contains(
                    SettingsObservationID(rawValue: id)
                ) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "instrument:") {
                guard instrumentIDs.contains(
                    InstrumentProfileID(rawValue: id)
                ) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "operator:") {
                guard operatorIDs.contains(
                    OperatorProfileID(rawValue: id)
                ) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "field_evidence:") {
                guard evidenceIDs.contains(
                    FieldEvidenceID(rawValue: id)
                ) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            // task_item:/commissioning_check:/equipment:/surface:/
            // mesh_anchor:/path: tokens bind external authorities the
            // working set cannot resolve — grammatically valid refs
            // pass through untouched.
        }

        func resolveEvidenceRef(_ ref: String) throws {
            if let path = ref.stripFieldAuthorityPathPrefix() {
                guard assetPaths.contains(path) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            if let id = parseID(ref, "field_evidence:") {
                guard evidenceIDs.contains(
                    FieldEvidenceID(rawValue: id)
                ) else {
                    throw FieldAuthorityModelError
                        .unboundReference(ref)
                }
                return
            }
            // `frame:`, `sha256:` and other external namespaces are
            // resolved at finalize/manifest time, not here.
        }

        if let operators = effective.operators {
            guard operators.captureRevisionID == captureRevisionID
            else {
                throw FieldAuthorityModelError.unboundReference(
                    "capture_revision_id"
                )
            }
        }

        if let fieldEvidence = effective.fieldEvidence {
            for record in fieldEvidence.records {
                for target in record.targetRefs {
                    try resolveTargetRef(target)
                }
                try requireOperator(record.operatorID)
                if let asset = record.asset {
                    switch asset.kind {
                    case .canonicalFrame:
                        guard let framePath = asset
                            .canonicalFramePathRef?
                            .stripFieldAuthorityPathPrefix(),
                            assetPaths.contains(framePath)
                        else {
                            throw FieldAuthorityModelError
                                .unboundReference(
                                    record.asset?.frameRef ?? ""
                                )
                        }
                    case .capturedPhoto, .importedFile:
                        guard let path = asset.assetPath,
                              assetPaths.contains(path)
                        else {
                            throw FieldAuthorityModelError
                                .missingAssetAuthority
                        }
                        // The recorded hash must match the bytes this
                        // commit (or an earlier one) wrote.
                        if let payload = bundle.assetWrites
                            .first(where: { $0.path == path })
                        {
                            guard EvidenceIntegrity.sha256(
                                of: payload.data
                            ) == asset.sha256
                            else {
                                throw FieldAuthorityModelError
                                    .missingAssetAuthority
                            }
                        }
                    }
                }
            }
        }

        if let settings = effective.settings {
            for observation in settings.observations {
                try resolveTargetRef(observation.targetRef)
                try requireOperator(observation.operatorID)
                for ref in observation.evidenceRefs {
                    try resolveEvidenceRef(ref)
                }
                for setting in observation.settings {
                    for ref in setting.evidenceRefs {
                        try resolveEvidenceRef(ref)
                    }
                }
            }
        }

        if let wiring = effective.wiring {
            for route in wiring.routes {
                for endpoint in [route.endpointA, route.endpointB] {
                    if let binding = endpoint.bindingRef {
                        try resolveTargetRef(binding)
                    }
                    if let space = endpoint.coordinateSpaceID {
                        guard coordinateSpaceIDs.contains(space)
                        else {
                            throw FieldAuthorityModelError
                                .unboundReference(
                                    space.description
                                )
                        }
                    }
                }
                try requireOperator(route.operatorID)
                for ref in route.evidenceRefs {
                    try resolveEvidenceRef(ref)
                }
                for segment in route.segments {
                    if let surface = segment.surfaceRef {
                        try resolveTargetRef(surface)
                    }
                    for ref in segment.evidenceRefs {
                        try resolveEvidenceRef(ref)
                    }
                }
            }
        }

        // Staged asset writes must be owned by the effective document —
        // a payload with no record is an orphan the manifest would pin
        // forever for no reason.
        if let fieldEvidence = effective.fieldEvidence {
            let ownedPaths = Set(
                fieldEvidence.records.compactMap(\.asset?.assetPath)
            )
            for payload in bundle.assetWrites {
                guard ownedPaths.contains(payload.path) else {
                    throw FieldAuthorityModelError
                        .unboundReference(payload.path)
                }
            }
            for payload in bundle.assetRemovals {
                guard !ownedPaths.contains(payload.path) else {
                    // Never remove bytes a committed record still binds.
                    throw FieldAuthorityModelError
                        .unboundReference(payload.path)
                }
            }
        }
    }

    private static func parseID(
        _ ref: String,
        _ prefix: String
    ) -> UUID? {
        guard ref.hasPrefix(prefix) else { return nil }
        return UUID(
            canonicalUUIDv4Text: String(ref.dropFirst(prefix.count))
        )
    }
}

private extension String {
    /// `path:x` → `x`; anything else → nil.
    func stripFieldAuthorityPathPrefix() -> String? {
        hasPrefix("path:") ? String(dropFirst(5)) : nil
    }
}

/// Bytes of a close-up photo captured for a field-evidence record
/// (issue #314). The photo is image evidence only — it carries no
/// frame descriptor, coordinate space, or pose, so it can never be
/// confused with a spatial AR frame.
public struct CapturedFieldPhoto: Sendable, Equatable {
    public let data: Data
    public let mediaType: FieldEvidenceMediaType
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(
        data: Data,
        mediaType: FieldEvidenceMediaType,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.data = data
        self.mediaType = mediaType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Draft-safe staging for a field-evidence binary asset: the path +
/// bytes. The manifest declaration is rebuilt deterministically from
/// the path at commit, so it is not persisted in the app-private
/// draft.
public struct StagedFieldAsset: Codable, Sendable, Equatable {
    public var path: String
    public var data: Data
    /// True when this asset is staged for removal instead of write —
    /// the byte identity check at commit protects against deleting a
    /// different payload.
    public var removal: Bool

    public init(path: String, data: Data, removal: Bool = false) {
        self.path = path
        self.data = data
        self.removal = removal
    }
}

/// The workspace's staged field-authority state (issues #300/#301/
/// #310/#314/#324/#331): everything the operator authored in the
/// annotation workspace beyond the canonical entity/measurement/
/// authority collections. Persisted in the app-private autosave draft
/// and committed to derived documents on Save.
public struct FieldAuthorityWorkspace: Codable, Sendable, Equatable {
    public var operatorProfiles: [OperatorProfile]
    /// The operator identity stamped onto newly authored records
    /// (issue #310); nil means anonymous — never fabricated.
    public var selectedOperatorID: OperatorProfileID?
    public var fieldEvidence: [FieldEvidenceRecord]
    public var fieldEvidenceAssets: [StagedFieldAsset]
    public var instruments: [MeasurementInstrumentProfile]
    public var settingsObservations: [InstalledSettingsObservation]
    public var wiringRoutes: [AsBuiltWiringRoute]
    /// #227: declared fiducial/reference targets and their
    /// observations — staged with the rest of the field bag so a
    /// draft round-trips them. Optional so drafts authored before
    /// targets existed still decode.
    public var referenceTargets: [ReferenceTargetDeclaration]?
    public var referenceTargetObservations:
        [ReferenceTargetObservation]?

    public init(
        operatorProfiles: [OperatorProfile] = [],
        selectedOperatorID: OperatorProfileID? = nil,
        fieldEvidence: [FieldEvidenceRecord] = [],
        fieldEvidenceAssets: [StagedFieldAsset] = [],
        instruments: [MeasurementInstrumentProfile] = [],
        settingsObservations: [InstalledSettingsObservation] = [],
        wiringRoutes: [AsBuiltWiringRoute] = [],
        referenceTargets: [ReferenceTargetDeclaration]? = nil,
        referenceTargetObservations:
            [ReferenceTargetObservation]? = nil
    ) {
        self.operatorProfiles = operatorProfiles
        self.selectedOperatorID = selectedOperatorID
        self.fieldEvidence = fieldEvidence
        self.fieldEvidenceAssets = fieldEvidenceAssets
        self.instruments = instruments
        self.settingsObservations = settingsObservations
        self.wiringRoutes = wiringRoutes
        self.referenceTargets = referenceTargets
        self.referenceTargetObservations =
            referenceTargetObservations
    }

    /// Any staged field-authority content worth committing.
    public var hasContent: Bool {
        !operatorProfiles.isEmpty || !fieldEvidence.isEmpty
            || !fieldEvidenceAssets.isEmpty || !instruments.isEmpty
            || !settingsObservations.isEmpty || !wiringRoutes.isEmpty
            || !(referenceTargets?.isEmpty ?? true)
            || !(referenceTargetObservations?.isEmpty ?? true)
    }
}

