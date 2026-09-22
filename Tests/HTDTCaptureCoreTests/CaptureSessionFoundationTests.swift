import Foundation
import XCTest
@testable import HTDTCaptureCore

final class CaptureSessionFoundationTests: XCTestCase {
    func testSessionFoundationPersistsExactConfigurationAuthority() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let capabilities = CaptureCapabilityMatrix(
            roomPlanSupported: true,
            worldTrackingSupported: true,
            sceneReconstructionSupported: true,
            sceneDepthSupported: true,
            smoothedSceneDepthSupported: true,
            highResolutionFrameSupported: false,
            combinedRoomPlanSceneDepthVerified: nil,
            sameSessionDepthAfterRoomPlanStopVerified: nil
        )
        let profile = CaptureConfigurationProfile(
            captureMode: .roomPlanMesh,
            worldAlignment: "gravity",
            planeDetection: ["vertical", "horizontal"],
            sceneReconstruction: "mesh_with_classification",
            frameSemantics: ["scene_depth"],
            videoFormat: VideoFormatDescriptor(
                width: 1920,
                height: 1440,
                framesPerSecond: 60
            ),
            autofocusEnabled: true,
            roomPlanOptions: [:]
        )
        let package =
            try CaptureSessionFoundationPackageBuilder.build(
                context: context,
                capabilities: capabilities,
                configurationProfile: profile,
                startedAtUTC: "2026-09-20T01:00:00Z",
                device: try CaptureDeviceDocument(
                    osVersion: "iOS 20.0",
                    hardwareModel: "iPhone99,1",
                    appVersion: "0.1.0",
                    appBuild: "1"
                )
            )

        XCTAssertEqual(
            package.configuration.planeDetection,
            ["horizontal", "vertical"]
        )
        XCTAssertEqual(
            package.session.configurationRef,
            "session/capture-configuration.json"
        )
        XCTAssertEqual(
            package.session.timingRef,
            "session/timing.json"
        )
        XCTAssertEqual(package.device.hardwareModel, "iPhone99,1")
        let configurationJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: package.configurationData
            ) as? [String: Any]
        )
        let video = try XCTUnwrap(
            configurationJSON["video_format"]
                as? [String: Any]
        )
        XCTAssertEqual(
            video["frames_per_second"] as? Int,
            60
        )
        XCTAssertNil(video["framesPerSecond"])

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        try await store.persistSessionFoundation(package)
        let timing = try CaptureTimingPackageBuilder.build(
            start: try CaptureTimingCorrelation(
                monotonicSeconds: 1.0,
                utc: "2026-09-20T01:00:00Z",
                method: "fixture"
            ),
            end: try CaptureTimingCorrelation(
                monotonicSeconds: 5.0,
                utc: "2026-09-20T01:00:04Z",
                method: "fixture"
            )
        )
        try await store.persistTimingPackage(timing)

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
            snapshot.payloadDeclarations.map(\.path),
            [
                "session/capabilities.json",
                "session/capture-configuration.json",
                "session/capture-session.json",
                "session/device.json",
                "session/revision-state.json",
                "session/timing.json",
            ]
        )

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                requireCompletedRoomPlan: false,
                minimumActiveMeshAnchors: 0,
                minimumEvidenceFrames: 0
            )
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testSessionFoundationTamperFailsIntegrityPreflight() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let package =
            try CaptureSessionFoundationPackageBuilder.build(
                context: context,
                capabilities: CaptureCapabilityMatrix(
                    roomPlanSupported: true,
                    worldTrackingSupported: true,
                    sceneReconstructionSupported: true,
                    sceneDepthSupported: false
                ),
                configurationProfile:
                    CaptureConfigurationProfile(
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
        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        try await store.persistSessionFoundation(package)

        try Data(#"{"tampered":true}"#.utf8).write(
            to: root.appendingPathComponent(
                CaptureSessionFoundationPackage.configurationPath
            ),
            options: .atomic
        )

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                requireCompletedRoomPlan: false,
                minimumActiveMeshAnchors: 0,
                minimumEvidenceFrames: 0
            )
        )
        XCTAssertEqual(quality.integrityStatus, .fail)
    }
}


extension CaptureSessionFoundationTests {
    func testEndRoomPlanTransactionRollsBackOnConflictAndCanRetry()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let foundation =
            try CaptureSessionFoundationPackageBuilder.build(
                context: context,
                capabilities: CaptureCapabilityMatrix(
                    roomPlanSupported: true,
                    worldTrackingSupported: true,
                    sceneReconstructionSupported: true,
                    sceneDepthSupported: true
                ),
                configurationProfile:
                    CaptureConfigurationProfile(
                        captureMode: .roomPlanMesh,
                        worldAlignment: "gravity",
                        sceneReconstruction: "mesh"
                    ),
                startedAtUTC: "2026-09-20T13:30:00Z",
                device: try CaptureDeviceDocument(
                    osVersion: "iOS 20.0",
                    hardwareModel: "iPhone99,1",
                    appVersion: "0.1.0",
                    appBuild: "1"
                )
            )
        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        try await store.persistSessionFoundation(foundation)

        let timing = try CaptureTimingPackageBuilder.build(
            start: try CaptureTimingCorrelation(
                monotonicSeconds: 1,
                utc: "2026-09-20T13:30:00Z",
                method: "fixture"
            ),
            end: try CaptureTimingCorrelation(
                monotonicSeconds: 8,
                utc: "2026-09-20T13:30:07Z",
                method: "fixture"
            )
        )
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"room":"raw"}"#.utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "iOS 20.0",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
        let lineage =
            RoomPlanEvidenceArtifactBuilder.attachProcessed(
                data: Data(#"{"room":"processed"}"#.utf8),
                to: raw
            )

        let writer = try AtomicCaptureFileWriter(
            rootDirectory: root
        )
        try await writer.write(
            Data("conflicting-processed".utf8),
            to: try CaptureStorePath(
                RoomPlanEvidenceArtifactBuilder.processedPath
            )
        )

        do {
            try await store.persistEndRoomPlanTransaction(
                timingPackage: timing,
                roomPlanLineage: lineage
            )
            XCTFail("expected conflicting processed file rejection")
        } catch {
            // Files from this transaction must be rolled back while the
            // unrelated conflicting file remains untouched.
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        CaptureTimingPackage.path
                    )
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        RoomPlanEvidenceArtifactBuilder.rawPath
                    )
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        RoomPlanEvidenceArtifactBuilder.processedPath
                    )
                    .path
            )
        )

        let failedSnapshot = await store.snapshot()
        XCTAssertNil(failedSnapshot.rawRoomPlanDescriptor)
        XCTAssertNil(failedSnapshot.processedRoomPlanDescriptor)
        XCTAssertFalse(
            failedSnapshot.payloadDeclarations.contains {
                $0.path == CaptureTimingPackage.path
                    || $0.path
                        == RoomPlanEvidenceArtifactBuilder.rawPath
                    || $0.path
                        == RoomPlanEvidenceArtifactBuilder.processedPath
            }
        )

        try await writer.removeIfPresent(
            try CaptureStorePath(
                RoomPlanEvidenceArtifactBuilder.processedPath
            )
        )
        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing,
            roomPlanLineage: lineage
        )

        let recovered = await store.snapshot()
        XCTAssertEqual(
            recovered.rawRoomPlanDescriptor,
            raw.descriptor
        )
        XCTAssertEqual(
            recovered.processedRoomPlanDescriptor,
            lineage.processed?.descriptor
        )

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                minimumActiveMeshAnchors: 0,
                minimumEvidenceFrames: 0
            )
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testAcceptedEndCanRollbackForAdditionalScanningAndReEnd()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let foundation =
            try CaptureSessionFoundationPackageBuilder.build(
                context: context,
                capabilities: CaptureCapabilityMatrix(
                    roomPlanSupported: true,
                    worldTrackingSupported: true,
                    sceneReconstructionSupported: true,
                    sceneDepthSupported: true
                ),
                configurationProfile:
                    CaptureConfigurationProfile(
                        captureMode: .roomPlanMesh,
                        worldAlignment: "gravity",
                        sceneReconstruction: "mesh"
                    ),
                startedAtUTC: "2026-09-20T18:00:00Z",
                device: try CaptureDeviceDocument(
                    osVersion: "iOS 20.0",
                    hardwareModel: "iPhone99,1",
                    appVersion: "0.1.0",
                    appBuild: "1"
                )
            )
        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        try await store.persistSessionFoundation(foundation)

        let frameID = EvidenceFrameID()
        let pixel = Data([1, 2, 3, 4])
        let frameDescriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
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
                "evidence/frames/"
                + frameID.description
                + ".pixelbin",
            pixelByteCount: pixel.count,
            pixelSHA256:
                EvidenceIntegrity.sha256(of: pixel),
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

        let timing1 = try CaptureTimingPackageBuilder.build(
            start: try CaptureTimingCorrelation(
                monotonicSeconds: 1,
                utc: "2026-09-20T18:00:00Z",
                method: "fixture"
            ),
            end: try CaptureTimingCorrelation(
                monotonicSeconds: 8,
                utc: "2026-09-20T18:00:07Z",
                method: "fixture"
            )
        )
        let raw1 = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"end":1}"#.utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "iOS 20.0",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
        let lineage1 =
            RoomPlanEvidenceArtifactBuilder.attachProcessed(
                data: Data(#"{"processed":1}"#.utf8),
                to: raw1
            )
        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing1,
            roomPlanLineage: lineage1
        )

        let mesh1 = try MeshEvidencePackageBuilder.build(
            snapshots: [
                MeshAnchorSnapshot(
                    anchorID: UUID(),
                    captureSessionID: context.captureSessionID,
                    coordinateSpaceID: context.coordinateSpaceID,
                    worldFromAnchor: .identity,
                    sessionTimestampSeconds: 7,
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
        try await store.persistMeshPackage(mesh1)

        try await store.rollbackAcceptedEndTransaction(
            removeOwnedMesh: true
        )

        let reopened = await store.snapshot()
        XCTAssertNil(reopened.rawRoomPlanDescriptor)
        XCTAssertNil(reopened.processedRoomPlanDescriptor)
        XCTAssertNil(reopened.meshAnchorCount)
        XCTAssertEqual(reopened.evidenceFrameCount, 1)
        XCTAssertTrue(
            reopened.payloadDeclarations.contains {
                $0.path == frameDescriptor.pixelRelativePath
            }
        )
        XCTAssertFalse(
            reopened.payloadDeclarations.contains {
                $0.path == CaptureTimingPackage.path
                    || $0.path
                        == RoomPlanEvidenceArtifactBuilder.rawPath
                    || $0.path
                        == RoomPlanEvidenceArtifactBuilder.processedPath
                    || $0.path == MeshEvidencePackage.indexPath
                    || $0.path.hasPrefix("mesh/geometry/")
            }
        )

        for path in [
            CaptureTimingPackage.path,
            RoomPlanEvidenceArtifactBuilder.rawPath,
            RoomPlanEvidenceArtifactBuilder.processedPath,
            MeshEvidencePackage.indexPath,
        ] {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                )
            )
        }

        let timing2 = try CaptureTimingPackageBuilder.build(
            start: try CaptureTimingCorrelation(
                monotonicSeconds: 1,
                utc: "2026-09-20T18:00:00Z",
                method: "fixture"
            ),
            end: try CaptureTimingCorrelation(
                monotonicSeconds: 14,
                utc: "2026-09-20T18:00:13Z",
                method: "fixture"
            )
        )
        let raw2 = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"end":2}"#.utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "iOS 20.0",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
        let lineage2 =
            RoomPlanEvidenceArtifactBuilder.attachProcessed(
                data: Data(#"{"processed":2}"#.utf8),
                to: raw2
            )
        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing2,
            roomPlanLineage: lineage2
        )

        let mesh2 = try MeshEvidencePackageBuilder.build(
            snapshots: [
                MeshAnchorSnapshot(
                    anchorID: UUID(),
                    captureSessionID: context.captureSessionID,
                    coordinateSpaceID: context.coordinateSpaceID,
                    worldFromAnchor: .identity,
                    sessionTimestampSeconds: 13,
                    geometry: try MeshGeometryPayload(
                        vertices: [
                            Float3(0, 0, 0),
                            Float3(2, 0, 0),
                            Float3(0, 2, 0),
                        ],
                        triangleIndices: [0, 1, 2]
                    )
                ),
            ]
        )
        try await store.persistMeshPackage(mesh2)

        let reended = await store.snapshot()
        XCTAssertEqual(reended.rawRoomPlanDescriptor, raw2.descriptor)
        XCTAssertEqual(
            reended.processedRoomPlanDescriptor,
            lineage2.processed?.descriptor
        )
        XCTAssertEqual(reended.meshAnchorCount, 1)
        XCTAssertEqual(reended.evidenceFrameCount, 1)

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                minimumActiveMeshAnchors: 1,
                minimumEvidenceFrames: 1
            )
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
        XCTAssertTrue(quality.readyForHTDTIngestion)
    }

    func testFoundationWithoutTimingFailsIntegrityPreflight()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let package =
            try CaptureSessionFoundationPackageBuilder.build(
                context: CaptureSessionContext(),
                capabilities: CaptureCapabilityMatrix(
                    roomPlanSupported: true,
                    worldTrackingSupported: true,
                    sceneReconstructionSupported: true,
                    sceneDepthSupported: false
                ),
                configurationProfile:
                    CaptureConfigurationProfile(
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
        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        try await store.persistSessionFoundation(package)

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                requireCompletedRoomPlan: false,
                minimumActiveMeshAnchors: 0,
                minimumEvidenceFrames: 0
            )
        )
        XCTAssertEqual(quality.integrityStatus, .fail)
    }

    func testTimingRejectsReverseMonotonicOrder() throws {
        XCTAssertThrowsError(
            try CaptureTimingPackageBuilder.build(
                start: try CaptureTimingCorrelation(
                    monotonicSeconds: 10,
                    utc: "2026-09-20T01:00:10Z",
                    method: "fixture"
                ),
                end: try CaptureTimingCorrelation(
                    monotonicSeconds: 9,
                    utc: "2026-09-20T01:00:11Z",
                    method: "fixture"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptureSessionMetadataError,
                .invalidCorrelationOrder
            )
        }
    }
}

// MARK: - Accepted Review boundary regression coverage (#101, #104, #105)

extension CaptureSessionFoundationTests {
    private func makeFoundationPackage(
        context: CaptureSessionContext
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
            startedAtUTC: "2026-09-20T18:00:00Z",
            device: try CaptureDeviceDocument(
                osVersion: "iOS 20.0",
                hardwareModel: "iPhone99,1",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
    }

    /// Shared fixture for accepted-Review boundary coverage: a working
    /// set holding the session foundation plus one fully committed
    /// strict v1 End transaction (timing + raw -> processed RoomPlan +
    /// metadata + coordinate-space policy), matching the boundary the
    /// host rolls back when the operator continues scanning.
    private func makeAcceptedEndStore(
        root: URL,
        marker: String = "accepted"
    ) async throws -> (
        store: CaptureWorkingSetStore,
        context: CaptureSessionContext,
        lineage: RoomPlanArtifactLineage
    ) {
        let context = CaptureSessionContext()
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(
            try makeFoundationPackage(context: context)
        )

        let timing = try CaptureTimingPackageBuilder.build(
            start: try CaptureTimingCorrelation(
                monotonicSeconds: 1,
                utc: "2026-09-20T18:00:00Z",
                method: "fixture"
            ),
            end: try CaptureTimingCorrelation(
                monotonicSeconds: 8,
                utc: "2026-09-20T18:00:07Z",
                method: "fixture"
            )
        )
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data("{\"end\":\"\(marker)\"}".utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "iOS 20.0",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data("{\"processed\":\"\(marker)\"}".utf8),
            to: raw
        )
        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing,
            roomPlanLineage: lineage
        )
        return (store, context, lineage)
    }

    /// #101: the Review rollback removes canonical files only when they
    /// match the accepted transaction byte-for-byte. A tampered raw
    /// RoomPlan payload must fail closed: nothing is removed and the
    /// accepted in-memory authority stays intact for diagnosis or
    /// finalization.
    func testAcceptedEndRollbackFailsClosedOnTamperedCanonicalFile()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let (store, _, lineage) = try await makeAcceptedEndStore(
            root: root
        )

        try Data(#"{"raw":"forged"}"#.utf8).write(
            to: root.appendingPathComponent(
                RoomPlanEvidenceArtifactBuilder.rawPath
            ),
            options: .atomic
        )

        do {
            try await store.rollbackAcceptedEndTransaction(
                removeOwnedMesh: false
            )
            XCTFail("expected tampered canonical file rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .integrityVerificationFailed)
        }

        for path in [
            CaptureTimingPackage.path,
            RoomPlanEvidenceArtifactBuilder.rawPath,
            RoomPlanEvidenceArtifactBuilder.processedPath,
            RoomPlanEvidenceArtifactBuilder.metadataPath,
            CoordinateSpacePolicyPackage.path,
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "rollback must not remove \(path) after a failed ownership check"
            )
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.rawRoomPlanDescriptor,
            lineage.raw.descriptor
        )
        XCTAssertEqual(
            snapshot.processedRoomPlanDescriptor,
            lineage.processed?.descriptor
        )
        XCTAssertNotNil(snapshot.capturedRoomMetadata)
        XCTAssertNotNil(snapshot.coordinateSpacePolicy)
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == CaptureTimingPackage.path
                    || $0.path
                        == RoomPlanEvidenceArtifactBuilder.rawPath
                    || $0.path
                        == RoomPlanEvidenceArtifactBuilder.processedPath
            }
        )
    }

    /// #101: rollback is defined only for a committed accepted End
    /// transaction. Before it exists — and after it was already rolled
    /// back — the call fails closed instead of inventing removals.
    func testAcceptedEndRollbackRequiresCommittedEndTransaction()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        // No session foundation and no End transaction at all.
        let emptyStore = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        do {
            try await emptyStore.rollbackAcceptedEndTransaction(
                removeOwnedMesh: false
            )
            XCTFail("rollback without any transaction must fail")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .integrityVerificationFailed)
        }

        // Foundation committed but no accepted End boundary yet.
        let context = CaptureSessionContext()
        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        try await store.persistSessionFoundation(
            try makeFoundationPackage(context: context)
        )
        do {
            try await store.rollbackAcceptedEndTransaction(
                removeOwnedMesh: false
            )
            XCTFail("rollback without an accepted End must fail")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .integrityVerificationFailed)
        }

        // Commit the End boundary, roll it back once, then prove the
        // second call has no accepted transaction left to remove.
        let timing = try CaptureTimingPackageBuilder.build(
            start: try CaptureTimingCorrelation(
                monotonicSeconds: 1,
                utc: "2026-09-20T18:00:00Z",
                method: "fixture"
            ),
            end: try CaptureTimingCorrelation(
                monotonicSeconds: 8,
                utc: "2026-09-20T18:00:07Z",
                method: "fixture"
            )
        )
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"end":"retry"}"#.utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "iOS 20.0",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data(#"{"processed":"retry"}"#.utf8),
            to: raw
        )
        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing,
            roomPlanLineage: lineage
        )

        do {
            try await store.rollbackAcceptedEndTransaction(
                removeOwnedMesh: false
            )
        } catch {
            XCTFail(
                "first rollback of the committed transaction must succeed: \(error)"
            )
        }

        // The boundary is gone: a second rollback has no accepted
        // transaction to remove and must fail closed.
        do {
            try await store.rollbackAcceptedEndTransaction(
                removeOwnedMesh: false
            )
            XCTFail("a second rollback must fail closed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .integrityVerificationFailed)
        }
    }

    /// #101: `removeOwnedMesh` is only valid when the accepted End
    /// actually committed mesh authority. Requesting mesh removal
    /// without an owned mesh fails closed and keeps the accepted
    /// transaction intact for a corrected retry.
    func testAcceptedEndRollbackRejectsUnownedMeshRemoval()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let (store, _, lineage) = try await makeAcceptedEndStore(
            root: root
        )

        do {
            try await store.rollbackAcceptedEndTransaction(
                removeOwnedMesh: true
            )
            XCTFail("mesh removal without an owned mesh must fail")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .integrityVerificationFailed)
        }

        // The rejected rollback left the accepted boundary untouched.
        let intact = await store.snapshot()
        XCTAssertEqual(
            intact.rawRoomPlanDescriptor,
            lineage.raw.descriptor
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(CaptureTimingPackage.path)
                    .path
            )
        )

        // A corrected retry without mesh removal succeeds.
        try await store.rollbackAcceptedEndTransaction(
            removeOwnedMesh: false
        )
        let cleared = await store.snapshot()
        XCTAssertNil(cleared.rawRoomPlanDescriptor)
        XCTAssertNil(cleared.processedRoomPlanDescriptor)
        XCTAssertFalse(
            cleared.payloadDeclarations.contains {
                $0.path == CaptureTimingPackage.path
            }
        )
    }

    /// #104/#105: preserved-Review provenance is persisted at warning
    /// severity, so transient background/thermal/storage pressure
    /// recorded after an accepted End stays visible in the quality
    /// record without permanently blocking finalization readiness.
    func testWarningResourceEventsKeepAcceptedReviewReady()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let (store, _, _) = try await makeAcceptedEndStore(
            root: root
        )

        let kinds: [CaptureResourceEventKind] = [
            .interruption,
            .thermalPressure,
            .storagePressure,
        ]
        for kind in kinds {
            await store.recordResourceEvent(
                CaptureResourceEvent(
                    kind: kind,
                    severity: .warning,
                    detail: "review-preserved \(kind.rawValue)"
                )
            )
        }

        let report = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                minimumActiveMeshAnchors: 0,
                minimumEvidenceFrames: 0
            )
        )
        XCTAssertEqual(report.integrityStatus, .pass)
        XCTAssertTrue(report.readyForHTDTIngestion)
        XCTAssertFalse(
            report.diagnostics.contains {
                $0.code == "resource_error"
            }
        )
        XCTAssertEqual(report.resourceEvents.count, 3)
        XCTAssertTrue(
            report.resourceEvents.allSatisfy {
                $0.severity == .warning
            }
        )
    }
}
