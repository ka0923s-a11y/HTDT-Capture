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
