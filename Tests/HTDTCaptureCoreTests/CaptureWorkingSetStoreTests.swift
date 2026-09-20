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
