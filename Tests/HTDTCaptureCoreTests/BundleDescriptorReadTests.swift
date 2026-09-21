import Foundation
import Testing
@testable import HTDTCaptureCore

private func makeTemporaryDirectory() throws -> URL {
    try BundleValidationFixture.makeDirectory()
}

@Test
func readerBindsBytesAndDigestToOneDescriptor() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let data = Data([1, 2, 3, 4])
    try data.write(to: root.appendingPathComponent("payload.bin"))

    let opened = try BundleFileReader.read(
        root.appendingPathComponent("payload.bin"),
        maxBytes: BundlePayloadLimits.maxManifestBytes
    )
    #expect(opened.data == data)
    #expect(opened.byteCount == Int64(data.count))
    #expect(opened.sha256 == EvidenceIntegrity.sha256(of: data))
}

@Test
func readerRejectsSymlinkInstalledAfterScan() throws {
    let fileManager = FileManager.default
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }
    let outside = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(outside) }

    let payloadURL = root.appendingPathComponent("payload.bin")
    try Data([1, 2, 3]).write(to: payloadURL)
    let scanned = try BundleDirectoryScanner.scan(root: root)
    #expect(scanned.map(\.path) == ["payload.bin"])

    // Swap the scanned regular file for a symlink before the validator
    // reopens it: the descriptor-level check must reject it rather than
    // following the link.
    let target = outside.appendingPathComponent("target.bin")
    try Data([9, 9, 9]).write(to: target)
    try fileManager.removeItem(at: payloadURL)
    try fileManager.createSymbolicLink(
        at: payloadURL,
        withDestinationURL: target
    )

    #expect(
        throws: BundleFilesystemError.fileOpenFailed(payloadURL.path)
    ) {
        _ = try BundleFileReader.read(payloadURL, maxBytes: 1024)
    }
}

@Test
func readerRejectsHardLinkInstalledAfterScan() throws {
    let fileManager = FileManager.default
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }
    let outside = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(outside) }

    let payloadURL = root.appendingPathComponent("payload.bin")
    try Data([1, 2, 3]).write(to: payloadURL)
    _ = try BundleDirectoryScanner.scan(root: root)

    let alias = outside.appendingPathComponent("alias.bin")
    try fileManager.linkItem(at: payloadURL, to: alias)

    #expect(
        throws: BundleFilesystemError.hardLinkForbidden(payloadURL.path)
    ) {
        _ = try BundleFileReader.read(payloadURL, maxBytes: 1024)
    }
}

@Test
func hasherRejectsSymlinkSwap() throws {
    let fileManager = FileManager.default
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }
    let outside = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(outside) }

    let target = outside.appendingPathComponent("target.bin")
    try Data([9, 9, 9]).write(to: target)
    let link = root.appendingPathComponent("payload.bin")
    try fileManager.createSymbolicLink(
        at: link,
        withDestinationURL: target
    )

    #expect(throws: BundleFilesystemError.fileOpenFailed(link.path)) {
        _ = try BundleFileHasher.sha256(url: link)
    }
}

@Test
func validatorRejectsSameSizePayloadReplacement() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "payload.bin",
                data: Data([1, 2, 3, 4]),
                mediaType: "application/octet-stream"
            ),
        ]
    )

    let payloadURL = root.appendingPathComponent("payload.bin")
    try FileManager.default.removeItem(at: payloadURL)
    try Data([5, 6, 7, 8]).write(to: payloadURL)

    do {
        _ = try BundleDirectoryValidator.validate(root: root)
        Issue.record("expected hashMismatch")
    } catch let error as BundleDirectoryValidationError {
        guard case .hashMismatch = error else {
            Issue.record("expected hashMismatch, got \(error)")
            return
        }
    }
}

@Test
func manifestBeyondDedicatedLimitRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

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

    let limits = BundleFilesystemLimits(maxManifestBytes: 64)
    #expect(
        throws: BundleDirectoryValidationError.manifestTooLarge
    ) {
        _ = try BundleDirectoryValidator.validate(
            root: root,
            limits: limits
        )
    }
}

@Test
func oversizedManifestRejectedAtDefaultLimit() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let oversized = Data(
        repeating: 0x20,
        count: Int(BundlePayloadLimits.maxManifestBytes) + 1
    )
    try oversized.write(to: root.appendingPathComponent("manifest.json"))

    #expect(
        throws: BundleDirectoryValidationError.manifestTooLarge
    ) {
        _ = try BundleDirectoryValidator.validate(root: root)
    }
}
