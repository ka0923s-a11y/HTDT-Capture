import Foundation
import Testing
@testable import HTDTCaptureCore

// #323: relocalization is an authority, not a UI state. The ARKit
// "relocalized" label alone is never sufficient — only a versioned
// acceptance policy may resume a scan into a new scan_segment_id,
// and everything else fails closed into a fresh coordinate space.

private func makeAttempt(
    outcome: RelocalizationARKitOutcome = .relocalized,
    checks: [RelocalizationReferenceCheck] = [],
    endedAt: String? = "2026-09-22T01:00:01Z",
    priorSpace: CoordinateSpaceID = CoordinateSpaceID(),
    decision: RelocalizationDecision? = nil,
    decisionPolicyID: String? = nil,
    decisionPolicyVersion: String? = nil
) throws -> RelocalizationAttempt {
    try RelocalizationAttempt(
        captureSessionID: CaptureSessionID(),
        priorSessionID: CaptureSessionID(),
        priorCoordinateSpaceID: priorSpace,
        mapIdentity: "sha256:map",
        interruptionBoundary: .applicationRestart,
        attemptStartedAtUTC: "2026-09-22T01:00:00Z",
        attemptEndedAtUTC: endedAt,
        arkitOutcome: outcome,
        referenceChecks: checks,
        decision: decision,
        decisionPolicyID: decisionPolicyID,
        decisionPolicyVersion: decisionPolicyVersion,
        appVersion: "1.0.0",
        osVersion: "26.0",
        deviceModel: "iPhone17,1"
    )
}

private func check(
    _ id: String,
    kind: RelocalizationReferenceKind = .fiducial,
    residual: Double
) throws -> RelocalizationReferenceCheck {
    try RelocalizationReferenceCheck(
        referenceID: id,
        kind: kind,
        residualMeters: residual
    )
}

@Test
func relocalizedLabelAloneIsRejected() throws {
    let policy = RelocalizationAcceptancePolicy.standard
    let attempt = try makeAttempt()
    guard case let .reject(reasons) = policy.evaluate(attempt) else {
        Issue.record("expected rejection")
        return
    }
    #expect(reasons.contains(.insufficientReferenceChecks))
    #expect(attempt.resumeDecision(
        evaluatedUnder: policy,
        sessionTimestampSeconds: 5
    ) == nil)
}

@Test
func verifiedChecksAcceptAndPreserveSpace() throws {
    let policy = RelocalizationAcceptancePolicy.standard
    let priorSpace = CoordinateSpaceID()
    let attempt = try makeAttempt(
        checks: [
            try check("fid-1", residual: 0.01),
            try check("anchor-7", kind: .spatialAnchor, residual: 0.04),
        ],
        priorSpace: priorSpace
    )
    guard case let .accept(disposition) = policy.evaluate(attempt)
    else {
        Issue.record("expected acceptance")
        return
    }
    #expect(disposition == .preserveCoordinateSpace)
    let segment = try #require(
        attempt.resumeDecision(
            evaluatedUnder: policy,
            sessionTimestampSeconds: 12
        )
    )
    #expect(segment.coordinateSpaceID == priorSpace)
    #expect(segment.openedByAttemptID == attempt.attemptID)
    #expect(segment.startedAtSessionTimestampSeconds == 12)
}

@Test
func acceptedWithLooseResidualResumesIntoFreshSpace() throws {
    let policy = RelocalizationAcceptancePolicy.standard
    let priorSpace = CoordinateSpaceID()
    let attempt = try makeAttempt(
        checks: [try check("fid-1", residual: 0.10)],
        priorSpace: priorSpace
    )
    guard case let .accept(disposition) = policy.evaluate(attempt)
    else {
        Issue.record("expected acceptance")
        return
    }
    #expect(disposition == .freshCoordinateSpace)
    let fresh = CoordinateSpaceID()
    let segment = try #require(
        attempt.resumeDecision(
            evaluatedUnder: policy,
            sessionTimestampSeconds: 3,
            freshSpace: fresh
        )
    )
    #expect(segment.coordinateSpaceID == fresh)
    #expect(segment.coordinateSpaceID != priorSpace)
}

@Test
func residualOverMaximumIsRejected() throws {
    let policy = RelocalizationAcceptancePolicy.standard
    let attempt = try makeAttempt(
        checks: [try check("fid-1", residual: 0.50)]
    )
    guard case let .reject(reasons) = policy.evaluate(attempt) else {
        Issue.record("expected rejection")
        return
    }
    #expect(reasons.contains(.residualExceedsMaximum))
}

@Test
func arkitFailureIsRejectedEvenWithGoodChecks() throws {
    let policy = RelocalizationAcceptancePolicy.standard
    let attempt = try makeAttempt(
        outcome: .failed,
        checks: [try check("fid-1", residual: 0.01)]
    )
    guard case let .reject(reasons) = policy.evaluate(attempt) else {
        Issue.record("expected rejection")
        return
    }
    #expect(reasons.contains(.arkitDidNotRelocalize))
}

@Test
func inFlightAttemptCannotBeADecisionAuthority() throws {
    let policy = RelocalizationAcceptancePolicy.standard
    let attempt = try makeAttempt(
        checks: [try check("fid-1", residual: 0.01)],
        endedAt: nil
    )
    guard case let .reject(reasons) = policy.evaluate(attempt) else {
        Issue.record("expected rejection")
        return
    }
    #expect(reasons.contains(.incompleteAttempt))
}

@Test
func unqualifiedCheckKindIsRejected() throws {
    let policy = RelocalizationAcceptancePolicy.standard
    let attempt = try makeAttempt(
        checks: [try check("mystery", kind: .unqualified, residual: 0.01)]
    )
    guard case let .reject(reasons) = policy.evaluate(attempt) else {
        Issue.record("expected rejection")
        return
    }
    #expect(reasons.contains(.unqualifiedCheckKind))
    #expect(reasons.contains(.insufficientReferenceChecks))
}

@Test
func recordDecisionStampsPolicyIdentity() throws {
    let policy = RelocalizationAcceptancePolicy.standard
    let accepted = try policy.recordDecision(
        on: makeAttempt(checks: [try check("fid-1", residual: 0.01)])
    )
    #expect(accepted.decision == .accepted)
    #expect(accepted.decisionPolicyID == policy.policyID)
    #expect(accepted.decisionPolicyVersion == policy.policyVersion)

    let rejected = try policy.recordDecision(on: makeAttempt())
    #expect(rejected.decision == .rejected)
    #expect(rejected.decisionPolicyID == policy.policyID)
}

@Test
func recordedAcceptedDecisionMustCitePolicyAndChecks() throws {
    #expect(throws: AnnotationModelError.invalidAuthorityComponent) {
        _ = try makeAttempt(
            checks: [try check("fid-1", residual: 0.01)],
            decision: .accepted
        )
    }
    #expect(throws: AnnotationModelError.invalidAuthorityComponent) {
        _ = try makeAttempt(
            outcome: .failed,
            checks: [try check("fid-1", residual: 0.01)],
            decision: .accepted,
            decisionPolicyID: "p",
            decisionPolicyVersion: "1.0.0"
        )
    }
    #expect(throws: AnnotationModelError.invalidAuthorityComponent) {
        _ = try makeAttempt(
            decision: .accepted,
            decisionPolicyID: "p",
            decisionPolicyVersion: "1.0.0"
        )
    }
}

@Test
func attemptAndSegmentRoundTrip() throws {
    let policy = RelocalizationAcceptancePolicy.standard
    let decided = try policy.recordDecision(
        on: makeAttempt(checks: [try check("fid-1", residual: 0.02)])
    )
    let data = try JSONEncoder().encode(decided)
    #expect(
        try JSONDecoder().decode(RelocalizationAttempt.self, from: data)
            == decided
    )
    let segment = try #require(
        decided.resumeDecision(
            evaluatedUnder: policy,
            sessionTimestampSeconds: 7
        )
    )
    let segmentData = try JSONEncoder().encode(segment)
    #expect(
        try JSONDecoder().decode(ScanSegment.self, from: segmentData)
            == segment
    )
}
