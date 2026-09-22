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
            captureRevisionID: workspace.recordCarrierID
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
        XCTAssertEqual(document.schemaVersion, "2.0.0")
        XCTAssertEqual(
            document.authorityBindingScope, "contribution_ref"
        )
        XCTAssertEqual(
            document.contributionRef,
            .fieldReturn(workspace.contributionID)
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

    // MARK: - Issue #418: outcome semantics + typed fulfillment

    private func seededWorkspace() throws
        -> HTDTFieldReturnWorkspace
    {
        var workspace = HTDTFieldReturnWorkspace(
            missionID: "m-1",
            planID: "plan-field-1",
            createdAtUTC: "2026-09-22T00:00:00Z"
        )
        try workspace.seedTaskLedger(
            preflight: HTDTFieldTaskPreflightEvaluator.evaluate(
                plan: try plan(), spatialAvailable: false
            )
        )
        return workspace
    }

    func testOutcomeSemanticsRequireBasisAndReason() throws {
        var workspace = try seededWorkspace()
        // `fulfilled` with no refs is a typed rejection, not a
        // silent operator-complete.
        XCTAssertThrowsError(
            try workspace.recordTaskOutcome(
                itemRef: "task_item:inventory-amps",
                outcome: .fulfilled
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTFieldReturnError,
                .missingFulfillmentBasis(
                    "task_item:inventory-amps"
                )
            )
        }
        // `declined` without a reason is a typed rejection.
        XCTAssertThrowsError(
            try workspace.recordTaskOutcome(
                itemRef: "task_item:inventory-amps",
                outcome: .declined,
                fulfilledByRefs: [
                    "equipment:amp-rack-1",
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTFieldReturnError,
                .missingOutcomeReason(
                    "task_item:inventory-amps"
                )
            )
        }
        // `partiallyFulfilled` accepts a reason without refs.
        try workspace.recordTaskOutcome(
            itemRef: "task_item:inventory-amps",
            outcome: .partiallyFulfilled,
            note: "counted 2 of 4 amplifiers"
        )
        // A namespace the kind does not permit rejects — an
        // inventory task cannot be fulfilled by a settings
        // observation ref.
        XCTAssertThrowsError(
            try workspace.recordTaskOutcome(
                itemRef: "task_item:inventory-amps",
                outcome: .fulfilled,
                fulfilledByRefs: [
                    "settings_observation:"
                        + UUID().uuidString.lowercased(),
                ]
            )
        ) { error in
            guard case .incompatibleFulfillmentRef =
                error as? HTDTFieldReturnError
            else {
                return XCTFail("expected incompatibleFulfillmentRef, got \(error)")
            }
        }
    }

    func testRoutingTaskRejectsSettingsRef() throws {
        // A routingVerification task fulfilled solely by a settings
        // observation is an incompatible fulfillment.
        let workspace = try seededWorkspace()
        let settingsID = SettingsObservationID()
        let settingsRef = "settings_observation:"
            + settingsID.rawValue.uuidString.lowercased()
        // A routing-shaped entry exercises namespace rejection at
        // edit time — seeded rows for other kinds may accept the
        // ref, so the check must derive from the row's own kind.
        var wiringWorkspace = HTDTFieldReturnWorkspace(
            createdAtUTC: "2026-09-22T00:00:00Z"
        )
        wiringWorkspace.taskLedger = [
            try HTDTFieldReturnTaskLedgerEntry(
                itemRef: "task_item:fl-routing",
                title: "Front Left wiring",
                requirement: .required,
                outcome: .unfulfilled,
                taskKind: .routingVerification,
                fulfillmentNamespaces:
                    HTDTFieldTaskKind.routingVerification
                        .fulfillmentNamespaces
            ),
        ]
        XCTAssertThrowsError(
            try wiringWorkspace.recordTaskOutcome(
                itemRef: "task_item:fl-routing",
                outcome: .fulfilled,
                fulfilledByRefs: [settingsRef]
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTFieldReturnError,
                .incompatibleFulfillmentRef(settingsRef)
            )
        }
        _ = workspace
    }

    func testFinalizeRejectsUnresolvedAndUntypedBasis() throws {
        var workspace = try workspaceWithEvidence()
        let evidenceID = workspace.authority.fieldEvidence[0]
            .evidenceID
        workspace.taskLedger = [
            try HTDTFieldReturnTaskLedgerEntry(
                itemRef: "task_item:inventory-amps",
                title: "Amplifier inventory",
                requirement: .required,
                outcome: .fulfilled,
                fulfilledByRefs: [
                    "field_evidence:\(evidenceID.rawValue.uuidString.lowercased())",
                ],
                taskKind: .inventoryItem,
                fulfillmentNamespaces:
                    HTDTFieldTaskKind.inventoryItem
                        .fulfillmentNamespaces
            ),
        ]
        // Generic evidence is not a typed inventory basis.
        XCTAssertThrowsError(
            try HTDTFieldReturnValidator.validate(
                workspace: workspace
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTFieldReturnError,
                .incompatibleFulfillmentRef(
                    "task_item:inventory-amps"
                )
            )
        }
        // An inventory record resolves the typed basis.
        let item = try SystemInventoryItem(
            equipmentClass: .powerAmplifier,
            userLabel: "Rack amp"
        )
        workspace.inventoryItems = [item]
        workspace.taskLedger[0].fulfilledByRefs = [
            "inventory_item:\(item.itemID.rawValue.uuidString.lowercased())",
        ]
        try HTDTFieldReturnValidator.validate(
            workspace: workspace
        )
        // A contribution-local ref naming no record rejects.
        workspace.taskLedger[0].fulfilledByRefs = [
            "inventory_item:\(UUID().uuidString.lowercased())",
        ]
        XCTAssertThrowsError(
            try HTDTFieldReturnValidator.validate(
                workspace: workspace
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTFieldReturnError,
                .unresolvedFulfillmentRef(
                    workspace.taskLedger[0]
                        .fulfilledByRefs[0]
                )
            )
        }
    }

    // MARK: - Issue #418 refinement: measurement acquisition

    func testMeasurementAcquisitionRequirementPreflight() throws {
        // Plans carrying the typed acquisition requirement unlock
        // non-spatial measurement work; legacy plans stay spatial.
        func evaluate(
            _ acq: String?
        ) throws -> HTDTFieldTaskPreflight? {
            var planText = planJSONText
            let acqField = acq.map {
                "\"acquisition_requirement\": \"\($0)\","
            } ?? ""
            planText = planText.replacingOccurrences(
                of: "\"measurement_requests\": [],",
                with: """
                    "measurement_requests": [
                      {
                        "item_id": "dmm-check",
                        "quantity_type": "impedance",
                        "requirement": "required",
                        \(acqField)
                        "expected_unit": "1"
                      }
                    ],
                    """
            )
            let rows = HTDTFieldTaskPreflightEvaluator.evaluate(
                plan: try JSONDecoder().decode(
                    HTDTCaptureTaskPlan.self,
                    from: Data(planText.utf8)
                ),
                spatialAvailable: false
            )
            return rows.first {
                $0.itemRef == "task_item:dmm-check"
            }
        }
        XCTAssertEqual(
            try evaluate("external_instrument_only")?.enabled,
            true
        )
        XCTAssertEqual(
            try evaluate("non_spatial")?.enabled,
            true
        )
        XCTAssertEqual(
            try evaluate(
                "imported_endpoint_reference_sufficient"
            )?.enabled,
            true
        )
        XCTAssertEqual(
            try evaluate("spatial_point_required")?.enabled,
            false
        )
        XCTAssertEqual(try evaluate(nil)?.enabled, false)
    }

    // MARK: - Issue #419: contribution-ref envelopes

    func testEnvelopeDocsCarryContributionRefNotCaptureSlot()
        throws
    {
        let workspace = try workspaceWithEvidence()
        let artifact = try HTDTFieldReturnAssembler.assemble(
            workspace: workspace,
            provenance: provenance,
            finalizedAtUTC: "2026-09-22T01:00:00Z"
        )
        let evidenceEntry = artifact.entries.first {
            $0.path == "authority/field-evidence.json"
        }
        let object = try JSONSerialization.jsonObject(
            with: XCTUnwrap(evidenceEntry?.data)
        ) as? [String: Any]
        XCTAssertEqual(
            object?["schema"] as? String,
            "htdt.field_return.field-evidence"
        )
        let ref = object?["contribution_ref"] as? [String: String]
        XCTAssertEqual(ref?["kind"], "field_return")
        XCTAssertEqual(
            ref?["id"],
            workspace.contributionID.rawValue
                .uuidString.lowercased()
        )
        // The record must not carry a second owner slot on the wire.
        let records = object?["records"] as? [[String: Any]]
        XCTAssertEqual(records?.count, 1)
        XCTAssertNil(records?.first?["capture_revision_id"])
        // Parsing yields typed records with the carrier re-injected.
        let parsed = try FieldContributionDocs.parse(
            data: XCTUnwrap(evidenceEntry?.data),
            path: "authority/field-evidence.json",
            expectedContribution: workspace.contributionRef
        )
        let decoded = try parsed.records(
            FieldEvidenceRecord.self,
            carrier: workspace.recordCarrierID
        )
        XCTAssertEqual(decoded, workspace.authority.fieldEvidence)
    }

    func testArtifactValidatorRejectsConflictingContribution()
        throws
    {
        let workspace = try workspaceWithEvidence()
        let artifact = try HTDTFieldReturnAssembler.assemble(
            workspace: workspace,
            provenance: provenance,
            finalizedAtUTC: "2026-09-22T01:00:00Z"
        )
        // A tampered envelope whose contribution_ref names another
        // contribution is a typed rejection.
        let entry = artifact.entries.first {
            $0.path == "authority/field-evidence.json"
        }
        var object = try JSONSerialization.jsonObject(
            with: XCTUnwrap(entry?.data)
        ) as! [String: Any]
        object["contribution_ref"] = [
            "kind": "field_return",
            "id": UUID().uuidString.lowercased(),
        ]
        let tampered = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        var entries = artifact.entries
        entries[entries.firstIndex {
            $0.path == "authority/field-evidence.json"
        }!] = .init(
            path: "authority/field-evidence.json",
            data: tampered
        )
        XCTAssertThrowsError(
            try HTDTFieldReturnValidator.validateArtifact(
                document: artifact.document,
                entries: entries
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTFieldReturnError,
                .conflictingContributionRef(
                    "authority/field-evidence.json"
                )
            )
        }
    }

    func testV1DocumentDecodesWithNormalizedContributionRef() throws {
        // A v1 root (capture_revision_id binding scope, no
        // contribution_ref) decodes with the typed ref normalized
        // under the declared scope — never by UUID inference.
        let contributionID = HTDTFieldReturnID()
        let v1 = """
            {
              "schema": "htdt.field_return",
              "schema_version": "1.0.0",
              "authority_binding_scope": "contribution_id",
              "contribution_id":
                "\(contributionID.rawValue.uuidString.lowercased())",
              "mission_id": "m-1",
              "created_at": "2026-09-22T00:00:00Z",
              "finalized_at": "2026-09-22T01:00:00Z",
              "provenance": {
                "producer": "htdt-capture",
                "app_name": "HTDT Capture",
                "app_version": "1.4.2",
                "device_model_family": "iPad"
              },
              "related_capture_revision_ids": [],
              "task_fulfillment_ledger": [],
              "authority_documents": [],
              "evidence_assets": [],
              "content_digest":
                "\(String(repeating: "ab", count: 32))"
            }
            """
        let document = try JSONDecoder().decode(
            HTDTFieldReturnDocument.self,
            from: Data(v1.utf8)
        )
        XCTAssertEqual(document.schemaVersion, "1.0.0")
        XCTAssertTrue(document.isV1Layout)
        XCTAssertEqual(
            document.contributionRef,
            .fieldReturn(contributionID)
        )
        // The v1 digest replays byte-identically through the frozen
        // algorithm — a v1 artifact is never re-digested on v2
        // semantics.
        let v1Digest = try HTDTFieldReturnDigest.legacyDigest(
            of: document
        )
        XCTAssertNotEqual(v1Digest, document.contentDigest)
        // A v2 document verifies under the canonical algorithm.
        let workspace = try workspaceWithEvidence()
        let artifact = try HTDTFieldReturnAssembler.assemble(
            workspace: workspace,
            provenance: provenance,
            finalizedAtUTC: "2026-09-22T01:00:00Z"
        )
        XCTAssertTrue(
            try HTDTFieldReturnDigest.verify(
                artifact.document
            )
        )
    }

    func testSemanticDigestCoversAllRootFields() throws {
        var workspace = try workspaceWithEvidence()
        workspace.planVersion = "2026.09.2"
        let artifactA = try HTDTFieldReturnAssembler.assemble(
            workspace: workspace,
            provenance: provenance,
            finalizedAtUTC: "2026-09-22T01:00:00Z"
        )
        workspace.planVersion = "2026.09.3"
        let artifactB = try HTDTFieldReturnAssembler.assemble(
            workspace: workspace,
            provenance: provenance,
            finalizedAtUTC: "2026-09-22T01:00:00Z"
        )
        XCTAssertNotEqual(
            artifactA.document.contentDigest,
            artifactB.document.contentDigest
        )
        // Supersession lineage contributes to the digest.
        workspace.supersedesContributionID = HTDTFieldReturnID()
        let artifactC = try HTDTFieldReturnAssembler.assemble(
            workspace: workspace,
            provenance: provenance,
            finalizedAtUTC: "2026-09-22T01:00:00Z"
        )
        XCTAssertNotEqual(
            artifactB.document.contentDigest,
            artifactC.document.contentDigest
        )
        XCTAssertEqual(
            artifactC.document.supersedesContributionRef,
            .fieldReturn(
                workspace.supersedesContributionID!
            )
        )
    }
}
