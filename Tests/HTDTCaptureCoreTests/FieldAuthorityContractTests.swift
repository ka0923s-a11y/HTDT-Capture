import Foundation
import Testing
@testable import HTDTCaptureCore

/// Contract coverage for the field-authority family (#300/#301/#310/
/// #314/#324/#331): schema registry mapping, compiled-schema
/// validation of canonical encodings, model invariants, and the
/// measurement authority extension.
private let fieldAuthorityPaths: [(String, String)] = [
    ("derived/operator-profiles.json", "operator-profiles"),
    ("derived/field-evidence.json", "field-evidence"),
    ("derived/instrument-profiles.json", "instrument-profiles"),
    ("derived/settings-observations.json",
     "settings-observations"),
    ("derived/wiring-routes.json", "wiring-routes"),
]

private let testRevisionID = CaptureRevisionID()
private let testSpaceID = CoordinateSpaceID()

private func compiledSchema(
    _ name: String
) throws -> CompiledJSONSchema {
    try CaptureBundleSchemaRegistry.compiledSchema(named: name)
}

private func validateEncoded(
    _ value: Encodable,
    schema name: String,
    fileID: String = #fileID
) throws -> JSONSchemaViolation? {
    let data = try FieldAuthorityCoding.encoder().encode(value)
    let parsed = try StrictJSON.parse(data)
    return JSONSchemaValidator.validate(
        parsed,
        schema: try compiledSchema(name)
    )
}

@Test
func fieldAuthorityRegistryMapping() throws {
    for (path, name) in fieldAuthorityPaths {
        #expect(
            CaptureBundleSchemaRegistry
                .schemaName(forPath: path) == name
        )
        _ = try compiledSchema(name)
    }
}

@Test
func operatorProfileDocumentSchemaRoundTrip() throws {
    let profile = try OperatorProfile(
        displayName: "Field Tech",
        organization: "Installers Inc",
        role: "installer"
    )
    let document = try OperatorProfileDocument(
        captureRevisionID: testRevisionID,
        operators: [profile]
    )
    #expect(
        try validateEncoded(
            document,
            schema: "operator-profiles"
        ) == nil
    )
    let data = try FieldAuthorityCoding.encoder().encode(document)
    let decoded = try JSONDecoder().decode(
        OperatorProfileDocument.self,
        from: data
    )
    #expect(decoded == document)
}

@Test
func operatorProfilePackageEmitsGrammarLegalSourceRef() throws {
    let profile = try OperatorProfile(
        displayName: "Field Tech",
        organization: "Installers Inc",
        role: "installer"
    )
    let package = try OperatorProfilePackage(
        document: OperatorProfileDocument(
            captureRevisionID: testRevisionID,
            operators: [profile]
        )
    )
    // The manifest source_refs grammar accepts only `path:` /
    // `sha256:` / `capture_session:` forms — a bare bundle path
    // trips malformedSourceRef at finalization.
    #expect(package.sourceRefs == ["path:annotations/entities.json"])
}

@Test
func fieldEvidenceDocumentSchemaValidation() throws {
    let entityID = AnnotationEntityID()
    let assetPath = "evidence/field/captured/"
        + FieldEvidenceID().description + ".heic"
    // The canonical stem must be the record's own UUIDv4.
    let evidenceID = FieldEvidenceID()
    let ownPath = FieldEvidenceAssetPaths.captured(
        evidenceID: evidenceID,
        mediaType: .heic
    )
    let asset = try FieldEvidenceAsset.capturedPhoto(
        assetPath: ownPath,
        sha256: EvidenceIntegrity.sha256(of: Data([1, 2, 3])),
        mediaType: .heic,
        pixelWidth: 1920,
        pixelHeight: 1440
    )
    let record = try FieldEvidenceRecord(
        evidenceID: evidenceID,
        kind: .installationPhoto,
        title: "In-wall run",
        note: nil,
        targetRefs: ["entity:" + entityID.description],
        asset: asset,
        captureRevisionID: testRevisionID
    )
    let document = try FieldEvidenceDocument(
        captureRevisionID: testRevisionID,
        records: [record]
    )
    #expect(
        try validateEncoded(
            document,
            schema: "field-evidence"
        ) == nil
    )
    // A close-up asset carries no spatial authority; only a linked
    // canonical frame does.
    #expect(asset.carriesSpatialAuthority == false)
    #expect(assetPath != ownPath)
}

@Test
func fieldEvidenceDocumentRejectsForeignRevision() throws {
    // Every record must be bound to the document's revision.
    let record = try FieldEvidenceRecord(
        kind: .generalNote,
        title: "note",
        targetRefs: [
            "capture_revision:" + testRevisionID.description
        ],
        asset: nil,
        captureRevisionID: testRevisionID
    )
    #expect(throws: (any Error).self) {
        _ = try FieldEvidenceDocument(
            captureRevisionID: CaptureRevisionID(),
            records: [record]
        )
    }
    // And a payload failing the schema's required/`const` checks must
    // be rejected before it ever reaches the store.
    let bad = try StrictJSON.parse(
        Data(#"{"schema":"wrong","records":[]}"#.utf8)
    )
    #expect(
        JSONSchemaValidator.validate(
            bad,
            schema: try compiledSchema("field-evidence")
        ) != nil
    )
}

@Test
func instrumentProfileDigestAndReference() throws {
    let calibration = EvidenceIntegrity.sha256(
        of: Data("certificate".utf8)
    )
    let profile = try MeasurementInstrumentProfile(
        instrumentID: InstrumentProfileID(),
        profileVersion: 1,
        instrumentClass: .measurementMicrophone,
        manufacturer: "miniDSP",
        model: "UMIK-1",
        serialOrAssetID: "SN-7",
        calibrationState: .calibrated,
        calibrationDate: "2026-09-01",
        calibrationValidUntil: nil,
        calibrationEvidenceKind: .calibrationCertificate,
        calibrationEvidenceRefs: [
            "sha256:" + calibration.description
        ],
        statedAccuracy: "±0.5 dB",
        operatorLabel: "mic A"
    )
    #expect(profile.verifyDigest())
    let reference = profile.reference
    #expect(reference.instrumentID == profile.instrumentID)
    #expect(reference.profileVersion == 1)
    #expect(
        reference.profileSHA256 == profile.profileSHA256
    )
    // A field change must mint a new version: digest shifts.
    let v2 = try MeasurementInstrumentProfile(
        instrumentID: profile.instrumentID,
        profileVersion: 2,
        instrumentClass: profile.instrumentClass,
        manufacturer: profile.manufacturer,
        model: profile.model,
        serialOrAssetID: profile.serialOrAssetID,
        calibrationState: .calibrated,
        calibrationDate: "2026-09-20",
        calibrationValidUntil: "2027-09-20",
        calibrationEvidenceKind: .calibrationCertificate,
        calibrationEvidenceRefs: [
            "sha256:" + calibration.description
        ],
        statedAccuracy: profile.statedAccuracy,
        operatorLabel: profile.operatorLabel
    )
    #expect(v2.profileSHA256 != profile.profileSHA256)

    let document = try InstrumentProfileDocument(
        captureRevisionID: testRevisionID,
        instruments: [profile, v2]
    )
    #expect(
        try validateEncoded(
            document,
            schema: "instrument-profiles"
        ) == nil
    )
    #expect(
        document.latestVersion(of: profile.instrumentID)
            == v2.profileVersion
    )
}

@Test
func measurementInstrumentAuthorityEncoding() throws {
    let instrumentProfile = try MeasurementInstrumentProfile(
        instrumentID: InstrumentProfileID(),
        profileVersion: 1,
        instrumentClass: .laserDistanceMeter,
        manufacturer: "Bosch",
        model: "GLM 50",
        serialOrAssetID: nil,
        calibrationState: .notApplicable,
        calibrationDate: nil,
        calibrationValidUntil: nil,
        calibrationEvidenceKind: nil,
        calibrationEvidenceRefs: [],
        statedAccuracy: nil,
        operatorLabel: nil
    )
    let measurement =
        try ManualAuthorityBuilder.scalarMeasurement(
            quantityType: "room_width",
            value: 4.2,
            unit: .meter,
            acquisitionMethod: .laserDistanceMeter
        )
    let stamped = try measurement
        .withInstrumentAuthority(instrumentProfile.reference)
        .withAuthorOperator(try OperatorProfile(
            displayName: "Tech"
        ).operatorID)
    let collection = try CaptureMeasurementCollection(
        measurements: [stamped]
    )
    #expect(
        try validateEncoded(
            collection,
            schema: "measurements-1.1.0"
        ) == nil
    )
    let data = try FieldAuthorityCoding.encoder().encode(collection)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"instrument_authority\""))
    #expect(text.contains("\"author_operator_id\""))
}

@Test
func entityAuthorOperatorSchema() throws {
    let operatorID = OperatorProfileID()
    let entity = try ManualAuthorityBuilder.annotation(
        type: .display,
        label: "Screen",
        xMeters: 1,
        yMeters: 1,
        zMeters: 0,
        coordinateSpaceID: testSpaceID
    ).withAuthorOperator(operatorID)
    let collection = try CaptureAnnotationCollection(
        entities: [entity]
    )
    #expect(
        try validateEncoded(
            collection,
            schema: "entities-1.3.0"
        ) == nil
    )
}

@Test
func installedSettingsObservationSchema() throws {
    let gain = try ObservedSetting(
        parameter: .channelGain,
        customParameter: nil,
        scope: "channel:sub1",
        state: .observed,
        valueNumber: -2.5,
        valueText: nil,
        unitText: "dB",
        expectedNumber: 0,
        expectedText: nil,
        expectedUnitText: "dB",
        expectedSourceRef: nil,
        deviatesFromExpected: true,
        deviationReason: "installer offset",
        evidenceRefs: []
    )
    let unknown = try ObservedSetting(
        parameter: .dspMode,
        customParameter: nil,
        scope: nil,
        state: .unknown
    )
    let observation = try InstalledSettingsObservation(
        captureRevisionID: testRevisionID,
        targetRef: "equipment:avr_denon_x3800",
        settings: [gain, unknown]
    )
    let document = try InstalledSettingsDocument(
        captureRevisionID: testRevisionID,
        observations: [observation]
    )
    #expect(
        try validateEncoded(
            document,
            schema: "settings-observations"
        ) == nil
    )
    // A deviation without reason/evidence must fail validation.
    #expect(throws: (any Error).self) {
        _ = try ObservedSetting(
            parameter: .channelDelay,
            state: .observed,
            valueNumber: 4.0,
            deviatesFromExpected: true
        )
    }
}

@Test
func wiringRouteSchemaAndHiddenPathRules() throws {
    let endpointA = try WiringTermination(
        kind: .speaker,
        label: "Front L",
        bindingRef: nil,
        connectorLabel: "binding post"
    )
    let endpointB = try WiringTermination(
        kind: .avReceiver,
        label: "AVR",
        bindingRef: "equipment:denon_x3800"
    )
    let hidden = try WiringSegment(
        order: 0,
        observation: .hiddenUnknown
    )
    // observed_as_built requires at least one observed segment —
    // hidden-only must reject.
    #expect(throws: (any Error).self) {
        _ = try AsBuiltWiringRoute(
            captureRevisionID: testRevisionID,
            cableType: "speaker_wire",
            state: .observedAsBuilt,
            endpointA: endpointA,
            endpointB: endpointB,
            segments: [try WiringSegment(
                order: 0,
                observation: .hiddenUnknown
            ), try WiringSegment(
                order: 1,
                observation: .hiddenUnknown
            )]
        )
    }
    let observedSegment = try WiringSegment(
        order: 0,
        observation: .observed,
        waypoints: [
            try SpatialVector3F(0, 0, 0),
            try SpatialVector3F(1, 0, 0),
        ]
    )
    let routeObserved = try AsBuiltWiringRoute(
        captureRevisionID: testRevisionID,
        cableType: "speaker_wire",
        state: .observedAsBuilt,
        endpointA: endpointA,
        endpointB: endpointB,
        segments: [
            observedSegment,
            try WiringSegment(order: 1, observation: .hiddenUnknown),
        ]
    )
    let document = try AsBuiltWiringDocument(
        captureRevisionID: testRevisionID,
        routes: [routeObserved]
    )
    #expect(
        try validateEncoded(
            document,
            schema: "wiring-routes"
        ) == nil
    )
    // A hidden segment can never carry geometry.
    #expect(throws: (any Error).self) {
        _ = try WiringSegment(
            order: 0,
            observation: .hiddenUnknown,
            waypoints: [try SpatialVector3F(0, 0, 0)]
        )
    }
}

@Test
func wiringIdenticalEndpointsRejected() throws {
    let endpoint = try WiringTermination(
        kind: .speaker,
        label: "same point"
    )
    #expect(throws: (any Error).self) {
        _ = try AsBuiltWiringRoute(
            captureRevisionID: testRevisionID,
            cableType: "speaker_wire",
            state: .planned,
            endpointA: endpoint,
            endpointB: endpoint
        )
    }
}

@Test
func draftDecodeWithoutFieldAuthority() throws {
    // Drafts saved before the field-authority extension lack the key;
    // they must still decode (issue #314).
    let draft = AnnotationWorkspaceDraft(
        captureRevisionID: testRevisionID,
        coordinateSpaceID: testSpaceID,
        savedAtUTC: "2026-09-21T00:00:00Z",
        annotations: [],
        measurements: []
    )
    var data = try JSONEncoder().encode(draft)
    var object = try JSONSerialization.jsonObject(
        with: data
    ) as! [String: Any]
    object.removeValue(forKey: "field_authority")
    data = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(
        AnnotationWorkspaceDraft.self,
        from: data
    )
    #expect(decoded.fieldAuthority == nil)
}
