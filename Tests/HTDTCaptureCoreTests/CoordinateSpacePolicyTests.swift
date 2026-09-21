import Foundation
import XCTest
@testable import HTDTCaptureCore

final class CoordinateSpacePolicyTests: XCTestCase {
    private func makeRuntime() -> CaptureRuntimeProvenance {
        CaptureRuntimeProvenance(
            osVersion: "iOS 20.0",
            appVersion: "0.1.0",
            appBuild: "1"
        )
    }

    private func makeFoundation(
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
            startedAtUTC: "2026-09-20T13:30:00Z",
            device: try CaptureDeviceDocument(
                osVersion: "iOS 20.0",
                hardwareModel: "iPhone99,1",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
    }

    private func makeEndTransaction(
        context: CaptureSessionContext,
        marker: String
    ) throws -> (
        CaptureTimingPackage,
        RoomPlanArtifactLineage
    ) {
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
            data: Data("{\"raw\":\"\(marker)\"}".utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: makeRuntime()
        )
        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data("{\"processed\":\"\(marker)\"}".utf8),
            to: raw
        )
        return (timing, lineage)
    }

    private func policyURL(_ root: URL) -> URL {
        root.appendingPathComponent(
            CoordinateSpacePolicyPackage.path
        )
    }

    func testEndCommitPersistsPreservedContinuityPolicy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(
            try makeFoundation(context: context)
        )
        let (timing, lineage) = try makeEndTransaction(
            context: context,
            marker: "policy"
        )
        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing,
            roomPlanLineage: lineage
        )

        let data = try Data(contentsOf: policyURL(root))
        let document = try JSONDecoder().decode(
            CoordinateSpacePolicyDocument.self,
            from: data
        )
        XCTAssertEqual(
            document.schema,
            "htdt.coordinate-space-policy"
        )
        XCTAssertEqual(document.schemaVersion, "1.0.0")
        XCTAssertEqual(
            document.captureRevisionID,
            store.identity.captureRevisionID
        )
        XCTAssertEqual(
            document.captureSessionID,
            context.captureSessionID
        )
        XCTAssertEqual(
            document.coordinateSpaceID,
            context.coordinateSpaceID
        )
        XCTAssertEqual(
            document.policy,
            .singleSpacePerRevision
        )
        XCTAssertEqual(
            document.discontinuityRequirement,
            .newRevisionRequired
        )
        XCTAssertEqual(
            document.worldOriginContinuity,
            .preserved
        )
        XCTAssertTrue(document.coordinateTransitions.isEmpty)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.coordinateSpacePolicy, document)
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == CoordinateSpacePolicyPackage.path
                    && $0.mediaType == "application/json"
                    && $0.producer == "capture_session"
                    && $0.provenanceClass == .captureAppDerived
                    && $0.role == .canonical
            }
        )

        let quality = await store.evaluateQuality()
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testRecordedDiscontinuityPersistsBrokenContinuityEvidence()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(
            try makeFoundation(context: context)
        )

        // Bind the working-set authority via raw RoomPlan evidence first.
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"raw":"bind"}"#.utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: makeRuntime()
        )
        try await store.persistRawRoomPlan(raw)

        // A mid-scan relocalization registers a new space in the domain
        // context; the working set records the event for provenance.
        var mutableContext = context
        let nextSpace = mutableContext.registerDiscontinuity(
            reason: .worldOriginReset,
            sessionTimestampSeconds: 42.5
        )
        try await store.recordCoordinateDiscontinuity(
            to: nextSpace,
            reason: .worldOriginReset,
            sessionTimestampSeconds: 42.5
        )

        // The bound space never advances: evidence carrying the new
        // space is rejected rather than silently reinterpreted.
        let mismatched = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"raw":"foreign"}"#.utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: nextSpace,
            runtime: makeRuntime()
        )
        do {
            try await store.persistRawRoomPlan(mismatched)
            XCTFail("expected authority mismatch for foreign space")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .authorityMismatch)
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.coordinateSpaceIDs,
            [context.coordinateSpaceID]
        )

        // A completed end commit persists the policy with the recorded
        // discontinuity and broken continuity provenance. The end
        // transaction requires an uncommitted RoomPlan state, so a fresh
        // working set binds its authority via frame evidence first.
        let root3 = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let context3 = CaptureSessionContext()
        let store3 = try CaptureWorkingSetStore(rootDirectory: root3)
        defer {
            try? FileManager.default.removeItem(at: root3)
        }
        try await store3.persistSessionFoundation(
            try makeFoundation(context: context3)
        )
        try await store3.persistFramePackage(
            try framePackage(
                sessionID: context3.captureSessionID,
                spaceID: context3.coordinateSpaceID
            )
        )
        let discontinuitySpace = CoordinateSpaceID()
        try await store3.recordCoordinateDiscontinuity(
            to: discontinuitySpace,
            reason: .arSessionRestart,
            sessionTimestampSeconds: 30.0
        )

        let (timing3, lineage3) = try makeEndTransaction(
            context: context3,
            marker: "broken"
        )
        try await store3.persistEndRoomPlanTransaction(
            timingPackage: timing3,
            roomPlanLineage: lineage3
        )

        let document = try JSONDecoder().decode(
            CoordinateSpacePolicyDocument.self,
            from: Data(
                contentsOf: policyURL(root3)
            )
        )
        XCTAssertEqual(document.worldOriginContinuity, .broken)
        XCTAssertEqual(document.coordinateTransitions.count, 1)
        let record = try XCTUnwrap(
            document.coordinateTransitions.first
        )
        XCTAssertEqual(
            record.previousCoordinateSpaceID,
            context3.coordinateSpaceID
        )
        XCTAssertEqual(
            record.nextCoordinateSpaceID,
            discontinuitySpace
        )
        XCTAssertEqual(record.reason, .arSessionRestart)
        XCTAssertEqual(record.sessionTimestampSeconds, 30.0)
    }

    func testDiscontinuityRecordingValidation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)

        // No bound space yet: nothing can transition.
        do {
            try await store.recordCoordinateDiscontinuity(
                to: CoordinateSpaceID(),
                reason: .worldOriginReset
            )
            XCTFail("expected unbound-space rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .coordinateDiscontinuityRequiresBoundSpace
            )
        }

        let context = CaptureSessionContext()
        try await store.persistFramePackage(
            try framePackage(
                sessionID: context.captureSessionID,
                spaceID: context.coordinateSpaceID
            )
        )

        // A transition whose target equals the bound space is not a
        // discontinuity.
        do {
            try await store.recordCoordinateDiscontinuity(
                to: context.coordinateSpaceID,
                reason: .worldOriginReset
            )
            XCTFail("expected same-space rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .invalidCoordinateTransition)
        }

        // Non-finite or negative timestamps are rejected.
        do {
            try await store.recordCoordinateDiscontinuity(
                to: CoordinateSpaceID(),
                reason: .worldOriginReset,
                sessionTimestampSeconds: .nan
            )
            XCTFail("expected invalid timestamp rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .invalidCoordinateTransition)
        }
    }

    func testRollbackRemovesPolicyDocument() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(
            try makeFoundation(context: context)
        )
        let (timing, lineage) = try makeEndTransaction(
            context: context,
            marker: "rollback"
        )
        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing,
            roomPlanLineage: lineage
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: policyURL(root).path
            )
        )

        try await store.rollbackAcceptedEndTransaction(
            removeOwnedMesh: false
        )

        let snapshot = await store.snapshot()
        XCTAssertNil(snapshot.coordinateSpacePolicy)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: policyURL(root).path
            )
        )
        XCTAssertFalse(
            snapshot.payloadDeclarations.contains {
                $0.path == CoordinateSpacePolicyPackage.path
            }
        )
    }

    func testTamperedPolicyDocumentFailsIntegrity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(
            try makeFoundation(context: context)
        )
        let (timing, lineage) = try makeEndTransaction(
            context: context,
            marker: "tamper"
        )
        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing,
            roomPlanLineage: lineage
        )

        try Data(#"{"forged":true}"#.utf8).write(
            to: policyURL(root),
            options: .atomic
        )

        let quality = await store.evaluateQuality()
        XCTAssertEqual(quality.integrityStatus, .fail)
    }

    func testPolicyBuilderRejectsForeignTransitionOrigin() throws {
        let bound = CoordinateSpaceID()
        XCTAssertThrowsError(
            try CoordinateSpacePolicyPackageBuilder.build(
                captureRevisionID: CaptureRevisionID(),
                captureSessionID: CaptureSessionID(),
                coordinateSpaceID: bound,
                transitions: [
                    CoordinateSpaceTransition(
                        previous: CoordinateSpaceID(),
                        next: CoordinateSpaceID(),
                        reason: .worldOriginReset,
                        sessionTimestampSeconds: 1
                    ),
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? CoordinateSpacePolicyError,
                .transitionAuthorityMismatch
            )
        }
    }

    private func framePackage(
        sessionID: CaptureSessionID,
        spaceID: CoordinateSpaceID
    ) throws -> FrameEvidencePackage {
        let frameID = EvidenceFrameID()
        let pixel = Data([1, 2, 3, 4])
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: spaceID,
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
            depthStatus: .unavailable
        )
        return try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: nil,
            confidencePayload: nil
        )
    }
}
