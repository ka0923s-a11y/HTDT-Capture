import Foundation
import XCTest
@testable import HTDTCaptureCore

final class LiveQualityFinalizationTests: XCTestCase {
    func testCompleteWorkingSetProducesReadyQualityAndFinalizes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let staging = root.appendingPathComponent(
            "working",
            isDirectory: true
        )
        let store = try CaptureWorkingSetStore(
            rootDirectory: staging
        )
        try await populateCompleteWorkingSet(store)

        let quality = await store.evaluateQuality()
        XCTAssertTrue(quality.readyForHTDTIngestion)
        XCTAssertEqual(quality.integrityStatus, .pass)
        XCTAssertEqual(quality.roomPlanStatus, .completed)
        XCTAssertEqual(quality.activeMeshAnchorCount, 1)
        XCTAssertEqual(quality.evidenceFrameCount, 1)

        try await store.persistQualityReport(quality)
        let snapshot = await store.snapshot()
        let request =
            try CaptureWorkingSetFinalizationRequestBuilder.build(
                snapshot: snapshot,
                qualityReport: quality,
                app: BundleAppIdentity(
                    version: "0.1.0",
                    build: "test"
                )
            )

        let destination = root.appendingPathComponent(
            "finalized",
            isDirectory: true
        )
        let finalized = try await BundleRevisionFinalizer()
            .finalize(
                stagingDirectory: staging,
                destinationDirectory: destination,
                request: request
            )

        XCTAssertEqual(
            finalized.captureRevisionID,
            snapshot.identity.captureRevisionID
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: staging.path)
        )
        let validation = try BundleDirectoryValidator.validate(
            root: destination
        )
        XCTAssertEqual(
            validation.bundleDigest,
            finalized.bundleDigest
        )
        XCTAssertTrue(
            validation.manifest.files.contains {
                $0.path == "quality/capture-quality.json"
            }
        )
    }

    func testQualityReportCanReplayRollbackAndRetryBeforePromotion()
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
        try await populateCompleteWorkingSet(store)

        let quality = await store.evaluateQuality()
        XCTAssertTrue(quality.readyForHTDTIngestion)
        XCTAssertEqual(quality.integrityStatus, .pass)

        try await store.persistQualityReport(quality)
        try await store.persistQualityReport(quality)

        var snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.payloadDeclarations.filter {
                $0.path == "quality/capture-quality.json"
            }.count,
            1
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        "quality/capture-quality.json"
                    )
                    .path
            )
        )

        try await store.discardUncommittedQualityReport(
            quality
        )

        snapshot = await store.snapshot()
        XCTAssertFalse(
            snapshot.payloadDeclarations.contains {
                $0.path == "quality/capture-quality.json"
            }
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        "quality/capture-quality.json"
                    )
                    .path
            )
        )

        let afterRollback = await store.evaluateQuality()
        XCTAssertTrue(afterRollback.readyForHTDTIngestion)
        XCTAssertEqual(afterRollback.integrityStatus, .pass)

        try await store.persistQualityReport(afterRollback)
        snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.payloadDeclarations.filter {
                $0.path == "quality/capture-quality.json"
            }.count,
            1
        )
    }

    func testSceneDepthCanExplicitlySubstituteForMissingMeshAtReview() {
        let observation = CaptureQualityObservation(
            roomPlanStatus: .completed,
            activeMeshAnchorCount: 0,
            evidenceFrameCount: 1,
            depthEvidenceCount: 1,
            integrityStatus: .pass
        )

        let strict = CaptureQualityEvaluator.evaluate(
            observation,
            requirements: CaptureQualityRequirements()
        )
        XCTAssertFalse(strict.readyForHTDTIngestion)
        XCTAssertTrue(
            strict.diagnostics.contains {
                $0.code == "insufficient_mesh_anchors"
                    && $0.severity == .error
            }
        )

        let depthFallback = CaptureQualityEvaluator.evaluate(
            observation,
            requirements: CaptureQualityRequirements(
                allowDepthEvidenceAsMeshFallback: true
            )
        )
        XCTAssertTrue(depthFallback.readyForHTDTIngestion)
        XCTAssertTrue(
            depthFallback.diagnostics.contains {
                $0.code == "mesh_depth_fallback"
                    && $0.severity == .warning
            }
        )
        XCTAssertFalse(
            depthFallback.diagnostics.contains {
                $0.code == "insufficient_mesh_anchors"
            }
        )
    }

    func testTamperTurnsIntegrityIntoQualityFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        try await populateCompleteWorkingSet(store)

        let snapshot = await store.snapshot()
        let frameDeclaration = try XCTUnwrap(
            snapshot.payloadDeclarations.first {
                $0.path.hasSuffix(".pixelbin")
            }
        )
        let frameURL = frameDeclaration.path
            .split(separator: "/")
            .reduce(root) { url, component in
                url.appendingPathComponent(String(component))
            }
        try Data([0xde, 0xad, 0xbe, 0xef]).write(
            to: frameURL,
            options: .atomic
        )

        let quality = await store.evaluateQuality()
        XCTAssertFalse(quality.readyForHTDTIngestion)
        XCTAssertEqual(quality.integrityStatus, .fail)
        XCTAssertTrue(
            quality.diagnostics.contains {
                $0.code == "integrity_failed"
            }
        )
    }

    private func populateCompleteWorkingSet(
        _ store: CaptureWorkingSetStore
    ) async throws {
        // The finalized v1 contract requires the foundation payload set
        // (#194): session/capabilities/configuration/device plus the
        // timing package, all sharing one session/coordinate authority
        // that every other evidence payload binds to.
        let context = CaptureSessionContext()
        let sessionID = context.captureSessionID
        let coordinateID = context.coordinateSpaceID
        let foundation = try CaptureSessionFoundationPackageBuilder
            .build(
                context: context,
                capabilities: CaptureCapabilityMatrix(
                    roomPlanSupported: true,
                    worldTrackingSupported: true,
                    sceneReconstructionSupported: true,
                    sceneDepthSupported: true,
                    smoothedSceneDepthSupported: true,
                    highResolutionFrameSupported: false,
                    combinedRoomPlanSceneDepthVerified: nil,
                    sameSessionDepthAfterRoomPlanStopVerified: nil
                ),
                configurationProfile: CaptureConfigurationProfile(
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
                ),
                startedAtUTC: "2026-09-20T01:00:00Z",
                device: try CaptureDeviceDocument(
                    osVersion: "iOS 20.0",
                    hardwareModel: "iPhone99,1",
                    appVersion: "0.1.0",
                    appBuild: "1"
                )
            )
        try await store.persistSessionFoundation(foundation)
        try await store.persistTimingPackage(
            try CaptureTimingPackageBuilder.build(
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
                    anchorID: UUID(),
                    captureSessionID: sessionID,
                    coordinateSpaceID: coordinateID,
                    worldFromAnchor: .identity,
                    sessionTimestampSeconds: 1,
                    geometry: geometry
                ),
            ]
        )
        try await store.persistMeshPackage(mesh)

        // The pixel payload must be a structurally valid
        // PackedPixelBuffer encoding — integrity validation decodes the
        // binary format, not just its hash.
        let pixel = try BundleValidationFixture.pixelPayload(
            width: 1,
            height: 1
        )
        let frameID = EvidenceFrameID()
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
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
            pixelFormatFourCC: 0x34323066,
            pixelRelativePath:
                "evidence/frames/\(frameID).pixelbin",
            pixelByteCount: pixel.count,
            pixelSHA256: EvidenceIntegrity.sha256(of: pixel),
            depthStatus: .unavailable
        )
        let framePackage = try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: nil,
            confidencePayload: nil
        )
        try await store.persistFramePackage(framePackage)
    }
}
