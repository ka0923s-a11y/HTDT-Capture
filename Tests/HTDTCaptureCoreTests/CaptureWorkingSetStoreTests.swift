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

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.rawRoomPlanDescriptor, raw.descriptor)
        XCTAssertEqual(
            snapshot.processedRoomPlanDescriptor,
            lineage.processed?.descriptor
        )
        XCTAssertEqual(snapshot.meshAnchorCount, 1)
        XCTAssertEqual(
            snapshot.payloadDeclarations.map(\.path),
            [
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
