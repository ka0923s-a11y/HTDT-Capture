import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Coverage for the integration/wiring payloads (issues #321, #351,
/// #353, #355): the HTDT repair task plan schema + ledger +
/// resolution lifecycle, the repair link document carried by the
/// repair revision, the mission-workflow reachability router, the
/// as-built plan import, and the file-import instrument adapter.
final class IntegrationWiringTests: XCTestCase {
    private let sourceRevision = CaptureRevisionID(
        rawValue: UUID(
            uuidString: "30000000-0000-4000-8000-000000000011"
        )!
    )
    private let repairSession = CaptureSessionID(
        rawValue: UUID(
            uuidString: "30000000-0000-4000-8000-000000000012"
        )!
    )
    private let repairRevision = CaptureRevisionID(
        rawValue: UUID(
            uuidString: "30000000-0000-4000-8000-000000000013"
        )!
    )
    private let spaceID = CoordinateSpaceID(
        rawValue: UUID(
            uuidString: "30000000-0000-4000-8000-000000000014"
        )!
    )

    private func makePlan(
        diagnostics: [HTDTIngestionDiagnostic] = [
            HTDTIngestionDiagnostic(
                issueCode: "coverage_gap",
                reason: "North wall unobserved",
                targetRef: "region:north-wall"
            ),
            HTDTIngestionDiagnostic(
                issueCode: "label_error",
                reason: "Speaker mislabeled",
                targetRef: "entity:speaker-1",
                requirement: .optional
            ),
        ]
    ) throws -> HTDTRepairTaskPlan {
        try HTDTRepairTaskMapping.plan(
            planID: "plan-1",
            planVersion: "1.0.0",
            projectRef: "project:demo",
            roomName: "Demo Room",
            sourceCaptureRevisionID: sourceRevision,
            sourceBundleDigest: EvidenceIntegrity.sha256(
                of: Data("bundle".utf8)
            ),
            ingestionReceiptRef: "receipt-1",
            issuedBySoftware: "htdt-ingest",
            issuedByProtocolVersion: "1.0.0",
            diagnostics: diagnostics
        )
    }

    // MARK: - #321 repair task plan

    func testDiagnosticMappingTable() {
        XCTAssertEqual(
            HTDTRepairTaskMapping.taskKind(
                forIssueCode: "label_error"
            ),
            .semanticCorrection
        )
        XCTAssertEqual(
            HTDTRepairTaskMapping.taskKind(
                forIssueCode: "evidence_missing"
            ),
            .sameCoordinateEvidence
        )
        XCTAssertEqual(
            HTDTRepairTaskMapping.taskKind(
                forIssueCode: "measurement_deviation"
            ),
            .externalMeasurement
        )
        XCTAssertEqual(
            HTDTRepairTaskMapping.taskKind(
                forIssueCode: "coverage_gap"
            ),
            .freshRescan
        )
        // Unknown codes degrade to fresh rescan — never a weaker guess.
        XCTAssertEqual(
            HTDTRepairTaskMapping.taskKind(
                forIssueCode: "something_unseen"
            ),
            .freshRescan
        )
    }

    func testRepairPlanFromDiagnostics() throws {
        let plan = try makePlan()
        XCTAssertEqual(plan.schema, HTDTRepairTaskPlan.schema)
        XCTAssertEqual(plan.tasks.count, 2)
        XCTAssertEqual(plan.tasks[0].kind, .freshRescan)
        XCTAssertEqual(
            plan.tasks[0].requiredEvidenceType,
            "fresh_revision_rescan"
        )
        XCTAssertEqual(plan.tasks[1].kind, .semanticCorrection)
        XCTAssertEqual(plan.tasks[1].requirement, .optional)
        XCTAssertEqual(
            plan.sourceCaptureRevisionID,
            sourceRevision.description
        )
    }

    func testRepairPlanImportRejectsWrongSchema() throws {
        let plan = try makePlan()
        let encoder = JSONEncoder()
        let good = try encoder.encode(plan)
        _ = try HTDTRepairTaskPlanImport(data: good)
        let bad = try XCTUnwrap(
            "{\"schema\":\"not.a.plan\"}".data(using: .utf8)
        )
        XCTAssertThrowsError(
            try HTDTRepairTaskPlanImport(data: bad)
        )
    }

    func testRepairPlanCanonicalReencode() throws {
        let plan = try makePlan()
        let planImport = try HTDTRepairTaskPlanImport(plan: plan)
        XCTAssertEqual(planImport.plan, plan)
        // Canonical bytes re-decode to the identical plan.
        let reparsed = try HTDTRepairTaskPlanImport(
            data: planImport.data
        )
        XCTAssertEqual(reparsed.plan, plan)
        XCTAssertEqual(
            reparsed.planSHA256, planImport.planSHA256
        )
    }

    func testRepairLedgerDedupeAndResolution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString, isDirectory: true
            )
        let store = HTDTRepairPlanStore(captureRoot: root)
        let planImport = try HTDTRepairTaskPlanImport(
            plan: makePlan()
        )
        let stored = try store.record(
            planImport, receivedAtUTC: "2026-09-22T00:00:00Z"
        )
        XCTAssertEqual(stored.tasks.count, 2)
        XCTAssertEqual(
            try store.unresolvedTaskRows().count, 2
        )

        try store.markTaskResolved(
            planKey: stored.planKey,
            taskID: "task-1",
            resolvedBy: repairRevision,
            at: "2026-09-22T00:30:00Z"
        )
        XCTAssertEqual(
            try store.unresolvedTaskRows().count, 1
        )
        let rows = try store.taskRows(
            forSourceRevisionID: sourceRevision
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(
            rows.first { $0.task.taskID == "task-1" }?
                .resolvedByRevisionID,
            repairRevision.description
        )

        // Idempotent re-handoff: same plan merges, resolution kept.
        let merged = try store.record(
            planImport, receivedAtUTC: "2026-09-22T01:00:00Z"
        )
        XCTAssertEqual(merged.tasks.count, 2)
        XCTAssertEqual(
            merged.tasks.first { $0.task.taskID == "task-1" }?
                .resolvedByRevisionID,
            repairRevision.description
        )
        XCTAssertEqual(try store.load().plans.count, 1)
    }

    func testRepairLedgerRejectsUnknownTask() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString, isDirectory: true
            )
        let store = HTDTRepairPlanStore(captureRoot: root)
        XCTAssertThrowsError(
            try store.markTaskResolved(
                planKey: "nope",
                taskID: "task-1",
                resolvedBy: repairRevision,
                at: "2026-09-22T00:00:00Z"
            )
        )
    }

    func testRepairLinkPackageRoundtrip() throws {
        let plan = try makePlan()
        let planImport = try HTDTRepairTaskPlanImport(
            plan: plan
        )
        let link = try HTDTRepairTaskLink(
            captureRevisionID: repairRevision,
            captureSessionID: repairSession,
            repairPlanID: plan.planID,
            repairPlanVersion: plan.planVersion,
            repairPlanSHA256: planImport.planSHA256,
            repairTaskID: "task-1",
            sourceCaptureRevisionID: sourceRevision,
            ingestionReceiptRef: plan.ingestionReceiptRef
        )
        let data = try link.package()
        let decoded = try JSONDecoder().decode(
            HTDTRepairTaskLink.self,
            from: data
        )
        XCTAssertEqual(decoded, link)
        XCTAssertEqual(
            HTDTRepairTaskLink.path,
            "session/repair-task-link.json"
        )
        XCTAssertEqual(
            decoded.sourceCaptureRevisionID, sourceRevision
        )
    }

    func testReceiptValidationRejectsUnpinnedPlan() throws {
        let digest = EvidenceIntegrity.sha256(
            of: Data("bundle".utf8)
        )
        var plan = try makePlan()
        // Rewrite the plan's pinned revision — must be refused.
        plan = try HTDTRepairTaskPlan(
            planID: plan.planID,
            planVersion: plan.planVersion,
            projectRef: plan.projectRef,
            roomName: plan.roomName,
            sourceCaptureRevisionID: repairRevision.description,
            sourceBundleDigest: plan.sourceBundleDigest,
            ingestionReceiptRef: plan.ingestionReceiptRef,
            issuedBySoftware: plan.issuedBySoftware,
            issuedByProtocolVersion: plan.issuedByProtocolVersion,
            tasks: plan.tasks
        )
        let response = HTDTIngestionResponse(
            ingestionOutcome: "accepted",
            captureRevisionID: sourceRevision.description,
            bundleDigest: digest.value,
            repairTaskPlan: plan
        )
        let data = try JSONEncoder().encode(response)
        XCTAssertThrowsError(
            try HTDTHandoffRequestBuilder.validateServerReceipt(
                data: data,
                captureRevisionID: sourceRevision,
                bundleDigest: digest
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTHandoffError,
                .archiveIdentityMismatch
            )
        }
    }

    func testReceiptValidationAcceptsPinnedPlan() throws {
        let digest = EvidenceIntegrity.sha256(
            of: Data("bundle".utf8)
        )
        let plan = try makePlan()
        let response = HTDTIngestionResponse(
            ingestionOutcome: "accepted",
            captureRevisionID: sourceRevision.description,
            bundleDigest: digest.value,
            repairTaskPlan: plan
        )
        let data = try JSONEncoder().encode(response)
        let validated = try HTDTHandoffRequestBuilder
            .validateServerReceipt(
                data: data,
                captureRevisionID: sourceRevision,
                bundleDigest: digest
            )
        XCTAssertEqual(validated.repairTaskPlan, plan)
    }

    // MARK: - #353 reachability router

    func testMissionRouterHidesWorkflowsOnPlainCapture() {
        let entries = MissionWorkflowRouter.entries(
            for: MissionWorkflowContext()
        )
        XCTAssertTrue(entries.isEmpty)
    }

    func testMissionRouterBlocksWithoutSpatialAuthority() {
        let context = MissionWorkflowContext(
            taskPlanLoaded: true,
            connectedSpaceIntent: true,
            asBuiltPlanLoaded: true,
            spatialAuthorityLive: false
        )
        let entries = MissionWorkflowRouter.entries(
            for: context
        )
        XCTAssertEqual(
            Set(entries.map(\.surface)),
            [.taskPlanChecklist, .connectedSpace,
             .asBuiltVerification]
        )
        XCTAssertEqual(
            MissionWorkflowRouter.reachableSurfaces(
                for: context
            ),
            [.taskPlanChecklist]
        )
    }

    func testMissionRouterReachableInLiveCapture() {
        let context = MissionWorkflowContext(
            taskPlanLoaded: true,
            connectedSpaceIntent: true,
            connectedSpaceActive: true,
            asBuiltPlanLoaded: true,
            spatialAuthorityLive: true,
            captureInProgress: true,
            annotationWorkspaceEnterable: true,
            unresolvedRepairTasks: 2
        )
        XCTAssertEqual(
            MissionWorkflowRouter.reachableSurfaces(
                for: context
            ),
            Set(MissionWorkflowSurface.allCases)
        )
    }

    func testMissionRouterAuthoringBlockedBeforeReview() {
        let context = MissionWorkflowContext(
            captureInProgress: true,
            annotationWorkspaceEnterable: false
        )
        let entries = MissionWorkflowRouter.entries(
            for: context
        )
        XCTAssertEqual(
            Set(entries.map(\.surface)),
            [.postScanAuthoring, .instrumentImport]
        )
        XCTAssertTrue(
            entries.allSatisfy {
                $0.availability == .blocked
            }
        )
    }

    // MARK: - #293 as-built plan import

    func testAsBuiltPlanImport() throws {
        let spec = try PlannedAsBuiltSpec(
            plannedEntityID: "spk-1",
            entityType: .speaker,
            channelRole: .left,
            label: "Left front speaker",
            positionScene: try SpatialVector3F(1.0, 0.5, 2.0),
            toleranceMeters: 0.05
        )
        let plan = try HTDTAsBuiltPlan(
            planID: "asbuilt-1",
            planVersion: "2.0.0",
            projectRef: "project:demo",
            roomName: "Demo Room",
            tolerancePolicyRef: "policy-1",
            specs: [spec]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let planImport = try HTDTAsBuiltPlanImport(
            data: encoder.encode(plan)
        )
        XCTAssertEqual(planImport.plan, plan)
        XCTAssertEqual(
            HTDTAsBuiltPlanImport.path,
            "session/as-built-plan.json"
        )
        XCTAssertThrowsError(
            try HTDTAsBuiltPlanImport(
                data: Data("{\"schema\":\"nope\"}".utf8)
            )
        )
    }

    // MARK: - #355 file-import instrument adapter

    func testFileImportAdapterJSON() async throws {
        let payload = """
            {"value":4.215,"unit":"m",
             "device_measurement_id":"dev-7",
             "calibration_status":"valid"}
            """
        let descriptor = try InstrumentAdapterDescriptor(
            adapterID: "file-import",
            acquisitionMethod: .externalInstrument,
            makeModel: "Bosch GLM 50",
            transport: "file"
        )
        let adapter = FileImportInstrumentAdapter(
            descriptor: descriptor,
            data: Data(payload.utf8)
        )
        let reading = try await adapter.readScalar()
        XCTAssertEqual(reading.value, 4.215)
        XCTAssertEqual(reading.unit, .meter)
        XCTAssertEqual(reading.deviceMeasurementID, "dev-7")
        XCTAssertEqual(reading.calibrationStatus, "valid")
    }

    func testFileImportAdapterPlainText() async throws {
        let descriptor = try InstrumentAdapterDescriptor(
            adapterID: "file-import",
            acquisitionMethod: .externalInstrument,
            makeModel: "Generic laser",
            transport: "file"
        )
        let adapter = FileImportInstrumentAdapter(
            descriptor: descriptor,
            data: Data("3.62 m".utf8)
        )
        let reading = try await adapter.readScalar()
        XCTAssertEqual(reading.value, 3.62)
        XCTAssertEqual(reading.unit, .meter)
        XCTAssertEqual(reading.receivedValueText, "3.62 m")
    }

    func testFileImportAdapterRejectsMalformed() async {
        guard let descriptor = try? InstrumentAdapterDescriptor(
            adapterID: "file-import",
            acquisitionMethod: .externalInstrument,
            makeModel: "Generic laser",
            transport: "file"
        ) else {
            XCTFail("descriptor must build")
            return
        }
        let adapter = FileImportInstrumentAdapter(
            descriptor: descriptor,
            data: Data("not a reading".utf8)
        )
        do {
            _ = try await adapter.readScalar()
            XCTFail("malformed payload must throw")
        } catch {
            XCTAssertEqual(
                error as? InstrumentAdapterError, .invalidReading
            )
        }
    }

    /// The exact staged value + provenance survive into the committed
    /// measurement only on explicit confirmation (#355).
    func testFileImportConfirmPreservesValue() async throws {
        let payload = """
            {"value":2.5,"unit":"m",
             "device_measurement_id":"d-1"}
            """
        let descriptor = try InstrumentAdapterDescriptor(
            adapterID: "file-import",
            acquisitionMethod: .externalInstrument,
            makeModel: "Leica D2",
            transport: "file"
        )
        var session = InstrumentMeasurementSession()
        let adapter = FileImportInstrumentAdapter(
            descriptor: descriptor,
            data: Data(payload.utf8)
        )
        let pending = try await session.stageReading(
            from: adapter
        )
        let measurement = try session.confirmMeasurement(
            pending,
            quantityType: "distance",
            coordinateSpaceID: spaceID,
            endpointRefs: ["entity:a", "entity:b"]
        )
        XCTAssertEqual(measurement.value, .scalar(2.5))
        XCTAssertEqual(measurement.unit, .meter)
        XCTAssertEqual(
            measurement.sourceValueText,
            pending.reading.receivedValueText
        )
        XCTAssertEqual(
            measurement.instrument?.makeModel, "Leica D2"
        )
        XCTAssertTrue(
            measurement.evidenceRefs.contains(
                "instrument_reading:d-1"
            )
        )
    }
}
