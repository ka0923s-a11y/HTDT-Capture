import Foundation
import Testing
@testable import HTDTCaptureCore

private func makeTemporaryDirectory() throws -> URL {
    let fileManager = FileManager.default
    let url = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}

@Test
func scannerAcceptsSingleLinkPayloads() throws {
    let fileManager = FileManager.default
    let root = try makeTemporaryDirectory()
    defer { try? fileManager.removeItem(at: root) }

    try Data([1, 2, 3]).write(
        to: root.appendingPathComponent("payload.bin")
    )

    let files = try BundleDirectoryScanner.scan(root: root)
    #expect(files.map { $0.path } == ["payload.bin"])
}

@Test
func scannerRejectsPayloadWithExternalHardLink() throws {
    let fileManager = FileManager.default
    let root = try makeTemporaryDirectory()
    defer { try? fileManager.removeItem(at: root) }

    let payload = root.appendingPathComponent("payload.bin")
    try Data([1, 2, 3]).write(to: payload)

    // The alias lives outside the bundle root: the finalized directory
    // entry can be moved away while this name still reaches the inode.
    let alias = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try fileManager.linkItem(at: payload, to: alias)
    defer { try? fileManager.removeItem(at: alias) }

    #expect(
        throws: BundleFilesystemError.hardLinkForbidden("payload.bin")
    ) {
        _ = try BundleDirectoryScanner.scan(root: root)
    }
}

@Test
func scannerRejectsPayloadAliasInsideBundle() throws {
    let fileManager = FileManager.default
    let root = try makeTemporaryDirectory()
    defer { try? fileManager.removeItem(at: root) }

    let payload = root.appendingPathComponent("payload.bin")
    try Data([1, 2, 3]).write(to: payload)
    try fileManager.linkItem(
        at: payload,
        to: root.appendingPathComponent("alias.bin")
    )

    #expect(throws: BundleFilesystemError.self) {
        _ = try BundleDirectoryScanner.scan(root: root)
    }
}

@Test
func externalAliasMutationStaysRejected() throws {
    let fileManager = FileManager.default
    let root = try makeTemporaryDirectory()
    defer { try? fileManager.removeItem(at: root) }

    let payload = root.appendingPathComponent("payload.bin")
    try Data([1, 2, 3]).write(to: payload)

    let alias = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try fileManager.linkItem(at: payload, to: alias)
    defer { try? fileManager.removeItem(at: alias) }

    // Writing through the external alias rewrites the bundle file's
    // inode, which is exactly why multi-link payloads are rejected.
    let handle = try FileHandle(forWritingTo: alias)
    try handle.write(contentsOf: Data([9, 9, 9]))
    try handle.close()
    let mutated = try Data(contentsOf: payload)
    #expect(mutated == Data([9, 9, 9]))

    #expect(
        throws: BundleFilesystemError.hardLinkForbidden("payload.bin")
    ) {
        _ = try BundleDirectoryScanner.scan(root: root)
    }
}

@Test
func removingExternalAliasRestoresAcceptance() throws {
    let fileManager = FileManager.default
    let root = try makeTemporaryDirectory()
    defer { try? fileManager.removeItem(at: root) }

    let payload = root.appendingPathComponent("payload.bin")
    try Data([1, 2, 3]).write(to: payload)

    let alias = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try fileManager.linkItem(at: payload, to: alias)

    #expect(throws: BundleFilesystemError.self) {
        _ = try BundleDirectoryScanner.scan(root: root)
    }

    // Dropping the second directory entry returns the payload to a
    // single-link inode; bytes are unchanged and scanning succeeds.
    try fileManager.removeItem(at: alias)
    let files = try BundleDirectoryScanner.scan(root: root)
    #expect(files.map { $0.path } == ["payload.bin"])
}

@Test
func validatorRejectsHardLinkedManifest() throws {
    let fileManager = FileManager.default
    let root = try makeTemporaryDirectory()
    defer { try? fileManager.removeItem(at: root) }

    // Stage a complete foundation set (#194) plus the test payload so
    // the manifest is a valid finalized v1 bundle.
    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "payload.bin",
                data: Data([1, 2, 3]),
                mediaType: "application/octet-stream"
            ),
        ]
    )
    let manifestURL = root.appendingPathComponent("manifest.json")

    // Complete single-link directory validates first.
    _ = try BundleDirectoryValidator.validate(root: root)

    // manifest.json is written by the finalizer before validation runs,
    // so the link-count rule must cover it like any other regular file.
    let alias = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try fileManager.linkItem(at: manifestURL, to: alias)
    defer { try? fileManager.removeItem(at: alias) }

    #expect(
        throws: BundleFilesystemError.hardLinkForbidden("manifest.json")
    ) {
        _ = try BundleDirectoryValidator.validate(root: root)
    }
}
