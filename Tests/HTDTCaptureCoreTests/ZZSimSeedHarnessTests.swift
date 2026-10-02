import Foundation
import XCTest
@testable import HTDTCaptureCore

/// TEMPORARY simulator-seed harness (not part of the suite).
/// Fabricates a real end-accepted working revision that carries a
/// declared `session/revisit-flags.json` document, verifies the full
/// restore + review-model pipeline in-process, and leaves the
/// directory under /tmp/htdt-sim-seed for injection into the iOS
/// Simulator app container. Run:
///   swift test --filter ZZSimSeedHarnessTests
final class ZZSimSeedHarnessTests: XCTestCase {

    static let seedRoot = URL(
        fileURLWithPath: "/tmp/htdt-sim-seed/capture",
        isDirectory: true
    )

    // MARK: - fixture helpers (mirrored from LifecycleRecoveryTests)

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
            startedAtUTC: "2026-09-21T10:00:00Z",
            device: try CaptureDeviceDocument(
                osVersion: "iOS 20.0",
                hardwareModel: "iPhone99,1",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
    }

    private func makeTiming() throws -> CaptureTimingPackage {
        try CaptureTimingPackageBuilder.build(
            start: try CaptureTimingCorrelation(
                monotonicSeconds: 1,
                utc: "2026-09-21T10:00:00Z",
                method: "fixture"
            ),
            end: try CaptureTimingCorrelation(
                monotonicSeconds: 8,
                utc: "2026-09-21T10:00:07Z",
                method: "fixture"
            )
        )
    }

    private func makeLineage(
        context: CaptureSessionContext
    ) throws -> RoomPlanArtifactLineage {
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
        return RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data(#"{"room":"processed"}"#.utf8),
            to: raw
        )
    }

    private func makeEndCoverage() -> CaptureEndCoverageSummary {
        CaptureEndCoverageSummary(
            algorithm: "fixture",
            algorithmVersion: "1.0.0",
            endSessionTimestampSeconds: 8,
            sectorCount: 12,
            minimumSamplesPerCell: 2,
            cellSampleCounts: Array(repeating: 2, count: 36),
            coverageFraction: 1,
            pitchBandFractions: [:],
            weakCells: [],
            latestTrackingState: .normal,
            latestTrackingReason: nil,
            latestMeshAnchorCount: 1,
            latestHasSceneDepth: true,
            spatialCellSizeMeters: 0.5,
            observedRegionCount: 1,
            weakRegionCount: 0,
            displayUnknownRegionCount: 0,
            usesDepthFallback: false,
            meshAvailabilityState: "available",
            weakRegionKeys: [],
            geometryEvidenceMode: "mesh",
            movementCapability: "unrestricted",
            guidanceCompletedAttempts: 0,
            guidanceMaximumAttempts: 4,
            actionableWeakRegionCount: 0,
            saturatedWeakRegionCount: 0,
            guidanceComplete: true,
            guidanceCompletionSource:
                ScanGuidanceCompletionSource.observed.rawValue
        )
    }

    // MARK: - seed + in-process verification

    func testFabricateDraftWithRevisitFlags() async throws {
        let captureRoot = Self.seedRoot
        try? FileManager.default.removeItem(at: captureRoot)
        try FileManager.default.createDirectory(
            at: captureRoot,
            withIntermediateDirectories: true
        )

        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let directory = captureRoot
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(
                identity.captureRevisionID.description,
                isDirectory: true
            )
        let store = try CaptureWorkingSetStore(
            identity: identity,
            rootDirectory: directory
        )
        try await store.persistSessionFoundation(
            makeFoundation(context: context)
        )
        await store.recordAdvisoryEndContext(makeEndCoverage())
        try await store.persistEndRoomPlanTransaction(
            timingPackage: makeTiming(),
            roomPlanLineage: makeLineage(context: context)
        )

        // Two flags: one unresolved (exercises Resolve menu + Skip),
        // one already resolved (exercises Reopen on open).
        var flagStore = CaptureRevisitFlagStore()
        let flagA = ScanRevisitFlag(
            flagID: "11111111-1111-4111-8111-111111111111",
            coordinateSpaceID: context.coordinateSpaceID,
            captureSessionID: context.captureSessionID,
            targetPointWorld: ScanRevisitFlagVector(
                x: 1.0, y: 1.2, z: 2.0
            ),
            targetFromRaycast: false,
            cameraPositionWorld: ScanRevisitFlagVector(
                x: 1.0, y: 1.6, z: 2.0
            ),
            cameraForwardWorld: ScanRevisitFlagVector(
                x: 0, y: 0, z: -1
            ),
            coverageCell: "2,3",
            category: .opening,
            note: "Doorway may not have been captured",
            createdSessionTimestampSeconds: 4.5
        )
        let flagB = ScanRevisitFlag(
            flagID: "22222222-2222-4222-8222-222222222222",
            coordinateSpaceID: context.coordinateSpaceID,
            captureSessionID: context.captureSessionID,
            targetPointWorld: ScanRevisitFlagVector(
                x: 0.5, y: 1.0, z: -1.0
            ),
            targetFromRaycast: true,
            cameraPositionWorld: ScanRevisitFlagVector(
                x: 0.4, y: 1.6, z: -0.8
            ),
            cameraForwardWorld: ScanRevisitFlagVector(
                x: 0, y: 0, z: -1
            ),
            coverageCell: "1,1",
            category: .measurement,
            note: "Verify counter height here",
            createdSessionTimestampSeconds: 6.0
        )
        XCTAssertTrue(flagStore.add(flagA))
        XCTAssertTrue(flagStore.add(flagB))
        XCTAssertTrue(
            flagStore.resolve(
                flagID: flagB.flagID,
                outcome: .linkedAuthority,
                authorityRef: "seed-authority-ref"
            )
        )

        // Same declaration the app's persistRevisitFlags writes.
        let document = flagStore.document(
            captureRevisionID: identity.captureRevisionID
        )
        try await store.replaceSupplementalDocument(
            WorkingSetSupplementalDocument(
                path: CaptureRevisitFlagDocument.path,
                data: try document.encoded(),
                declaration: BundlePayloadDeclaration(
                    path: CaptureRevisitFlagDocument.path,
                    mediaType: "application/json",
                    producer: "capture_session",
                    provenanceClass: .captureAppDerived,
                    role: .canonical
                ),
                coordinateSpaceIDs: [context.coordinateSpaceID],
                captureSessionIDs: [context.captureSessionID]
            )
        )

        // --- verify the whole restore pipeline in-process ---
        let draft = RecoverableWorkingRevision(
            url: directory,
            revisionID: identity.captureRevisionID,
            phase: .endAccepted,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            retainedBytes: 0
        )
        let restored = try await CaptureWorkingSetStore
            .restoreWorkingRevision(draft)
        let snapshot = await restored.store.snapshot()
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == CaptureRevisitFlagDocument.path
            },
            "flags doc must survive restore as a declared payload"
        )
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == "session/revisit-flags.json"
            }
        )
        let model = CaptureReviewWorkspaceLoader.loadWorkingSet(
            snapshot: snapshot
        )
        XCTAssertEqual(model.revisitFlags.count, 2)
        XCTAssertEqual(
            model.revisitFlags.first {
                $0.flagID == flagA.flagID
            }?.status,
            .unresolved
        )
        XCTAssertEqual(
            model.revisitFlags.first {
                $0.flagID == flagB.flagID
            }?.status,
            .resolved
        )
        // Sanity: the persisted doc itself is decodable + revision-bound.
        let persisted = try JSONDecoder().decode(
            CaptureRevisitFlagDocument.self,
            from: Data(
                contentsOf: directory.appendingPathComponent(
                    CaptureRevisitFlagDocument.path
                )
            )
        )
        XCTAssertEqual(
            persisted.captureRevisionID,
            identity.captureRevisionID
        )
        XCTAssertEqual(persisted.flags.count, 2)

        print("HTDT-SEED-DIR=\(directory.path)")
        print("HTDT-SEED-REV=\(identity.captureRevisionID.description)")
        print(
            "HTDT-SEED-FLAGS=\(persisted.flags.map { $0.flagID + ":" + $0.status.rawValue })"
        )
    }

    /// Second restore on the already-restored directory — replicates
    /// what the app does when it reopens the injected draft (the
    /// first restore already ran in the fabrication test).
    func testSecondRestoreKeepsFlagsDeclared() async throws {
        let directory = Self.seedRoot
            .appendingPathComponent("working", isDirectory: true)
        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let dir = try XCTUnwrap(children.first)
        let state = try XCTUnwrap(
            CaptureWorkingSetStore.peekRevisionPhase(
                workingRevisionURL: dir
            )
        )
        let draft = RecoverableWorkingRevision(
            url: dir,
            revisionID: try XCTUnwrap(
                CaptureRevisionID(
                    canonicalString: dir.lastPathComponent
                )
            ),
            phase: state.phase,
            captureSessionID: state.captureSessionID,
            coordinateSpaceID: state.coordinateSpaceID,
            retainedBytes: 0
        )
        let restored = try await CaptureWorkingSetStore
            .restoreWorkingRevision(draft)
        let snapshot = await restored.store.snapshot()
        let declared = snapshot.payloadDeclarations.map(\.path)
        print("HTDT-DECLARED=\(declared)")
        XCTAssertTrue(
            declared.contains(CaptureRevisitFlagDocument.path),
            "second restore dropped the flags doc declaration"
        )
        let model = CaptureReviewWorkspaceLoader.loadWorkingSet(
            snapshot: snapshot
        )
        print("HTDT-MODEL-FLAGS=\(model.revisitFlags.count)")
        XCTAssertEqual(model.revisitFlags.count, 2)
    }
}
