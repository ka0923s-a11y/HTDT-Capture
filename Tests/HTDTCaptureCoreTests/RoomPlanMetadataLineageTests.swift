import Foundation
import XCTest
@testable import HTDTCaptureCore

final class RoomPlanMetadataLineageTests: XCTestCase {
    private func makeRuntime() -> CaptureRuntimeProvenance {
        CaptureRuntimeProvenance(
            osVersion: "iOS 20.0",
            osBuild: "22A1",
            appVersion: "0.1.0",
            appBuild: "1"
        )
    }

    private func metadataURL(_ root: URL) -> URL {
        root.appendingPathComponent(
            RoomPlanEvidenceArtifactBuilder.metadataPath
        )
    }

    func testRawCommitPersistsRawOnlyMetadataDocument() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let sessionID = CaptureSessionID()
        let coordinateID = CoordinateSpaceID()
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"raw":"evidence"}"#.utf8),
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            runtime: makeRuntime()
        )

        try await store.persistRawRoomPlan(raw)

        let url = metadataURL(root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(
            CapturedRoomMetadataDocument.self,
            from: data
        )
        XCTAssertEqual(document.schema, "htdt.captured-room-metadata")
        XCTAssertEqual(document.schemaVersion, "1.0.0")
        XCTAssertEqual(
            document.captureRevisionID,
            store.identity.captureRevisionID
        )
        XCTAssertEqual(document.captureSessionID, sessionID)
        XCTAssertEqual(document.coordinateSpaceID, coordinateID)
        XCTAssertEqual(
            document.rawPayloadPath,
            RoomPlanEvidenceArtifactBuilder.rawPath
        )
        XCTAssertEqual(document.rawSHA256, raw.descriptor.sha256)
        XCTAssertEqual(
            document.rawByteCount,
            raw.descriptor.byteCount
        )
        XCTAssertEqual(
            document.rawSerializationFormat,
            raw.descriptor.serializationFormat
        )
        XCTAssertNil(document.processedPayloadPath)
        XCTAssertNil(document.processedSHA256)
        XCTAssertNil(document.processedByteCount)
        XCTAssertEqual(document.runtime, raw.descriptor.runtime)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.capturedRoomMetadata, document)

        let declaration = snapshot.payloadDeclarations.first {
            $0.path == RoomPlanEvidenceArtifactBuilder.metadataPath
        }
        XCTAssertEqual(declaration?.mediaType, "application/json")
        XCTAssertEqual(declaration?.producer, "capture_app")
        XCTAssertEqual(
            declaration?.provenanceClass,
            .captureAppDerived
        )
        XCTAssertEqual(declaration?.role, .canonical)
        XCTAssertEqual(
            declaration?.sourceRefs,
            ["path:\(RoomPlanEvidenceArtifactBuilder.rawPath)"]
        )
    }

    func testProcessedCommitUpgradesMetadataWithProcessedLineage()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"raw":1}"#.utf8),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            runtime: makeRuntime()
        )
        try await store.persistRawRoomPlan(raw)

        let rawOnlyBytes = try Data(contentsOf: metadataURL(root))

        let summary = try CapturedRoomContentSummary(
            surfaceCount: 7,
            objectCount: 3,
            dimensionsMeters: try CapturedRoomDimensionsSummary(
                xMeters: 4.5,
                yMeters: 2.7,
                zMeters: 5.25
            )
        )
        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data(#"{"processed":1}"#.utf8),
            to: raw,
            capturedRoomVersion: "2025.1",
            metadataSummary: summary
        )
        let processed = try XCTUnwrap(lineage.processed)
        try await store.persistProcessedRoomPlan(processed)

        let data = try Data(contentsOf: metadataURL(root))
        XCTAssertNotEqual(data, rawOnlyBytes)

        let document = try JSONDecoder().decode(
            CapturedRoomMetadataDocument.self,
            from: data
        )
        XCTAssertEqual(
            document.processedPayloadPath,
            RoomPlanEvidenceArtifactBuilder.processedPath
        )
        XCTAssertEqual(
            document.processedSHA256,
            processed.descriptor.sha256
        )
        XCTAssertEqual(
            processed.descriptor.sourceRawSHA256,
            document.rawSHA256
        )
        XCTAssertEqual(document.capturedRoomVersion, "2025.1")
        XCTAssertEqual(document.summary, summary)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.capturedRoomMetadata, document)
        let declaration = snapshot.payloadDeclarations.first {
            $0.path == RoomPlanEvidenceArtifactBuilder.metadataPath
        }
        XCTAssertEqual(
            declaration?.sourceRefs,
            [
                "path:\(RoomPlanEvidenceArtifactBuilder.rawPath)",
                "path:\(RoomPlanEvidenceArtifactBuilder.processedPath)",
            ]
        )

        let quality = await store.evaluateQuality()
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testEndRoomPlanTransactionPersistsMetadataAtomically()
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
        let store = try CaptureWorkingSetStore(rootDirectory: root)
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
            data: Data(#"{"end":"raw"}"#.utf8),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            runtime: makeRuntime()
        )
        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data(#"{"end":"processed"}"#.utf8),
            to: raw,
            capturedRoomVersion: "2025.1"
        )

        try await store.persistEndRoomPlanTransaction(
            timingPackage: timing,
            roomPlanLineage: lineage
        )

        let snapshot = await store.snapshot()
        let document = try XCTUnwrap(snapshot.capturedRoomMetadata)
        XCTAssertEqual(
            document.processedSHA256,
            lineage.processed?.descriptor.sha256
        )
        XCTAssertEqual(document.rawSHA256, raw.descriptor.sha256)
        XCTAssertEqual(
            document.captureSessionID,
            context.captureSessionID
        )
        XCTAssertEqual(
            document.coordinateSpaceID,
            context.coordinateSpaceID
        )

        let onDisk = try Data(contentsOf: metadataURL(root))
        let decoded = try JSONDecoder().decode(
            CapturedRoomMetadataDocument.self,
            from: onDisk
        )
        XCTAssertEqual(decoded, document)

        let paths = snapshot.payloadDeclarations.map(\.path)
        XCTAssertTrue(
            paths.contains(
                RoomPlanEvidenceArtifactBuilder.metadataPath
            )
        )

        let quality = await store.evaluateQuality()
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testRollbackRemovesMetadataAndAllowsReEnd() async throws {
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
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(foundation)

        func makeLineage(_ marker: String)
            -> (CaptureTimingPackage, RoomPlanArtifactLineage)
        {
            let timing = try! CaptureTimingPackageBuilder.build(
                start: try! CaptureTimingCorrelation(
                    monotonicSeconds: 1,
                    utc: "2026-09-20T13:30:00Z",
                    method: "fixture"
                ),
                end: try! CaptureTimingCorrelation(
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
            let lineage =
                RoomPlanEvidenceArtifactBuilder.attachProcessed(
                    data: Data(
                        "{\"processed\":\"\(marker)\"}".utf8
                    ),
                    to: raw
                )
            return (timing, lineage)
        }

        let first = makeLineage("one")
        try await store.persistEndRoomPlanTransaction(
            timingPackage: first.0,
            roomPlanLineage: first.1
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: metadataURL(root).path
            )
        )

        try await store.rollbackAcceptedEndTransaction(
            removeOwnedMesh: false
        )

        let rolledBack = await store.snapshot()
        XCTAssertNil(rolledBack.capturedRoomMetadata)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: metadataURL(root).path
            )
        )
        XCTAssertFalse(
            rolledBack.payloadDeclarations.contains {
                $0.path
                    == RoomPlanEvidenceArtifactBuilder.metadataPath
            }
        )

        let second = makeLineage("two")
        try await store.persistEndRoomPlanTransaction(
            timingPackage: second.0,
            roomPlanLineage: second.1
        )
        let reended = await store.snapshot()
        XCTAssertEqual(
            reended.capturedRoomMetadata?.rawSHA256,
            second.1.raw.descriptor.sha256
        )
        let quality = await store.evaluateQuality()
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testTamperedMetadataFailsIntegrity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"raw":"tamper"}"#.utf8),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            runtime: makeRuntime()
        )
        try await store.persistRawRoomPlan(raw)

        try Data(#"{"forged":true}"#.utf8).write(
            to: metadataURL(root),
            options: .atomic
        )

        let quality = await store.evaluateQuality()
        XCTAssertEqual(quality.integrityStatus, .fail)
    }

    func testMetadataEncodingIsDeterministicAndCanonical() throws {
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"raw":"canon"}"#.utf8),
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
            runtime: makeRuntime()
        )
        let revisionID = CaptureRevisionID(
            rawValue: UUID(
                uuidString:
                    "10000000-0000-4000-8000-0000000000ff"
            )!
        )

        let first = try CapturedRoomMetadataPackageBuilder.build(
            captureRevisionID: revisionID,
            raw: raw.descriptor,
            processed: nil
        )
        let second = try CapturedRoomMetadataPackageBuilder.build(
            captureRevisionID: revisionID,
            raw: raw.descriptor,
            processed: nil
        )
        XCTAssertEqual(first.data, second.data)

        let json = String(decoding: first.data, as: UTF8.self)
        XCTAssertTrue(
            json.contains("\"schema\":\"htdt.captured-room-metadata\"")
        )
        XCTAssertTrue(json.contains("\"schema_version\":\"1.0.0\""))
        XCTAssertTrue(json.contains("\"raw_sha256\""))
        // Sorted-key canonical JSON: capture_revision_id precedes
        // capture_session_id and schema follows runtime.
        let revisionRange = try XCTUnwrap(
            json.range(of: "\"capture_revision_id\"")
        )
        let sessionRange = try XCTUnwrap(
            json.range(of: "\"capture_session_id\"")
        )
        let schemaRange = try XCTUnwrap(
            json.range(of: "\"schema\"")
        )
        XCTAssertLessThan(
            revisionRange.lowerBound,
            sessionRange.lowerBound
        )
        XCTAssertLessThan(
            sessionRange.lowerBound,
            schemaRange.lowerBound
        )
    }

    func testMetadataRejectsInvalidSummaryAndLineage() throws {
        XCTAssertThrowsError(
            try CapturedRoomContentSummary(surfaceCount: -1)
        ) { error in
            XCTAssertEqual(
                error as? CapturedRoomMetadataError,
                .negativeCount
            )
        }
        XCTAssertThrowsError(
            try CapturedRoomDimensionsSummary(
                xMeters: .nan,
                yMeters: 1,
                zMeters: 1
            )
        ) { error in
            XCTAssertEqual(
                error as? CapturedRoomMetadataError,
                .nonFiniteDimension
            )
        }

        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"raw":"x"}"#.utf8),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            runtime: makeRuntime()
        )
        var mismatchedProcessed = RoomPlanProcessedEvidenceDescriptor(
            captureSessionID: raw.descriptor.captureSessionID,
            coordinateSpaceID: raw.descriptor.coordinateSpaceID,
            relativePath:
                RoomPlanEvidenceArtifactBuilder.processedPath,
            byteCount: 1,
            sha256: try EvidenceSHA256(
                String(repeating: "ab", count: 32)
            ),
            sourceRawSHA256: try EvidenceSHA256(
                String(repeating: "cd", count: 32)
            ),
            runtime: raw.descriptor.runtime
        )
        XCTAssertThrowsError(
            try CapturedRoomMetadataPackageBuilder.build(
                captureRevisionID: CaptureRevisionID(),
                raw: raw.descriptor,
                processed: mismatchedProcessed
            )
        ) { error in
            XCTAssertEqual(
                error as? CapturedRoomMetadataError,
                .processedLineageMismatch
            )
        }

        mismatchedProcessed.sourceRawSHA256 =
            raw.descriptor.sha256
        mismatchedProcessed.relativePath =
            "roomplan/elsewhere.json"
        XCTAssertThrowsError(
            try CapturedRoomMetadataPackageBuilder.build(
                captureRevisionID: CaptureRevisionID(),
                raw: raw.descriptor,
                processed: mismatchedProcessed
            )
        ) { error in
            XCTAssertEqual(
                error as? CapturedRoomMetadataError,
                .nonCanonicalArtifactPath
            )
        }
    }
}
