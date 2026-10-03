import Foundation
import Testing
@testable import HTDTCaptureCore

private func makeTemporaryDirectory() throws -> URL {
    try BundleValidationFixture.makeDirectory()
}

private func validationFailure(
    in root: URL
) throws -> BundleDirectoryValidationError? {
    do {
        _ = try BundleDirectoryValidator.validate(root: root)
        return nil
    } catch let error as BundleDirectoryValidationError {
        return error
    }
}

@Test
func validCanonicalSessionPayloadAccepted() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: try BundleValidationFixture.canonical(
                    BundleValidationFixture.sessionValue()
                ),
                mediaType: "application/json"
            ),
        ]
    )

    let report = try BundleDirectoryValidator.validate(root: root)
    #expect(report.valid)
    // staged session + auto-staged remaining foundation payloads
    #expect(report.payloadCount == 4)
}

@Test
func payloadWithInsignificantWhitespaceRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var bytes = try BundleValidationFixture.canonical(
        BundleValidationFixture.sessionValue()
    )
    guard let colon = bytes.firstIndex(of: 0x3A) else {
        Issue.record("expected a colon in canonical session JSON")
        return
    }
    bytes.insert(0x20, at: colon + 1)

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: bytes,
                mediaType: "application/json"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadNotCanonicalJSON, got success")
        return
    }
    guard case .payloadNotCanonicalJSON = error else {
        Issue.record("expected payloadNotCanonicalJSON, got \(error)")
        return
    }
}

@Test
func payloadWithUnsortedKeysRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let sessionUUID = BundleValidationFixture.sessionUUID
    let spaceUUID = BundleValidationFixture.spaceUUID
    let raw =
        "{\"timing_ref\":\"session/timing.json\",\"schema\":\"htdt.capture.session\",\"schema_version\":\"1.0.0\",\"capture_session_id\":\"\(sessionUUID)\",\"coordinate_space_id\":\"\(spaceUUID)\",\"configuration_ref\":\"session/capture-configuration.json\"}"

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: Data(raw.utf8),
                mediaType: "application/json"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadNotCanonicalJSON, got success")
        return
    }
    guard case .payloadNotCanonicalJSON = error else {
        Issue.record("expected payloadNotCanonicalJSON, got \(error)")
        return
    }
}

@Test
func payloadWithDuplicateKeyRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let sessionUUID = BundleValidationFixture.sessionUUID
    let spaceUUID = BundleValidationFixture.spaceUUID
    let raw =
        "{\"schema\":\"htdt.capture.session\",\"schema\":\"htdt.capture.session\",\"schema_version\":\"1.0.0\",\"capture_session_id\":\"\(sessionUUID)\",\"coordinate_space_id\":\"\(spaceUUID)\",\"configuration_ref\":\"session/capture-configuration.json\",\"timing_ref\":\"session/timing.json\"}"

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: Data(raw.utf8),
                mediaType: "application/json"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadNotCanonicalJSON, got success")
        return
    }
    guard case .payloadNotCanonicalJSON = error else {
        Issue.record("expected payloadNotCanonicalJSON, got \(error)")
        return
    }
}

@Test
func payloadWithNonNFCStringRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    // "e + combining acute" decomposes e-acute; the canonical byte
    // profile requires NFC scalars.
    let sessionUUID = BundleValidationFixture.sessionUUID
    let spaceUUID = BundleValidationFixture.spaceUUID
    let raw =
        "{\"schema\":\"htdt.capture.session\",\"schema_version\":\"1.0.0\",\"capture_session_id\":\"\(sessionUUID)\",\"coordinate_space_id\":\"\(spaceUUID)\",\"configuration_ref\":\"e\\u0301\",\"timing_ref\":\"session/timing.json\"}"

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: Data(raw.utf8),
                mediaType: "application/json"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadNotCanonicalJSON, got success")
        return
    }
    guard case .payloadNotCanonicalJSON = error else {
        Issue.record("expected payloadNotCanonicalJSON, got \(error)")
        return
    }
}

@Test
func payloadWithByteOrderMarkRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var bytes = Data([0xEF, 0xBB, 0xBF])
    bytes.append(
        try BundleValidationFixture.canonical(
            BundleValidationFixture.sessionValue()
        )
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: bytes,
                mediaType: "application/json"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadNotCanonicalJSON, got success")
        return
    }
    guard case .payloadNotCanonicalJSON = error else {
        Issue.record("expected payloadNotCanonicalJSON, got \(error)")
        return
    }
}

@Test
func payloadWithInvalidUTF8Rejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var bytes = try BundleValidationFixture.canonical(
        BundleValidationFixture.sessionValue()
    )
    guard let index = bytes.firstIndex(of: 0x65) else {
        Issue.record("expected string content")
        return
    }
    bytes[index] = 0xFF

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: bytes,
                mediaType: "application/json"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadNotCanonicalJSON, got success")
        return
    }
    guard case .payloadNotCanonicalJSON = error else {
        Issue.record("expected payloadNotCanonicalJSON, got \(error)")
        return
    }
}

@Test
func payloadWithNonCanonicalNumberRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let canonical = try BundleValidationFixture.canonical(
        BundleValidationFixture.meshAnchorsValue(
            geometryPath: "mesh/ignored.meshbin",
            geometrySHA256: String(repeating: "0", count: 64),
            vertexCount: 3,
            faceCount: 1
        )
    )
    var text = String(decoding: canonical, as: UTF8.self)
    text = text.replacingOccurrences(
        of: "\"session_timestamp_s\":1.0",
        with: "\"session_timestamp_s\":1e0"
    )
    #expect(text.contains("1e0"))

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "mesh/anchors.json",
                data: Data(text.utf8),
                mediaType: "application/json"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadNotCanonicalJSON, got success")
        return
    }
    guard case .payloadNotCanonicalJSON = error else {
        Issue.record("expected payloadNotCanonicalJSON, got \(error)")
        return
    }
}

@Test
func payloadWithTrailingBytesRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var bytes = try BundleValidationFixture.canonical(
        BundleValidationFixture.sessionValue()
    )
    bytes.append(0x20)

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "session/capture-session.json",
                data: bytes,
                mediaType: "application/json"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadNotCanonicalJSON, got success")
        return
    }
    guard case .payloadNotCanonicalJSON = error else {
        Issue.record("expected payloadNotCanonicalJSON, got \(error)")
        return
    }
}

@Test
func unownedJSONPayloadRejected() throws {
    // legacy bolph71656-ai/HTDT-Capture#332: a manifest-declared .json payload must be owned by a
    // published schema or be a declared external authority payload —
    // generic supplemental persistence cannot bypass validation.
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "docs/notes.json",
                data: Data("{ \"pretty\": true }".utf8),
                mediaType: "application/json"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected schemaValidationFailed, got success")
        return
    }
    guard case .schemaValidationFailed = error else {
        Issue.record("expected schemaValidationFailed, got \(error)")
        return
    }
}
