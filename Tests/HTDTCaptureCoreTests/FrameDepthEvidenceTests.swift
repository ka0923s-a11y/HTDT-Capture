import Foundation
import Testing
@testable import HTDTCaptureCore

@Test
func evidenceIntegrityMatchesKnownSHA256Vector() {
    let digest = EvidenceIntegrity.sha256(
        of: Data("abc".utf8)
    )
    #expect(
        digest.description
            == "ba7816bf8f01cfea414140de5dae2223"
                + "b00361a396177a9cb410ff61f20015ad"
    )
}

@Test
func packedPixelBufferRoundTripPreservesPlanesAndExcludesPadding() throws {
    let luma = try PackedPixelPlane(
        width: 4,
        height: 2,
        sourceBytesPerRow: 8,
        packedBytesPerRow: 4,
        bytes: Data([
            1, 2, 3, 4,
            5, 6, 7, 8,
        ])
    )
    let chroma = try PackedPixelPlane(
        width: 2,
        height: 1,
        sourceBytesPerRow: 8,
        packedBytesPerRow: 4,
        bytes: Data([9, 10, 11, 12])
    )
    let payload = try PackedPixelBuffer(
        width: 4,
        height: 2,
        pixelFormatFourCC: 0x34323066,
        planes: [luma, chroma]
    )

    let encoded = try PixelBufferBinaryCodec.encode(payload)
    let decoded = try PixelBufferBinaryCodec.decode(encoded)

    #expect(decoded == payload)
    #expect(!encoded.contains(0xee))
    #expect(decoded.planes[0].sourceBytesPerRow == 8)
    #expect(decoded.planes[0].bytes.count == 8)
}

@Test
func pixelCodecRejectsTrailingBytes() throws {
    let plane = try PackedPixelPlane(
        width: 2,
        height: 1,
        sourceBytesPerRow: 2,
        packedBytesPerRow: 2,
        bytes: Data([1, 2])
    )
    let payload = try PackedPixelBuffer(
        width: 2,
        height: 1,
        pixelFormatFourCC: 1,
        planes: [plane]
    )
    var encoded = try PixelBufferBinaryCodec.encode(payload)
    encoded.append(0xff)

    #expect(throws: PixelBufferBinaryCodecError.self) {
        _ = try PixelBufferBinaryCodec.decode(encoded)
    }
}

@Test
func depthRoundTripPreservesExplicitInvalidity() throws {
    let payload = try DepthMapPayload(
        width: 2,
        height: 2,
        valuesMeters: [1, 0, 2.5, 3],
        validityMask: [1, 0, 1, 1]
    )

    let encoded = try DepthBinaryCodec.encode(payload)
    let decoded = try DepthBinaryCodec.decode(encoded)

    #expect(decoded == payload)
}

@Test
func confidenceRoundTripPreservesRawConfidenceCodes() throws {
    let payload = try ConfidenceMapPayload(
        width: 2,
        height: 2,
        values: [0, 1, 2, 2]
    )

    let decoded = try ConfidenceBinaryCodec.decode(
        ConfidenceBinaryCodec.encode(payload)
    )
    #expect(decoded == payload)
}

@Test
func depthModelRejectsNonFiniteTransportValues() {
    #expect(throws: DepthEvidenceError.self) {
        _ = try DepthMapPayload(
            width: 1,
            height: 1,
            valuesMeters: [.nan]
        )
    }
}

@Test
func frameDescriptorKeepsExplicitDepthStatusAndLineage() throws {
    let pixelHash = try EvidenceSHA256(
        String(repeating: "a", count: 64)
    )
    let depthHash = try EvidenceSHA256(
        String(repeating: "b", count: 64)
    )
    let confidenceHash = try EvidenceSHA256(
        String(repeating: "c", count: 64)
    )
    let depth = DepthEvidenceReference(
        kind: .discreteSceneDepth,
        depthRelativePath: "evidence/depth/frame.depthbin",
        depthByteCount: 64,
        depthSHA256: depthHash,
        confidenceRelativePath: "evidence/depth/frame.confidencebin",
        confidenceByteCount: 32,
        confidenceSHA256: confidenceHash
    )
    let descriptor = FrameEvidenceDescriptor(
        captureSessionID: CaptureSessionID(),
        coordinateSpaceID: CoordinateSpaceID(),
        sessionTimestampSeconds: 1.25,
        worldFromCamera: .identity,
        intrinsics: try CameraIntrinsics3x3(values: [
            1, 0, 0,
            0, 1, 0,
            0, 0, 1,
        ]),
        imageWidth: 1920,
        imageHeight: 1440,
        pixelFormatFourCC: 0x34323066,
        pixelRelativePath: "evidence/frames/frame.pixelbin",
        pixelByteCount: 128,
        pixelSHA256: pixelHash,
        depthStatus: .capturedDiscrete,
        depth: depth
    )

    #expect(descriptor.depthStatus == .capturedDiscrete)
    #expect(descriptor.depth?.kind == .discreteSceneDepth)
    #expect(descriptor.depth?.depthSHA256 == depthHash)
    #expect(descriptor.depth?.confidenceSHA256 == confidenceHash)
}
