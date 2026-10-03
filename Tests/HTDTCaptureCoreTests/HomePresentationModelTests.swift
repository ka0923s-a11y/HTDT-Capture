import XCTest
@testable import HTDTCaptureCore

/// Issue bolph71656-ai/HTDT-Capture#406: Home IA v2 — three bounded intents, a single "what's
/// next" decision, badges that only carry actionable counts.
final class HomePresentationModelTests: XCTestCase {

    private func draft() -> RecoverableWorkingRevision {
        RecoverableWorkingRevision(
            url: URL(fileURLWithPath: "/tmp/draft-a"),
            revisionID: CaptureRevisionID(),
            phase: .endAccepted,
            captureSessionID: nil,
            coordinateSpaceID: nil,
            retainedBytes: 128
        )
    }

    private func mission(
        recordID: String,
        lifecycle: HTDTMissionLifecycle
    ) -> HTDTMissionRecord {
        HTDTMissionRecord(
            recordID: recordID,
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

    private func job(
        id: String,
        state: HTDTDeliveryJobState
    ) -> HTDTDeliveryJob {
        HTDTDeliveryJob(
            deliveryJobID: id,
            captureRevisionID: CaptureRevisionID(),
            captureSeriesID: CaptureSeriesID(),
            bundleDigest: String(repeating: "a", count: 64),
            archiveSHA256: String(repeating: "b", count: 64),
            archiveByteCount: 50,
            payloadRelativePath:
                "delivery-queue/payloads/x.htdtcapture",
            destination: HTDTHandoffDestination(
                name: "receiver",
                kind: .shareSheet
            ),
            createdAtUTC: "2026-09-21T00:02:00Z",
            state: state
        )
    }

    private func emptyModel(
        recoverableDrafts: [RecoverableWorkingRevision] = [],
        missions: [HTDTMissionRecord] = [],
        activeMissionRecordID: String? = nil,
        deliveryJobs: [HTDTDeliveryJob] = [],
        libraryCaptureCount: Int = 0,
        librarySeriesCount: Int = 0,
        mostRecentRevisionID: CaptureRevisionID? = nil,
        captureAvailable: Bool = true
    ) -> CaptureHomeModel {
        CaptureHomeModel(
            recoverableDrafts: recoverableDrafts,
            missions: missions,
            activeMissionRecordID: activeMissionRecordID,
            deliveryJobs: deliveryJobs,
            pairedDestinationCount: 0,
            libraryCaptureCount: libraryCaptureCount,
            librarySeriesCount: librarySeriesCount,
            mostRecentRevisionID: mostRecentRevisionID,
            maintenance: HomeMaintenanceSummary(
                quarantinedArtifactCount: 0,
                workingOrphanCount: 0,
                enumerationFailureCount: 0
            ),
            readinessAttentions: [],
            captureAvailable: captureAvailable
        )
    }

    // MARK: - Next action

    /// A resumable draft beats every other demand — finishing in-
    /// flight work precedes starting new work.
    func testDraftWinsOverMissionsAndCapture() {
        let d = draft()
        let model = emptyModel(
            recoverableDrafts: [d],
            missions: [
                mission(
                    recordID: "m1",
                    lifecycle: .inProgress
                ),
            ],
            mostRecentRevisionID: CaptureRevisionID()
        )
        XCTAssertEqual(
            model.nextAction, .resumeDraft(d)
        )
    }

    /// The mission the device is actively capturing continues first;
    /// only when no draft/active work exists does a startable mission
    /// win; new capture follows after that.
    func testMissionPriorityChain() {
        let startable = mission(
            recordID: "m-start", lifecycle: .received
        )
        let active = mission(
            recordID: "m-active", lifecycle: .inProgress
        )

        let model = emptyModel(
            missions: [startable, active],
            activeMissionRecordID: "m-active"
        )
        XCTAssertEqual(
            model.nextAction, .continueMission(active)
        )

        let startOnly = emptyModel(missions: [startable])
        XCTAssertEqual(
            startOnly.nextAction, .startMission(startable)
        )

        let idle = emptyModel()
        XCTAssertEqual(idle.nextAction, .newCapture)
    }

    /// Without a camera-eligible device the fallback is reopening the
    /// most recent artifact; a failed delivery only surfaces when no
    /// better action remains.
    func testFallbackChain() {
        let revision = CaptureRevisionID()
        let model = emptyModel(
            deliveryJobs: [job(id: "j1", state: .failed)],
            mostRecentRevisionID: revision,
            captureAvailable: false
        )
        XCTAssertEqual(
            model.nextAction, .openRecentArtifact(revision)
        )

        let blocked = job(id: "j1", state: .blocked)
        let retry = emptyModel(
            deliveryJobs: [blocked],
            captureAvailable: false
        )
        XCTAssertEqual(
            retry.nextAction, .retryDelivery(blocked)
        )
    }

    /// Nothing to do — empty home shows no next action rather than a
    /// disabled suggestion.
    func testEmptyModelHasNoNextAction() {
        let model = emptyModel(captureAvailable: false)
        XCTAssertEqual(model.nextAction, .none)
        XCTAssertTrue(model.workItems.isEmpty)
    }

    // MARK: - Work items

    /// Work items order: drafts → active → startable → follow-ups →
    /// deliveries → review artifact. Each row carries a stable
    /// identity the view can reuse.
    func testWorkItemOrderingAndIdentity() {
        let d = draft()
        let startable = mission(
            recordID: "m-start", lifecycle: .received
        )
        let followUp = mission(
            recordID: "m-follow", lifecycle: .needsFollowUp
        )
        let revision = CaptureRevisionID()
        let model = emptyModel(
            recoverableDrafts: [d],
            missions: [startable, followUp],
            deliveryJobs: [job(id: "j1", state: .paused)],
            mostRecentRevisionID: revision
        )
        XCTAssertEqual(
            model.workItems.map(\.kind),
            [
                .resumeDraft, .startMission, .missionFollowUp,
                .retryDelivery, .reviewArtifact,
            ]
        )
        XCTAssertEqual(
            model.workItems[0].identity, d.url.path
        )
        XCTAssertEqual(
            model.workItems[1].identity, "m-start"
        )
        XCTAssertEqual(
            model.workItems[3].identity, "j1"
        )
    }

    /// Non-actionable deliveries never become work — in-flight and
    /// delivered jobs are informational, not demands.
    func testOnlyActionableJobsBecomeWorkItems() {
        let model = emptyModel(
            deliveryJobs: [
                job(id: "j-failed", state: .failed),
                job(id: "j-sending", state: .sending),
                job(id: "j-done", state: .deliveredStaged),
            ]
        )
        XCTAssertEqual(
            model.workItems.map(\.identity), ["j-failed"]
        )
    }

    // MARK: - Send summary

    /// The send badge carries only actionable count — in-flight and
    /// completed work stays informative.
    func testSendSummaryClassifiesJobs() {
        let send = HomeSendSummary(
            deliveryJobs: [
                job(id: "j-failed", state: .failed),
                job(id: "j-sending", state: .sending),
                job(id: "j-done", state: .deliveredStaged),
            ],
            pairedDestinationCount: 2
        )
        XCTAssertEqual(send.actionableCount, 1)
        XCTAssertEqual(send.inFlightJobs.count, 1)
        XCTAssertEqual(send.completedJobs.count, 1)
        XCTAssertEqual(send.pairedDestinationCount, 2)
    }
}
