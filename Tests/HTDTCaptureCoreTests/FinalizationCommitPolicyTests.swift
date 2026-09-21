import Foundation
import Testing
@testable import HTDTCaptureCore

// MARK: - adoptFinalized commit-boundary transitions (#160)

@Test
func validatingCanAdoptCommittedFinalizedRevision() throws {
    var machine = CaptureStateMachine(state: .validating)
    try machine.apply(.adoptFinalized)
    #expect(machine.state == .finalized)
}

@Test
func failedHostCanAdoptCommittedFinalizedRevision() throws {
    // Commit wins: a failure that raced a completed promotion must not
    // leave the durable finalized revision unadopted.
    var machine = CaptureStateMachine(
        state: .failed,
        lastFailure: .interrupted
    )
    try machine.apply(.adoptFinalized)
    #expect(machine.state == .finalized)
}

@Test
func adoptFinalizedIsRejectedOutsideCommitBoundaries() {
    for state in [
        CaptureState.scanning,
        .paused,
        .reviewing,
        .annotating,
        .finalized,
        .exported,
    ] {
        var machine = CaptureStateMachine(state: state)
        #expect(throws: CaptureStateMachineError.self) {
            try machine.apply(.adoptFinalized)
        }
        #expect(machine.state == state)
    }
}

// MARK: - FinalizationCommitPolicy (#185)

@Test
func inactiveCommitDoesNotFenceFailures() {
    var policy = FinalizationCommitPolicy()
    #expect(!policy.isClaimed)
    #expect(policy.fenceLifecycleFailure(.interrupted) == false)
    #expect(policy.preCommitFailure() == nil)
    #expect(policy.postCommitFailure() == nil)
}

@Test
func claimedCommitFencesLifecycleFailureBeforePromotion() {
    var policy = FinalizationCommitPolicy()
    policy.claimCommit()

    #expect(policy.isClaimed)
    #expect(policy.fenceLifecycleFailure(.interrupted))
    // Non-lifecycle failures are never fenced.
    #expect(
        policy.fenceLifecycleFailure(.persistenceFailure) == false
    )
    // Only the first fenced failure is retained for a deterministic
    // resolution.
    #expect(policy.fenceLifecycleFailure(.thermalPressure))
    #expect(policy.preCommitFailure() == .interrupted)
    #expect(policy.postCommitFailure() == nil)
}

@Test
func promotedCommitWinsOverFencedFailure() {
    var policy = FinalizationCommitPolicy()
    policy.claimCommit()
    #expect(policy.fenceLifecycleFailure(.storagePressure))

    policy.markPromoted()
    #expect(policy.isPromoted)
    // Pre-commit cancellation is no longer available once promoted.
    #expect(policy.preCommitFailure() == nil)
    #expect(policy.postCommitFailure() == .storagePressure)

    // A failure fenced after promotion is also retained as
    // post-commit status.
    var promotedPolicy = FinalizationCommitPolicy(
        phase: .promoted
    )
    #expect(promotedPolicy.fenceLifecycleFailure(.interrupted))
    #expect(promotedPolicy.postCommitFailure() == .interrupted)
}

@Test
func resolvedCommitStopsFencing() {
    var policy = FinalizationCommitPolicy()
    policy.claimCommit()
    #expect(policy.fenceLifecycleFailure(.thermalPressure))
    policy.reset()

    #expect(!policy.isClaimed)
    #expect(policy.fencedFailure == nil)
    #expect(policy.fenceLifecycleFailure(.interrupted) == false)
    #expect(policy.preCommitFailure() == nil)
    #expect(policy.postCommitFailure() == nil)
}

@Test
func lifecycleFailureClassification() {
    #expect(CaptureFailureCode.interrupted.isLifecycleFailure)
    #expect(CaptureFailureCode.thermalPressure.isLifecycleFailure)
    #expect(CaptureFailureCode.storagePressure.isLifecycleFailure)
    #expect(!CaptureFailureCode.persistenceFailure.isLifecycleFailure)
    #expect(!CaptureFailureCode.trackingUnavailable.isLifecycleFailure)
    #expect(!CaptureFailureCode.roomPlanFailure.isLifecycleFailure)
    #expect(!CaptureFailureCode.permissionDenied.isLifecycleFailure)
    #expect(!CaptureFailureCode.unsupportedDevice.isLifecycleFailure)
    #expect(!CaptureFailureCode.unknown.isLifecycleFailure)
}
