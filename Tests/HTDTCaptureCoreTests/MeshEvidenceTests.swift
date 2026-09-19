import Foundation
import Testing
@testable import HTDTCaptureCore

@Test
func meshBinaryRoundTripPreservesPortableGeometry() throws {
    let geometry = try MeshGeometryPayload(
        vertices: [
            Float3(0, 0, 0),
            Float3(1, 0, 0),
            Float3(0, 1, 0),
        ],
        normals: [
            Float3(0, 0, 1),
            Float3(0, 0, 1),
            Float3(0, 0, 1),
        ],
        triangleIndices: [0, 1, 2],
        faceClassifications: [1]
    )

    let encoded = try MeshBinaryCodec.encode(geometry)
    let decoded = try MeshBinaryCodec.decode(encoded)

    #expect(decoded == geometry)
    #expect(encoded.prefix(8) == Data("HTDTMSH1".utf8))
}

@Test
func meshBinaryRoundTripSupportsNoOptionalChannels() throws {
    let geometry = try MeshGeometryPayload(
        vertices: [
            Float3(0, 0, 0),
            Float3(1, 0, 0),
            Float3(0, 1, 0),
        ],
        triangleIndices: [0, 1, 2]
    )

    let decoded = try MeshBinaryCodec.decode(
        MeshBinaryCodec.encode(geometry)
    )
    #expect(decoded == geometry)
    #expect(decoded.normals == nil)
    #expect(decoded.faceClassifications == nil)
}

@Test
func meshGeometryRejectsOutOfBoundsIndex() {
    #expect(throws: MeshGeometryError.self) {
        _ = try MeshGeometryPayload(
            vertices: [
                Float3(0, 0, 0),
                Float3(1, 0, 0),
                Float3(0, 1, 0),
            ],
            triangleIndices: [0, 1, 3]
        )
    }
}

@Test
func meshCodecRejectsTrailingBytes() throws {
    let geometry = try MeshGeometryPayload(
        vertices: [
            Float3(0, 0, 0),
            Float3(1, 0, 0),
            Float3(0, 1, 0),
        ],
        triangleIndices: [0, 1, 2]
    )
    var encoded = try MeshBinaryCodec.encode(geometry)
    encoded.append(0xff)

    #expect(throws: MeshBinaryCodecError.self) {
        _ = try MeshBinaryCodec.decode(encoded)
    }
}

@Test
func roomPlanProcessedEvidenceKeepsRawLineage() throws {
    let rawHash = try EvidenceSHA256(
        String(repeating: "a", count: 64)
    )
    let processedHash = try EvidenceSHA256(
        String(repeating: "b", count: 64)
    )
    let runtime = CaptureRuntimeProvenance(
        osVersion: "17.0",
        appVersion: "0.1.0",
        appBuild: "test"
    )
    let session = CaptureSessionID()
    let space = CoordinateSpaceID()

    let raw = RoomPlanRawEvidenceDescriptor(
        captureSessionID: session,
        coordinateSpaceID: space,
        relativePath: "roomplan/captured-room-data.json",
        byteCount: 100,
        sha256: rawHash,
        runtime: runtime
    )
    let processed = RoomPlanProcessedEvidenceDescriptor(
        captureSessionID: session,
        coordinateSpaceID: space,
        relativePath: "roomplan/captured-room.json",
        byteCount: 80,
        sha256: processedHash,
        sourceRawSHA256: raw.sha256,
        capturedRoomVersion: "test",
        runtime: runtime
    )

    #expect(processed.sourceRawSHA256 == raw.sha256)
    #expect(processed.captureSessionID == raw.captureSessionID)
    #expect(processed.coordinateSpaceID == raw.coordinateSpaceID)
}
