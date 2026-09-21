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
        "quality/capture-quality.json": "quality",
        "evidence/frames/anything.json": "frame",
    ]
    for (path, name) in expected {
        #expect(CaptureBundleSchemaRegistry.schemaName(forPath: path) == name)
        _ = try CaptureBundleSchemaRegistry.compiledSchema(named: name)
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
        members[index] = (
            "capture_session_id",
            .string(BundleValidationFixture.sessionUUID.uppercased())
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
