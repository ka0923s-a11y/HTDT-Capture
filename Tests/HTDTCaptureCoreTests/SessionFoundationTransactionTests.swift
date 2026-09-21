import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #203: session foundation persistence is one recoverable
/// transaction. A failure at any of the four canonical write positions
/// leaves either no committed foundation or a complete prior
/// foundation — never a partial set of declarations or a bound
/// authority without durable bytes. Byte-identical leftovers from an
/// interrupted attempt are adopted so an exact retry can finish the
/// transaction; conflicting bytes fail closed.
final class SessionFoundationTransactionTests: XCTestCase {
    /// Canonical write order inside
    /// `CaptureSessionFoundationPackage.persist(using:)`.
    private let writeOrder = [
        CaptureSessionFoundationPackage.capabilitiesPath,
        CaptureSessionFoundationPackage.configurationPath,
        CaptureSessionFoundationPackage.devicePath,
        CaptureSessionFoundationPackage.sessionPath,
    ]

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

    private func foundationBytes(
        _ package: CaptureSessionFoundationPackage
    ) -> [String: Data] {
        [
            CaptureSessionFoundationPackage.capabilitiesPath:
                package.capabilitiesData,
            CaptureSessionFoundationPackage.configurationPath:
                package.configurationData,
            CaptureSessionFoundationPackage.devicePath:
                package.deviceData,
            CaptureSessionFoundationPackage.sessionPath:
                package.sessionData,
        ]
    }

    /// Inject a conflicting pre-existing file at each write position in
    /// turn. Every position must leave no committed foundation: files
    /// created earlier in the batch roll back, the conflicting bytes
    /// are preserved, and no declarations or identity publish.
    func testFailureAtEachWritePositionLeavesNoCommittedFoundation()
        async throws
    {
        for (index, conflictPath) in writeOrder.enumerated() {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )
            defer {
                try? FileManager.default.removeItem(at: root)
            }

            let store = try CaptureWorkingSetStore(rootDirectory: root)
            let writer = try AtomicCaptureFileWriter(
                rootDirectory: root
            )
            let context = CaptureSessionContext()
            let package = try makeFoundation(context: context)
            let conflictBytes = Data(
                "conflict-\(index)".utf8
            )
            try await writer.write(
                conflictBytes,
                to: try CaptureStorePath(conflictPath)
            )

            do {
                try await store.persistSessionFoundation(package)
                XCTFail(
                    "expected rejection at write position \(index)"
                )
            } catch let error as CaptureFileWriterError {
                guard case .alreadyExists = error else {
                    XCTFail("unexpected writer error: \(error)")
                    return
                }
            }

            // Files created earlier in this batch are rolled back;
            // files later in the batch were never created.
            for (earlierIndex, path) in writeOrder.enumerated()
            where earlierIndex != index {
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: root
                            .appendingPathComponent(path)
                            .path
                    ),
                    "position \(earlierIndex) file survived a "
                        + "failed transaction at position \(index)"
                )
            }
            // The conflicting bytes belong to no attempt and are
            // never deleted.
            XCTAssertEqual(
                try Data(
                    contentsOf: root.appendingPathComponent(
                        conflictPath
                    )
                ),
                conflictBytes
            )

            // No subset of foundation declarations and no authority.
            let snapshot = await store.snapshot()
            XCTAssertTrue(
                snapshot.payloadDeclarations
                    .filter { $0.path.hasPrefix("session/") }
                    .isEmpty,
                "partial declarations after failure at \(index)"
            )
            XCTAssertTrue(snapshot.captureSessionIDs.isEmpty)
            XCTAssertTrue(snapshot.coordinateSpaceIDs.isEmpty)

            // Removing the conflict and retrying the exact same
            // package commits the complete foundation.
            try await writer.removeIfPresent(
                try CaptureStorePath(conflictPath)
            )
            try await store.persistSessionFoundation(package)

            let recovered = await store.snapshot()
            XCTAssertEqual(
                recovered.payloadDeclarations
                    .filter { $0.path.hasPrefix("session/") }
                    .count,
                4
            )
            XCTAssertEqual(
                recovered.captureSessionIDs,
                [context.captureSessionID]
            )
            XCTAssertEqual(
                recovered.coordinateSpaceIDs,
                [context.coordinateSpaceID]
            )
        }
    }

    /// Byte-identical leftovers from an interrupted attempt are
    /// adopted: the retry completes the transaction rather than
    /// failing on files it would have written itself.
    func testIdenticalLeftoverFilesAreAdoptedAndComplete() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let package = try makeFoundation(context: context)
        let bytes = foundationBytes(package)

        // Simulate an interrupted earlier attempt that left exact
        // bytes at the first two write positions.
        let writer = try AtomicCaptureFileWriter(
            rootDirectory: root
        )
        for path in writeOrder.prefix(2) {
            try await writer.write(
                try XCTUnwrap(bytes[path]),
                to: try CaptureStorePath(path)
            )
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(package)

        for path in writeOrder {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                )
            )
            XCTAssertEqual(
                try Data(
                    contentsOf: root.appendingPathComponent(path)
                ),
                bytes[path]
            )
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.payloadDeclarations
                .filter { $0.path.hasPrefix("session/") }
                .count,
            4
        )
        XCTAssertEqual(
            snapshot.captureSessionIDs,
            [context.captureSessionID]
        )
        XCTAssertEqual(
            snapshot.coordinateSpaceIDs,
            [context.coordinateSpaceID]
        )
    }

    /// A subset of foundation files with different bytes is not a
    /// resumable state — the attempt fails closed and preserves the
    /// foreign bytes.
    func testConflictingPreExistingFoundationBytesFailClosed()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let foreignBytes = Data("foreign-foundation".utf8)
        let writer = try AtomicCaptureFileWriter(
            rootDirectory: root
        )
        try await writer.write(
            foreignBytes,
            to: try CaptureStorePath(
                CaptureSessionFoundationPackage.capabilitiesPath
            )
        )
        try await writer.write(
            foreignBytes,
            to: try CaptureStorePath(
                CaptureSessionFoundationPackage.configurationPath
            )
        )

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        do {
            try await store.persistSessionFoundation(
                try makeFoundation()
            )
            XCTFail("expected conflicting foundation rejection")
        } catch let error as CaptureFileWriterError {
            guard case .alreadyExists = error else {
                XCTFail("unexpected writer error: \(error)")
                return
            }
        }

        XCTAssertEqual(
            try Data(
                contentsOf: root.appendingPathComponent(
                    CaptureSessionFoundationPackage.capabilitiesPath
                )
            ),
            foreignBytes
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        CaptureSessionFoundationPackage.devicePath
                    )
                    .path
            )
        )
        let snapshot = await store.snapshot()
        XCTAssertTrue(
            snapshot.payloadDeclarations
                .filter { $0.path.hasPrefix("session/") }
                .isEmpty
        )
        XCTAssertTrue(snapshot.captureSessionIDs.isEmpty)
    }

    /// An identical replay is a no-op, and a different foundation
    /// package on a committed working set fails closed.
    func testCommittedFoundationReplayAndConflict() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let context = CaptureSessionContext()
        let package = try makeFoundation(context: context)
        try await store.persistSessionFoundation(package)

        // Byte-identical replay: idempotent, still exactly four
        // declarations.
        try await store.persistSessionFoundation(package)
        var snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.payloadDeclarations
                .filter { $0.path.hasPrefix("session/") }
                .count,
            4
        )

        // A different foundation is a conflicting canonical payload.
        do {
            try await store.persistSessionFoundation(
                try makeFoundation(context: CaptureSessionContext())
            )
            XCTFail("expected conflicting foundation rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .authorityMismatch)
        }

        snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.captureSessionIDs,
            [context.captureSessionID]
        )
        XCTAssertEqual(
            snapshot.coordinateSpaceIDs,
            [context.coordinateSpaceID]
        )
    }

    /// Reentrant identical attempts adopt each other's durable bytes;
    /// neither may delete the other's committed files.
    func testConcurrentIdenticalAttemptsCommitOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let context = CaptureSessionContext()
        let package = try makeFoundation(context: context)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 4 {
                group.addTask {
                    try await store.persistSessionFoundation(package)
                }
            }
            try await group.waitForAll()
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.payloadDeclarations
                .filter { $0.path.hasPrefix("session/") }
                .count,
            4
        )
        for path in writeOrder {
            XCTAssertEqual(
                try Data(
                    contentsOf: root.appendingPathComponent(path)
                ),
                foundationBytes(package)[path]
            )
        }
    }
}
