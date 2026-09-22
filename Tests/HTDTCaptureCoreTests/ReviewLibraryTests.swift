import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Coverage for the review-library issue cluster: room reference
/// frame (#232), opening review (#231), library metadata + storage
/// (#219/#251), failed-capture diagnostics (#224), HTDT handoff
/// (#225), evidence-privacy removal (#241), discard fencing (#254),
/// revision comparison (#221), and abort transitions (#254).
final class ReviewLibraryTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

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

    private func makeFramePackage(
        sessionID: CaptureSessionID,
        spaceID: CoordinateSpaceID
    ) throws -> FrameEvidencePackage {
        let frameID = EvidenceFrameID()
        let pixel = Data([1, 2, 3, 4])
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: spaceID,
            sessionTimestampSeconds: 2,
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

    private func readyStore(
        root: URL,
        identity: CaptureWorkingSetIdentity =
            CaptureWorkingSetIdentity(),
        context: CaptureSessionContext = CaptureSessionContext()
    ) async throws -> CaptureWorkingSetStore {
        let store = try CaptureWorkingSetStore(
            identity: identity,
            rootDirectory: root
        )
        try await store.persistSessionFoundation(
            makeFoundation(context: context)
        )
        return store
    }

    // MARK: - #232 room reference frame

    func testRoomReferenceFrameNormalizesFrontDirection() throws {
        let doc = try RoomReferenceFrameDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            originMeters: WorldPoint3D(x: 1, y: 0, z: 1),
            frontDirection: WorldPoint3D(x: 0, y: 0, z: -4),
            confirmedAtUTC: "2026-09-20T01:02:03Z"
        )
        XCTAssertEqual(
            doc.frontDirection,
            WorldPoint3D(x: 0, y: 0, z: -1)
        )
    }

    func testRoomReferenceFrameTwoPointProjectsHorizontal() throws {
        // The second point's height drift must not tilt the recorded
        // front direction (#232).
        let doc = try RoomReferenceFrameDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            originMeters: WorldPoint3D(x: 0, y: 1.4, z: 0),
            frontPointMeters: WorldPoint3D(
                x: 0,
                y: 0.9,
                z: -2
            ),
            confirmedAtUTC: "2026-09-20T01:02:03Z"
        )
        XCTAssertEqual(doc.frontDirection.y, 0)
        XCTAssertEqual(doc.frontDirection.z, -1, accuracy: 1e-9)
    }

    func testRoomReferenceFrameRejectsDegenerateFront() throws {
        XCTAssertThrowsError(
            try RoomReferenceFrameDocument(
                captureRevisionID: CaptureRevisionID(),
                captureSessionID: CaptureSessionID(),
                coordinateSpaceID: CoordinateSpaceID(),
                originMeters: WorldPoint3D(x: 0, y: 0, z: 0),
                frontDirection: WorldPoint3D(
                    x: 0,
                    y: 0,
                    z: 0
                ),
                confirmedAtUTC: "2026-09-20T01:02:03Z"
            )
        ) { error in
            XCTAssertEqual(
                error as? RoomReferenceFrameError,
                .degenerateFrontDirection
            )
        }
    }

    func testRoomReferenceFrameRejectsNonUTCTimestamp() throws {
        XCTAssertThrowsError(
            try RoomReferenceFrameDocument(
                captureRevisionID: CaptureRevisionID(),
                captureSessionID: CaptureSessionID(),
                coordinateSpaceID: CoordinateSpaceID(),
                originMeters: WorldPoint3D(x: 0, y: 0, z: 0),
                frontDirection: WorldPoint3D(
                    x: 0,
                    y: 0,
                    z: -1
                ),
                confirmedAtUTC: "not-a-timestamp"
            )
        ) { error in
            XCTAssertEqual(
                error as? RoomReferenceFrameError,
                .invalidTimestamp
            )
        }
    }

    func testRoomReferenceFramePackageRoundTrips() throws {
        let document = try RoomReferenceFrameDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            originMeters: WorldPoint3D(x: 1, y: 0, z: 2),
            frontDirection: WorldPoint3D(x: -1, y: 0, z: 0),
            confirmedAtUTC: "2026-09-20T01:02:03Z"
        )
        let package = try RoomReferenceFramePackageBuilder.build(
            document: document
        )
        XCTAssertEqual(
            package.payloadDeclaration.path,
            RoomReferenceFramePackage.path
        )
        XCTAssertEqual(
            package.payloadDeclaration.producer,
            "room_frame"
        )
        XCTAssertEqual(
            package.payloadDeclaration.provenanceClass,
            .userAnnotation
        )
        let decoded = try JSONDecoder().decode(
            RoomReferenceFrameDocument.self,
            from: package.data
        )
        XCTAssertEqual(decoded, document)
    }

    func testCommitRoomReferenceFrameBindsToSession() async throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let store = try await readyStore(
            root: root,
            identity: identity,
            context: context
        )
        let document = try RoomReferenceFrameDocument(
            captureRevisionID: identity.captureRevisionID,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            originMeters: WorldPoint3D(x: 0, y: 0, z: 0),
            frontDirection: WorldPoint3D(x: 0, y: 0, z: -1),
            confirmedAtUTC: "2026-09-20T01:02:03Z"
        )
        try await store.commitRoomReferenceFrame(
            RoomReferenceFramePackageBuilder.build(
                document: document
            )
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.roomReferenceFrame, document)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    RoomReferenceFramePackage.path
                ).path
            )
        )
        // Removal is safe whenever the set is mutable (#232).
        try await store.removeRoomReferenceFrame()
        let afterRemoval = await store.snapshot()
        XCTAssertNil(afterRemoval.roomReferenceFrame)
    }

    func testCommitRoomReferenceFrameRejectsOtherRevision()
        async throws
    {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let store = try await readyStore(
            root: root,
            context: context
        )
        let document = try RoomReferenceFrameDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            originMeters: WorldPoint3D(x: 0, y: 0, z: 0),
            frontDirection: WorldPoint3D(x: 0, y: 0, z: -1),
            confirmedAtUTC: "2026-09-20T01:02:03Z"
        )
        do {
            try await store.commitRoomReferenceFrame(
                RoomReferenceFramePackageBuilder.build(
                    document: document
                )
            )
            XCTFail("foreign revision must be rejected")
        } catch {
            XCTAssertEqual(
                error as? CaptureWorkingSetError,
                .authorityMismatch
            )
        }
    }

    // MARK: - #231 opening review

    private func opening(
        kind: RoomOpeningKind = .door,
        sourceRef: String = "roomplan:door:00000000-0000-4000-8000-000000000010",
        disposition: RoomOpeningDisposition = .unreviewed
    ) throws -> RoomOpeningCandidate {
        try RoomOpeningCandidate(
            kind: kind,
            source: .roomplanInference,
            sourceRef: sourceRef,
            disposition: disposition
        )
    }

    func testOpeningReviewEditorPreservesDispositionsBySourceRef()
        throws
    {
        let door = try opening()
        let reviewed = try XCTUnwrap(
            OpeningReviewEditor.setDisposition(
                .confirmed,
                openingID: door.openingID,
                in: [door],
                reviewedAtUTC: "2026-09-20T01:05:00Z"
            )
        )
        let merged = OpeningReviewEditor.merge(
            existing: reviewed,
            enumerated: [
                try opening(
                    kind: .window,
                    sourceRef:
                        "roomplan:window:00000000-0000-4000-8000-000000000011"
                ),
                door,
            ]
        )
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(
            merged.first {
                $0.sourceRef
                    == "roomplan:door:00000000-0000-4000-8000-000000000010"
            }?.disposition,
            .confirmed
        )
    }

    func testOpeningReviewPackageRoundTrips() throws {
        let document = try OpeningReviewDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            openings: [
                try opening(
                    disposition: .needsMoreScanning
                ),
            ]
        )
        let package = try OpeningReviewPackageBuilder.build(
            document: document
        )
        XCTAssertEqual(
            package.payloadDeclaration.path,
            OpeningReviewPackage.path
        )
        XCTAssertEqual(
            package.payloadDeclaration.provenanceClass,
            .userAnnotation
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                OpeningReviewDocument.self,
                from: package.data
            ),
            document
        )
    }

    func testCommitOpeningReviewUpsertsAtomically() async throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let store = try await readyStore(
            root: root,
            identity: identity,
            context: context
        )
        let first = try OpeningReviewDocument(
            captureRevisionID: identity.captureRevisionID,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            openings: [try opening()]
        )
        try await store.commitOpeningReview(
            OpeningReviewPackageBuilder.build(document: first)
        )
        // An upsert replaces the committed document; the single
        // reserved path never duplicates.
        let second = try OpeningReviewDocument(
            captureRevisionID: identity.captureRevisionID,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            openings: [
                try opening(disposition: .confirmed),
            ]
        )
        try await store.commitOpeningReview(
            OpeningReviewPackageBuilder.build(document: second)
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.openingReview, second)
    }

    func testOpeningReviewDanglingEvidenceRefRejected() async throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let store = try await readyStore(
            root: root,
            identity: identity,
            context: context
        )
        let base = try opening()
        let dangling = try RoomOpeningCandidate(
            openingID: base.openingID,
            kind: base.kind,
            source: base.source,
            sourceRef: base.sourceRef,
            disposition: base.disposition,
            evidenceRefs: [
                "path:evidence/frames/00000000-0000-4000-8000-000000000099.json",
            ]
        )
        let document = try OpeningReviewDocument(
            captureRevisionID: identity.captureRevisionID,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            openings: [dangling]
        )
        do {
            try await store.commitOpeningReview(
                OpeningReviewPackageBuilder.build(
                    document: document
                )
            )
            XCTFail("unresolvable evidence ref must fail closed")
        } catch CaptureWorkingSetError
            .unresolvableSpatialEvidenceLink
        {}
    }

    // MARK: - #219 library metadata + #251 storage

    func testLibraryMetadataStoreRoundTrip() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let store = CaptureLibraryMetadataStore(captureRoot: root)
        let revisionID = CaptureRevisionID()
        let seriesID = CaptureSeriesID()
        try store.updateRevision(
            revisionID,
            displayName: "Room 3F",
            note: "north wing"
        )
        try store.updateSeries(
            seriesID,
            displayName: "Building A",
            note: nil
        )
        let document = try store.load()
        XCTAssertEqual(
            document.revisions[revisionID.description]?.displayName,
            "Room 3F"
        )
        XCTAssertEqual(
            document.series[seriesID.description]?.displayName,
            "Building A"
        )
        // Reloading a missing file must not synthesize stale content.
        let other = try CaptureLibraryMetadataStore(
            captureRoot: root.appendingPathComponent(
                "absent",
                isDirectory: true
            )
        ).load()
        XCTAssertTrue(other.revisions.isEmpty)
        XCTAssertTrue(other.series.isEmpty)
    }

    func testSeriesGroupingAndSearch() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let series = CaptureSeriesID()
        let other = CaptureSeriesID()
        let metadata = CaptureLibraryMetadataDocument(
            series: [
                series.description: CaptureLibraryEntryMetadata(
                    displayName: "HQ Lobby"
                ),
            ]
        )
        let record = PersistedCaptureRecord(
            captureRevisionID: CaptureRevisionID(),
            captureSeriesID: series,
            finalizedAtUTC: "2026-09-20T01:00:00Z",
            finalizedDirectory: root,
            finalizedValidation: nil,
            exportArchive: nil,
            exportValidation: nil
        )
        let unrelated = PersistedCaptureRecord(
            captureRevisionID: CaptureRevisionID(),
            captureSeriesID: other,
            finalizedAtUTC: "2026-09-20T02:00:00Z",
            finalizedDirectory: root,
            finalizedValidation: nil,
            exportArchive: nil,
            exportValidation: nil
        )
        let groups = CaptureSeriesGrouper.group(
            records: [record, unrelated],
            metadata: metadata
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(
            CaptureSeriesGrouper.matches(
                group: groups.first {
                    $0.captureSeriesID == series
                }!,
                revisionNotes: [:],
                query: "lobby"
            )
        )
        XCTAssertFalse(
            CaptureSeriesGrouper.matches(
                group: groups.first {
                    $0.captureSeriesID == other
                }!,
                revisionNotes: [:],
                query: "lobby"
            )
        )
    }

    func testStorageRecordBreakdownAndDerivedCopy() throws {
        // #251: a record with both copies reports the split and marks
        // the archive as a derived copy the operator may delete
        // independently; archive-only records report archive bytes.
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let archive = root.appendingPathComponent(
            "capture.htdtcapture",
            isDirectory: false
        )
        let revisionID = CaptureRevisionID()
        let manifest = try BundleManifest(
            captureSeriesID: CaptureSeriesID(),
            captureRevisionID: revisionID,
            parentRevisionID: nil,
            captureSessionIDs: [CaptureSessionID()],
            coordinateSpaceIDs: [CoordinateSpaceID()],
            createdAtUTC: "2026-09-20T00:00:00Z",
            finalizedAtUTC: "2026-09-20T01:00:00Z",
            app: BundleAppIdentity(
                version: "test",
                build: "test"
            ),
            files: []
        )
        let validation = try BundleValidationReport(
            manifest: manifest,
            bundleDigest: EvidenceSHA256(
                "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
            ),
            payloadCount: 0
        )
        let both = PersistedCaptureRecord(
            captureRevisionID: revisionID,
            captureSeriesID: manifest.captureSeriesID,
            finalizedAtUTC: "2026-09-20T01:00:00Z",
            finalizedDirectory: root,
            finalizedValidation: validation,
            exportArchive: archive,
            exportValidation: validation,
            finalizedByteCount: 100,
            exportArchiveByteCount: 10
        )
        XCTAssertEqual(both.retainedByteCount, 110)
        XCTAssertTrue(both.exportArchiveIsDerivedCopy)
        XCTAssertTrue(both.canOpen)

        let archiveOnly = PersistedCaptureRecord(
            captureRevisionID: CaptureRevisionID(),
            captureSeriesID: CaptureSeriesID(),
            finalizedAtUTC: "2026-09-20T01:00:00Z",
            finalizedDirectory: nil,
            finalizedValidation: nil,
            exportArchive: archive,
            exportValidation: nil,
            exportArchiveByteCount: 10
        )
        XCTAssertEqual(archiveOnly.retainedByteCount, 10)
        XCTAssertFalse(archiveOnly.exportArchiveIsDerivedCopy)
        XCTAssertFalse(archiveOnly.canOpen)
    }

    // MARK: - #224 failed-capture diagnostics

    func testFailedCaptureInspectionAndDiagnosticPackage() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let revisionID = CaptureRevisionID()
        let working = root
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(
                revisionID.description,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: working,
            withIntermediateDirectories: true
        )
        try Data([1, 2, 3, 4]).write(
            to: working.appendingPathComponent(
                "partial.bin",
                isDirectory: false
            )
        )

        let inspection = try FailedCaptureInspector.inspect(
            workingSetRoot: working,
            captureRevisionID: revisionID,
            failureCode: .interrupted,
            resourceEvents: []
        )
        XCTAssertEqual(inspection.captureRevisionID, revisionID)
        XCTAssertEqual(inspection.entries.count, 1)
        XCTAssertEqual(inspection.totalByteCount, 4)

        let url = try CaptureDiagnosticPackageWriter.write(
            inspection: inspection,
            captureRoot: root,
            stem: revisionID.description
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let report = try JSONDecoder().decode(
            CaptureDiagnosticReport.self,
            from: try Data(contentsOf: url)
        )
        XCTAssertEqual(
            report.schema,
            "htdt.capture.diagnostic-report"
        )
        XCTAssertEqual(
            report.captureRevisionID,
            revisionID.description
        )
        XCTAssertEqual(report.failureCode, "interrupted")
        XCTAssertEqual(report.totalByteCount, 4)
    }

    // MARK: - #225 HTDT handoff

    func testHandoffRequestCarriesDigestHeaders() throws {
        let digest = try EvidenceSHA256(
            "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
        )
        let archiveSHA = try EvidenceSHA256(
            "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        )
        let archive = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString + ".htdtcapture",
                isDirectory: false
            )
        try Data([1, 2, 3]).write(to: archive)
        defer { try? FileManager.default.removeItem(at: archive) }
        let request = try HTDTHandoffRequestBuilder.buildRequest(
            endpoint: URL(string: "https://htdt.example.com/ingest")!,
            archive: archive,
            archiveSHA256: archiveSHA,
            archiveByteCount: 128,
            captureRevisionID: CaptureRevisionID(),
            bundleDigest: digest
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(
            request.value(
                forHTTPHeaderField: "X-HTDT-Capture-Revision-ID"
            )
        )
        XCTAssertEqual(
            request.value(
                forHTTPHeaderField: "X-HTDT-Bundle-Digest"
            ),
            digest.value
        )
        XCTAssertEqual(
            request.value(
                forHTTPHeaderField: "X-HTDT-Archive-SHA256"
            ),
            archiveSHA.value
        )
        XCTAssertEqual(
            request.value(
                forHTTPHeaderField: "X-HTDT-Archive-Bytes"
            ),
            "128"
        )
    }

    func testHandoffRequestRejectsNonHTTPS() throws {
        let archive = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString + ".htdtcapture",
                isDirectory: false
            )
        try Data([1]).write(to: archive)
        defer { try? FileManager.default.removeItem(at: archive) }
        XCTAssertThrowsError(
            try HTDTHandoffRequestBuilder.buildRequest(
                endpoint: URL(
                    string: "http://htdt.example.com/ingest"
                )!,
                archive: archive,
                archiveSHA256: EvidenceSHA256(
                    "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
                ),
                archiveByteCount: 1,
                captureRevisionID: CaptureRevisionID(),
                bundleDigest: EvidenceSHA256(
                    "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTHandoffError,
                .invalidEndpointURL
            )
        }
    }

    func testServerReceiptEchoMismatchRejected() throws {
        let digest = try EvidenceSHA256(
            "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
        )
        let receiptJSON = """
            {
              "ingestion_outcome": "accepted",
              "capture_revision_id": "00000000-0000-4000-8000-0000000000ff",
              "bundle_digest": "0000000000000000000000000000000000000000000000000000000000000000",
              "detail": null
            }
            """.data(using: .utf8)!
        XCTAssertThrowsError(
            try HTDTHandoffRequestBuilder.validateServerReceipt(
                data: receiptJSON,
                captureRevisionID: CaptureRevisionID(
                    canonicalString:
                        "00000000-0000-4000-8000-0000000000ff"
                )!,
                bundleDigest: digest
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTHandoffError,
                .archiveIdentityMismatch
            )
        }
    }

    func testReceiptStoreAppendsAndQueriesByRevision() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let store = HTDTHandoffReceiptStore(captureRoot: root)
        let revision = CaptureRevisionID()
        let receipt = HTDTHandoffReceipt(
            receiptID: UUID().uuidString,
            captureRevisionID: revision,
            captureSeriesID: CaptureSeriesID(),
            bundleDigest:
                "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
            archiveSHA256:
                "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
            archiveByteCount: 7,
            destination: HTDTHandoffDestination(
                name: "Share",
                kind: .shareSheet
            ),
            initiatedAtUTC: "2026-09-20T01:07:00Z",
            outcome: "delivered",
            detail: "operator_shared_via_system_sheet"
        )
        try store.append(receipt)
        try store.append(receipt)
        XCTAssertEqual(
            try store.receipts(for: revision).count,
            2
        )
        XCTAssertTrue(
            try store.receipts(
                for: CaptureRevisionID()
            ).isEmpty
        )
    }

    // MARK: - #254 abort transition + discard fencing

    func testAbortCaptureTransitions() throws {
        func scanToReviewing() -> CaptureStateMachine {
            var machine = CaptureStateMachine()
            for event: CaptureEvent in [
                .beginCapabilityCheck,
                .capabilitiesAccepted,
                .permissionsGranted,
                .prepared,
                .beginReview,
            ] {
                try? machine.apply(event)
            }
            return machine
        }
        // Abort from scanning.
        var machine = CaptureStateMachine()
        for event: CaptureEvent in [
            .beginCapabilityCheck,
            .capabilitiesAccepted,
            .permissionsGranted,
            .prepared,
        ] {
            try machine.apply(event)
        }
        XCTAssertEqual(machine.state, .scanning)
        try machine.apply(.abortCapture)
        XCTAssertEqual(machine.state, .idle)

        // Abort from reviewing.
        var reviewing = scanToReviewing()
        XCTAssertEqual(reviewing.state, .reviewing)
        try reviewing.apply(.abortCapture)
        XCTAssertEqual(reviewing.state, .idle)
    }

    func testAbortCaptureNeverRunsWhileValidating() throws {
        var machine = CaptureStateMachine()
        for event: CaptureEvent in [
            .beginCapabilityCheck,
            .capabilitiesAccepted,
            .permissionsGranted,
            .prepared,
            .beginReview,
            .beginAnnotation,
            .beginValidation,
        ] {
            try machine.apply(event)
        }
        XCTAssertEqual(machine.state, .validating)
        XCTAssertThrowsError(
            try machine.apply(.abortCapture)
        ) { error in
            XCTAssertEqual(
                error as? CaptureStateMachineError,
                CaptureStateMachineError(
                    state: .validating,
                    event: .abortCapture
                )
            )
        }
    }

    func testDiscardRemovesWorkingRevisionDirectory() async throws {
        // The discard guard only fires for the canonical
        // HTDTCapture/working/<revision> layout — anything else fails
        // closed rather than deleting an unexpected path.
        let base = try makeRoot()
        defer { BundleValidationFixture.remove(base) }
        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let revisionDir = base
            .appendingPathComponent("HTDTCapture", isDirectory: true)
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(
                identity.captureRevisionID.description,
                isDirectory: true
            )
        let store = try CaptureWorkingSetStore(
            identity: identity,
            rootDirectory: revisionDir
        )
        try await store.persistSessionFoundation(
            makeFoundation(context: context)
        )
        try await store.persistFramePackage(
            makeFramePackage(
                sessionID: context.captureSessionID,
                spaceID: context.coordinateSpaceID
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: revisionDir.appendingPathComponent(
                    CaptureSessionFoundationPackage.sessionPath
                ).path
            )
        )
        try await store.discardIncompleteRevision()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: revisionDir.path)
        )
        // The store is consumed: further mutations fail closed.
        do {
            try await store.markEndBoundaryFrames([
                EvidenceFrameID(),
            ])
            XCTFail("consumed store must reject mutations")
        } catch CaptureWorkingSetError.workingSetConsumed {}
    }

    // MARK: - #241 evidence privacy removal

    func testRemoveEvidenceFrameGuards() async throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let store = try await readyStore(
            root: root,
            context: context
        )
        let framePackage = try makeFramePackage(
            sessionID: context.captureSessionID,
            spaceID: context.coordinateSpaceID
        )
        try await store.persistFramePackage(framePackage)
        let frameID = framePackage.descriptor.frameID

        // End-boundary frames are closing evidence: never removable.
        try await store.markEndBoundaryFrames([frameID])
        do {
            try await store.removeEvidenceFrame(frameID)
            XCTFail("end-boundary frame must not be removable")
        } catch CaptureWorkingSetError
            .unresolvableSpatialEvidenceLink(let ref)
        {
            XCTAssertTrue(ref.hasPrefix("end_boundary:"))
        }

        // A frame referenced by committed annotation authority is
        // retained: removing it would dangle the reference. Uses a
        // second frame so the end-boundary guard above cannot mask the
        // referenced check.
        let referencedPackage = try makeFramePackage(
            sessionID: context.captureSessionID,
            spaceID: context.coordinateSpaceID
        )
        try await store.persistFramePackage(referencedPackage)
        let referencedID = referencedPackage.descriptor.frameID
        let ref = "path:" + referencedPackage.descriptorPath
        let annotation = try AnnotationEvidencePackageBuilder.build(
            entities: [
                try CaptureAnnotationEntity(
                    type: .referencePoint,
                    coordinateSpaceID: context.coordinateSpaceID,
                    worldFromAnnotation: .identity,
                    referencePointSemantics: .userReferencePoint,
                    label: "note",
                    provenanceClass: .userAnnotation,
                    placement: PlacementProvenance(
                        method: .manualNumeric
                    ),
                    evidenceRefs: [ref]
                ),
            ]
        )
        try await store.persistAnnotationPackage(annotation)
        do {
            try await store.removeEvidenceFrame(referencedID)
            XCTFail("referenced frame must not be removable")
        } catch CaptureWorkingSetError
            .unresolvableSpatialEvidenceLink(let detail)
        {
            XCTAssertTrue(detail.hasPrefix("referenced:"))
        }
    }

    func testRemoveEvidenceFrameDeletesPayloads() async throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let store = try await readyStore(
            root: root,
            context: context
        )
        let framePackage = try makeFramePackage(
            sessionID: context.captureSessionID,
            spaceID: context.coordinateSpaceID
        )
        try await store.persistFramePackage(framePackage)
        let frameID = framePackage.descriptor.frameID
        let snapshotBefore = await store.snapshot()
        XCTAssertEqual(snapshotBefore.evidenceFrameCount, 1)

        try await store.removeEvidenceFrame(frameID)

        let snapshotAfter = await store.snapshot()
        XCTAssertEqual(snapshotAfter.evidenceFrameCount, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    framePackage.descriptorPath
                ).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    framePackage.descriptor.pixelRelativePath
                ).path
            )
        )
    }

    // MARK: - #213 workspace loader

    func testWorkspaceLoaderMarksRetentionAndRemovability()
        async throws
    {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let store = try await readyStore(
            root: root,
            context: context
        )
        let closing = try makeFramePackage(
            sessionID: context.captureSessionID,
            spaceID: context.coordinateSpaceID
        )
        let optional = try makeFramePackage(
            sessionID: context.captureSessionID,
            spaceID: context.coordinateSpaceID
        )
        try await store.persistFramePackage(closing)
        try await store.persistFramePackage(optional)
        try await store.markEndBoundaryFrames([
            closing.descriptor.frameID,
        ])
        let ref = "path:" + optional.descriptorPath
        try await store.persistAnnotationPackage(
            AnnotationEvidencePackageBuilder.build(
                entities: [
                    try CaptureAnnotationEntity(
                        type: .referencePoint,
                        coordinateSpaceID:
                            context.coordinateSpaceID,
                        worldFromAnnotation: .identity,
                        referencePointSemantics:
                            .userReferencePoint,
                        label: "linked",
                        provenanceClass: .userAnnotation,
                        placement: PlacementProvenance(
                            method: .manualNumeric
                        ),
                        evidenceRefs: [ref]
                    ),
                ]
            )
        )

        let snapshot = await store.snapshot()
        let model = CaptureReviewWorkspaceLoader.loadWorkingSet(
            snapshot: snapshot,
            endBoundaryFrameIDs: Set(
                snapshot.endBoundaryFrameIDs
            )
        )
        XCTAssertEqual(model.evidenceItems.count, 2)
        let closingItem = try XCTUnwrap(
            model.evidenceItems.first {
                $0.frameID == closing.descriptor.frameID
            }
        )
        XCTAssertEqual(
            closingItem.retentionReason,
            .endBoundary
        )
        XCTAssertFalse(closingItem.removable)

        let optionalItem = try XCTUnwrap(
            model.evidenceItems.first {
                $0.frameID == optional.descriptor.frameID
            }
        )
        XCTAssertEqual(
            optionalItem.retentionReason,
            .linkedToAuthority
        )
        XCTAssertFalse(optionalItem.removable)
        // The item records the owning authority (an entity id), never
        // just the ref token — so the operator sees WHO retains it.
        XCTAssertEqual(
            optionalItem.referencedBy.count,
            1
        )
        XCTAssertTrue(
            optionalItem.referencedBy.first?.hasPrefix(
                "entity:"
            ) == true
        )
    }

    func testWorkspaceLoaderOperatorSavedFrameIsRemovable() async throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let store = try await readyStore(
            root: root,
            context: context
        )
        let package = try makeFramePackage(
            sessionID: context.captureSessionID,
            spaceID: context.coordinateSpaceID
        )
        try await store.persistFramePackage(package)
        let snapshot = await store.snapshot()
        let model = CaptureReviewWorkspaceLoader.loadWorkingSet(
            snapshot: snapshot,
            endBoundaryFrameIDs: []
        )
        let item = try XCTUnwrap(model.evidenceItems.first)
        XCTAssertEqual(item.retentionReason, .operatorSaved)
        XCTAssertTrue(item.removable)
    }

    // MARK: - #221 revision comparison

    private func persistedContents(
        revisionID: CaptureRevisionID,
        parentRevisionID: CaptureRevisionID? = nil,
        spaceIDs: [CoordinateSpaceID],
        frameCount: Int = 0,
        finalizedAtUTC: String = "2026-09-20T01:00:00Z"
    ) throws -> PersistedCaptureContents {
        let manifest = try BundleManifest(
            captureSeriesID: CaptureSeriesID(),
            captureRevisionID: revisionID,
            parentRevisionID: parentRevisionID,
            captureSessionIDs: [CaptureSessionID()],
            coordinateSpaceIDs: spaceIDs,
            createdAtUTC: "2026-09-20T00:00:00Z",
            finalizedAtUTC: finalizedAtUTC,
            app: BundleAppIdentity(
                version: "test",
                build: "test"
            ),
            files: []
        )
        return PersistedCaptureContents(
            manifest: manifest,
            qualityReport: nil,
            roomMetadata: nil,
            sessionDocument: nil,
            coordinateSpacePolicy: nil,
            entities: [],
            measurements: [],
            openingReview: nil,
            roomReferenceFrame: nil,
            frameDescriptors: [],
            issues: []
        )
    }

    func testRevisionComparisonDetectsFreshSpace() throws {
        let parentSpace = CoordinateSpaceID()
        let parent = try persistedContents(
            revisionID: CaptureRevisionID(),
            spaceIDs: [parentSpace]
        )
        let child = try persistedContents(
            revisionID: CaptureRevisionID(),
            parentRevisionID:
                parent.manifest.captureRevisionID,
            spaceIDs: [CoordinateSpaceID()],
            finalizedAtUTC: "2026-09-20T02:00:00Z"
        )
        let comparison = CaptureRevisionComparator.compare(
            parent: parent,
            child: child
        )
        XCTAssertEqual(
            comparison.parentRevisionID,
            parent.manifest.captureRevisionID
        )
        let freshSpace = try XCTUnwrap(
            comparison.fields.first {
                $0.field == "fresh_coordinate_space"
            }
        )
        XCTAssertEqual(freshSpace.child, "yes")
    }

    func testRevisionComparisonFlagsSharedSpace() throws {
        let shared = CoordinateSpaceID()
        let parent = try persistedContents(
            revisionID: CaptureRevisionID(),
            spaceIDs: [shared]
        )
        let child = try persistedContents(
            revisionID: CaptureRevisionID(),
            parentRevisionID:
                parent.manifest.captureRevisionID,
            spaceIDs: [shared]
        )
        let comparison = CaptureRevisionComparator.compare(
            parent: parent,
            child: child
        )
        let freshSpace = try XCTUnwrap(
            comparison.fields.first {
                $0.field == "fresh_coordinate_space"
            }
        )
        XCTAssertTrue(
            freshSpace.child.contains("same space")
        )
    }

    // MARK: - #232 field/install datum

    private func fieldDatumPackage(
        identity: CaptureWorkingSetIdentity,
        context: CaptureSessionContext,
        sourceEvidenceRefs: [String] = ["room_reference_frame"]
    ) throws -> RoomFieldDatumPackage {
        let origin = try RoomFieldDatumOrigin(
            kind: .roomFrameOrigin,
            ref: "room_reference_frame",
            pointMeters: WorldPoint3D(
                x: 1.5, y: 1.4, z: -0.3
            )
        )
        let axis = try RoomFieldDatumAxis(
            kind: .roomFrameFront,
            refs: ["room_reference_frame"],
            directionMeters: WorldPoint3D(
                x: 0, y: 0.4, z: -1
            )
        )
        let vertical = try RoomFieldDatumVertical(
            kind: .finishedFloor,
            ref: "room_reference_frame",
            zeroElevationMeters: -0.02
        )
        let transform = try RoomFieldDatumPackageBuilder
            .fieldTransform(
                origin: origin,
                axis: axis,
                verticalDatum: vertical
            )
        let document = try RoomFieldDatumDocument(
            captureRevisionID: identity.captureRevisionID,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            origin: origin,
            axis: axis,
            verticalDatum: vertical,
            fieldFromCaptureWorld: transform,
            uncertaintyMeters: nil,
            residualMeters: nil,
            sourceEvidenceRefs: sourceEvidenceRefs,
            confirmedAtUTC: "2026-09-20T01:04:00Z"
        )
        return try RoomFieldDatumPackageBuilder.build(
            document: document
        )
    }

    func testRoomFieldDatumDerivesLeveledTransform() throws {
        let origin = try RoomFieldDatumOrigin(
            kind: .roomFrameOrigin,
            ref: "room_reference_frame",
            pointMeters: WorldPoint3D(
                x: 1.5, y: 1.4, z: -0.3
            )
        )
        let axis = try RoomFieldDatumAxis(
            kind: .roomFrameFront,
            refs: ["room_reference_frame"],
            directionMeters: WorldPoint3D(
                x: 0, y: 0.4, z: -1
            )
        )
        let vertical = try RoomFieldDatumVertical(
            kind: .finishedFloor,
            ref: "room_reference_frame",
            zeroElevationMeters: -0.02
        )
        let transform = try RoomFieldDatumPackageBuilder
            .fieldTransform(
                origin: origin,
                axis: axis,
                verticalDatum: vertical
            )
        // The marked origin keeps its horizontal position but is
        // re-leveled onto the declared vertical zero so field Z = 0
        // lands on the finished floor.
        XCTAssertEqual(
            transform.originMeters,
            WorldPoint3D(x: 1.5, y: -0.02, z: -0.3)
        )
        XCTAssertEqual(
            transform.yAxis,
            WorldPoint3D(x: 0, y: 0, z: -1)
        )
        XCTAssertEqual(
            transform.zAxis,
            WorldPoint3D(x: 0, y: 1, z: 0)
        )
        XCTAssertEqual(
            transform.xAxis,
            WorldPoint3D(x: 1, y: 0, z: 0)
        )
    }

    func testRoomFieldDatumPackageRoundTrips() throws {
        let context = CaptureSessionContext()
        let package = try fieldDatumPackage(
            identity: CaptureWorkingSetIdentity(),
            context: context
        )
        XCTAssertEqual(
            package.payloadDeclaration.path,
            RoomFieldDatumPackage.path
        )
        XCTAssertEqual(
            package.payloadDeclaration.role,
            .canonical
        )
        XCTAssertEqual(
            package.payloadDeclaration.provenanceClass,
            .userAnnotation
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                RoomFieldDatumDocument.self,
                from: package.data
            ),
            package.document
        )
        XCTAssertEqual(package.document.units, "m")
        XCTAssertEqual(
            package.document.axisConvention,
            "y_front_z_up"
        )
        // The emitted document must validate against the published
        // room-field-datum schema.
        _ = try CanonicalPayloadValidator.validateSchemaOwnedJSON(
            path: RoomFieldDatumPackage.path,
            data: package.data
        )
    }

    func testCommitRoomFieldDatumBindsToSession() async throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let store = try await readyStore(
            root: root,
            identity: identity,
            context: context
        )
        let package = try fieldDatumPackage(
            identity: identity,
            context: context
        )
        try await store.commitRoomFieldDatum(package)
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.roomFieldDatum, package.document)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    RoomFieldDatumPackage.path
                ).path
            )
        )
        try await store.removeRoomFieldDatum()
        let afterRemoval = await store.snapshot()
        XCTAssertNil(afterRemoval.roomFieldDatum)
    }

    func testCommitRoomFieldDatumRejectsOtherRevision()
        async throws
    {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let store = try await readyStore(
            root: root,
            context: context
        )
        let package = try fieldDatumPackage(
            identity: CaptureWorkingSetIdentity(),
            context: context
        )
        do {
            try await store.commitRoomFieldDatum(package)
            XCTFail("foreign revision must be rejected")
        } catch {
            XCTAssertEqual(
                error as? CaptureWorkingSetError,
                .authorityMismatch
            )
        }
    }

    func testRoomFieldDatumDanglingFrameRefRejected() async throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let store = try await readyStore(
            root: root,
            identity: identity,
            context: context
        )
        // `frame:` tokens are enforced: an uncommitted frame id
        // fails closed like every other authority reference.
        let package = try fieldDatumPackage(
            identity: identity,
            context: context,
            sourceEvidenceRefs: [
                "frame:00000000-0000-4000-8000-000000000099",
            ]
        )
        do {
            try await store.commitRoomFieldDatum(package)
            XCTFail("unresolvable evidence ref must fail closed")
        } catch CaptureWorkingSetError
            .unresolvableSpatialEvidenceLink
        {}
    }

    func testRoomFieldDatumStalenessEvaluation() throws {
        let context = CaptureSessionContext()
        let document = try fieldDatumPackage(
            identity: CaptureWorkingSetIdentity(),
            context: context
        ).document
        // room_reference_frame + room_reference_frame (x2) are the
        // datum's only refs here.
        var universe = RoomFieldDatumReferenceUniverse(
            tokens: ["room_reference_frame"]
        )
        XCTAssertEqual(
            RoomFieldDatumStalenessEvaluator.evaluate(
                datum: document,
                universe: universe
            ),
            .current
        )
        universe.tokens = []
        XCTAssertEqual(
            RoomFieldDatumStalenessEvaluator.evaluate(
                datum: document,
                universe: universe
            ),
            .stale(
                unresolvedRefs: ["room_reference_frame"]
            )
        )
    }

    func testRoomFieldDatumRoomPlanAndUserRefResolution() throws {
        let uuid = "00000000-0000-4000-8000-0000000000ab"
        let payload = Data(
            "{\"identifier\":\"\(uuid)\"}".utf8
        )
        let universe = RoomFieldDatumReferenceUniverse(
            roomPlanPayload: payload
        )
        XCTAssertTrue(
            universe.resolves("roomplan:wall:\(uuid)")
        )
        XCTAssertFalse(
            universe.resolves(
                "roomplan:wall:00000000-0000-4000-8000-0000000000ff"
            )
        )
        // Operator-resolved `user:` refs never depend on revision
        // content.
        XCTAssertTrue(universe.resolves("user:abc123"))
        XCTAssertFalse(universe.resolves("entity:abc123"))
    }

    // MARK: - #231 opening kinds + open state

    func testOpeningReviewNewKindsAndOpenStateRoundTrip() throws {
        let candidate = try RoomOpeningCandidate(
            kind: .servicePenetration,
            source: .userDeclared,
            sourceRef: "user:00000000-0000-4000-8000-0000000000aa",
            openState: .closed
        )
        XCTAssertEqual(candidate.openState, .closed)
        let encoded = try JSONEncoder().encode(candidate)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: encoded
            ) as? [String: Any]
        )
        // The field is always emitted so persisted captures record
        // the explicit state, not an inferred default.
        XCTAssertEqual(
            object["open_state"] as? String,
            "closed"
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                RoomOpeningCandidate.self,
                from: encoded
            ),
            candidate
        )
        // Legacy payloads without open_state decode as unknown.
        var legacy = object
        legacy.removeValue(forKey: "open_state")
        let legacyData = try JSONSerialization.data(
            withJSONObject: legacy
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                RoomOpeningCandidate.self,
                from: legacyData
            ).openState,
            .unknown
        )
        XCTAssertEqual(
            RoomOpeningKind.hvacGrille.rawValue,
            "hvac_grille"
        )
        XCTAssertEqual(
            RoomOpeningKind.transferGrille.rawValue,
            "transfer_grille"
        )
        XCTAssertEqual(
            RoomOpeningKind.doorUndercut.rawValue,
            "door_undercut"
        )
        XCTAssertEqual(
            RoomOpeningKind.servicePenetration.rawValue,
            "service_penetration"
        )
    }

    func testOpeningReviewEditorOpenStateAndUserDeclared() throws {
        let existing = try opening()
        let updated = try XCTUnwrap(
            OpeningReviewEditor.setOpenState(
                .closed,
                openingID: existing.openingID,
                in: [existing]
            )
        )
        XCTAssertEqual(updated.first?.openState, .closed)

        let appended = try XCTUnwrap(
            OpeningReviewEditor.addUserDeclaredCandidate(
                kind: .hvacGrille,
                sourceRef: "user:00000000-0000-4000-8000-0000000000bb",
                centerMeters: WorldPoint3D(
                    x: 0.4, y: 1.1, z: -2.0
                ),
                widthMeters: 0.3,
                heightMeters: 0.25,
                openState: .open,
                evidenceRefs: [],
                to: updated
            )
        )
        XCTAssertEqual(appended.count, 2)
        let declared = try XCTUnwrap(
            appended.first {
                $0.sourceRef
                    == "user:00000000-0000-4000-8000-0000000000bb"
            }
        )
        XCTAssertEqual(declared.source, .userDeclared)
        XCTAssertEqual(declared.kind, .hvacGrille)
        XCTAssertEqual(declared.openState, .open)
        // Duplicate source refs are rejected, never duplicated.
        XCTAssertNil(
            OpeningReviewEditor.addUserDeclaredCandidate(
                kind: .hvacGrille,
                sourceRef:
                    "user:00000000-0000-4000-8000-0000000000bb",
                centerMeters: WorldPoint3D(
                    x: 0, y: 0, z: 0
                ),
                widthMeters: 0.3,
                heightMeters: 0.3,
                openState: .open,
                evidenceRefs: [],
                to: appended
            )
        )
    }

    // MARK: - #241 automatic keyframe retention

    func testAutomaticKeyframeRetentionClassification()
        async throws
    {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let context = CaptureSessionContext()
        let identity = CaptureWorkingSetIdentity()
        let store = try await readyStore(
            root: root,
            identity: identity,
            context: context
        )
        let frame = try makeFramePackage(
            sessionID: context.captureSessionID,
            spaceID: context.coordinateSpaceID
        )
        try await store.persistFramePackage(frame)
        let keyframe = frame.descriptor.frameID
        try await store.recordAdvisoryNote(
            CaptureAdvisoryNote(
                kind: .automaticKeyframe,
                sessionTimestampSeconds: 1,
                detail:
                    "policy=v1 frame=\(keyframe) usability=0.9"
            )
        )
        let snapshot = await store.snapshot()
        let model = CaptureReviewWorkspaceLoader.loadWorkingSet(
            snapshot: snapshot
        )
        let item = try XCTUnwrap(
            model.evidenceItems.first {
                $0.frameID == keyframe
            }
        )
        XCTAssertEqual(
            item.retentionReason,
            .automaticKeyframe
        )
        XCTAssertTrue(item.removable)
    }
}
