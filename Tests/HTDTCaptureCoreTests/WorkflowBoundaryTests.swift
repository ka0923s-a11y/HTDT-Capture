import XCTest
@testable import HTDTCaptureCore

/// Issue #410: the workflow composition boundary is enforced data —
/// every public root action belongs to exactly one workflow, and
/// mission launch classifies into a typed route instead of
/// implicitly opening capture.
final class WorkflowBoundaryTests: XCTestCase {

    private func missionRecord(
        lifecycle: HTDTMissionLifecycle = .received
    ) -> HTDTMissionRecord {
        HTDTMissionRecord(
            recordID: UUID().uuidString.lowercased(),
            missionID: "mission-1",
            missionKind: .initialSurvey,
            purpose: nil,
            payloadRelativePath: "mission-inbox/x.json",
            payloadSHA256: String(repeating: "c", count: 64),
            planID: "plan-1",
            planVersion: "1",
            planSHA256: String(repeating: "d", count: 64),
            projectRef: "proj",
            roomName: "room",
            issuedAtUTC: nil,
            importedAtUTC: "2026-09-21T00:03:00Z",
            lifecycle: lifecycle
        )
    }

    private func semanticTask(
        itemID: String,
        kind: SemanticTaskKind,
        targetRef: String? = nil,
        requirement: TaskPlanRequirement = .required
    ) throws -> HTDTTaskPlanSemanticItem {
        try HTDTTaskPlanSemanticItem(
            itemID: itemID,
            requirement: requirement,
            semanticKind: kind,
            targetRef: targetRef,
            label: itemID
        )
    }

    // MARK: - Action inventory

    /// The ROOT-10 contract: every workflow's action set is
    /// non-empty, sets are disjoint, and the table classifies every
    /// name it owns.
    func testActionTableIsDisjointAndComplete() {
        XCTAssertEqual(CaptureWorkflow.allCases.count, 7)
        var seen: Set<String> = []
        for (workflow, names) in CaptureWorkflowActionMap.table {
            XCTAssertFalse(
                names.isEmpty, "\(workflow) has no actions"
            )
            for name in names {
                XCTAssertTrue(
                    seen.insert(name).inserted,
                    "\(name) appears in two workflows"
                )
                XCTAssertEqual(
                    CaptureWorkflowActionMap.workflow(
                        forActionName: name
                    ),
                    workflow
                )
            }
        }
        XCTAssertGreaterThan(seen.count, 100)
    }

    /// Every declared action resolves to an owner; invented names
    /// surface as unclassified; stale table entries surface as
    /// unknown.
    func testClassificationQueries() {
        let all = CaptureWorkflowActionMap.table.values
            .flatMap { $0 }.sorted()
        XCTAssertEqual(
            CaptureWorkflowActionMap.unclassifiedActionNames(all),
            []
        )
        XCTAssertEqual(
            CaptureWorkflowActionMap.unknownActionNames(all),
            []
        )
        XCTAssertEqual(
            CaptureWorkflowActionMap.unclassifiedActionNames(
                ["beginCapture", "definitelyNotAnAction"]
            ),
            ["definitelyNotAnAction"]
        )
        XCTAssertEqual(
            CaptureWorkflowActionMap.unknownActionNames(
                ["beginCapture"]
            ),
            CaptureWorkflowActionMap.table.values
                .flatMap { $0 }
                .filter { $0 != "beginCapture" }
                .sorted()
        )
    }

    // MARK: - Mission launch routing

    /// A mission whose plan no longer decodes is unsupported with a
    /// typed reason — never silently routed into capture.
    func testMissingPlanIsUnsupported() {
        let decision = MissionLaunchRouter.route(
            for: missionRecord(),
            plan: nil,
            spatialAvailable: true
        )
        XCTAssertEqual(
            decision.route,
            .unsupported(reason: .planUnavailable)
        )
        XCTAssertFalse(decision.route.isSupported)
    }

    /// A plan with only non-spatial tasks routes to field return —
    /// inventory/routing/commissioning work stands alone and never
    /// opens a scan.
    func testNonSpatialPlanRoutesToFieldReturn() throws {
        let plan = try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "proj",
            roomName: "room",
            semanticTasks: [
                semanticTask(
                    itemID: "inv-1",
                    kind: .inventoryItem
                ),
                semanticTask(
                    itemID: "route-1",
                    kind: .routingVerification,
                    requirement: .optional
                ),
            ]
        )
        let decision = MissionLaunchRouter.route(
            for: missionRecord(),
            plan: plan,
            spatialAvailable: true
        )
        XCTAssertEqual(decision.route, .fieldReturn)
        XCTAssertEqual(
            Set(decision.fieldItemRefs),
            ["task_item:inv-1", "task_item:route-1"]
        )
        XCTAssertTrue(decision.spatialItemRefs.isEmpty)
    }

    /// Spatial tasks with a capable device route to spatial capture;
    /// the same plan on a device without scene reconstruction is
    /// unsupported, carrying the spatial refs as evidence.
    func testSpatialPlanRespectsDeviceCapability() throws {
        let plan = try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "proj",
            roomName: "room",
            semanticTasks: [
                semanticTask(
                    itemID: "surf-1",
                    kind: .surfaceSemantics,
                    targetRef: "wall-1"
                ),
                semanticTask(
                    itemID: "inv-1",
                    kind: .inventoryItem
                ),
            ]
        )
        let capable = MissionLaunchRouter.route(
            for: missionRecord(),
            plan: plan,
            spatialAvailable: true
        )
        XCTAssertEqual(capable.route, .spatialCapture)
        XCTAssertEqual(
            capable.spatialItemRefs, ["task_item:surf-1"]
        )
        XCTAssertEqual(
            capable.fieldItemRefs, ["task_item:inv-1"]
        )

        let incapable = MissionLaunchRouter.route(
            for: missionRecord(),
            plan: plan,
            spatialAvailable: false
        )
        XCTAssertEqual(
            incapable.route,
            .unsupported(reason: .spatialCaptureUnavailable)
        )
    }

    /// A lifecycle that can no longer start routes to artifact
    /// review — field work is done; the remaining surface is the
    /// produced artifact.
    func testPostFieldLifecycleRoutesToArtifactReview() throws {
        let plan = try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "proj",
            roomName: "room",
            semanticTasks: [
                semanticTask(
                    itemID: "surf-1",
                    kind: .surfaceSemantics,
                    targetRef: "wall-1"
                ),
            ]
        )
        let decision = MissionLaunchRouter.route(
            for: missionRecord(lifecycle: .finalized),
            plan: plan,
            spatialAvailable: true
        )
        XCTAssertEqual(decision.route, .artifactReview)
        XCTAssertEqual(
            decision.spatialItemRefs, ["task_item:surf-1"]
        )
    }

    /// An empty plan cannot launch anything — the router reports a
    /// typed unsupported reason rather than opening an empty capture.
    func testEmptyPlanIsUnsupported() throws {
        let plan = try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "proj",
            roomName: "room"
        )
        let decision = MissionLaunchRouter.route(
            for: missionRecord(),
            plan: plan,
            spatialAvailable: true
        )
        XCTAssertEqual(
            decision.route,
            .unsupported(reason: .noExecutableTasks)
        )
    }
}
