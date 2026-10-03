import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issues bolph71656-ai/HTDT-Capture#422/legacy bolph71656-ai/HTDT-Capture#423: the paired Mission receive leg (pull model —
/// pairing-scoped enumeration, digest-pinned download, canonical
/// inbox import, receive receipts) and the artifact-aware delivery
/// queue (deliverable identity, generic wire headers, per-kind
/// capability admission, legacy migration).
final class HTDTPairedDeliveryTests: XCTestCase {

    // MARK: - Scripted transports

    /// legacy bolph71656-ai/HTDT-Capture#422: serves a canned listing plus package bytes and records
    /// every call so tests can assert enumeration/download/receipt
    /// behavior without a network.
    private actor MissionTransport: HTDTMissionReceiveTransport {
        struct Script {
            var listing: HTDTPendingMissionListing?
            var packages: [String: Data] = [:]
            var listingError: Error?
            var receiptError: Error?
        }
        private var script: Script
        init(script: Script = Script()) {
            self.script = script
        }
        func setScript(_ script: Script) {
            self.script = script
        }
        private(set) var listCalls = 0
        private(set) var downloads: [String] = []
        private(set) var postedReceipts:
            [HTDTMissionReceiveReceipt] = []

        func listPending(
            captureInstanceID: String,
            endpoint: URL,
            pinnedIdentity: String?
        ) async throws -> HTDTPendingMissionListing {
            listCalls += 1
            if let e = script.listingError { throw e }
            return script.listing ?? HTDTPendingMissionListing(
                captureInstanceID: captureInstanceID,
                packages: []
            )
        }

        func downloadPackage(
            packageID: String,
            captureInstanceID: String,
            endpoint: URL,
            pinnedIdentity: String?,
            maxBytes: Int64
        ) async throws -> Data {
            downloads.append(packageID)
            guard let data = script.packages[packageID] else {
                throw HTDTMissionReceiveError.transportFailed(
                    "no fixture package"
                )
            }
            return data
        }

        func postReceipt(
            _ receipt: HTDTMissionReceiveReceipt,
            endpoint: URL,
            pinnedIdentity: String?
        ) async throws {
            if let e = script.receiptError { throw e }
            postedReceipts.append(receipt)
        }
    }

    /// legacy bolph71656-ai/HTDT-Capture#423: accepts everything and echoes the artifact identity
    /// back the way a legacy bolph71656-ai/HTDT-Capture#423-aware receiver must.
    private actor EchoTransport: HTDTDeliveryTransport {
        private(set) var submissions:
            [(deliverable: HTDTDeliverableIdentity, deliveryID: String?)]
            = []

        func submit(
            archive: URL,
            archiveSHA256: EvidenceSHA256,
            archiveByteCount: Int64,
            deliverable: HTDTDeliverableIdentity,
            endpoint: URL,
            deliveryID: String?,
            pinnedIdentity: String?
        ) async throws -> HTDTIngestionResponse {
            submissions.append((
                deliverable: deliverable, deliveryID: deliveryID
            ))
            return HTDTIngestionResponse(
                ingestionOutcome:
                    HTDTIngestionResponse.outcomeAccepted,
                captureRevisionID: deliverable.artifactID,
                bundleDigest: deliverable.semanticDigest,
                artifactKind: deliverable.artifactKind.rawValue,
                artifactID: deliverable.artifactID,
                artifactDigest: deliverable.semanticDigest,
                stagingRef: "st-1"
            )
        }
    }

    // MARK: - Fixtures

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func planJSON(planID: String) -> String {
        """
        {
          "schema": "htdt.capture-task-plan",
          "schema_version": "1.0.0",
          "plan_id": "\(planID)",
          "plan_version": "2026.09.1",
          "project_ref": "proj-1/doc-1",
          "room_name": "Theater A",
          "issued_at": "2026-09-20T08:00:00Z",
          "entity_checklist": [],
          "measurement_requests": [],
          "surface_review_tasks": [],
          "evidence_targets": [],
          "expected_channel_roles": []
        }
        """
    }

    private func missionData(
        missionID: String,
        planID: String,
        supersedesMissionID: String? = nil
    ) -> Data {
        var fields = """
              "schema": "htdt.capture-mission",
              "schema_version": "1.0.0",
              "mission_id": "\(missionID)",
              "mission_kind": "initial_survey",
              "issued_at": "2026-09-21T00:00:00Z",
              "dependencies": [],
              "plan": \(planJSON(planID: planID))
            """
        if let supersedesMissionID {
            fields += ",\n  \"supersedes_mission_id\": "
                + "\"\(supersedesMissionID)\""
        }
        return Data("{\n\(fields)\n}".utf8)
    }

    private func descriptor(
        for data: Data,
        packageID: String,
        missionID: String? = nil
    ) -> HTDTPendingMissionDescriptor {
        HTDTPendingMissionDescriptor(
            packageID: packageID,
            missionID: missionID,
            byteSize: Int64(data.count),
            packageSHA256: "sha256:"
                + EvidenceIntegrity.sha256(of: data).value
        )
    }

    private func pinText() -> String {
        "sha256:"
            + String(repeating: "a", count: 64)
    }

    private func pairReceiver(
        root: URL,
        missionsURL: String? = "https://rx.local:8443/missions",
        revoked: Bool = false
    ) throws -> PairedHTDTDestination {
        let store = PairedHTDTDestinationStore(captureRoot: root)
        let payload = HTDTReceiverPairingPayload(
            receiverInstanceID: "rx-1",
            displayName: "Stage Mac",
            endpointURL: "https://rx.local:8443/ingest",
            missionsEndpointURL: missionsURL,
            pinnedIdentity: pinText(),
            pairingToken: "tok"
        )
        var destination = try store.pair(payload: payload)
        if revoked {
            try store.revoke(destinationID: destination.destinationID)
            destination = try XCTUnwrap(
                try store.load().destinations.first
            )
        }
        return destination
    }

    private func writeArchive(
        _ root: URL, name: String, bytes: Int = 2048
    ) throws -> (url: URL, sha: EvidenceSHA256, count: Int64) {
        let url = root.appendingPathComponent(name)
        let data = Data((0..<bytes).map { UInt8($0 % 253) })
        try data.write(to: url)
        return (url, EvidenceIntegrity.sha256(of: data),
                Int64(data.count))
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#422 receive leg

    func testReceiveImportsAndPostsReceipt() async throws {
        let root = try makeRoot()
        let destination = try pairReceiver(root: root)
        let package = missionData(
            missionID: "m-100", planID: "p-1"
        )
        var script = MissionTransport.Script()
        script.packages["pkg-1"] = package
        script.listing = HTDTPendingMissionListing(
            packages: [
                descriptor(
                    for: package,
                    packageID: "pkg-1",
                    missionID: "m-100"
                )
            ]
        )
        let transport = MissionTransport(script: script)
        let service = HTDTMissionReceiveService(
            captureRoot: root, transport: transport
        )

        let reports = await service.syncAll()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].enumerated, 1)
        XCTAssertEqual(reports[0].imported, 1)
        XCTAssertEqual(reports[0].conflicts, [])

        // The canonical importer ran — the record is in the inbox.
        let record = try XCTUnwrap(
            try service.inboxStore.record(missionID: "m-100")
        )
        XCTAssertEqual(record.missionID, "m-100")

        // Receipt is local AND posted — "received and staged", the
        // only claim the receipt makes.
        let receipts = try service.receiptStore.receipts(
            for: destination.destinationID
        )
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].validationResult, "imported")
        XCTAssertEqual(receipts[0].missionRecordID, record.recordID)
        let posted = await transport.postedReceipts
        XCTAssertEqual(posted.count, 1)
        XCTAssertTrue(posted[0].receiverMayMarkReceived)
    }

    func testReceiveDuplicateIsIdempotent() async throws {
        let root = try makeRoot()
        _ = try pairReceiver(root: root)
        let package = missionData(
            missionID: "m-200", planID: "p-2"
        )
        var script = MissionTransport.Script()
        script.packages["pkg-2"] = package
        script.listing = HTDTPendingMissionListing(
            packages: [
                descriptor(
                    for: package,
                    packageID: "pkg-2",
                    missionID: "m-200"
                )
            ]
        )
        let transport = MissionTransport(script: script)
        let service = HTDTMissionReceiveService(
            captureRoot: root, transport: transport
        )

        _ = await service.syncAll()
        let second = await service.syncAll()
        XCTAssertEqual(second[0].duplicates, 1)
        XCTAssertEqual(second[0].imported, 0)
        // Same pinned digest: the retry acknowledges without a
        // second download (legacy bolph71656-ai/HTDT-Capture#422 retry semantics).
        let downloads = await transport.downloads
        XCTAssertEqual(downloads.count, 1)
        let records = try service.inboxStore.records()
        XCTAssertEqual(records.count, 1)
        let posted = await transport.postedReceipts
        XCTAssertEqual(posted.count, 2)
    }

    func testReceiveConflictNeverMerges() async throws {
        let root = try makeRoot()
        _ = try pairReceiver(root: root)
        let variant = missionData(
            missionID: "m-300", planID: "p-3b"
        )
        var script = MissionTransport.Script()
        script.packages["pkg-3"] = variant
        script.listing = HTDTPendingMissionListing(
            packages: [
                descriptor(
                    for: variant,
                    packageID: "pkg-3",
                    missionID: "m-300"
                )
            ]
        )
        let transport = MissionTransport(script: script)
        let service = HTDTMissionReceiveService(
            captureRoot: root, transport: transport
        )
        // Pre-stage mission m-300 with different bytes.
        try service.inboxStore.importMission(
            data: missionData(missionID: "m-300", planID: "p-3")
        )

        let reports = await service.syncAll()
        XCTAssertEqual(reports[0].conflicts, ["pkg-3"])
        XCTAssertEqual(reports[0].imported, 0)
        // No merge, no overwrite — still exactly the staged record.
        XCTAssertEqual(try service.inboxStore.records().count, 1)
        // A conflict is a local receipt only — the receiver must not
        // mark this package `received`.
        let posted = await transport.postedReceipts
        XCTAssertTrue(posted.isEmpty)
    }

    func testReceiveExplicitSupersession() async throws {
        let root = try makeRoot()
        _ = try pairReceiver(root: root)
        let v2 = missionData(
            missionID: "m-400-v2",
            planID: "p-4",
            supersedesMissionID: "m-400"
        )
        var script = MissionTransport.Script()
        script.packages["pkg-4"] = v2
        script.listing = HTDTPendingMissionListing(
            packages: [
                descriptor(
                    for: v2, packageID: "pkg-4",
                    missionID: "m-400-v2"
                )
            ]
        )
        let transport = MissionTransport(script: script)
        let service = HTDTMissionReceiveService(
            captureRoot: root, transport: transport
        )
        try service.inboxStore.importMission(
            data: missionData(missionID: "m-400", planID: "p-4")
        )

        let reports = await service.syncAll()
        XCTAssertEqual(reports[0].superseded, 1)
        XCTAssertEqual(try service.inboxStore.records().count, 2)
    }

    func testReceiveRejectsTamperedBytes() async throws {
        let root = try makeRoot()
        _ = try pairReceiver(root: root)
        // Descriptor pins bytes that don't match the download.
        let package = missionData(
            missionID: "m-500", planID: "p-5"
        )
        let badDescriptor = HTDTPendingMissionDescriptor(
            packageID: "pkg-5",
            missionID: "m-500",
            byteSize: Int64(package.count),
            packageSHA256: "sha256:"
                + EvidenceIntegrity.sha256(
                    of: Data("tampered".utf8)
                ).value
        )
        var script = MissionTransport.Script()
        script.packages["pkg-5"] = package
        script.listing = HTDTPendingMissionListing(
            packages: [badDescriptor]
        )
        let transport = MissionTransport(script: script)
        let service = HTDTMissionReceiveService(
            captureRoot: root, transport: transport
        )

        let reports = await service.syncAll()
        XCTAssertEqual(reports[0].rejected, ["pkg-5"])
        XCTAssertEqual(reports[0].imported, 0)
        XCTAssertTrue(try service.inboxStore.records().isEmpty)
    }

    func testReceiveSkipsRevokedAndUnserved() async throws {
        let root = try makeRoot()
        // Revoked destination: skipped by syncAll entirely, and a
        // direct sync notes the revocation without fetching —
        // revocation stops network activity but keeps records
        // (legacy bolph71656-ai/HTDT-Capture#422 §revocation).
        let revoked = try pairReceiver(root: root, revoked: true)
        let transport = MissionTransport()
        let service = HTDTMissionReceiveService(
            captureRoot: root, transport: transport
        )
        var reports = await service.syncAll()
        XCTAssertTrue(reports.isEmpty)
        let revokedReport = await service.sync(destination: revoked)
        XCTAssertEqual(
            revokedReport.notes, ["destination_revoked"]
        )
        var listCalls = await transport.listCalls
        XCTAssertEqual(listCalls, 0)

        // Pairing without a Mission-serving URL: noted, no fetch.
        let root2 = try makeRoot()
        _ = try pairReceiver(root: root2, missionsURL: nil)
        let transport2 = MissionTransport()
        let service2 = HTDTMissionReceiveService(
            captureRoot: root2, transport: transport2
        )
        reports = await service2.syncAll()
        XCTAssertEqual(reports[0].notes, ["missions_not_served"])
        listCalls = await transport2.listCalls
        XCTAssertEqual(listCalls, 0)
    }

    func testCaptureIdentityStableAcrossSyncs() async throws {
        let root = try makeRoot()
        _ = try pairReceiver(root: root)
        let service = HTDTMissionReceiveService(
            captureRoot: root, transport: MissionTransport()
        )
        _ = await service.syncAll()
        let first = try service.identityStore.loadOrCreate()
        _ = await service.syncAll()
        let second = try service.identityStore.loadOrCreate()
        // Retries reuse the persisted Capture identity — a retry
        // never mints a second one (legacy bolph71656-ai/HTDT-Capture#422 §offline).
        XCTAssertEqual(
            first.captureInstanceID, second.captureInstanceID
        )
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#423 artifact-aware delivery

    func testLegacyJobDecodesToCaptureBundleDeliverable() throws {
        // A ledger row written before legacy bolph71656-ai/HTDT-Capture#423: no `deliverable` field.
        let legacy = """
            {
              "delivery_job_id": "job-legacy",
              "capture_revision_id":
                "00000000-0000-4000-8000-0000000000aa",
              "capture_series_id":
                "00000000-0000-4000-8000-0000000000bb",
              "bundle_digest": "digest-1",
              "archive_sha256": "\(String(repeating: "0", count: 64))",
              "archive_byte_count": 10,
              "payload_relative_path":
                "delivery-queue/payloads/job-legacy.htdtcapture",
              "source_archive_name": "capture.htdtcapture",
              "destination": {
                "name": "Stage Mac", "kind": "endpoint",
                "url": "https://rx.local:8443/ingest"
              },
              "created_at": "2026-09-01T00:00:00Z",
              "attempt_count": 0, "state": "queued"
            }
            """.data(using: .utf8)!
        let job = try JSONDecoder().decode(
            HTDTDeliveryJob.self, from: legacy
        )
        XCTAssertNil(job.deliverable)
        let deliverable = job.normalizedDeliverable
        XCTAssertEqual(deliverable.artifactKind, .captureBundle)
        XCTAssertEqual(
            deliverable.artifactID,
            "00000000-0000-4000-8000-0000000000aa"
        )
        XCTAssertEqual(deliverable.semanticDigest, "digest-1")
        XCTAssertEqual(job.artifactKind, .captureBundle)
    }

    func testEnqueueFieldReturnWritesExplicitDeliverable() throws {
        let root = try makeRoot()
        let (url, sha, count) = try writeArchive(
            root, name: "ret.htdtfieldreturn"
        )
        let queue = HTDTDeliveryQueue(
            captureRoot: root, transport: EchoTransport()
        )
        let contributionID = HTDTFieldReturnID()
        let job = try queue.enqueueFieldReturn(
            contributionID: contributionID,
            contentDigest: "fr-digest-1",
            archiveSHA256: sha,
            archiveByteCount: count,
            archiveURL: url,
            destination: HTDTHandoffDestination(
                name: "Stage Mac", kind: .endpoint,
                url: "https://rx.local:8443/ingest"
            ),
            missionRecordID: "mission-rec-9"
        )
        // The kind persists explicitly — no reliance on the file
        // extension to rediscover it (legacy bolph71656-ai/HTDT-Capture#423 §4).
        let deliverable = try XCTUnwrap(job.deliverable)
        XCTAssertEqual(deliverable.artifactKind, .fieldReturn)
        XCTAssertEqual(
            deliverable.artifactID, contributionID.description
        )
        XCTAssertEqual(deliverable.semanticDigest, "fr-digest-1")
        // No fake CaptureRevisionID is minted for a field return.
        XCTAssertNil(job.captureRevisionID)
        XCTAssertNil(job.bundleDigest)
        XCTAssertTrue(
            job.payloadRelativePath.hasSuffix(".htdtfieldreturn")
        )
        XCTAssertEqual(
            try queue.jobs().first?.deliverable?.artifactKind,
            .fieldReturn
        )
    }

    func testFieldReturnRequestUsesGenericHeadersOnly() throws {
        let root = try makeRoot()
        let (url, sha, _) = try writeArchive(
            root, name: "ret.htdtfieldreturn", bytes: 16
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let contributionID = HTDTFieldReturnID()
        let deliverable = HTDTDeliverableIdentity.fieldReturn(
            contributionID: contributionID,
            contentDigest: "fr-digest-1"
        )
        let request = try HTDTHandoffRequestBuilder.buildRequest(
            endpoint: URL(
                string: "https://rx.local:8443/ingest"
            )!,
            archive: url,
            archiveSHA256: sha,
            archiveByteCount: 16,
            deliverable: deliverable,
            deliveryID: "job-7"
        )
        // Generic versioned headers carry the artifact identity…
        XCTAssertEqual(
            request.value(
                forHTTPHeaderField: "X-HTDT-Artifact-Kind"
            ),
            "field_return"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-HTDT-Artifact-ID"),
            contributionID.description
        )
        XCTAssertEqual(
            request.value(
                forHTTPHeaderField: "X-HTDT-Artifact-Digest"
            ),
            "fr-digest-1"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-HTDT-Delivery-ID"),
            "job-7"
        )
        // …and the Capture legacy headers are never attached to a
        // field return — a contribution id is not a revision id.
        XCTAssertNil(
            request.value(
                forHTTPHeaderField: "X-HTDT-Capture-Revision-ID"
            )
        )
        XCTAssertNil(
            request.value(
                forHTTPHeaderField: "X-HTDT-Bundle-Digest"
            )
        )
    }

    func testCaptureRequestKeepsLegacyHeaders() throws {
        let root = try makeRoot()
        let (url, sha, _) = try writeArchive(
            root, name: "cap.htdtcapture", bytes: 16
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let revisionID = CaptureRevisionID()
        let digest = EvidenceIntegrity.sha256(of: Data("b".utf8))
        let request = try HTDTHandoffRequestBuilder.buildRequest(
            endpoint: URL(
                string: "https://rx.local:8443/ingest"
            )!,
            archive: url,
            archiveSHA256: sha,
            archiveByteCount: 16,
            deliverable: .captureBundle(
                revisionID: revisionID,
                bundleDigest: digest.value
            )
        )
        // During migration both the generic and legacy headers ride —
        // Capture-only receivers stay usable (legacy bolph71656-ai/HTDT-Capture#423 §5).
        XCTAssertEqual(
            request.value(
                forHTTPHeaderField: "X-HTDT-Artifact-Kind"
            ),
            "capture_bundle"
        )
        XCTAssertEqual(
            request.value(
                forHTTPHeaderField: "X-HTDT-Capture-Revision-ID"
            ),
            revisionID.description
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-HTDT-Bundle-Digest"),
            digest.value
        )
    }

    func testFieldReturnReceiptRequiresArtifactEcho() throws {
        let contributionID = HTDTFieldReturnID()
        let deliverable = HTDTDeliverableIdentity.fieldReturn(
            contributionID: contributionID,
            contentDigest: "fr-digest-1"
        )
        // A bare HTTP 200 / receipt without the artifact echo is
        // never accepted as proof of staging (legacy bolph71656-ai/HTDT-Capture#423 §6).
        let empty = Data(
            "{\"ingestion_outcome\":\"accepted\"}".utf8
        )
        XCTAssertThrowsError(
            try HTDTHandoffRequestBuilder.validateServerReceipt(
                data: empty, deliverable: deliverable
            )
        )
        // A mismatched artifact echo is rejected just as hard.
        let wrong = HTDTIngestionResponse(
            ingestionOutcome: HTDTIngestionResponse.outcomeAccepted,
            artifactKind: "capture_bundle",
            artifactID: "not-the-contribution",
            artifactDigest: "other-digest"
        )
        XCTAssertThrowsError(
            try HTDTHandoffRequestBuilder.validateServerReceipt(
                data: JSONEncoder().encode(wrong),
                deliverable: deliverable
            )
        )
        // An exact echo validates.
        let right = HTDTIngestionResponse(
            ingestionOutcome: HTDTIngestionResponse.outcomeAccepted,
            artifactKind: "field_return",
            artifactID: contributionID.description,
            artifactDigest: "fr-digest-1"
        )
        XCTAssertNoThrow(
            try HTDTHandoffRequestBuilder.validateServerReceipt(
                data: JSONEncoder().encode(right),
                deliverable: deliverable
            )
        )
    }

    func testFieldReturnJobStagesAndReceiptsWithEcho() async throws {
        let root = try makeRoot()
        let (url, sha, count) = try writeArchive(
            root, name: "ret.htdtfieldreturn"
        )
        let transport = EchoTransport()
        let queue = HTDTDeliveryQueue(
            captureRoot: root, transport: transport
        )
        let receipts = HTDTHandoffReceiptStore(captureRoot: root)
        let contributionID = HTDTFieldReturnID()
        let job = try queue.enqueueFieldReturn(
            contributionID: contributionID,
            contentDigest: "fr-digest-1",
            archiveSHA256: sha,
            archiveByteCount: count,
            archiveURL: url,
            destination: HTDTHandoffDestination(
                name: "Stage Mac", kind: .endpoint,
                url: "https://rx.local:8443/ingest"
            )
        )
        let jobs = await queue.processDueJobs(
            receiptStore: receipts
        )
        XCTAssertEqual(jobs.first?.state, .deliveredStaged)
        let saved = try receipts.receipts(
            forArtifactID: contributionID.description
        )
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].artifactKind, "field_return")
        XCTAssertEqual(
            saved[0].artifactID, contributionID.description
        )
        XCTAssertEqual(saved[0].deliveryJobID, job.deliveryJobID)
    }

    func testDeliverablePreflightGatesOnArtifactKind() throws {
        // A capability document with no declared artifact kinds is a
        // Capture-only receiver (legacy bolph71656-ai/HTDT-Capture#423 §5) — captures stay usable,
        // field returns are refused with a named gap.
        let captureOnly = HTDTEndpointCapabilityDocument(
            endpointIdentity: "rx-1",
            handoffProtocolVersions: [
                HTDTEndpointCapabilityDocument.handoffProtocol
            ],
            acceptedBundleSchemaVersions: ["1.0.0"]
        )
        XCTAssertEqual(captureOnly.acceptedKinds.count, 1)
        XCTAssertEqual(
            captureOnly.acceptedKinds[0].artifactKind,
            "capture_bundle"
        )
        let fieldReturn = HTDTDeliverableIdentity.fieldReturn(
            contributionID: HTDTFieldReturnID(),
            contentDigest: "d"
        )
        var verdict = HTDTCompatibilityChecker.checkDeliverable(
            deliverable: fieldReturn,
            archiveByteCount: 100,
            capabilities: captureOnly
        )
        guard case .incompatible(let gaps) = verdict else {
            return XCTFail("expected incompatible")
        }
        XCTAssertTrue(
            gaps.contains {
                $0.kind == .unsupportedArtifactKind
            }
        )
        // A capture bundle to the same receiver is unaffected.
        let capture = HTDTDeliverableIdentity.captureBundle(
            revisionID: CaptureRevisionID(),
            bundleDigest: "bd"
        )
        verdict = HTDTCompatibilityChecker.checkDeliverable(
            deliverable: capture,
            archiveByteCount: 100,
            capabilities: captureOnly
        )
        XCTAssertEqual(verdict, .compatible)

        // Declaring field_return admission flips the verdict.
        let fieldReturnAware = HTDTEndpointCapabilityDocument(
            endpointIdentity: "rx-1",
            handoffProtocolVersions: [
                HTDTEndpointCapabilityDocument.handoffProtocol
            ],
            acceptedBundleSchemaVersions: ["1.0.0"],
            acceptedArtifactKinds: [
                HTDTArtifactKindCapability(
                    artifactKind: "capture_bundle",
                    acceptedSchemaVersions: ["1.0.0"]
                ),
                HTDTArtifactKindCapability(
                    artifactKind: "field_return",
                    acceptedSchemaVersions: [
                        HTDTFieldReturnDocument.schemaVersionValue
                    ]
                ),
            ]
        )
        verdict = HTDTCompatibilityChecker.checkDeliverable(
            deliverable: fieldReturn,
            archiveByteCount: 100,
            capabilities: fieldReturnAware
        )
        XCTAssertEqual(verdict, .compatible)
    }
}
