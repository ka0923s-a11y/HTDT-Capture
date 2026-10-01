import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #169: quality must observe usable geometry, not containers.
/// The store exposes bounded, persistence-time metrics on its snapshot
/// for the quality evaluator to consume.
final class UsableGeometryMetricsTests: XCTestCase {
    private func makeStore(root: URL) throws -> CaptureWorkingSetStore {
        try CaptureWorkingSetStore(rootDirectory: root)
    }

    private func meshPackage(
        geometries: [MeshGeometryPayload]
    ) throws -> MeshEvidencePackage {
        try MeshEvidencePackageBuilder.build(
            snapshots: geometries.map {
                MeshAnchorSnapshot(
                    anchorID: UUID(),
                    captureSessionID: CaptureSessionID(
                        rawValue: UUID(
                            uuidString:
                                "10000000-0000-4000-8000-000000000003"
                        )!
                    ),
                    coordinateSpaceID: CoordinateSpaceID(
                        rawValue: UUID(
                            uuidString:
                                "10000000-0000-4000-8000-000000000004"
                        )!
                    ),
                    worldFromAnchor: .identity,
                    sessionTimestampSeconds: 1,
                    geometry: $0
                )
            }
        )
    }

    private func framePackage(
        depthPayload: Data?
    ) throws -> FrameEvidencePackage {
        let frameID = EvidenceFrameID()
        let pixel = Data([1, 2, 3, 4])
        let depthReference: DepthEvidenceReference?
        if let depthPayload {
            depthReference = try DepthEvidenceReference(
                kind: .discreteSceneDepth,
                depthRelativePath:
                    "evidence/depth/\(frameID).depthbin",
                depthByteCount: depthPayload.count,
                depthSHA256: EvidenceIntegrity.sha256(
                    of: depthPayload
                )
            )
        } else {
            depthReference = nil
        }
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: CaptureSessionID(
                rawValue: UUID(
                    uuidString:
                        "10000000-0000-4000-8000-000000000003"
                )!
            ),
            coordinateSpaceID: CoordinateSpaceID(
                rawValue: UUID(
                    uuidString:
                        "10000000-0000-4000-8000-000000000004"
                )!
            ),
            sessionTimestampSeconds: 1,
            worldFromCamera: .identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [
                    1, 0, 0,
                    0, 1, 0,
                    0, 0, 1,
                ]
            ),
            imageWidth: 1,
            imageHeight: 1,
            pixelFormatFourCC: 0,
            pixelRelativePath:
                "evidence/frames/\(frameID).pixelbin",
            pixelByteCount: pixel.count,
            pixelSHA256: EvidenceIntegrity.sha256(of: pixel),
            depthStatus: depthPayload == nil
                ? .unavailable
                : .capturedDiscrete,
            depth: depthReference
        )
        return try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: depthPayload,
            confidencePayload: nil
        )
    }

    func testZeroFaceMeshAnchorIsNotUsable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        let mesh = try meshPackage(
            geometries: [
                try MeshGeometryPayload(
                    vertices: [Float3(0, 0, 0)],
                    triangleIndices: []
                ),
            ]
        )
        try await store.persistMeshPackage(mesh)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.meshAnchorCount, 1)
        XCTAssertEqual(snapshot.usableMeshAnchorCount, 0)
    }

    func testMeshWithFacesCountsUsableAnchors() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        let mesh = try meshPackage(
            geometries: [
                // One anchor with a real face.
                try MeshGeometryPayload(
                    vertices: [
                        Float3(0, 0, 0),
                        Float3(1, 0, 0),
                        Float3(0, 1, 0),
                    ],
                    triangleIndices: [0, 1, 2]
                ),
                // One anchor with vertices but no faces.
                try MeshGeometryPayload(
                    vertices: [Float3(5, 5, 5)],
                    triangleIndices: []
                ),
            ]
        )
        try await store.persistMeshPackage(mesh)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.meshAnchorCount, 2)
        XCTAssertEqual(snapshot.usableMeshAnchorCount, 1)

        try await store.rollbackCurrentMeshPackage()
        let rolledBack = await store.snapshot()
        XCTAssertNil(rolledBack.meshAnchorCount)
        XCTAssertNil(rolledBack.usableMeshAnchorCount)
    }

    func testAllInvalidDepthMapIsNotUsable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)

        // A structurally valid depth map whose validity mask marks every
        // sample unusable must not satisfy the mesh fallback.
        let allInvalid = try DepthBinaryCodec.encode(
            DepthMapPayload(
                width: 2,
                height: 2,
                valuesMeters: [1.0, 2.0, 3.0, 4.0],
                validityMask: [0, 0, 0, 0]
            )
        )
        try await store.persistFramePackage(
            try framePackage(depthPayload: allInvalid)
        )

        // Zero-depth (no-return) samples are also unusable even with a
        // permissive mask.
        let zeroDepth = try DepthBinaryCodec.encode(
            DepthMapPayload(
                width: 2,
                height: 1,
                valuesMeters: [0, 0],
                validityMask: [1, 1]
            )
        )
        try await store.persistFramePackage(
            try framePackage(depthPayload: zeroDepth)
        )

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.evidenceFrameCount, 2)
        XCTAssertEqual(snapshot.depthEvidenceCount, 2)
        XCTAssertEqual(snapshot.usableDepthSampleCount, 0)
        XCTAssertEqual(snapshot.usableDepthEvidenceCount, 0)
    }

    func testValidDepthMapCountsUsableSamples() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        let depth = try DepthBinaryCodec.encode(
            DepthMapPayload(
                width: 2,
                height: 2,
                valuesMeters: [1.5, 0.0, 2.5, 0.0],
                validityMask: [1, 1, 0, 1]
            )
        )
        try await store.persistFramePackage(
            try framePackage(depthPayload: depth)
        )

        // No-mask payloads treat every finite positive sample as usable.
        let unmasked = try DepthBinaryCodec.encode(
            DepthMapPayload(
                width: 1,
                height: 2,
                valuesMeters: [3.0, 0.0]
            )
        )
        try await store.persistFramePackage(
            try framePackage(depthPayload: unmasked)
        )

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.depthEvidenceCount, 2)
        // 1.5 (masked valid) + 2.5's mask entry is 0 -> excluded;
        // unmasked frame contributes only the positive 3.0 sample.
        XCTAssertEqual(snapshot.usableDepthSampleCount, 2)
        XCTAssertEqual(snapshot.usableDepthEvidenceCount, 2)
    }

    func testUndecodableDepthPayloadContributesNoUsableSamples()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        // Opaque bytes that do not decode as a depthbin remain canonical
        // evidence but carry no usable geometry.
        try await store.persistFramePackage(
            try framePackage(
                depthPayload: Data([7, 8, 9, 10])
            )
        )

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.depthEvidenceCount, 1)
        XCTAssertEqual(snapshot.usableDepthSampleCount, 0)
        XCTAssertEqual(snapshot.usableDepthEvidenceCount, 0)

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }
}
