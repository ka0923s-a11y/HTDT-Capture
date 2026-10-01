import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #180: the working set needs an actor-owned finalization
/// barrier. `sealForFinalization` rejects new mutations, drains
/// already-owned writes, re-verifies durable bytes, evaluates quality
/// from that exact state, and persists the matching canonical quality
/// payload before returning an immutable sealed snapshot.
final class FinalizationSealTests: XCTestCase {
    /// Requirements that an empty-but-intact working set satisfies, so
    /// seal behavior can be tested without a full capture.
    private var relaxedRequirements: CaptureQualityRequirements {
        CaptureQualityRequirements(
            rulesetVersion: "0.0.0-test",
            requireCompletedRoomPlan: false,
            minimumActiveMeshAnchors: 0,
            minimumEvidenceFrames: 0
        )
    }

    private func makeStore(root: URL) throws -> CaptureWorkingSetStore {
        try CaptureWorkingSetStore(rootDirectory: root)
    }

    private func framePackage() throws -> FrameEvidencePackage {
        let frameID = EvidenceFrameID()
        let pixel = Data([1, 2, 3, 4])
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: CaptureSessionID(
                rawValue: UUID(
                    uuidString:
                        "10000000-0000-4000-8000-000000000003"
                )!
            ),
            coordinateSpaceID: CoordinateSpaceID(
                rawValue: UUID(
                    uuidString:
                        "10000000-0000-4000-8000-000000000004"
                )!
            ),
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
            depthStatus: .unavailable,
            depth: nil
        )
        return try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: nil,
            confidencePayload: nil
        )
    }

    func testSealPersistsQualityReportAndReturnsSealedSnapshot()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        try await store.persistFramePackage(try framePackage())

        let sealed = try await store.sealForFinalization(
            requirements: relaxedRequirements
        )

        XCTAssertTrue(sealed.qualityReport.readyForHTDTIngestion)
        XCTAssertEqual(
            sealed.qualityReport.integrityStatus,
            .pass
        )
        // The persisted canonical quality payload is derived from the
        // same sealed state the declaration snapshot carries.
        XCTAssertEqual(sealed.qualityReport.evidenceFrameCount, 1)
        XCTAssertTrue(
            sealed.snapshot.payloadDeclarations.contains {
                $0.path == "quality/capture-quality.json"
            }
        )
        let qualityURL = root.appendingPathComponent(
            "quality/capture-quality.json"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: qualityURL.path)
        )
        let persisted = try JSONDecoder().decode(
            CaptureQualityReport.self,
            from: Data(contentsOf: qualityURL)
        )
        XCTAssertEqual(persisted, sealed.qualityReport)

        let isSealed = await store.isSealedForFinalization
        let isConsumed = await store.isConsumed
        XCTAssertTrue(isSealed)
        XCTAssertFalse(isConsumed)
        // The store's live snapshot equals the immutable sealed state.
        let liveSnapshot = await store.snapshot()
        XCTAssertEqual(liveSnapshot, sealed.snapshot)

        // The sealed result feeds the finalization request builder
        // directly, so the promotion request can only describe the
        // exact state the seal froze.
        let request = try CaptureWorkingSetFinalizationRequestBuilder
            .build(
                sealed: sealed,
                app: BundleAppIdentity(version: "1.0", build: "1"),
                finalizedAtUTC: sealed.sealedAtUTC
            )
        XCTAssertEqual(
            request.captureSessionIDs,
            sealed.snapshot.captureSessionIDs
        )
        XCTAssertEqual(
            request.coordinateSpaceIDs,
            sealed.snapshot.coordinateSpaceIDs
        )
        XCTAssertEqual(
            request.payloads,
            sealed.snapshot.payloadDeclarations
        )
        XCTAssertEqual(request.qualityReport, sealed.qualityReport)
    }

    func testMutationsRejectedWhileSealed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        let sealed = try await store.sealForFinalization(
            requirements: relaxedRequirements
        )
        let declarationCount =
            sealed.snapshot.payloadDeclarations.count

        do {
            try await store.persistFramePackage(try framePackage())
            XCTFail("expected workingSetSealed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetSealed)
        }
        do {
            try await store.persistAnnotationPackage(
                try AnnotationEvidencePackageBuilder.build(
                    entities: []
                )
            )
            XCTFail("expected workingSetSealed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetSealed)
        }
        do {
            try await store.rollbackCurrentMeshPackage()
            XCTFail("expected workingSetSealed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetSealed)
        }
        do {
            try await store.persistQualityReport(sealed.qualityReport)
            XCTFail("expected workingSetSealed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetSealed)
        }

        // The non-throwing observation sinks drop events while sealed;
        // the drop is counted for diagnostics.
        await store.recordTrackingEvent(
            TrackingQualityEvent(
                sessionTimestampSeconds: 4,
                state: .limited,
                reason: "sealed"
            )
        )
        await store.recordResourceEvent(
            CaptureResourceEvent(
                kind: .interruption,
                severity: .warning,
                detail: "dropped while sealed"
            )
        )

        let rejected = await store.rejectedSealedMutationCount
        XCTAssertEqual(rejected, 6)

        // The sealed snapshot is unchanged.
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot, sealed.snapshot)
        XCTAssertEqual(
            snapshot.payloadDeclarations.count,
            declarationCount
        )
    }

    func testSecondSealIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        _ = try await store.sealForFinalization(
            requirements: relaxedRequirements
        )
        do {
            _ = try await store.sealForFinalization(
                requirements: relaxedRequirements
            )
            XCTFail("expected workingSetSealed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetSealed)
        }
    }

    func testUnsealReopensMutationsAndRemovesSealedReport() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        try await store.persistFramePackage(try framePackage())
        let first = try await store.sealForFinalization(
            requirements: relaxedRequirements
        )
        XCTAssertEqual(first.qualityReport.evidenceFrameCount, 1)

        // Pre-promotion recoverable failure: unseal for a Review retry.
        try await store.unseal()
        let stillSealed = await store.isSealedForFinalization
        XCTAssertFalse(stillSealed)

        // The sealed quality payload is rolled back exactly: it
        // described the sealed state and would be stale once mutations
        // resume.
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        "quality/capture-quality.json"
                    )
                    .path
            )
        )
        let unsealed = await store.snapshot()
        XCTAssertFalse(
            unsealed.payloadDeclarations.contains {
                $0.path == "quality/capture-quality.json"
            }
        )

        // Mutations are accepted again, and a second seal re-evaluates
        // from the new state and persists a fresh report.
        try await store.persistFramePackage(try framePackage())
        let second = try await store.sealForFinalization(
            requirements: relaxedRequirements
        )
        XCTAssertEqual(second.qualityReport.evidenceFrameCount, 2)
        XCTAssertNotEqual(second.sealToken, first.sealToken)
        XCTAssertEqual(
            second.qualityReport.integrityStatus,
            .pass
        )
    }

    func testConsumeSealedWorkingSetIsTerminal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        _ = try await store.sealForFinalization(
            requirements: relaxedRequirements
        )
        try await store.consumeSealedWorkingSet()
        let consumed = await store.isConsumed
        let sealedAfterConsume = await store.isSealedForFinalization
        XCTAssertTrue(consumed)
        XCTAssertFalse(sealedAfterConsume)

        do {
            try await store.persistFramePackage(try framePackage())
            XCTFail("expected workingSetConsumed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetConsumed)
        }
        do {
            try await store.unseal()
            XCTFail("expected workingSetConsumed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetConsumed)
        }
        do {
            _ = try await store.sealForFinalization(
                requirements: relaxedRequirements
            )
            XCTFail("expected workingSetConsumed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetConsumed)
        }
        do {
            try await store.consumeSealedWorkingSet()
            XCTFail("expected workingSetConsumed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetConsumed)
        }
    }

    func testUnsealAndConsumeRequireASeal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        do {
            try await store.unseal()
            XCTFail("expected workingSetNotSealed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetNotSealed)
        }
        do {
            try await store.consumeSealedWorkingSet()
            XCTFail("expected workingSetNotSealed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetNotSealed)
        }
    }

    func testFailedSealLeavesStoreMutable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        // Default requirements demand a completed RoomPlan capture, so
        // the seal cannot produce a ready report.
        do {
            _ = try await store.sealForFinalization(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
            XCTFail("expected qualityReportNotReady")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .qualityReportNotReady)
        }

        // The failed seal released the barrier: the store is mutable
        // and no canonical quality payload was left behind.
        let sealedAfterFailure = await store.isSealedForFinalization
        XCTAssertFalse(sealedAfterFailure)
        try await store.persistFramePackage(try framePackage())
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        "quality/capture-quality.json"
                    )
                    .path
            )
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.evidenceFrameCount, 1)
        XCTAssertFalse(
            snapshot.payloadDeclarations.contains {
                $0.path == "quality/capture-quality.json"
            }
        )
    }

    func testWriterSuspendedAcrossSealCannotCommitAfterSeal()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        let packages = try (0..<6).map { _ in
            try framePackage()
        }

        enum RaceOutcome: Sendable {
            case frameCommitted
            case frameRejectedBySeal
            case frameUnexpected(String)
            case sealed
            case sealFailed(String)
        }
        let outcomes = await withTaskGroup(
            of: RaceOutcome.self
        ) { group in
            for package in packages {
                group.addTask {
                    do {
                        try await store.persistFramePackage(package)
                        return .frameCommitted
                    } catch let error as CaptureWorkingSetError {
                        return error == .workingSetSealed
                            ? .frameRejectedBySeal
                            : .frameUnexpected("\(error)")
                    } catch {
                        return .frameUnexpected("\(error)")
                    }
                }
            }
            group.addTask {
                do {
                    _ = try await store.sealForFinalization(
                        requirements: CaptureQualityRequirements(
                            rulesetVersion: "0.0.0-test",
                            requireCompletedRoomPlan: false,
                            minimumActiveMeshAnchors: 0,
                            minimumEvidenceFrames: 0
                        )
                    )
                    return .sealed
                } catch {
                    return .sealFailed("\(error)")
                }
            }
            var collected: [RaceOutcome] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        var committedCount = 0
        var rejectedCount = 0
        var unexpected: [String] = []
        var sealFailures: [String] = []
        for outcome in outcomes {
            switch outcome {
            case .frameCommitted:
                committedCount += 1
            case .frameRejectedBySeal:
                rejectedCount += 1
            case .frameUnexpected(let message):
                unexpected.append(message)
            case .sealed:
                break
            case .sealFailed(let message):
                sealFailures.append(message)
            }
        }
        XCTAssertTrue(
            unexpected.isEmpty,
            "unexpected frame errors: \(unexpected)"
        )
        XCTAssertTrue(
            sealFailures.isEmpty,
            "seal failures: \(sealFailures)"
        )
        XCTAssertEqual(committedCount + rejectedCount, packages.count)

        // Whichever side won each race, the sealed state is internally
        // consistent: every committed frame is declared, every rejected
        // frame left nothing behind, and integrity still passes.
        let sealedAtEnd = await store.isSealedForFinalization
        XCTAssertTrue(sealedAtEnd)
        let snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.evidenceFrameCount,
            committedCount
        )
        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(quality.integrityStatus, .pass)

        // After the seal, further mutations are rejected.
        do {
            try await store.persistFramePackage(try framePackage())
            XCTFail("expected workingSetSealed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .workingSetSealed)
        }
    }
}
