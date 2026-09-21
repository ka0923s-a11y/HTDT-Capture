import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #202: session/coordinate identity is part of the logical
/// persistence commit. A failed durable write must leave the working
/// set's authority exactly as it was — no ghost binding — and a
/// successful commit publishes the binding exactly once alongside its
/// durable evidence.
final class AuthorityCommitBindingTests: XCTestCase {
    private func makeFoundation(
        context: CaptureSessionContext = CaptureSessionContext()
    ) throws -> CaptureSessionFoundationPackage {
        try CaptureSessionFoundationPackageBuilder.build(
            context: context,
            capabilities: CaptureCapabilityMatrix(
                roomPlanSupported: true,
                worldTrackingSupported: true,
                sceneReconstructionSupported: true,
                sceneDepthSupported: true
            ),
            configurationProfile: CaptureConfigurationProfile(
                captureMode: .roomPlanMesh,
                worldAlignment: "gravity",
                sceneReconstruction: "mesh"
            ),
            startedAtUTC: "2026-09-20T01:00:00Z",
            device: try CaptureDeviceDocument(
                osVersion: "iOS 20.0",
                hardwareModel: "iPhone99,1",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
    }

    private func makeFramePackage(
        sessionID: CaptureSessionID,
        spaceID: CoordinateSpaceID
    ) throws -> FrameEvidencePackage {
        let frameID = EvidenceFrameID()
        let pixel = Data([1, 2, 3, 4])
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: spaceID,
            sessionTimestampSeconds: 2,
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
        return try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: nil,
            confidencePayload: nil
        )
    }

    private func makeMeshPackage(
        sessionID: CaptureSessionID,
        spaceID: CoordinateSpaceID
    ) throws -> MeshEvidencePackage {
        try MeshEvidencePackageBuilder.build(
            snapshots: [
                MeshAnchorSnapshot(
                    anchorID: UUID(),
                    captureSessionID: sessionID,
                    coordinateSpaceID: spaceID,
                    worldFromAnchor: .identity,
                    sessionTimestampSeconds: 3,
                    geometry: try MeshGeometryPayload(
                        vertices: [
                            Float3(0, 0, 0),
                            Float3(1, 0, 0),
                            Float3(0, 1, 0),
                        ],
                        triangleIndices: [0, 1, 2]
                    )
                ),
            ]
        )
    }

    private func makeAnnotationPackage(
        space: CoordinateSpaceID
    ) throws -> AnnotationEvidencePackage {
        try AnnotationEvidencePackageBuilder.build(
            entities: [
                try CaptureAnnotationEntity(
                    type: .referencePoint,
                    coordinateSpaceID: space,
                    worldFromAnnotation: .identity,
                    referencePointSemantics: .userReferencePoint,
                    label: "note",
                    provenanceClass: .userAnnotation,
                    placement: PlacementProvenance(
                        method: .manualNumeric
                    )
                ),
            ]
        )
    }

    private func makeMeasurementPackage(
        space: CoordinateSpaceID
    ) throws -> MeasurementEvidencePackage {
        try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: "wall_length",
                    value: .scalar(4.2),
                    unit: .meter,
                    acquisitionMethod: .laserDistanceMeter,
                    userAttestation: .attested,
                    provenanceClass: .userAttestedMeasurement
                ),
            ]
        )
    }

    private func makeVectorMeasurementPackage(
        space: CoordinateSpaceID
    ) throws -> MeasurementEvidencePackage {
        try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: "anchor_point",
                    value: .vector3(1, 2, 3),
                    unit: .meter,
                    coordinateSpaceID: space,
                    acquisitionMethod: .laserDistanceMeter,
                    userAttestation: .attested,
                    provenanceClass: .userAttestedMeasurement
                ),
            ]
        )
    }

    /// A failed initial foundation write must not bind the proposed
    /// session/coordinate authority: the retry path must accept a
    /// different valid foundation instead of failing on a ghost
    /// mismatch.
    func testFailedFoundationWriteLeavesAuthorityUnbound() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let writer = try AtomicCaptureFileWriter(rootDirectory: root)

        let contextA = CaptureSessionContext()
        let packageA = try makeFoundation(context: contextA)

        // Pre-seed conflicting bytes at the third write position so the
        // batch fails after two files were created and must roll back.
        let conflictBytes = Data("conflicting-device".utf8)
        try await writer.write(
            conflictBytes,
            to: try CaptureStorePath(
                CaptureSessionFoundationPackage.devicePath
            )
        )

        do {
            try await store.persistSessionFoundation(packageA)
            XCTFail("expected conflicting foundation bytes rejection")
        } catch let error as CaptureFileWriterError {
            guard case .alreadyExists = error else {
                XCTFail("unexpected writer error: \(error)")
                return
            }
        }

        // No ghost authority and no partial declarations survive.
        let failed = await store.snapshot()
        XCTAssertTrue(failed.captureSessionIDs.isEmpty)
        XCTAssertTrue(failed.coordinateSpaceIDs.isEmpty)
        XCTAssertFalse(
            failed.payloadDeclarations.contains {
                $0.path.hasPrefix("session/")
            }
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        CaptureSessionFoundationPackage.capabilitiesPath
                    )
                    .path
            )
        )

        // A retry with a different valid foundation succeeds.
        try await writer.removeIfPresent(
            try CaptureStorePath(
                CaptureSessionFoundationPackage.devicePath
            )
        )
        let contextB = CaptureSessionContext()
        let packageB = try makeFoundation(context: contextB)
        try await store.persistSessionFoundation(packageB)

        let recovered = await store.snapshot()
        XCTAssertEqual(
            recovered.captureSessionIDs,
            [contextB.captureSessionID]
        )
        XCTAssertEqual(
            recovered.coordinateSpaceIDs,
            [contextB.coordinateSpaceID]
        )
    }

    /// The first frame write carries session/coordinate authority: a
    /// mid-batch failure must not leave that authority bound.
    func testFailedFirstFrameWriteLeavesAuthorityUnbound() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let writer = try AtomicCaptureFileWriter(rootDirectory: root)

        let sessionID = CaptureSessionID()
        let spaceID = CoordinateSpaceID()
        let package = try makeFramePackage(
            sessionID: sessionID,
            spaceID: spaceID
        )

        // Conflict at the descriptor path — the batch's last write — so
        // the pixel payload is created and then rolled back.
        try await writer.write(
            Data("conflicting-descriptor".utf8),
            to: try CaptureStorePath(package.descriptorPath)
        )

        do {
            try await store.persistFramePackage(package)
            XCTFail("expected conflicting frame bytes rejection")
        } catch let error as CaptureFileWriterError {
            guard case .alreadyExists = error else {
                XCTFail("unexpected writer error: \(error)")
                return
            }
        }

        let failed = await store.snapshot()
        XCTAssertTrue(failed.captureSessionIDs.isEmpty)
        XCTAssertTrue(failed.coordinateSpaceIDs.isEmpty)
        XCTAssertEqual(failed.evidenceFrameCount, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        package.descriptor.pixelRelativePath
                    )
                    .path
            )
        )

        // A different authority can still win the revision afterwards.
        let context = CaptureSessionContext()
        try await store.persistSessionFoundation(
            try makeFoundation(context: context)
        )
        let recovered = await store.snapshot()
        XCTAssertEqual(
            recovered.captureSessionIDs,
            [context.captureSessionID]
        )
        XCTAssertEqual(
            recovered.coordinateSpaceIDs,
            [context.coordinateSpaceID]
        )
    }

    /// A failed first mesh write must not establish coordinate
    /// authority that was never durably committed.
    func testFailedFirstMeshWriteLeavesAuthorityUnbound() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let writer = try AtomicCaptureFileWriter(rootDirectory: root)

        let sessionID = CaptureSessionID()
        let spaceID = CoordinateSpaceID()
        let package = try makeMeshPackage(
            sessionID: sessionID,
            spaceID: spaceID
        )

        try await writer.write(
            Data("conflicting-index".utf8),
            to: try CaptureStorePath(MeshEvidencePackage.indexPath)
        )

        do {
            try await store.persistMeshPackage(package)
            XCTFail("expected conflicting mesh bytes rejection")
        } catch let error as CaptureFileWriterError {
            guard case .alreadyExists = error else {
                XCTFail("unexpected writer error: \(error)")
                return
            }
        }

        let failed = await store.snapshot()
        XCTAssertTrue(failed.captureSessionIDs.isEmpty)
        XCTAssertTrue(failed.coordinateSpaceIDs.isEmpty)
        XCTAssertNil(failed.meshAnchorCount)

        let context = CaptureSessionContext()
        try await store.persistSessionFoundation(
            try makeFoundation(context: context)
        )
        let recovered = await store.snapshot()
        XCTAssertEqual(
            recovered.coordinateSpaceIDs,
            [context.coordinateSpaceID]
        )
    }

    /// A failed paired annotation+measurement write must not bind the
    /// collection's coordinate space.
    func testFailedAnnotationTransactionLeavesSpaceUnbound()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let writer = try AtomicCaptureFileWriter(rootDirectory: root)

        let spaceA = CoordinateSpaceID()
        try await writer.write(
            Data("conflicting-measurements".utf8),
            to: try CaptureStorePath(
                MeasurementEvidencePackage.path
            )
        )

        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try makeAnnotationPackage(
                    space: spaceA
                ),
                measurementPackage: try makeMeasurementPackage(
                    space: spaceA
                )
            )
            XCTFail("expected conflicting measurement bytes rejection")
        } catch let error as CaptureFileWriterError {
            guard case .alreadyExists = error else {
                XCTFail("unexpected writer error: \(error)")
                return
            }
        }

        let failed = await store.snapshot()
        XCTAssertTrue(failed.coordinateSpaceIDs.isEmpty)
        XCTAssertFalse(
            failed.payloadDeclarations.contains {
                $0.path == AnnotationEvidencePackage.path
                    || $0.path == MeasurementEvidencePackage.path
            }
        )

        // Retrying with a different space must not hit a ghost
        // authority mismatch.
        try await writer.removeIfPresent(
            try CaptureStorePath(
                MeasurementEvidencePackage.path
            )
        )
        let spaceB = CoordinateSpaceID()
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try makeAnnotationPackage(
                space: spaceB
            ),
            measurementPackage: try makeMeasurementPackage(
                space: spaceB
            )
        )
        let recovered = await store.snapshot()
        XCTAssertEqual(recovered.coordinateSpaceIDs, [spaceB])
    }

    /// The standalone single-package paths follow the same rule: no
    /// durable commit, no coordinate binding.
    func testFailedSinglePackageWritesLeaveSpaceUnbound() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let writer = try AtomicCaptureFileWriter(rootDirectory: root)

        let spaceA = CoordinateSpaceID()
        try await writer.write(
            Data("conflicting-entities".utf8),
            to: try CaptureStorePath(
                AnnotationEvidencePackage.path
            )
        )

        do {
            try await store.persistAnnotationPackage(
                try makeAnnotationPackage(space: spaceA)
            )
            XCTFail("expected conflicting annotation bytes rejection")
        } catch let error as CaptureFileWriterError {
            guard case .alreadyExists = error else {
                XCTFail("unexpected writer error: \(error)")
                return
            }
        }

        try await writer.write(
            Data("conflicting-measurements".utf8),
            to: try CaptureStorePath(
                MeasurementEvidencePackage.path
            )
        )
        do {
            try await store.persistMeasurementPackage(
                try makeVectorMeasurementPackage(space: spaceA)
            )
            XCTFail("expected conflicting measurement bytes rejection")
        } catch let error as CaptureFileWriterError {
            guard case .alreadyExists = error else {
                XCTFail("unexpected writer error: \(error)")
                return
            }
        }

        let failed = await store.snapshot()
        XCTAssertTrue(failed.coordinateSpaceIDs.isEmpty)

        try await writer.removeIfPresent(
            try CaptureStorePath(AnnotationEvidencePackage.path)
        )
        try await writer.removeIfPresent(
            try CaptureStorePath(MeasurementEvidencePackage.path)
        )
        let spaceB = CoordinateSpaceID()
        try await store.persistAnnotationPackage(
            try makeAnnotationPackage(space: spaceB)
        )
        try await store.persistMeasurementPackage(
            try makeVectorMeasurementPackage(space: spaceB)
        )
        let recovered = await store.snapshot()
        XCTAssertEqual(recovered.coordinateSpaceIDs, [spaceB])
    }

    /// Successful persistence publishes the authority exactly once with
    /// the durable evidence, and integrity verification agrees.
    func testSuccessfulFoundationPublishesAuthorityOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let context = CaptureSessionContext()
        try await store.persistSessionFoundation(
            try makeFoundation(context: context)
        )

        let snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.captureSessionIDs,
            [context.captureSessionID]
        )
        XCTAssertEqual(
            snapshot.coordinateSpaceIDs,
            [context.coordinateSpaceID]
        )
        XCTAssertEqual(
            snapshot.payloadDeclarations
                .filter { $0.path.hasPrefix("session/") }
                .count,
            4
        )
    }

    /// Two reentrant transactions proposing different authorities can
    /// race the durable commit. Exactly one may win; the loser's
    /// failure must never roll back or overwrite the committed
    /// authority (issue #202).
    func testReentrantConflictingFoundationsPublishExactlyOneAuthority()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let contextA = CaptureSessionContext()
        let contextB = CaptureSessionContext()
        let packageA = try makeFoundation(context: contextA)
        let packageB = try makeFoundation(context: contextB)

        var errors: [Error] = []
        await withTaskGroup(of: Error?.self) { group in
            for package in [packageA, packageB] {
                group.addTask {
                    do {
                        try await store
                            .persistSessionFoundation(package)
                        return nil
                    } catch {
                        return error
                    }
                }
            }
            for await error in group {
                if let error {
                    errors.append(error)
                }
            }
        }

        let snapshot = await store.snapshot()
        // Exactly one transaction committed; the snapshot reports only
        // that authority — never a mixture or a loser's identity.
        let committedIsA =
            snapshot.captureSessionIDs == [contextA.captureSessionID]
            && snapshot.coordinateSpaceIDs
                == [contextA.coordinateSpaceID]
        let committedIsB =
            snapshot.captureSessionIDs == [contextB.captureSessionID]
            && snapshot.coordinateSpaceIDs
                == [contextB.coordinateSpaceID]
        XCTAssertTrue(
            committedIsA || committedIsB,
            "snapshot must report exactly one committed authority"
        )
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(
            snapshot.payloadDeclarations
                .filter { $0.path.hasPrefix("session/") }
                .count,
            4
        )

        // The committed authority is durable and internally consistent:
        // a further conflicting proposal still fails closed.
        do {
            let loser = committedIsA ? packageB : packageA
            try await store.persistSessionFoundation(loser)
            XCTFail("expected committed-authority rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .authorityMismatch)
        }
    }
}
