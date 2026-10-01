import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #147: the production working-set persistence path must run
/// through the byte/item admission budget — reservations are taken
/// before evidence becomes queued writer work, released on every exit,
/// and exhaustion produces typed backpressure plus a bounded
/// `persistence_backlog` diagnostic.
final class AdmissionBudgetTests: XCTestCase {
    private func makeStore(
        root: URL,
        maxBytes: Int = 64 * 1024 * 1024,
        maxItems: Int = 32
    ) throws -> CaptureWorkingSetStore {
        try CaptureWorkingSetStore(
            rootDirectory: root,
            admissionController: CaptureStoreAdmissionController(
                maxBytes: maxBytes,
                maxItems: maxItems
            )
        )
    }

    private func framePackage(
        pixelBytes: Int = 1024
    ) throws -> FrameEvidencePackage {
        let frameID = EvidenceFrameID()
        let pixel = Data(
            repeating: 0xAB,
            count: pixelBytes
        )
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

    func testReservationsReleaseOnSuccessAndFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try makeStore(root: root)
        try await store.persistFramePackage(try framePackage())

        // A committed write leaves no pending reservation.
        var budget = await store.admissionBudgetSnapshot
        XCTAssertEqual(budget.reservedBytes, 0)
        XCTAssertEqual(budget.reservedItems, 0)

        // A failed write also releases its reservation: pre-seed a
        // conflicting descriptor payload so the frame batch fails.
        let conflicting = try framePackage()
        let writer = try AtomicCaptureFileWriter(
            rootDirectory: root
        )
        try await writer.write(
            Data("conflicting".utf8),
            to: try CaptureStorePath(
                conflicting.descriptor.pixelRelativePath
            )
        )
        do {
            try await store.persistFramePackage(conflicting)
            XCTFail("expected conflicting-bytes rejection")
        } catch let error as CaptureFileWriterError {
            guard case .alreadyExists = error else {
                XCTFail("unexpected writer error: \(error)")
                return
            }
        }

        budget = await store.admissionBudgetSnapshot
        XCTAssertEqual(budget.reservedBytes, 0)
        XCTAssertEqual(budget.reservedItems, 0)
    }

    func testOversizedPackageGetsTypedBackpressure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        // A 4 KB budget cannot admit a 1 MB pixel package.
        let store = try makeStore(root: root, maxBytes: 4 * 1024)
        do {
            try await store.persistFramePackage(
                try framePackage(pixelBytes: 1 << 20)
            )
            XCTFail("expected byteLimitExceeded")
        } catch let error as CaptureStoreAdmissionError {
            guard case .byteLimitExceeded = error else {
                XCTFail("unexpected admission error: \(error)")
                return
            }
        }

        // The rejection emitted a bounded persistence_backlog
        // diagnostic and left nothing reserved or written.
        let report = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertTrue(
            report.resourceEvents.contains {
                $0.kind == .persistenceBacklog
                    && $0.severity == .error
                    && $0.detail.contains("admission_rejected")
            }
        )
        let budget = await store.admissionBudgetSnapshot
        XCTAssertEqual(budget.reservedBytes, 0)
        XCTAssertEqual(budget.reservedItems, 0)
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.evidenceFrameCount, 0)
    }

    func testConcurrentLargeWritesAreBoundedByBudget() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        // Budget admits at most three 512 KB packages at once; eight
        // overlapping writes must serialize or reject explicitly.
        let store = try makeStore(
            root: root,
            maxBytes: 3 * 512 * 1024,
            maxItems: 64
        )
        let packages = try (0..<8).map { _ in
            try framePackage(pixelBytes: 512 * 1024)
        }

        enum Outcome: Sendable {
            case committed
            case rejectedByAdmission
            case unexpected(String)
        }
        let outcomes = await withTaskGroup(
            of: Outcome.self
        ) { group in
            for package in packages {
                group.addTask {
                    do {
                        try await store.persistFramePackage(package)
                        return .committed
                    } catch is CaptureStoreAdmissionError {
                        return .rejectedByAdmission
                    } catch {
                        return .unexpected("\(error)")
                    }
                }
            }
            var collected: [Outcome] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        var committed = 0
        var unexpected: [String] = []
        for outcome in outcomes {
            switch outcome {
            case .committed:
                committed += 1
            case .rejectedByAdmission:
                break
            case .unexpected(let message):
                unexpected.append(message)
            }
        }
        XCTAssertTrue(
            unexpected.isEmpty,
            "unexpected frame errors: \(unexpected)"
        )
        XCTAssertGreaterThan(committed, 0)
        XCTAssertLessThanOrEqual(
            committed,
            packages.count
        )

        // Every reservation was released: the ledger returns to zero.
        let budget = await store.admissionBudgetSnapshot
        XCTAssertEqual(budget.reservedBytes, 0)
        XCTAssertEqual(budget.reservedItems, 0)

        // Committed frames are exactly the ones declared; the bundle
        // remains integrity-clean.
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.evidenceFrameCount, committed)
        let report = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(report.integrityStatus, .pass)
    }

    func testExternalReservationPressureRejectsStoreWrite()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        // A reservation held through the injected controller
        // deterministically leaves too little budget for the next
        // store write — no timing dependence. The budget is sized from
        // the package's real bytes so the margins are exact.
        let package = try framePackage(pixelBytes: 1024)
        let packageBytes = package.descriptorData.count
            + package.pixelPayload.count
        let controller = CaptureStoreAdmissionController(
            maxBytes: packageBytes + 64,
            maxItems: 8
        )
        let store = try CaptureWorkingSetStore(
            rootDirectory: root,
            admissionController: controller
        )
        let held = try controller.reserve(bytes: 1024)

        do {
            try await store.persistFramePackage(package)
            XCTFail("expected byteLimitExceeded")
        } catch let error as CaptureStoreAdmissionError {
            guard case .byteLimitExceeded = error else {
                XCTFail("unexpected admission error: \(error)")
                return
            }
        }

        // Releasing the external hold unblocks the same write — the
        // rejection was recoverable backpressure, not corruption.
        try controller.release(held)
        try await store.persistFramePackage(package)

        let budget = await store.admissionBudgetSnapshot
        XCTAssertEqual(budget.reservedBytes, 0)
        XCTAssertEqual(budget.reservedItems, 0)
        let report = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(report.integrityStatus, .pass)
    }
}
