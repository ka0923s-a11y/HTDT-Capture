import Foundation
import XCTest
@testable import HTDTCaptureCore

final class CaptureWorkingSetStoreTests: XCTestCase {
    func testPersistsRawProcessedAndMeshWithFinalizerDeclarations() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        let sessionID = CaptureSessionID(
            rawValue: UUID(
                uuidString: "10000000-0000-4000-8000-000000000003"
            )!
        )
        let coordinateID = CoordinateSpaceID(
            rawValue: UUID(
                uuidString: "10000000-0000-4000-8000-000000000004"
            )!
        )
        let runtime = CaptureRuntimeProvenance(
            osVersion: "test-os",
            appVersion: "0.1.0",
            appBuild: "test"
        )

        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"raw":true}"#.utf8),
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            runtime: runtime
        )
        try await store.persistRawRoomPlan(raw)

        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data(#"{"processed":true}"#.utf8),
            to: raw
        )
        try await store.persistProcessedRoomPlan(
            try XCTUnwrap(lineage.processed)
        )

        let geometry = try MeshGeometryPayload(
            vertices: [
                Float3(0, 0, 0),
                Float3(1, 0, 0),
                Float3(0, 1, 0),
            ],
            triangleIndices: [0, 1, 2]
        )
        let mesh = try MeshEvidencePackageBuilder.build(
            snapshots: [
                MeshAnchorSnapshot(
                    anchorID: UUID(
                        uuidString:
                            "10000000-0000-4000-8000-000000000005"
                    )!,
                    captureSessionID: sessionID,
                    coordinateSpaceID: coordinateID,
                    worldFromAnchor: .identity,
                    sessionTimestampSeconds: 12.5,
                    geometry: geometry
                ),
            ]
        )
        try await store.persistMeshPackage(mesh)

        let pixel = Data([1, 2, 3, 4])
        let frameID = EvidenceFrameID(
            rawValue: UUID(
                uuidString:
                    "10000000-0000-4000-8000-000000000006"
            )!
        )
        let frameDescriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            sessionTimestampSeconds: 12.5,
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
            depthStatus: .unavailable
        )
        try await store.persistFramePackage(
            try FrameEvidencePackageBuilder.build(
                descriptor: frameDescriptor,
                pixelPayload: pixel,
                depthPayload: nil,
                confidencePayload: nil
            )
        )

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.rawRoomPlanDescriptor, raw.descriptor)
        XCTAssertEqual(
            snapshot.processedRoomPlanDescriptor,
            lineage.processed?.descriptor
        )
        XCTAssertEqual(snapshot.meshAnchorCount, 1)
        XCTAssertEqual(snapshot.evidenceFrameCount, 1)
        XCTAssertEqual(snapshot.depthEvidenceCount, 0)
        XCTAssertEqual(
            snapshot.evidenceFrameRefs,
            [
                "path:evidence/frames/"
                    + frameID.description
                    + ".json",
            ]
        )
        XCTAssertEqual(snapshot.captureSessionIDs, [sessionID])
        XCTAssertEqual(snapshot.coordinateSpaceIDs, [coordinateID])
        XCTAssertEqual(
            snapshot.payloadDeclarations.map(\.path),
            [
                "evidence/frames/10000000-0000-4000-8000-000000000006.json",
                "evidence/frames/10000000-0000-4000-8000-000000000006.pixelbin",
                "mesh/anchors.json",
                "mesh/geometry/10000000-0000-4000-8000-000000000005.meshbin",
                "roomplan/captured-room-data.json",
                "roomplan/captured-room.json",
            ]
        )

        let byPath = Dictionary(
            uniqueKeysWithValues: snapshot.payloadDeclarations.map {
                ($0.path, $0)
            }
        )
        XCTAssertEqual(
            byPath["roomplan/captured-room.json"]?.sourceRefs,
            ["sha256:\(raw.descriptor.sha256.description)"]
        )
        XCTAssertEqual(
            byPath["mesh/anchors.json"]?.sourceRefs,
            [
                "path:mesh/geometry/10000000-0000-4000-8000-000000000005.meshbin"
            ]
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        "roomplan/captured-room-data.json"
                    )
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("mesh/anchors.json")
                    .path
            )
        )
    }

    func testProcessedRoomPlanCannotBePersistedBeforeRaw() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data("raw".utf8),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            runtime: CaptureRuntimeProvenance(
                osVersion: "test",
                appVersion: "test",
                appBuild: "test"
            )
        )
        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data("processed".utf8),
            to: raw
        )
        let processed = try XCTUnwrap(lineage.processed)

        do {
            try await store.persistProcessedRoomPlan(processed)
            XCTFail("expected processed-before-raw rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .processedRoomPlanRequiresRaw
            )
        }
    }

    func testExactRoomPlanCompletionReplayIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        let sessionID = CaptureSessionID()
        let coordinateID = CoordinateSpaceID()
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"room":"same"}"#.utf8),
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "test",
                appVersion: "test",
                appBuild: "test"
            )
        )
        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data(#"{"processed":"same"}"#.utf8),
            to: raw
        )
        let processed = try XCTUnwrap(lineage.processed)

        try await store.persistRawRoomPlan(raw)
        try await store.persistRawRoomPlan(raw)
        try await store.persistProcessedRoomPlan(processed)
        try await store.persistProcessedRoomPlan(processed)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.rawRoomPlanDescriptor, raw.descriptor)
        XCTAssertEqual(
            snapshot.processedRoomPlanDescriptor,
            processed.descriptor
        )
        XCTAssertEqual(
            snapshot.payloadDeclarations.filter {
                $0.path == RoomPlanEvidenceArtifactBuilder.rawPath
                    || $0.path
                        == RoomPlanEvidenceArtifactBuilder.processedPath
            }.count,
            2
        )
    }

    func testConcurrentExactRoomPlanCompletionReplayIsIdempotent()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        let sessionID = CaptureSessionID()
        let coordinateID = CoordinateSpaceID()
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(repeating: 0x52, count: 512 * 1024),
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "test",
                appVersion: "test",
                appBuild: "test"
            )
        )
        let processed = try XCTUnwrap(
            RoomPlanEvidenceArtifactBuilder.attachProcessed(
                data: Data(repeating: 0x50, count: 512 * 1024),
                to: raw
            ).processed
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await store.persistRawRoomPlan(raw)
                }
            }
            try await group.waitForAll()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await store.persistProcessedRoomPlan(processed)
                }
            }
            try await group.waitForAll()
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.rawRoomPlanDescriptor, raw.descriptor)
        XCTAssertEqual(
            snapshot.processedRoomPlanDescriptor,
            processed.descriptor
        )
        XCTAssertEqual(
            snapshot.payloadDeclarations.filter {
                $0.path == RoomPlanEvidenceArtifactBuilder.rawPath
                    || $0.path
                        == RoomPlanEvidenceArtifactBuilder.processedPath
            }.count,
            2
        )
    }

    func testFramePersistenceRecoversFromPartialCanonicalFilesAndDropsConflictingPreview()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let sessionID = CaptureSessionID()
        let coordinateID = CoordinateSpaceID()
        let frameID = EvidenceFrameID()
        let pixel = Data([1, 2, 3, 4, 5, 6])
        let depth = Data([7, 8, 9, 10])
        let preview = Data([11, 12, 13])

        let depthReference = try DepthEvidenceReference(
            kind: .discreteSceneDepth,
            depthRelativePath:
                "evidence/depth/\(frameID).depthbin",
            depthByteCount: depth.count,
            depthSHA256: EvidenceIntegrity.sha256(of: depth)
        )
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            sessionTimestampSeconds: 12.0,
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
            depthStatus: .capturedDiscrete,
            depth: depthReference
        )
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: depth,
            confidencePayload: nil,
            previewPayload: preview
        )
        let writer = try AtomicCaptureFileWriter(
            rootDirectory: root
        )

        // Simulate a previous interrupted end-save that already committed
        // some byte-identical canonical payloads.
        try await writer.write(
            pixel,
            to: try CaptureStorePath(
                descriptor.pixelRelativePath
            )
        )
        try await writer.write(
            depth,
            to: try CaptureStorePath(
                depthReference.depthRelativePath
            )
        )

        // A stale/conflicting preview must not invalidate canonical evidence.
        let previewPath = try XCTUnwrap(package.preview?.path)
        try await writer.write(
            Data([99, 98, 97]),
            to: try CaptureStorePath(previewPath)
        )

        try await store.persistFramePackage(package)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.evidenceFrameCount, 1)
        XCTAssertEqual(snapshot.depthEvidenceCount, 1)
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == package.descriptorPath
            }
        )
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == descriptor.pixelRelativePath
            }
        )
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == depthReference.depthRelativePath
            }
        )
        XCTAssertFalse(
            snapshot.payloadDeclarations.contains {
                $0.path == previewPath
            }
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(previewPath).path
            )
        )

        let quality = await store.evaluateQuality()
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testConcurrentExactFrameReplayCountsOneEvidenceFrame()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let sessionID = CaptureSessionID()
        let coordinateID = CoordinateSpaceID()
        let frameID = EvidenceFrameID()
        let pixel = Data(repeating: 0x31, count: 64 * 1024)
        let depth = Data(repeating: 0x42, count: 32 * 1024)
        let depthReference = try DepthEvidenceReference(
            kind: .discreteSceneDepth,
            depthRelativePath:
                "evidence/depth/\(frameID).depthbin",
            depthByteCount: depth.count,
            depthSHA256: EvidenceIntegrity.sha256(of: depth)
        )
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            sessionTimestampSeconds: 18.0,
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
            depthStatus: .capturedDiscrete,
            depth: depthReference
        )
        let package = try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: depth,
            confidencePayload: nil
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await store.persistFramePackage(package)
                }
            }
            try await group.waitForAll()
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.evidenceFrameCount, 1)
        XCTAssertEqual(snapshot.depthEvidenceCount, 1)
        XCTAssertEqual(
            snapshot.payloadDeclarations.filter {
                $0.path == package.descriptorPath
                    || $0.path == descriptor.pixelRelativePath
                    || $0.path == depthReference.depthRelativePath
            }.count,
            3
        )
    }

    func testMeshPersistenceFailureRollsBackPartialFilesAndCanRetry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let sessionID = CaptureSessionID()
        let coordinateID = CoordinateSpaceID()
        let geometry = try MeshGeometryPayload(
            vertices: [
                Float3(0, 0, 0),
                Float3(1, 0, 0),
                Float3(0, 1, 0),
            ],
            triangleIndices: [0, 1, 2]
        )
        let mesh = try MeshEvidencePackageBuilder.build(
            snapshots: [
                MeshAnchorSnapshot(
                    anchorID: UUID(
                        uuidString:
                            "10000000-0000-4000-8000-000000000105"
                    )!,
                    captureSessionID: sessionID,
                    coordinateSpaceID: coordinateID,
                    worldFromAnchor: .identity,
                    sessionTimestampSeconds: 1.0,
                    geometry: geometry
                ),
                MeshAnchorSnapshot(
                    anchorID: UUID(
                        uuidString:
                            "10000000-0000-4000-8000-000000000106"
                    )!,
                    captureSessionID: sessionID,
                    coordinateSpaceID: coordinateID,
                    worldFromAnchor: .identity,
                    sessionTimestampSeconds: 1.0,
                    geometry: geometry
                ),
            ]
        )
        XCTAssertEqual(mesh.geometryFiles.count, 2)

        let stalePath = mesh.geometryFiles[1].path
        let externalWriter = try AtomicCaptureFileWriter(
            rootDirectory: root
        )
        try await externalWriter.write(
            Data("stale-partial-mesh".utf8),
            to: try CaptureStorePath(stalePath)
        )

        do {
            try await store.persistMeshPackage(mesh)
            XCTFail("expected stale partial mesh to reject first write")
        } catch {
            // The exact filesystem error is intentionally not part of the
            // store contract; rollback and retryability are the authority.
        }

        let meshPaths =
            mesh.geometryFiles.map(\.path)
            + [MeshEvidencePackage.indexPath]
        for path in meshPaths {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "partial mesh path should be rolled back: \(path)"
            )
        }

        let failedSnapshot = await store.snapshot()
        XCTAssertNil(failedSnapshot.meshAnchorCount)
        XCTAssertFalse(
            failedSnapshot.payloadDeclarations.contains {
                $0.path.hasPrefix("mesh/")
            }
        )

        try await store.persistMeshPackage(mesh)

        let recoveredSnapshot = await store.snapshot()
        XCTAssertEqual(recoveredSnapshot.meshAnchorCount, 2)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(MeshEvidencePackage.indexPath)
                    .path
            )
        )
    }

    func testRejectsMeshPackageWhenIndexBytesDoNotMatchTypedIndex() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        let valid = try MeshEvidencePackageBuilder.build(
            snapshots: []
        )
        let invalid = MeshEvidencePackage(
            index: valid.index,
            indexData: Data(#"{"schema":"wrong"}"#.utf8),
            geometryFiles: valid.geometryFiles
        )

        do {
            try await store.persistMeshPackage(invalid)
            XCTFail("expected invalid mesh package rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .invalidMeshPackage)
        }
    }
}


extension CaptureWorkingSetStoreTests {
    func testRejectsMeshFromDifferentCoordinateAuthority() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let sessionID = CaptureSessionID()
        let roomCoordinateID = CoordinateSpaceID()
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data("raw".utf8),
            captureSessionID: sessionID,
            coordinateSpaceID: roomCoordinateID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "test",
                appVersion: "test",
                appBuild: "test"
            )
        )
        try await store.persistRawRoomPlan(raw)

        let geometry = try MeshGeometryPayload(
            vertices: [
                Float3(0, 0, 0),
                Float3(1, 0, 0),
                Float3(0, 1, 0),
            ],
            triangleIndices: [0, 1, 2]
        )
        let mesh = try MeshEvidencePackageBuilder.build(
            snapshots: [
                MeshAnchorSnapshot(
                    anchorID: UUID(),
                    captureSessionID: sessionID,
                    coordinateSpaceID: CoordinateSpaceID(),
                    worldFromAnchor: .identity,
                    sessionTimestampSeconds: 1.0,
                    geometry: geometry
                ),
            ]
        )

        do {
            try await store.persistMeshPackage(mesh)
            XCTFail("expected coordinate authority rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .authorityMismatch)
        }
    }
}


extension CaptureWorkingSetStoreTests {
    func testDiscardRemovesOnlyOwnedIncompleteWorkingRevision()
        async throws
    {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: base)
        }

        let identity = CaptureWorkingSetIdentity()
        let root = base
            .appendingPathComponent(
                "HTDTCapture",
                isDirectory: true
            )
            .appendingPathComponent(
                "working",
                isDirectory: true
            )
            .appendingPathComponent(
                identity.captureRevisionID.description,
                isDirectory: true
            )
        let store = try CaptureWorkingSetStore(
            identity: identity,
            rootDirectory: root
        )
        try Data("incomplete".utf8).write(
            to: root.appendingPathComponent("sentinel.bin")
        )

        try await store.discardIncompleteRevision()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.path)
        )
    }

    func testDiscardRejectsUnexpectedDirectoryShape()
        async throws
    {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: base)
        }

        let identity = CaptureWorkingSetIdentity()
        let root = base
            .appendingPathComponent(
                "not-working",
                isDirectory: true
            )
            .appendingPathComponent(
                identity.captureRevisionID.description,
                isDirectory: true
            )
        let store = try CaptureWorkingSetStore(
            identity: identity,
            rootDirectory: root
        )

        do {
            try await store.discardIncompleteRevision()
            XCTFail("expected unsafe discard path rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .unsafeDiscardPath)
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.path)
        )
    }
}
