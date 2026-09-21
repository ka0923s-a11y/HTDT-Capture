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
func randomMeshBytesRejectedDespiteMatchingHash() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "mesh/a.meshbin",
                data: Data((0 ..< 64).map { UInt8($0 & 0xFF) }),
                mediaType: "application/vnd.htdt.meshbin"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected binaryPayloadInvalid, got success")
        return
    }
    guard case .binaryPayloadInvalid = error else {
        Issue.record("expected binaryPayloadInvalid, got \(error)")
        return
    }
}

@Test
func meshPayloadWithTrailingBytesRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var mesh = try BundleValidationFixture.meshPayload(
        vertexCount: 3,
        faceCount: 1
    )
    mesh.append(contentsOf: [0, 0, 0, 0])

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "mesh/a.meshbin",
                data: mesh,
                mediaType: "application/vnd.htdt.meshbin"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected binaryPayloadInvalid, got success")
        return
    }
    guard case .binaryPayloadInvalid = error else {
        Issue.record("expected binaryPayloadInvalid, got \(error)")
        return
    }
}

@Test
func meshPayloadWithUnknownVersionRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var mesh = try BundleValidationFixture.meshPayload(
        vertexCount: 3,
        faceCount: 1
    )
    // Header layout: 8-byte magic, then little-endian major/minor.
    mesh[8] = 2

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "mesh/a.meshbin",
                data: mesh,
                mediaType: "application/vnd.htdt.meshbin"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected binaryPayloadInvalid, got success")
        return
    }
    guard case .binaryPayloadInvalid = error else {
        Issue.record("expected binaryPayloadInvalid, got \(error)")
        return
    }
}

@Test
func meshPayloadWithReservedByteSetRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    var mesh = try BundleValidationFixture.meshPayload(
        vertexCount: 3,
        faceCount: 1
    )
    // Reserved field sits at header offsets 26...31.
    mesh[26] = 1

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "mesh/a.meshbin",
                data: mesh,
                mediaType: "application/vnd.htdt.meshbin"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected binaryPayloadInvalid, got success")
        return
    }
    guard case .binaryPayloadInvalid = error else {
        Issue.record("expected binaryPayloadInvalid, got \(error)")
        return
    }
}

@Test
func meshAnchorCountMismatchRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let meshData = try BundleValidationFixture.meshPayload(
        vertexCount: 3,
        faceCount: 1
    )
    let anchors = BundleValidationFixture.meshAnchorsValue(
        geometryPath: "mesh/a.meshbin",
        geometrySHA256: EvidenceIntegrity.sha256(of: meshData).description,
        vertexCount: 4,
        faceCount: 1
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "mesh/anchors.json",
                data: try BundleValidationFixture.canonical(anchors),
                mediaType: "application/json"
            ),
            (
                path: "mesh/a.meshbin",
                data: meshData,
                mediaType: "application/vnd.htdt.meshbin"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadCrossCheckFailed, got success")
        return
    }
    guard case .payloadCrossCheckFailed = error else {
        Issue.record("expected payloadCrossCheckFailed, got \(error)")
        return
    }
}

@Test
func meshAnchorUndeclaredGeometryRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let anchors = BundleValidationFixture.meshAnchorsValue(
        geometryPath: "mesh/missing.meshbin",
        geometrySHA256: String(repeating: "0", count: 64),
        vertexCount: 3,
        faceCount: 1
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "mesh/anchors.json",
                data: try BundleValidationFixture.canonical(anchors),
                mediaType: "application/json"
            ),
            (
                path: "mesh/a.meshbin",
                data: try BundleValidationFixture.meshPayload(
                    vertexCount: 3,
                    faceCount: 1
                ),
                mediaType: "application/vnd.htdt.meshbin"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadCrossCheckFailed, got success")
        return
    }
    guard case .payloadCrossCheckFailed = error else {
        Issue.record("expected payloadCrossCheckFailed, got \(error)")
        return
    }
}

@Test
func pixelDimensionMismatchRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let pixelData = try BundleValidationFixture.pixelPayload(
        width: 4,
        height: 3
    )
    let frameID = BundleValidationFixture.frameUUID
    let pixelPath = "evidence/frames/\(frameID).pixelbin"
    let descriptor = BundleValidationFixture.frameDescriptorValue(
        pixelPath: pixelPath,
        pixelByteCount: pixelData.count,
        pixelSHA256: EvidenceIntegrity.sha256(of: pixelData).description,
        imageWidth: 8,
        imageHeight: 3,
        pixelFormatFourCC: 0x3432_3066
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "evidence/frames/\(frameID).json",
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

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadCrossCheckFailed, got success")
        return
    }
    guard case .payloadCrossCheckFailed = error else {
        Issue.record("expected payloadCrossCheckFailed, got \(error)")
        return
    }
}

@Test
func confidenceDimensionMismatchRejected() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let frameID = BundleValidationFixture.frameUUID
    let pixelData = try BundleValidationFixture.pixelPayload(
        width: 4,
        height: 3
    )
    let pixelPath = "evidence/frames/\(frameID).pixelbin"
    let depthData = try BundleValidationFixture.depthPayload(
        width: 2,
        height: 2
    )
    let depthPath = "evidence/depth/\(frameID).depthbin"
    let confidenceData = try BundleValidationFixture.confidencePayload(
        width: 2,
        height: 1
    )
    let confidencePath = "evidence/depth/\(frameID).confidencebin"

    let descriptor = BundleValidationFixture.frameDescriptorValue(
        pixelPath: pixelPath,
        pixelByteCount: pixelData.count,
        pixelSHA256: EvidenceIntegrity.sha256(of: pixelData).description,
        imageWidth: 4,
        imageHeight: 3,
        pixelFormatFourCC: 0x3432_3066,
        depthStatus: "captured_scene_depth",
        depth: BundleValidationFixture.depthReferenceValue(
            depthPath: depthPath,
            depthByteCount: depthData.count,
            depthSHA256: EvidenceIntegrity.sha256(of: depthData)
                .description,
            confidencePath: confidencePath,
            confidenceByteCount: confidenceData.count,
            confidenceSHA256: EvidenceIntegrity.sha256(of: confidenceData)
                .description
        )
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "evidence/frames/\(frameID).json",
                data: try BundleValidationFixture.canonical(descriptor),
                mediaType: "application/json"
            ),
            (
                path: pixelPath,
                data: pixelData,
                mediaType: "application/vnd.htdt.pixelbin"
            ),
            (
                path: depthPath,
                data: depthData,
                mediaType: "application/vnd.htdt.depthbin"
            ),
            (
                path: confidencePath,
                data: confidenceData,
                mediaType: "application/vnd.htdt.confidencebin"
            ),
        ]
    )

    guard let error = try validationFailure(in: root) else {
        Issue.record("expected payloadCrossCheckFailed, got success")
        return
    }
    guard case .payloadCrossCheckFailed = error else {
        Issue.record("expected payloadCrossCheckFailed, got \(error)")
        return
    }
}

@Test
func consistentBinaryEvidenceBundleAccepted() throws {
    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }

    let frameID = BundleValidationFixture.frameUUID
    let meshData = try BundleValidationFixture.meshPayload(
        vertexCount: 4,
        faceCount: 2
    )
    let anchors = BundleValidationFixture.meshAnchorsValue(
        geometryPath: "mesh/a.meshbin",
        geometrySHA256: EvidenceIntegrity.sha256(of: meshData).description,
        vertexCount: 4,
        faceCount: 2
    )
    let pixelData = try BundleValidationFixture.pixelPayload(
        width: 4,
        height: 3
    )
    let pixelPath = "evidence/frames/\(frameID).pixelbin"
    let depthData = try BundleValidationFixture.depthPayload(
        width: 2,
        height: 2
    )
    let depthPath = "evidence/depth/\(frameID).depthbin"
    let confidenceData = try BundleValidationFixture.confidencePayload(
        width: 2,
        height: 2
    )
    let confidencePath = "evidence/depth/\(frameID).confidencebin"

    let descriptor = BundleValidationFixture.frameDescriptorValue(
        pixelPath: pixelPath,
        pixelByteCount: pixelData.count,
        pixelSHA256: EvidenceIntegrity.sha256(of: pixelData).description,
        imageWidth: 4,
        imageHeight: 3,
        pixelFormatFourCC: 0x3432_3066,
        depthStatus: "captured_scene_depth",
        depth: BundleValidationFixture.depthReferenceValue(
            depthPath: depthPath,
            depthByteCount: depthData.count,
            depthSHA256: EvidenceIntegrity.sha256(of: depthData)
                .description,
            confidencePath: confidencePath,
            confidenceByteCount: confidenceData.count,
            confidenceSHA256: EvidenceIntegrity.sha256(of: confidenceData)
                .description
        )
    )

    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: "mesh/anchors.json",
                data: try BundleValidationFixture.canonical(anchors),
                mediaType: "application/json"
            ),
            (
                path: "mesh/a.meshbin",
                data: meshData,
                mediaType: "application/vnd.htdt.meshbin"
            ),
            (
                path: "evidence/frames/\(frameID).json",
                data: try BundleValidationFixture.canonical(descriptor),
                mediaType: "application/json"
            ),
            (
                path: pixelPath,
                data: pixelData,
                mediaType: "application/vnd.htdt.pixelbin"
            ),
            (
                path: depthPath,
                data: depthData,
                mediaType: "application/vnd.htdt.depthbin"
            ),
            (
                path: confidencePath,
                data: confidenceData,
                mediaType: "application/vnd.htdt.confidencebin"
            ),
        ]
    )

    let report = try BundleDirectoryValidator.validate(root: root)
    #expect(report.valid)
    // 6 evidence payloads + auto-staged foundation set (#194)
    #expect(report.payloadCount == 10)
}
