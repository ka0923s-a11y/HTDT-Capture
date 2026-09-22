import Foundation
import Testing
@testable import HTDTCaptureCore

private func makeTemporaryDirectory() throws -> URL {
    try BundleValidationFixture.makeDirectory()
}

@Test
func registryMapsEverySchemaOwnedPath() throws {
    let expected: [String: String] = [
        "manifest.json": "manifest",
        "session/capture-session.json": "session",
        "session/device.json": "device",
        "session/capabilities.json": "capabilities",
        "session/capture-configuration.json": "capture-configuration",
        "session/timing.json": "timing",
        "mesh/anchors.json": "mesh-anchors",
        "annotations/entities.json": "entities",
        "annotations/measurements.json": "measurements",
        "annotations/authorities.json": "authorities",
        "quality/capture-quality.json": "quality",
        "quality/capture-advisory.json": "capture-advisory",
        "evidence/frames/anything.json": "frame",
        "session/room-reference-frame.json":
            "room-reference-frame",
        "annotations/opening-review.json": "opening-review",
        "session/room-field-datum.json": "room-field-datum",
        "derived/operator-profiles.json": "operator-profiles",
        "derived/field-evidence.json": "field-evidence",
        "derived/instrument-profiles.json": "instrument-profiles",
        "derived/settings-observations.json":
            "settings-observations",
        "derived/wiring-routes.json": "wiring-routes",
        "session/field-notes.json": "field-notes",
        "session/revisit-flags.json": "revisit-flags",
        "session/coordinate-space-policy.json":
            "coordinate-space-policy",
        "session/connected-spaces.json": "connected-spaces",
        "session/capture-task-plan.json": "capture-task-plan",
        "session/task-plan-status.json": "task-plan-status",
        "session/revision-state.json": "working-revision-state",
        "session/capture-strategy.json": "capture-strategy",
        "advisory/operator-advisories.json": "advisory-notes",
        "revision/intent.json": "revision-intent",
        "revision/registrations.json":
            "cross-revision-registration",
        "reference/plan-underlay.json": "plan-underlay",
        "derived/authority-dependencies.json":
            "authority-dependencies",
        "derived/geometry-candidates.json":
            "derived-geometry-candidates",
        "derived/equipment-identity.json": "equipment-identity",
        "evidence/reference-targets.json": "reference-targets",
        "verification/as-built.json": "as-built",
    ]
    for (path, name) in expected {
        #expect(CaptureBundleSchemaRegistry.schemaName(forPath: path) == name)
        // The emitted version's registry document must compile —
        // versioned families have no same-named document key.
        if let contract = CaptureBundleSchemaRegistry
            .supportMatrix.families[name],
           let emitted = contract.emitted,
           let documentName = contract.documents[emitted]
        {
            _ = try CaptureBundleSchemaRegistry.compiledSchema(
                named: documentName
            )
        }
    }
    #expect(
        CaptureBundleSchemaRegistry.schemaName(
            forPath: "docs/notes.json"
        ) == nil
    )
    #expect(
        CaptureBundleSchemaRegistry.schemaName(
            forPath: "evidence/frames/nested/anything.json"
        ) == nil
    )
}

/// #452: a registry-owned path missing from the support matrix
/// silently bypassed payload-version dispatch *and* failed the
/// remote validator outright. The matrix is the single authority —
/// every declared path must resolve back to the family that declares
/// it, and every declared document key must compile.
@Test
func everyMatrixPathResolvesBackToItsFamily() throws {
    for (name, contract) in CaptureBundleSchemaRegistry
        .supportMatrix.families
    {
        guard !contract.external else { continue }
        for path in contract.paths {
            #expect(
                CaptureBundleSchemaRegistry.schemaName(
                    forPath: path
                ) == name
            )
        }
        for documentName in contract.documents.values {
            _ = try CaptureBundleSchemaRegistry.compiledSchema(
                named: documentName
            )
        }
    }
}

/// #451/#452: session/revisit-flags.json is a declared canonical
/// payload — it validates against the published revisit-flags
/// schema instead of failing as an unowned .json payload.
@Test
func revisitFlagsPayloadValidatesAgainstPublishedSchema() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let payload: StrictJSONValue = .object([
        ("schema", .string("htdt.capture.revisit_flags")),
        ("schema_version", .string("1.0.0")),
        (
            "capture_revision_id",
            .string(BundleValidationFixture.sessionUUID)
        ),
        (
            "flags",
            .array([
                .object([
                    (
                        "flagID",
                        .string(
                            "00000000-0000-4000-8000-000000000030"
                        )
                    ),
                    (
                        "coordinateSpaceID",
                        .string(BundleValidationFixture.spaceUUID)
                    ),
                    (
                        "captureSessionID",
                        .string(BundleValidationFixture.sessionUUID)
                    ),
                    (
                        "targetFromRaycast",
                        .boolean(false)
                    ),
                    ("status", .string("unresolved")),
                    (
                        "createdSessionTimestampSeconds",
                        .number(12.5)
                    ),
                ]),
            ])
        ),
    ])

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/revisit-flags.json",
                data: try BundleValidationFixture.canonical(payload),
                mediaType: "application/json"
            ),
        ]
    )

    _ = try BundleDirectoryValidator.validate(root: root)
}

/// #449: task-plan-status 2.0.0 — a pending item may carry no
/// fulfillment decoration in *either* representation; `fulfillment`
/// and `fulfillment_ref` are the same invariant under two keys.
@Test
func pendingTaskItemRejectsFulfillmentRef() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    func statusPayload(fulfillmentRef: StrictJSONValue)
        -> StrictJSONValue
    {
        .object([
            (
                "schema",
                .string("htdt.capture-task-plan-status")
            ),
            ("schema_version", .string("2.0.0")),
            (
                "capture_revision_id",
                .string(BundleValidationFixture.sessionUUID)
            ),
            (
                "capture_session_id",
                .string(BundleValidationFixture.sessionUUID)
            ),
            ("plan_id", .string("plan-1")),
            ("plan_version", .string("1")),
            (
                "plan_sha256",
                .string(
                    String(repeating: "ab", count: 32)
                )
            ),
            (
                "items",
                .array([
                    .object([
                        ("item_id", .string("m-1")),
                        ("outcome", .string("pending")),
                        ("fulfillment_ref", fulfillmentRef),
                    ]),
                ])
            ),
        ])
    }

    // A pending item carrying a fulfillment_ref string is rejected.
    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/task-plan-status.json",
                data: try BundleValidationFixture.canonical(
                    statusPayload(
                        fulfillmentRef: .string("frame:1")
                    )
                ),
                mediaType: "application/json"
            ),
        ]
    )
    do {
        _ = try BundleDirectoryValidator.validate(root: root)
        Issue.record("expected schemaValidationFailed")
    } catch let error as BundleDirectoryValidationError {
        guard case .schemaValidationFailed = error else {
            Issue.record("expected schemaValidationFailed, got \(error)")
            return
        }
    }

    // An explicit null passes — the decoration is absent, not
    // forbidden from existing as a null slot.
    let clean = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(clean) }
    try BundleValidationFixture.stage(
        clean,
        payloads: [
            (
                path: "session/task-plan-status.json",
                data: try BundleValidationFixture.canonical(
                    statusPayload(fulfillmentRef: .null)
                ),
                mediaType: "application/json"
            ),
        ]
    )
    _ = try BundleDirectoryValidator.validate(root: clean)
}

@Test
func hashCorrectButSchemaInvalidPayloadRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    // Const mismatch: schema_version must be "1.0.0".
    var members = BundleValidationFixture.sessionValue().members ?? []
    members[1] = ("schema_version", .string("2.0.0"))
    let invalid = try BundleValidationFixture.canonical(
        .object(members)
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: invalid,
                mediaType: "application/json"
            ),
        ]
    )

    do {
        _ = try BundleDirectoryValidator.validate(root: root)
        Issue.record("expected schemaValidationFailed")
    } catch let error as BundleDirectoryValidationError {
        guard case let .schemaValidationFailed(path, _) = error else {
            Issue.record("expected schemaValidationFailed, got \(error)")
            return
        }
        #expect(path == "session/capture-session.json")
    }
}

@Test
func schemaMissingRequiredPropertyRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var members = BundleValidationFixture.qualityValue().members ?? []
    members.removeAll { $0.key == "diagnostics" }
    let invalid = try BundleValidationFixture.canonical(
        .object(members)
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "quality/capture-quality.json",
                data: invalid,
                mediaType: "application/json"
            ),
        ]
    )

    do {
        _ = try BundleDirectoryValidator.validate(root: root)
        Issue.record("expected schemaValidationFailed")
    } catch let error as BundleDirectoryValidationError {
        guard case .schemaValidationFailed = error else {
            Issue.record("expected schemaValidationFailed, got \(error)")
            return
        }
    }
}

@Test
func schemaAdditionalPropertyRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var members = BundleValidationFixture.sessionValue().members ?? []
    members.append(("unexpected", .string("x")))
    let invalid = try BundleValidationFixture.canonical(
        .object(members)
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: invalid,
                mediaType: "application/json"
            ),
        ]
    )

    do {
        _ = try BundleDirectoryValidator.validate(root: root)
        Issue.record("expected schemaValidationFailed")
    } catch let error as BundleDirectoryValidationError {
        guard case .schemaValidationFailed = error else {
            Issue.record("expected schemaValidationFailed, got \(error)")
            return
        }
    }
}

@Test
func schemaPatternViolationRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var members = BundleValidationFixture.sessionValue().members ?? []
    for (index, member) in members.enumerated()
    where member.key == "capture_session_id"
    {
        // The schema pattern requires lowercase hex; the shared fixture
        // UUID is digit-only, so an explicit uppercase variant is needed.
        members[index] = (
            "capture_session_id",
            .string("A0000000-0000-4000-8000-00000000000A")
        )
    }
    let invalid = try BundleValidationFixture.canonical(
        .object(members)
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: invalid,
                mediaType: "application/json"
            ),
        ]
    )

    do {
        _ = try BundleDirectoryValidator.validate(root: root)
        Issue.record("expected schemaValidationFailed")
    } catch let error as BundleDirectoryValidationError {
        guard case .schemaValidationFailed = error else {
            Issue.record("expected schemaValidationFailed, got \(error)")
            return
        }
    }
}

@Test
func entitiesConditionalSchemaApplied() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    // A "speaker" entity without orientation/channel_role must fail the
    // schema's if/then constraint even though every byte hashes.
    let entities: StrictJSONValue = .object([
        ("schema", .string("htdt.capture.entities")),
        ("schema_version", .string("1.0.0")),
        (
            "entities",
            .array([
                .object([
                    (
                        "entity_id",
                        .string(BundleValidationFixture.anchorUUID)
                    ),
                    ("type", .string("speaker")),
                    (
                        "coordinate_space_id",
                        .string(BundleValidationFixture.spaceUUID)
                    ),
                    (
                        "T_world_from_annotation",
                        BundleValidationFixture.matrix4Value()
                    ),
                    (
                        "reference_point_semantics",
                        .string("acoustic_center")
                    ),
                    ("label", .string("speaker L")),
                    ("provenance_class", .string("user_annotation")),
                    ("verification_state", .string("user_attested")),
                    (
                        "placement",
                        .object([
                            ("method", .string("manual_numeric")),
                            (
                                "source_evidence_refs",
                                .array([.string("path:a")])
                            ),
                        ])
                    ),
                    ("orientation", .null),
                    ("channel_role", .null),
                    ("acoustic_center", .null),
                    ("equipment_ref", .null),
                    ("evidence_refs", .array([.string("path:a")])),
                ]),
            ])
        ),
    ])

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "annotations/entities.json",
                data: try BundleValidationFixture.canonical(entities),
                mediaType: "application/json"
            ),
        ]
    )

    do {
        _ = try BundleDirectoryValidator.validate(root: root)
        Issue.record("expected schemaValidationFailed")
    } catch let error as BundleDirectoryValidationError {
        guard case .schemaValidationFailed = error else {
            Issue.record("expected schemaValidationFailed, got \(error)")
            return
        }
    }
}

@Test
func schemaCompilerFailsClosedOnUnsupportedConstructs() throws {
    let remoteRef = try StrictJSON.parse(
        Data(
            "{\"type\":\"object\",\"properties\":{\"x\":{\"$ref\":\"https://example.com/x\"}}}"
                .utf8
        )
    )
    #expect(throws: JSONSchemaError.unsupportedRef(
        "https://example.com/x"
    )) {
        _ = try JSONSchemaValidator.compile(remoteRef)
    }

    let unknownKeyword = try StrictJSON.parse(
        Data(
            "{\"type\":\"object\",\"description\":\"annotated\"}".utf8
        )
    )
    #expect(throws: JSONSchemaError.unsupportedKeyword("description")) {
        _ = try JSONSchemaValidator.compile(unknownKeyword)
    }
}

@Test
func frameDescriptorPathUsesFrameSchema() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let pixelData = try BundleValidationFixture.pixelPayload(
        width: 4,
        height: 3
    )
    let pixelPath = "evidence/frames/\(BundleValidationFixture.frameUUID).pixelbin"
    let descriptor = BundleValidationFixture.frameDescriptorValue(
        pixelPath: pixelPath,
        pixelByteCount: pixelData.count,
        pixelSHA256: EvidenceIntegrity.sha256(of: pixelData).description,
        imageWidth: 4,
        imageHeight: 3,
        pixelFormatFourCC: 0x3432_3066
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "evidence/frames/\(BundleValidationFixture.frameUUID).json",
                data: try BundleValidationFixture.canonical(descriptor),
                mediaType: "application/json"
            ),
            (
                path: pixelPath,
                data: pixelData,
                mediaType: "application/vnd.htdt.pixelbin"
            ),
        ]
    )

    let report = try BundleDirectoryValidator.validate(root: root)
    #expect(report.valid)
}
