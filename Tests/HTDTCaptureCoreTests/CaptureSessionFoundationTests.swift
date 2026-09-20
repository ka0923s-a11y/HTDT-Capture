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
                startedAtUTC: "2026-09-20T01:00:00Z"
            )

        XCTAssertEqual(
            package.configuration.planeDetection,
            ["horizontal", "vertical"]
        )
        XCTAssertEqual(
            package.session.configurationRef,
            "session/capture-configuration.json"
        )
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
                startedAtUTC: "2026-09-20T01:00:00Z"
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
