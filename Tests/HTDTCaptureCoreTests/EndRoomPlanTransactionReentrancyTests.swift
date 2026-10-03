import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue bolph71656-ai/HTDT-Capture#161: the End RoomPlan transaction suspends the store actor at
/// writer awaits, so a second identical invocation can re-enter. The
/// transaction must be attempt-safe: committed bytes are never removed
/// by another attempt's failure, and logical authority commits exactly
/// once.
final class EndRoomPlanTransactionReentrancyTests: XCTestCase {
    private func makeStore(
        root: URL,
        context: CaptureSessionContext
    ) async throws -> CaptureWorkingSetStore {
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(
            CaptureSessionFoundationPackageBuilder.build(
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
        )
        return store
    }

    private func makeTransaction(
        context: CaptureSessionContext,
        marker: String,
        byteCount: Int = 64 * 1024
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
        var rawBytes = Data(
            repeating: 0x52,
            count: byteCount
        )
        rawBytes.append(
            contentsOf: marker.utf8
        )
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: rawBytes,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: CaptureRuntimeProvenance(
                osVersion: "iOS 20.0",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
        var processedBytes = Data(
            repeating: 0x50,
            count: byteCount
        )
        processedBytes.append(
            contentsOf: marker.utf8
        )
        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: processedBytes,
            to: raw
        )
        return (timing, lineage)
    }

    func testConcurrentIdenticalEndTransactionsCommitExactlyOnce()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let store = try await makeStore(root: root, context: context)
        let (timing, lineage) = try makeTransaction(
            context: context,
            marker: "identical"
        )

        // Eight overlapping identical transactions: every invocation
        // must succeed (idempotent replay) and exactly one logical
        // commit may result.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await store.persistEndRoomPlanTransaction(
                        timingPackage: timing,
                        roomPlanLineage: lineage
                    )
                }
            }
            try await group.waitForAll()
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

        let expectedPaths: Set<String> = [
            CaptureTimingPackage.path,
            RoomPlanEvidenceArtifactBuilder.rawPath,
            RoomPlanEvidenceArtifactBuilder.processedPath,
            RoomPlanEvidenceArtifactBuilder.metadataPath,
            CoordinateSpacePolicyPackage.path,
        ]
        let declared = snapshot.payloadDeclarations.filter {
            expectedPaths.contains($0.path)
        }
        XCTAssertEqual(declared.count, expectedPaths.count)

        for path in expectedPaths {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "missing committed file \(path)"
            )
        }

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testConcurrentConflictingEndTransactionsFailClosed()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let store = try await makeStore(root: root, context: context)
        let (timingA, lineageA) = try makeTransaction(
            context: context,
            marker: "alpha"
        )
        let (timingB, lineageB) = try makeTransaction(
            context: context,
            marker: "beta-beta"
        )

        enum Outcome { case committed, rejected }
        let outcomes = await withTaskGroup(
            of: (String, Outcome).self
        ) { group in
            group.addTask {
                do {
                    try await store.persistEndRoomPlanTransaction(
                        timingPackage: timingA,
                        roomPlanLineage: lineageA
                    )
                    return ("alpha", .committed)
                } catch {
                    return ("alpha", .rejected)
                }
            }
            group.addTask {
                do {
                    try await store.persistEndRoomPlanTransaction(
                        timingPackage: timingB,
                        roomPlanLineage: lineageB
                    )
                    return ("beta", .committed)
                } catch {
                    return ("beta", .rejected)
                }
            }
            var collected: [(String, Outcome)] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        // Timing documents are identical, so the conflict is decided at
        // the RoomPlan payloads: exactly one lineage may commit.
        let committed = outcomes.filter { $0.1 == .committed }
        let rejected = outcomes.filter { $0.1 == .rejected }
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(rejected.count, 1)

        let snapshot = await store.snapshot()
        let expectedRaw =
            committed.first?.0 == "alpha"
                ? lineageA.raw.descriptor
                : lineageB.raw.descriptor
        let expectedProcessed =
            committed.first?.0 == "alpha"
                ? lineageA.processed?.descriptor
                : lineageB.processed?.descriptor
        XCTAssertEqual(
            snapshot.rawRoomPlanDescriptor,
            expectedRaw
        )
        XCTAssertEqual(
            snapshot.processedRoomPlanDescriptor,
            expectedProcessed
        )

        // The winning commit is fully intact: no failing attempt removed
        // any of its files.
        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testFailedTransactionLeavesNoPartialFilesOrDeclarations()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let store = try await makeStore(root: root, context: context)
        let (timing, lineage) = try makeTransaction(
            context: context,
            marker: "conflict"
        )

        // Pre-seed a conflicting canonical metadata payload so the batch
        // fails partway through.
        let writer = try AtomicCaptureFileWriter(
            rootDirectory: root
        )
        try await writer.write(
            Data("conflicting-metadata".utf8),
            to: try CaptureStorePath(
                RoomPlanEvidenceArtifactBuilder.metadataPath
            )
        )

        do {
            try await store.persistEndRoomPlanTransaction(
                timingPackage: timing,
                roomPlanLineage: lineage
            )
            XCTFail("expected conflicting metadata rejection")
        } catch {
            // Expected: the batch rolls back only attempt-owned files.
        }

        let transactionPaths = [
            CaptureTimingPackage.path,
            RoomPlanEvidenceArtifactBuilder.rawPath,
            RoomPlanEvidenceArtifactBuilder.processedPath,
        ]
        for path in transactionPaths {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "rolled-back file still present: \(path)"
            )
        }
        // The conflicting pre-existing file must remain untouched.
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        RoomPlanEvidenceArtifactBuilder
                            .metadataPath
                    )
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        CoordinateSpacePolicyPackage.path
                    )
                    .path
            )
        )

        let snapshot = await store.snapshot()
        XCTAssertNil(snapshot.rawRoomPlanDescriptor)
        XCTAssertNil(snapshot.processedRoomPlanDescriptor)
        XCTAssertNil(snapshot.capturedRoomMetadata)
        XCTAssertNil(snapshot.coordinateSpacePolicy)
        XCTAssertFalse(
            snapshot.payloadDeclarations.contains {
                transactionPaths.contains($0.path)
                    || $0.path
                        == RoomPlanEvidenceArtifactBuilder
                            .metadataPath
                    || $0.path
                        == CoordinateSpacePolicyPackage.path
            }
        )

        // Removing the conflicting bytes makes the same transaction
        // recoverable.
        try await writer.removeIfPresent(
            try CaptureStorePath(
                RoomPlanEvidenceArtifactBuilder.metadataPath
            )
        )
        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing,
            roomPlanLineage: lineage
        )
        let recovered = await store.snapshot()
        XCTAssertEqual(
            recovered.rawRoomPlanDescriptor,
            lineage.raw.descriptor
        )
        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }
}
