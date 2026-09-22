import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #400: the non-spatial field-mission return — a first-class
/// contribution that completes inventory/photo/settings/wiring plan
/// tasks without a RoomPlan capture revision. Covers the per-task
/// capability preflight, the fulfillment ledger, artifact assembly
/// and container round-trip, the index store, and the mission
/// contribution union.
final class HTDTFieldReturnTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private let planJSONText = """
        {
          "schema": "htdt.capture-task-plan",
          "schema_version": "1.0.0",
          "plan_id": "plan-field-1",
          "plan_version": "2026.09.1",
          "project_ref": "proj-77/doc-9",
          "room_name": "Theater A",
          "issued_at": "2026-09-20T08:00:00Z",
          "entity_checklist": [
            {
              "item_id": "speaker-left",
              "entity_type": "speaker",
              "requirement": "required",
              "channel_role": "L",
              "label_hint": "Left main"
            }
          ],
          "measurement_requests": [],
          "surface_review_tasks": [],
          "semantic_tasks": [
            {
              "item_id": "inventory-amps",
              "requirement": "required",
              "semantic_kind": "inventory_item",
              "label": "Amplifier inventory"
            },
            {
              "item_id": "wall-finish",
              "requirement": "optional",
              "semantic_kind": "surface_semantics",
              "label": "Wall surface"
            }
          ],
          "evidence_tasks": [
            {
              "item_id": "front-photo",
              "requirement": "required",
              "purpose": "front_wall_photo"
            }
          ]
        }
        """

    private func plan() throws -> HTDTCaptureTaskPlan {
        try JSONDecoder().decode(
            HTDTCaptureTaskPlan.self,
            from: Data(planJSONText.utf8)
        )
    }

    private let provenance = HTDTFieldReturnProvenance(
        appName: "HTDT Capture",
        appVersion: "1.4.2",
        deviceModelFamily: "iPad"
    )

    // MARK: - Per-task preflight

    func testPreflightDisablesOnlySpatialTasks() throws {
        let rows = HTDTFieldTaskPreflightEvaluator.evaluate(
            plan: try plan(), spatialAvailable: false
        )
        XCTAssertEqual(rows.count, 4)

        let entity = rows.first {
            $0.itemRef == "task_item:speaker-left"
        }
        XCTAssertEqual(entity?.spatialRequirement, .spatial)
        XCTAssertEqual(entity?.enabled, false)
        XCTAssertEqual(
            entity?.disabledReason,
            HTDTFieldTaskPreflightEvaluator
                .spatialUnavailableReason
        )

        // Inventory + photo tasks stay enabled — they are the
        // non-spatial deliverables this return exists for.
        let inventory = rows.first {
            $0.itemRef == "task_item:inventory-amps"
        }
        XCTAssertEqual(inventory?.spatialRequirement, .nonSpatial)
        XCTAssertEqual(inventory?.enabled, true)
        XCTAssertNil(inventory?.disabledReason)

        let surface = rows.first {
            $0.itemRef == "task_item:wall-finish"
        }
        XCTAssertEqual(surface?.enabled, false)

        let photo = rows.first {
            $0.itemRef == "task_item:front-photo"
        }
        XCTAssertEqual(photo?.spatialRequirement, .nonSpatial)
        XCTAssertEqual(photo?.enabled, true)
    }

    func testPreflightEnablesEverythingWhenSpatialAvailable() throws {
        let rows = HTDTFieldTaskPreflightEvaluator.evaluate(
            plan: try plan(), spatialAvailable: true
        )
        XCTAssertTrue(rows.allSatisfy(\.enabled))
        XCTAssertTrue(rows.allSatisfy { $0.disabledReason == nil })
    }

    // MARK: - Task ledger

    func testSeedTaskLedgerDefaultsAndOutcomeRecording() throws {
        var workspace = HTDTFieldReturnWorkspace(
            missionID: "m-1",
            planID: "plan-field-1",
            createdAtUTC: "2026-09-22T00:00:00Z"
        )
        let preflight = HTDTFieldTaskPreflightEvaluator.evaluate(
            plan: try plan(), spatialAvailable: false
        )
        try workspace.seedTaskLedger(preflight: preflight)
        XCTAssertEqual(workspace.taskLedger.count, 4)

        let inventory = workspace.taskLedger.first {
            $0.itemRef == "task_item:inventory-amps"
        }
        XCTAssertEqual(inventory?.outcome, .unfulfilled)
        // Disabled spatial tasks pre-mark not-applicable — the
        // operator never has to touch them.
        let entity = workspace.taskLedger.first {
            $0.itemRef == "task_item:speaker-left"
        }
        XCTAssertEqual(entity?.outcome, .notApplicable)

        try workspace.recordTaskOutcome(
            itemRef: "task_item:inventory-amps",
            outcome: .fulfilled,
            fulfilledByRefs: [
                "task_item:inventory-amps",
                "equipment:amp-rack-1",
            ],
            note: "counted 2 amplifiers"
        )
        let updated = workspace.taskLedger.first {
            $0.itemRef == "task_item:inventory-amps"
        }
        XCTAssertEqual(updated?.outcome, .fulfilled)
        XCTAssertEqual(
            updated?.fulfilledByRefs,
            ["task_item:inventory-amps", "equipment:amp-rack-1"]
        )

        // Invalid refs and unknown items are typed rejections.
        XCTAssertThrowsError(
            try workspace.recordTaskOutcome(
                itemRef: "task_item:inventory-amps",
                outcome: .fulfilled,
                fulfilledByRefs: ["frame:\(UUID())"]
            )
        )
        XCTAssertThrowsError(
            try workspace.recordTaskOutcome(
                itemRef: "task_item:nope",
                outcome: .fulfilled
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTFieldReturnError,
                .invalidBindingRef("task_item:nope")
            )
        }
        // The ledger is seeded once.
        XCTAssertThrowsError(
            try workspace.seedTaskLedger(preflight: preflight)
        ) { error in
            XCTAssertEqual(
                error as? HTDTFieldReturnError,
                .artifactAlreadyFinalized
            )
        }
    }

    // MARK: - Assemble / container round-trip

    private func workspaceWithEvidence() throws
        -> HTDTFieldReturnWorkspace
    {
        var workspace = HTDTFieldReturnWorkspace(
            missionID: "m-1",
            planID: "plan-field-1",
            planVersion: "2026.09.1",
            createdAtUTC: "2026-09-22T00:00:00Z"
        )
        let evidenceID = FieldEvidenceID()
        let assetPath = FieldEvidenceAssetPaths.imported(
            evidenceID: evidenceID,
            mediaType: .jpeg
        )
        let evidence = try FieldEvidenceRecord(
            evidenceID: evidenceID,
            kind: .installationPhoto,
            title: "Rack front",
            targetRefs: ["task_item:front-photo"],
            asset: .importedFile(
                assetPath: assetPath,
                sha256: try EvidenceSHA256(
                    String(repeating: "ab", count: 32)
                ),
                mediaType: .jpeg,
                originalFilename: "rack.jpg"
            ),
            captureRevisionID: workspace.bindingRevisionID
        )
        workspace.authority.fieldEvidence = [evidence]
        workspace.authority.fieldEvidenceAssets = [
            StagedFieldAsset(
                path: assetPath,
                data: Data("jpeg bytes".utf8)
            ),
        ]
        return workspace
    }

    func testAssembleWriteReadRoundTrip() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = try workspaceWithEvidence()
        let artifact = try HTDTFieldReturnAssembler.assemble(
            workspace: workspace,
            provenance: provenance,
            finalizedAtUTC: "2026-09-22T01:00:00Z"
        )
        let document = artifact.document
        XCTAssertEqual(document.schema, "htdt.field_return")
        XCTAssertEqual(document.schemaVersion, "1.0.0")
        XCTAssertEqual(
            document.authorityBindingScope, "contribution_id"
        )
        XCTAssertEqual(
            document.contributionID, workspace.contributionID
        )
        XCTAssertEqual(document.missionID, "m-1")
        XCTAssertEqual(
            document.finalizedAtUTC, "2026-09-22T01:00:00Z"
        )
        XCTAssertEqual(
            document.authorityDocuments.map(\.path),
            ["authority/field-evidence.json"]
        )
        let stagedPath = workspace.authority.fieldEvidenceAssets[0]
            .path
        XCTAssertEqual(
            document.evidenceAssets.map(\.path), [stagedPath]
        )

        let destination = root.appendingPathComponent(
            "return.\(HTDTFieldReturnArchiveWriter.pathExtension)"
        )
        try HTDTFieldReturnArchiveWriter.write(
            artifact: artifact, to: destination
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.path
            )
        )

        let read = try HTDTFieldReturnArchiveReader.read(
            archive: destination
        )
        XCTAssertEqual(read.document, artifact.document)
        XCTAssertEqual(
            Set(read.entries.map(\.path)),
            Set(artifact.entries.map(\.path))
        )
        let evidenceEntry = read.entries.first {
            $0.path == stagedPath
        }
        XCTAssertEqual(evidenceEntry?.data, Data("jpeg bytes".utf8))
    }

    func testAssemblyRejectsForeignBoundRecord() throws {
        var workspace = HTDTFieldReturnWorkspace(
            createdAtUTC: "2026-09-22T00:00:00Z"
        )
        // A record authored against a real capture revision never
        // silently rebinds into this return — it is a typed failure.
        let foreign = try FieldEvidenceRecord(
            kind: .generalNote,
            title: "from another capture",
            targetRefs: ["task_item:front-photo"],
            asset: nil,
            captureRevisionID: CaptureRevisionID(
                rawValue: UUID(
                    uuidString:
                        "40000000-0000-4000-8000-000000000009"
                )!
            )
        )
        workspace.authority.fieldEvidence = [foreign]
        XCTAssertThrowsError(
            try HTDTFieldReturnAssembler.assemble(
                workspace: workspace,
                provenance: provenance,
                finalizedAtUTC: "2026-09-22T01:00:00Z"
            )
        ) { error in
            guard case .authorityBindingMismatch =
                error as? HTDTFieldReturnError
            else {
                return XCTFail("expected authorityBindingMismatch")
            }
        }
    }

    func testReaderRejectsTamperedArchive() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try workspaceWithEvidence()
        let artifact = try HTDTFieldReturnAssembler.assemble(
            workspace: workspace,
            provenance: provenance,
            finalizedAtUTC: "2026-09-22T01:00:00Z"
        )
        let destination = root.appendingPathComponent(
            "return.htdtfieldreturn"
        )
        _ = try HTDTFieldReturnArchiveWriter.write(
            artifact: artifact, to: destination
        )

        // Flip bytes inside the stored ZIP — the manifest verification
        // must refuse the read.
        var bytes = try Data(contentsOf: destination)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: destination)
        XCTAssertThrowsError(
            try HTDTFieldReturnArchiveReader.read(
                archive: destination
            )
        )

        // The container is its own family — a wrong extension is a
        // typed rejection before any byte inspection.
        XCTAssertThrowsError(
            try HTDTFieldReturnArchiveReader.read(
                archive: root.appendingPathComponent("fake.zip")
            )
        ) { error in
            guard case .invalidContainer =
                error as? HTDTFieldReturnArchiveReader.ReadError
            else {
                return XCTFail("expected invalidContainer")
            }
        }
    }

    // MARK: - Index store + mission linkage

    func testStoreIndexPersistsAcrossReopen() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var workspace = try workspaceWithEvidence()
        let artifact = try HTDTFieldReturnAssembler.assemble(
            workspace: workspace,
            provenance: provenance,
            finalizedAtUTC: "2026-09-22T01:00:00Z"
        )
        workspace.finalizedAtUTC = "2026-09-22T01:00:00Z"
        workspace.finalizedDigest = artifact.document.contentDigest
            .value

        let store = HTDTFieldReturnStore(captureRoot: root)
        var document = try store.load()
        XCTAssertTrue(document.workspaces.isEmpty)
        document.workspaces.append(workspace)
        try store.save(document)

        let reloaded = try HTDTFieldReturnStore(captureRoot: root)
            .load()
        XCTAssertEqual(reloaded.workspaces, [workspace])
    }

    func testMissionRecordAssociatesFieldReturn() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HTDTMissionInboxStore(captureRoot: root)
        let mission = """
            {
              "schema": "htdt.capture-mission",
              "schema_version": "1.0.0",
              "mission_id": "m-1",
              "mission_kind": "initial_survey",
              "purpose": "survey",
              "issued_at": "2026-09-21T00:00:00Z",
              "dependencies": [],
              "plan": \(planJSONText)
            }
            """
        let outcome = try store.importMission(
            data: Data(mission.utf8)
        )
        guard case .imported(let record) = outcome else {
            return XCTFail("expected imported, got \(outcome)")
        }

        let contributionID = HTDTFieldReturnID()
        try store.associateFieldReturn(
            recordID: record.recordID,
            contributionID: contributionID
        )
        let updated = try store.record(id: record.recordID)
        XCTAssertEqual(
            updated?.fieldReturnIDs,
            [contributionID.description]
        )
        XCTAssertEqual(
            updated?.contributions,
            [.fieldReturn(contributionID)]
        )
    }

    func testContributionUnionRoundTrip() throws {
        let contributions: [HTDTMissionContribution] = [
            .captureRevision(
                CaptureRevisionID(
                    rawValue: UUID(
                        uuidString:
                            "40000000-0000-4000-8000-00000000000a"
                    )!
                )
            ),
            .fieldReturn(HTDTFieldReturnID()),
        ]
        let data = try JSONEncoder().encode(contributions)
        let decoded = try JSONDecoder().decode(
            [HTDTMissionContribution].self, from: data
        )
        XCTAssertEqual(decoded, contributions)
        XCTAssertEqual(
            contributions.map(\.kind),
            ["capture_revision", "field_return"]
        )
    }
}
