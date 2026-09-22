import Foundation

/// Selectable capture-strategy identifiers (issue #307). A strategy is a
/// published, versioned advisory-policy bundle: it sizes the guidance
/// and evidence budgets the operator works against (spatial guidance
/// attempts, weak-region re-observation, automatic evidence-frame
/// retention) plus the advisory review posture the app prompts for.
/// It never redefines `ready_for_htdt_ingestion`, never claims capture
/// accuracy, and is orthogonal to the #217 task-completeness profile —
/// a task profile describes what the operator intends to document,
/// while a strategy describes how the app budgets guidance to get there.
public enum CaptureStrategyIdentifier:
    String,
    Codable,
    Sendable,
    CaseIterable
{
    /// Fast coverage pass: small budgets so a quick sweep does not
    /// nag the operator for additional orbits or retained evidence.
    case quickScan = "quick_scan"
    /// The pre-#307 fixed policy, named and persisted explicitly.
    case standard = "standard"
    /// Large-room sweep: bigger guidance and evidence budgets.
    case detailed = "detailed"
    /// Commissioning/maximum-evidence pass: largest budgets, strict
    /// review posture, loop-closure and complex-object prompts on.
    case commissioning = "commissioning"
}

/// Advisory review posture a strategy asks the operator to hold. This
/// only steers prompts and checklist emphasis; it carries no authority
/// over quality gates.
public enum CaptureStrategyReviewExpectation:
    String,
    Codable,
    Sendable
{
    case minimal
    case standard
    case thorough
}

/// Where the strategy selection came from (issue #307). An operator
/// choice is recorded verbatim; a #240 capture-task plan may recommend
/// or pin a strategy — a pinned strategy is the plan's binding, not an
/// operator preference.
public enum CaptureStrategySource: String, Codable, Sendable {
    case operatorSelected = "operator_selected"
    case taskPlanRecommended = "task_plan_recommended"
    case taskPlanPinned = "task_plan_pinned"
}

/// One published strategy profile (issue #307). Instances are produced
/// only by `CaptureStrategyCatalog`; the identifier+policyVersion pair
/// is the persisted contract — once published, a combination never
/// changes meaning.
public struct CaptureStrategyProfile: Sendable, Equatable {
    public let identifier: CaptureStrategyIdentifier
    /// Version of the resolved policy values embedded in the persisted
    /// `session/capture-strategy.json` document.
    public let policyVersion: String
    /// Stable English display token; localized presentation lives in
    /// the app shell, never in persisted bytes.
    public let displayName: String
    /// One-line operator-facing summary of what the strategy asks for.
    public let summary: String
    /// Resolved spatial/weak-region guidance budgets.
    public let motionGuidance: ScanMotionGuidanceConfiguration
    /// Resolved automatic evidence-frame budget.
    public let automaticKeyframes: AutomaticKeyframeConfiguration
    /// Whether the app should prompt the operator to review complex
    /// objects (mirrors, glass, reflective surfaces) extra carefully.
    public let promptsComplexObjectReview: Bool
    /// Whether the app should surface loop-closure (return-to-start)
    /// check prompts for this strategy.
    public let promptsLoopClosureCheck: Bool
    public let reviewExpectation: CaptureStrategyReviewExpectation

    public init(
        identifier: CaptureStrategyIdentifier,
        policyVersion: String,
        displayName: String,
        summary: String,
        motionGuidance: ScanMotionGuidanceConfiguration,
        automaticKeyframes: AutomaticKeyframeConfiguration,
        reviewExpectation: CaptureStrategyReviewExpectation,
        promptsComplexObjectReview: Bool,
        promptsLoopClosureCheck: Bool
    ) {
        precondition(!policyVersion.isEmpty)
        precondition(!displayName.isEmpty)
        precondition(!summary.isEmpty)
        self.identifier = identifier
        self.policyVersion = policyVersion
        self.displayName = displayName
        self.summary = summary
        self.motionGuidance = motionGuidance
        self.automaticKeyframes = automaticKeyframes
        self.reviewExpectation = reviewExpectation
        self.promptsComplexObjectReview = promptsComplexObjectReview
        self.promptsLoopClosureCheck = promptsLoopClosureCheck
    }
}

/// The published strategy catalog (issue #307). A `strategy_id` +
/// `policy_version` pair always denotes exactly this resolved profile;
/// changing a budget requires a new `policy_version` so persisted
/// bundles keep their recorded meaning.
public enum CaptureStrategyCatalog {
    /// Version of the v1 policy tables. Bump only when a published
    /// profile's resolved values change; new identifiers join v1.
    public static let currentPolicyVersion = "capture_strategy_v1"

    /// Deterministic presentation order for the picker.
    public static let orderedProfiles: [CaptureStrategyProfile] = [
        .quickScan,
        .standard,
        .detailed,
        .commissioning,
    ]

    public static func profile(
        for identifier: CaptureStrategyIdentifier
    ) -> CaptureStrategyProfile {
        switch identifier {
        case .quickScan:
            return .quickScan
        case .standard:
            return .standard
        case .detailed:
            return .detailed
        case .commissioning:
            return .commissioning
        }
    }

    /// Resolves a persisted `strategy_id` string back to its catalog
    /// identifier; unknown identifiers fail closed (`nil`).
    public static func identifier(
        forPersistedValue value: String
    ) -> CaptureStrategyIdentifier? {
        CaptureStrategyIdentifier(rawValue: value)
    }
}

extension CaptureStrategyProfile {
    public static let quickScan = CaptureStrategyProfile(
        identifier: .quickScan,
        policyVersion: CaptureStrategyCatalog.currentPolicyVersion,
        displayName: "Quick scan",
        summary:
            "Fast sweep with small guidance and evidence budgets for a first-pass capture.",
        motionGuidance: ScanMotionGuidanceConfiguration(
            spatialGuidanceActivationCoverageFraction: 0.45,
            maximumWeakRegionGuidanceAttempts: 1,
            maximumSpatialGuidanceAttempts: 3,
            completionDirectionCoverageFraction: 0.85
        ),
        automaticKeyframes: AutomaticKeyframeConfiguration(
            maximumRetainedFrames: 4,
            minimumIntervalSeconds: 15,
            minimumTranslationMeters: 1.0,
            minimumRotationRadians: .pi / 2,
            maximumRetainedBytes: 64 * 1024 * 1024,
            maximumNoDepthFrames: 1
        ),
        reviewExpectation: .minimal,
        promptsComplexObjectReview: false,
        promptsLoopClosureCheck: false
    )

    public static let standard = CaptureStrategyProfile(
        identifier: .standard,
        policyVersion: CaptureStrategyCatalog.currentPolicyVersion,
        displayName: "Standard",
        summary:
            "Default guidance and evidence budgets, matching the historical fixed policy.",
        motionGuidance: .standard,
        automaticKeyframes: .standard,
        reviewExpectation: .standard,
        promptsComplexObjectReview: true,
        promptsLoopClosureCheck: true
    )

    public static let detailed = CaptureStrategyProfile(
        identifier: .detailed,
        policyVersion: CaptureStrategyCatalog.currentPolicyVersion,
        displayName: "Detailed",
        summary:
            "Larger guidance and evidence budgets for big rooms and thorough documentation.",
        motionGuidance: ScanMotionGuidanceConfiguration(
            minimumTranslationBaselineMeters: 0.25,
            spatialGuidanceActivationCoverageFraction: 0.70,
            maximumWeakRegionGuidanceAttempts: 3,
            maximumSpatialGuidanceAttempts: 8,
            completionDirectionCoverageFraction: 0.98
        ),
        automaticKeyframes: AutomaticKeyframeConfiguration(
            maximumRetainedFrames: 10,
            minimumIntervalSeconds: 8,
            minimumTranslationMeters: 0.5,
            minimumRotationRadians: .pi / 4,
            maximumRetainedBytes: 256 * 1024 * 1024,
            maximumNoDepthFrames: 3
        ),
        reviewExpectation: .thorough,
        promptsComplexObjectReview: true,
        promptsLoopClosureCheck: true
    )

    public static let commissioning = CaptureStrategyProfile(
        identifier: .commissioning,
        policyVersion: CaptureStrategyCatalog.currentPolicyVersion,
        displayName: "Commissioning",
        summary:
            "Maximum guidance coverage and evidence retention for formal commissioning work.",
        motionGuidance: ScanMotionGuidanceConfiguration(
            minimumRepeatedWeakObservations: 4,
            minimumTranslationBaselineMeters: 0.20,
            spatialGuidanceActivationCoverageFraction: 0.80,
            maximumWeakRegionGuidanceAttempts: 4,
            maximumSpatialGuidanceAttempts: 12,
            completionDirectionCoverageFraction: 1.0
        ),
        automaticKeyframes: AutomaticKeyframeConfiguration(
            maximumRetainedFrames: 12,
            minimumIntervalSeconds: 6,
            minimumTranslationMeters: 0.4,
            minimumRotationRadians: .pi / 5,
            maximumRetainedBytes: 384 * 1024 * 1024,
            maximumNoDepthFrames: 4
        ),
        reviewExpectation: .thorough,
        promptsComplexObjectReview: true,
        promptsLoopClosureCheck: true
    )
}

public enum CaptureStrategyError: Error, Sendable, Equatable {
    case encodedDocumentMismatch
}

/// Resolved policy values persisted alongside the strategy identity so
/// the bundle records exactly which budgets drove the capture — a
/// consumer never has to re-derive them from the catalog.
public struct CaptureStrategyPolicyEcho:
    Codable,
    Sendable,
    Equatable
{
    public let maximumSpatialGuidanceAttempts: Int
    public let maximumWeakRegionGuidanceAttempts: Int
    public let spatialGuidanceActivationCoverageFraction: Double
    public let completionDirectionCoverageFraction: Double
    public let keyframePolicyVersion: String
    public let maximumRetainedFrames: Int
    public let maximumRetainedBytes: Int
    public let maximumNoDepthFrames: Int
    public let minimumKeyframeIntervalSeconds: Double
    public let minimumKeyframeTranslationMeters: Double
    public let minimumKeyframeRotationRadians: Double

    public init(profile: CaptureStrategyProfile) {
        let guidance = profile.motionGuidance
        let keyframes = profile.automaticKeyframes
        self.maximumSpatialGuidanceAttempts =
            guidance.maximumSpatialGuidanceAttempts
        self.maximumWeakRegionGuidanceAttempts =
            guidance.maximumWeakRegionGuidanceAttempts
        self.spatialGuidanceActivationCoverageFraction =
            guidance.spatialGuidanceActivationCoverageFraction
        self.completionDirectionCoverageFraction =
            guidance.completionDirectionCoverageFraction
        self.keyframePolicyVersion = keyframes.policyVersion
        self.maximumRetainedFrames = keyframes.maximumRetainedFrames
        self.maximumRetainedBytes = keyframes.maximumRetainedBytes
        self.maximumNoDepthFrames = keyframes.maximumNoDepthFrames
        self.minimumKeyframeIntervalSeconds =
            keyframes.minimumIntervalSeconds
        self.minimumKeyframeTranslationMeters =
            keyframes.minimumTranslationMeters
        self.minimumKeyframeRotationRadians =
            keyframes.minimumRotationRadians
    }

    private enum CodingKeys: String, CodingKey {
        case maximumSpatialGuidanceAttempts =
            "maximum_spatial_guidance_attempts"
        case maximumWeakRegionGuidanceAttempts =
            "maximum_weak_region_guidance_attempts"
        case spatialGuidanceActivationCoverageFraction =
            "spatial_guidance_activation_coverage_fraction"
        case completionDirectionCoverageFraction =
            "completion_direction_coverage_fraction"
        case keyframePolicyVersion = "keyframe_policy_version"
        case maximumRetainedFrames = "maximum_retained_frames"
        case maximumRetainedBytes = "maximum_retained_bytes"
        case maximumNoDepthFrames = "maximum_no_depth_frames"
        case minimumKeyframeIntervalSeconds =
            "minimum_keyframe_interval_s"
        case minimumKeyframeTranslationMeters =
            "minimum_keyframe_translation_m"
        case minimumKeyframeRotationRadians =
            "minimum_keyframe_rotation_rad"
    }
}

/// Persisted `session/capture-strategy.json` document (issue #307):
/// which published strategy drove this revision's advisory budgets,
/// where the selection came from, and the resolved policy echo. The
/// document is advisory provenance only — nothing in it feeds
/// `ready_for_htdt_ingestion` and it claims nothing about the achieved
/// spatial accuracy of the capture.
public struct CaptureStrategyDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.strategy"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    /// Catalog `strategy_id`; one of the `CaptureStrategyIdentifier`
    /// persisted values.
    public let strategyID: String
    /// Catalog `policy_version`; pins the meaning of `resolved_policy`.
    public let policyVersion: String
    public let source: CaptureStrategySource
    public let reviewExpectation: CaptureStrategyReviewExpectation
    public let promptsComplexObjectReview: Bool
    public let promptsLoopClosureCheck: Bool
    public let resolvedPolicy: CaptureStrategyPolicyEcho
    public let selectedAtUTC: String

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        profile: CaptureStrategyProfile,
        source: CaptureStrategySource,
        selectedAtUTC: String
    ) throws {
        guard SchemaTimestampText.isUTCTimestamp(selectedAtUTC) else {
            throw CaptureWorkingSetError.invalidCaptureStrategy
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.strategyID = profile.identifier.rawValue
        self.policyVersion = profile.policyVersion
        self.source = source
        self.reviewExpectation = profile.reviewExpectation
        self.promptsComplexObjectReview =
            profile.promptsComplexObjectReview
        self.promptsLoopClosureCheck =
            profile.promptsLoopClosureCheck
        self.resolvedPolicy = CaptureStrategyPolicyEcho(
            profile: profile
        )
        self.selectedAtUTC = selectedAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case strategyID = "strategy_id"
        case policyVersion = "policy_version"
        case source
        case reviewExpectation = "review_expectation"
        case promptsComplexObjectReview = "complex_object_prompts"
        case promptsLoopClosureCheck = "loop_closure_prompts"
        case resolvedPolicy = "resolved_policy"
        case selectedAtUTC = "selected_at"
    }
}

/// Encoded `session/capture-strategy.json` package ready for the
/// working-set store (issue #307).
public struct CaptureStrategyPackage: Sendable, Equatable {
    public static let path = "session/capture-strategy.json"

    public let document: CaptureStrategyDocument
    public let data: Data

    public init(document: CaptureStrategyDocument, data: Data) {
        self.document = document
        self.data = data
    }

    /// Canonical-session provenance: the strategy selection binds to
    /// the capture session it steered, expressed through a
    /// `capture_session:` source ref like the room reference frame.
    public var payloadDeclaration: BundlePayloadDeclaration {
        BundlePayloadDeclaration(
            path: Self.path,
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical,
            sourceRefs: [
                "capture_session:"
                    + document.captureSessionID.description
            ]
        )
    }
}

public enum CaptureStrategyPackageBuilder {
    public static func build(
        document: CaptureStrategyDocument
    ) throws -> CaptureStrategyPackage {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)

        guard let decoded = try? JSONDecoder().decode(
            CaptureStrategyDocument.self,
            from: data
        ), decoded == document else {
            throw CaptureStrategyError.encodedDocumentMismatch
        }
        return CaptureStrategyPackage(
            document: document,
            data: data
        )
    }
}
