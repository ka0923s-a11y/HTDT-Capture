import Foundation
import XCTest
@testable import HTDTCaptureCore

final class MeshEvidencePackageTests: XCTestCase {
    func testBuildProducesDeterministicSchemaBoundMeshPackage() throws {
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
        let firstAnchor = UUID(
            uuidString: "10000000-0000-4000-8000-000000000006"
        )!
        let secondAnchor = UUID(
            uuidString: "10000000-0000-4000-8000-000000000005"
        )!

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
            faceClassifications: [2]
        )

        let snapshots = [
            MeshAnchorSnapshot(
                anchorID: firstAnchor,
                captureSessionID: sessionID,
                coordinateSpaceID: coordinateID,
                worldFromAnchor: .identity,
                sessionTimestampSeconds: 13.0,
                geometry: geometry
            ),
            MeshAnchorSnapshot(
                anchorID: secondAnchor,
                captureSessionID: sessionID,
                coordinateSpaceID: coordinateID,
                worldFromAnchor: .identity,
                sessionTimestampSeconds: 12.5,
                geometry: geometry
            ),
        ]

        let package = try MeshEvidencePackageBuilder.build(
            snapshots: snapshots
        )

        XCTAssertEqual(
            package.index.anchors.map(\.anchorID),
            [
                secondAnchor.uuidString.lowercased(),
                firstAnchor.uuidString.lowercased(),
            ]
        )
        XCTAssertEqual(
            package.geometryFiles.map(\.path),
            [
                "mesh/geometry/\(secondAnchor.uuidString.lowercased()).meshbin",
                "mesh/geometry/\(firstAnchor.uuidString.lowercased()).meshbin",
            ]
        )

        for file in package.geometryFiles {
            XCTAssertEqual(
                file.sha256,
                EvidenceIntegrity.sha256(of: file.data)
            )
            XCTAssertEqual(
                try MeshBinaryCodec.decode(file.data),
                geometry
            )
        }

        let decoded = try JSONDecoder().decode(
            MeshAnchorEvidenceIndex.self,
            from: package.indexData
        )
        XCTAssertEqual(decoded, package.index)
        XCTAssertEqual(decoded.schema, "htdt.capture.mesh-anchors")
        XCTAssertEqual(decoded.schemaVersion, "1.0.0")
        XCTAssertEqual(decoded.anchors[0].vertexCount, 3)
        XCTAssertEqual(decoded.anchors[0].faceCount, 1)
        XCTAssertEqual(
            decoded.anchors[0].geometrySHA256,
            package.geometryFiles[0].sha256
        )
    }

    func testBuildAllowsExplicitEmptyActiveAnchorSet() throws {
        let package = try MeshEvidencePackageBuilder.build(
            snapshots: []
        )

        XCTAssertTrue(package.index.anchors.isEmpty)
        XCTAssertTrue(package.geometryFiles.isEmpty)

        let decoded = try JSONDecoder().decode(
            MeshAnchorEvidenceIndex.self,
            from: package.indexData
        )
        XCTAssertEqual(decoded, package.index)
        XCTAssertEqual(decoded.schema, "htdt.capture.mesh-anchors")
    }

    func testBuildFailsClosedWhenTimestampIsMissing() throws {
        let geometry = try MeshGeometryPayload(
            vertices: [
                Float3(0, 0, 0),
                Float3(1, 0, 0),
                Float3(0, 1, 0),
            ],
            triangleIndices: [0, 1, 2]
        )
        let anchorID = UUID(
            uuidString: "10000000-0000-4000-8000-000000000005"
        )!
        let snapshot = MeshAnchorSnapshot(
            anchorID: anchorID,
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            worldFromAnchor: .identity,
            sessionTimestampSeconds: nil,
            geometry: geometry
        )

        XCTAssertThrowsError(
            try MeshEvidencePackageBuilder.build(
                snapshots: [snapshot]
            )
        ) { error in
            XCTAssertEqual(
                error as? MeshEvidencePackageError,
                .missingSessionTimestamp(anchorID)
            )
        }
    }

    func testBuildRejectsDuplicateAnchorIdentity() throws {
        let geometry = try MeshGeometryPayload(
            vertices: [
                Float3(0, 0, 0),
                Float3(1, 0, 0),
                Float3(0, 1, 0),
            ],
            triangleIndices: [0, 1, 2]
        )
        let anchorID = UUID(
            uuidString: "10000000-0000-4000-8000-000000000005"
        )!
        let snapshot = MeshAnchorSnapshot(
            anchorID: anchorID,
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            worldFromAnchor: .identity,
            sessionTimestampSeconds: 1.0,
            geometry: geometry
        )

        XCTAssertThrowsError(
            try MeshEvidencePackageBuilder.build(
                snapshots: [snapshot, snapshot]
            )
        ) { error in
            XCTAssertEqual(
                error as? MeshEvidencePackageError,
                .duplicateAnchorID(anchorID)
            )
        }
    }
}
