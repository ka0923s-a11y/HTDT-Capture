import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #386: the mission inbox — import idempotence, conflict
/// fail-closed behavior, explicit supersession, dependency gating,
/// single-active-mission enforcement, and honest resume semantics.
final class HTDTMissionInboxTests: XCTestCase {
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
          "evidence_targets": ["frame:north-wall"],
          "expected_channel_roles": ["L", "R"]
        }
        """
    }

    private func missionData(
        missionID: String,
        planID: String,
        supersedesMissionID: String? = nil,
        dependencies: String = "[]",
        receiverRequirement: String? = nil,
        missionKind: String = "initial_survey"
    ) throws -> Data {
        var fields = """
              "schema": "htdt.capture-mission",
              "schema_version": "1.0.0",
              "mission_id": "\(missionID)",
              "mission_kind": "\(missionKind)",
              "purpose": "survey",
              "issued_at": "2026-09-21T00:00:00Z",
              "dependencies": \(dependencies),
              "plan": \(planJSON(planID: planID))
            """
        if let supersedesMissionID {
            fields += ",\n  \"supersedes_mission_id\": "
                + "\"\(supersedesMissionID)\""
        }
        if let receiverRequirement {
            fields += ",\n  \"receiver_requirement\": "
                + receiverRequirement
        }
        return Data("{\n\(fields)\n}".utf8)
    }

    // MARK: - Import

    func testImportEnvelopeAndBarePlan() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)

        // Envelope payload -> mission record with mission identity.
        let outcome = try store.importMission(
            data: missionData(missionID: "m-1", planID: "plan-1")
        )
        guard case .imported(let record) = outcome else {
            XCTFail("expected imported, got \(outcome)")
            return
        }
        XCTAssertEqual(record.missionID, "m-1")
        XCTAssertEqual(record.planID, "plan-1")
        XCTAssertEqual(record.lifecycle, .received)
        XCTAssertEqual(record.projectRef, "proj-77/doc-9")
        XCTAssertEqual(record.roomName, "Theater A")

        // Bare task plan -> derived mission identity `plan:<id>`.
        let bare = try store.importMission(
            data: Data(planJSON(planID: "plan-2").utf8)
        )
        guard case .imported(let bareRecord) = bare else {
            XCTFail("expected imported, got \(bare)")
            return
        }
        XCTAssertEqual(bareRecord.missionID, "plan:plan-2")
    }

    func testDuplicateImportIsIdempotent() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        let data = try missionData(
            missionID: "m-1",
            planID: "plan-1"
        )
        _ = try store.importMission(data: data)
        let outcome = try store.importMission(data: data)
        guard case .duplicate(let record) = outcome else {
            XCTFail("expected duplicate, got \(outcome)")
            return
        }
        XCTAssertEqual(record.missionID, "m-1")
        XCTAssertEqual(try store.records().count, 1)
    }

    func testConflictingIdentityFailsClosed() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        _ = try store.importMission(
            data: missionData(missionID: "m-1", planID: "plan-1")
        )
        // Same mission_id, different bytes, no supersession — never
        // a silent in-place rewrite.
        XCTAssertThrowsError(
            try store.importMission(
                data: missionData(
                    missionID: "m-1",
                    planID: "plan-DIFFERENT"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? HTDTMissionInboxError,
                .conflictingIdentity
            )
        }
        XCTAssertEqual(try store.records().count, 1)
    }

    func testSupersessionPreservesOldAssociations() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        let outcome = try store.importMission(
            data: missionData(missionID: "m-1", planID: "plan-1")
        )
        guard case .imported(let original) = outcome else {
            XCTFail("expected imported, got \(outcome)")
            return
        }
        try store.associateCapture(
            recordID: original.recordID,
            captureRevisionID: CaptureRevisionID()
        )

        let superseding = try store.importMission(
            data: missionData(
                missionID: "m-2",
                planID: "plan-2",
                supersedesMissionID: "m-1"
            )
        )
        guard case .superseding(
            let newRecord, let oldRecord
        ) = superseding else {
            XCTFail("expected superseding, got \(superseding)")
            return
        }
        XCTAssertEqual(newRecord.supersedesMissionID, "m-1")
        XCTAssertEqual(oldRecord.lifecycle, .superseded)
        XCTAssertEqual(oldRecord.supersededByMissionID, "m-2")
        // The replaced record keeps its captures — supersession is
        // recorded, not destructive.
        XCTAssertEqual(
            oldRecord.associatedCaptureRevisionIDs.count,
            1
        )
        XCTAssertEqual(try store.records().count, 2)
    }

    // MARK: - Dependencies and start

    func testStartBlockedOnMissingRequiredDependency() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        let dependencies = """
            [{
              "ref": "m-0",
              "kind": "mission_completed",
              "required": true
            }]
            """
        let outcome = try store.importMission(
            data: missionData(
                missionID: "m-1",
                planID: "plan-1",
                dependencies: dependencies
            )
        )
        guard case .imported(let record) = outcome else {
            XCTFail()
            return
        }
        let report = try store.evaluateDependencies(
            recordID: record.recordID
        )
        XCTAssertTrue(report.startBlocked)
        XCTAssertEqual(report.missingRequired, ["m-0"])

        XCTAssertThrowsError(
            try store.startMission(recordID: record.recordID)
        ) { error in
            guard case HTDTMissionInboxError
                .blockedDependencies(let refs) = error
            else {
                XCTFail("expected blockedDependencies, got \(error)")
                return
            }
            XCTAssertEqual(refs, ["m-0"])
        }
        // The record itself is marked blocked_dependency — the same
        // state the detail view renders.
        XCTAssertEqual(
            try store.record(id: record.recordID)?.lifecycle,
            .blockedDependency
        )
    }

    func testStartReturnsResumeWithHonestARClaim() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        let outcome = try store.importMission(
            data: missionData(missionID: "m-1", planID: "plan-1")
        )
        guard case .imported(let record) = outcome else {
            XCTFail()
            return
        }
        let resume = try store.startMission(
            recordID: record.recordID
        )
        XCTAssertEqual(
            resume.planImport.plan.planID,
            "plan-1"
        )
        XCTAssertTrue(resume.workflowProgressResumable)
        // A live AR session is NEVER resumed — resume claims only
        // record + plan + non-AR progress.
        XCTAssertFalse(resume.liveARSessionResumable)
        XCTAssertEqual(
            try store.activeMissionRecord()?.recordID,
            record.recordID
        )
        XCTAssertEqual(
            try store.record(id: record.recordID)?.lifecycle,
            .inProgress
        )
    }

    func testOnlyOneMissionActiveAtATime() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        guard case .imported(let first) = try store.importMission(
            data: missionData(missionID: "m-1", planID: "plan-1")
        ), case .imported(let second) = try store.importMission(
            data: missionData(missionID: "m-2", planID: "plan-2")
        ) else {
            XCTFail()
            return
        }
        _ = try store.startMission(recordID: first.recordID)
        XCTAssertThrowsError(
            try store.startMission(recordID: second.recordID)
        ) { error in
            guard case HTDTMissionInboxError
                .missionAlreadyInProgress = error
            else {
                XCTFail("expected missionAlreadyInProgress")
                return
            }
        }
        // Resume of the same active record is allowed.
        _ = try store.startMission(recordID: first.recordID)
    }

    func testPauseResumeAndArchive() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        guard case .imported(let record) = try store.importMission(
            data: missionData(missionID: "m-1", planID: "plan-1")
        ) else {
            XCTFail()
            return
        }
        _ = try store.startMission(recordID: record.recordID)
        try store.pauseActiveMission()
        XCTAssertNil(try store.activeMissionRecord())
        // Pausing clears the active pointer only — the record's
        // lifecycle and its capture associations are untouched.
        XCTAssertEqual(
            try store.record(id: record.recordID)?.lifecycle,
            .inProgress
        )
        try store.setLifecycle(
            recordID: record.recordID,
            .archived
        )
        XCTAssertFalse(
            try store.activeRecords().contains {
                $0.recordID == record.recordID
            }
        )
    }

    /// #454: resume re-opens an in-progress mission only — it is
    /// not a second Start that admits received/ready/blocked
    /// missions while skipping dependency evaluation.
    func testResumeRefusesNonInProgressMission() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        guard case .imported(let record) = try store.importMission(
            data: missionData(missionID: "m-1", planID: "plan-1")
        ) else {
            XCTFail()
            return
        }
        // .received — never started, dependencies never evaluated.
        XCTAssertThrowsError(
            try store.resumeMission(recordID: record.recordID)
        ) { error in
            guard case HTDTMissionInboxError
                .invalidLifecycleTransition = error
            else {
                XCTFail("expected invalidLifecycleTransition")
                return
            }
        }
        // Started then in-progress: resume is admitted.
        _ = try store.startMission(recordID: record.recordID)
        let resume = try store.resumeMission(
            recordID: record.recordID
        )
        XCTAssertEqual(resume.planImport.plan.planID, "plan-1")
        // Archived is refused too.
        try store.setLifecycle(
            recordID: record.recordID,
            .archived
        )
        XCTAssertThrowsError(
            try store.resumeMission(recordID: record.recordID)
        ) { error in
            guard case HTDTMissionInboxError
                .invalidLifecycleTransition = error
            else {
                XCTFail("expected invalidLifecycleTransition")
                return
            }
        }
    }

    func testGroupedByProjectAndRoom() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        _ = try store.importMission(
            data: missionData(missionID: "m-1", planID: "plan-1")
        )
        _ = try store.importMission(
            data: missionData(missionID: "m-2", planID: "plan-2")
        )
        let grouped = try store.grouped()
        XCTAssertEqual(
            grouped["proj-77/doc-9"]?["Theater A"]?.count,
            2
        )
    }

    func testDeliveryJobAssociation() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        guard case .imported(let record) = try store.importMission(
            data: missionData(missionID: "m-1", planID: "plan-1")
        ) else {
            XCTFail()
            return
        }
        try store.associateDeliveryJob(
            recordID: record.recordID,
            deliveryJobID: "job-7"
        )
        XCTAssertEqual(
            try store.record(id: record.recordID)?
                .deliveryJobIDs,
            ["job-7"]
        )
    }

    func testPersistenceSurvivesStoreReopen() throws {
        let root = try makeRoot()
        let store = HTDTMissionInboxStore(captureRoot: root)
        let data = try missionData(
            missionID: "m-1",
            planID: "plan-1"
        )
        guard case .imported(let record) = try store.importMission(
            data: data
        ) else {
            XCTFail()
            return
        }
        let reopened = HTDTMissionInboxStore(captureRoot: root)
        let reloaded = try reopened.record(id: record.recordID)
        XCTAssertEqual(reloaded?.missionID, "m-1")
        // The plan bytes are readable back from the payload file.
        let plan = try reopened.plan(for: reloaded!)
        XCTAssertEqual(plan.planID, "plan-1")
    }
}
