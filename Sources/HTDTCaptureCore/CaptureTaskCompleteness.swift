import Foundation

/// A single match clause inside a task requirement. The `kind` selects
/// which authority collection the `value` applies to; `endpoint_refs`
/// further constrains `measurement_endpoint_pair` matches to a specific
/// ordered endpoint binding.
public struct CaptureTaskMatch: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case annotationEntityType = "annotation_entity_type"
        case annotationChannelRole = "annotation_channel_role"
        case measurementQuantityType = "measurement_quantity_type"
        case measurementEndpointPair = "measurement_endpoint_pair"
    }

    public let kind: Kind
    public let value: String
    public let endpointRefs: [String]

    public init(kind: Kind, value: String, endpointRefs: [String] = []) {
        self.kind = kind
        self.value = value
        self.endpointRefs = endpointRefs
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case value
        case endpointRefs = "endpoint_refs"
    }
}

/// One operator-level completeness requirement. `alternativeGroup`
/// members form a logical OR: the group requirement is satisfied when
/// any member with the same group name is satisfied. Non-optional
/// requirements that support an explicit skip outcome may record
/// `skipped` instead of satisfied/missing.
public struct CaptureTaskRequirement: Sendable, Equatable, Codable {
    public let identifier: String
    public let match: CaptureTaskMatch
    public let minimumCount: Int
    public let maximumCount: Int?
    public let isOptional: Bool
    public let alternativeGroup: String?
    public let allowsSkippedOutcome: Bool

    public init(
        identifier: String,
        match: CaptureTaskMatch,
        minimumCount: Int = 1,
        maximumCount: Int? = nil,
        isOptional: Bool = false,
        alternativeGroup: String? = nil,
        allowsSkippedOutcome: Bool = true
    ) {
        self.identifier = identifier
        self.match = match
        self.minimumCount = max(0, minimumCount)
        self.maximumCount = maximumCount
        self.isOptional = isOptional
        self.alternativeGroup = alternativeGroup
        self.allowsSkippedOutcome = allowsSkippedOutcome
    }

    enum CodingKeys: String, CodingKey {
        case identifier
        case match
        case minimumCount = "minimum_count"
        case maximumCount = "maximum_count"
        case isOptional = "is_optional"
        case alternativeGroup = "alternative_group"
        case allowsSkippedOutcome = "allows_skipped_outcome"
    }
}

/// The operator-declared intent for the capture. A profile never feeds
/// `ready_for_htdt_ingestion`; it evaluates only against the task
/// completeness layer (#217/#259).
public struct CaptureTaskProfile: Sendable, Equatable, Codable {
    public let identifier: String
    public let title: String
    public let requirements: [CaptureTaskRequirement]

    public init(
        identifier: String,
        title: String,
        requirements: [CaptureTaskRequirement]
    ) {
        self.identifier = identifier
        self.title = title
        self.requirements = requirements
    }

    public static let geometryOnly = CaptureTaskProfile(
        identifier: "geometry_only",
        title: "Geometry only",
        requirements: []
    )

    public static let roomAndListeningPosition = CaptureTaskProfile(
        identifier: "room_and_listening_position",
        title: "Room + listening position",
        requirements: [
            CaptureTaskRequirement(
                identifier: "primary_listening_position",
                match: CaptureTaskMatch(
                    kind: .annotationEntityType,
                    value: AnnotationEntityType.listeningPosition.rawValue
                ),
                minimumCount: 1,
                maximumCount: 1,
                allowsSkippedOutcome: false
            ),
        ]
    )

    /// Built-in profiles that a device-local default may seed
    /// (#338). Project/task plans remain the override authority — a
    /// stored identifier only initializes an unset capture.
    public static let standalonePresets: [CaptureTaskProfile] = [
        .geometryOnly,
        .roomAndListeningPosition,
    ]

    /// Resolves a stored preset identifier to the built-in profile.
    /// Unknown identifiers degrade to nil so a stale or future
    /// identifier never silently selects the wrong strategy.
    public static func standalonePreset(
        identifier: String
    ) -> CaptureTaskProfile? {
        standalonePresets.first { $0.identifier == identifier }
    }

    /// Theater layout profile: exactly one MLP, at least one screen or
    /// display, one annotation per selected speaker role, and a
    /// configurable subwoofer count. The role list is caller-chosen so
    /// nonstandard topologies stay representable (#217).
    public static func theaterLayout(
        speakerRoles: [String],
        subwooferCount: Int = 0
    ) -> CaptureTaskProfile {
        var requirements: [CaptureTaskRequirement] = [
            CaptureTaskRequirement(
                identifier: "primary_listening_position",
                match: CaptureTaskMatch(
                    kind: .annotationEntityType,
                    value: AnnotationEntityType.listeningPosition.rawValue
                ),
                minimumCount: 1,
                maximumCount: 1,
                allowsSkippedOutcome: false
            ),
            CaptureTaskRequirement(
                identifier: "screen_or_display",
                match: CaptureTaskMatch(
                    kind: .annotationEntityType,
                    value: AnnotationEntityType.display.rawValue
                ),
                minimumCount: 1,
                alternativeGroup: "screen_presence",
                allowsSkippedOutcome: false
            ),
            CaptureTaskRequirement(
                identifier: "screen_or_display_projection",
                match: CaptureTaskMatch(
                    kind: .annotationEntityType,
                    value: AnnotationEntityType.projectionScreen.rawValue
                ),
                minimumCount: 1,
                alternativeGroup: "screen_presence",
                allowsSkippedOutcome: false
            ),
        ]
        let roles = Array(Set(speakerRoles.map { $0.uppercased() }))
            .sorted()
        for role in roles {
            requirements.append(
                CaptureTaskRequirement(
                    identifier: "speaker_role_\(role)",
                    match: CaptureTaskMatch(
                        kind: .annotationChannelRole,
                        value: role
                    ),
                    minimumCount: 1,
                    allowsSkippedOutcome: false
                )
            )
        }
        if subwooferCount > 0 {
            requirements.append(
                CaptureTaskRequirement(
                    identifier: "subwoofers",
                    match: CaptureTaskMatch(
                        kind: .annotationChannelRole,
                        value: "LFE"
                    ),
                    minimumCount: subwooferCount,
                    allowsSkippedOutcome: false
                )
            )
        }
        return CaptureTaskProfile(
            identifier: "theater_layout",
            title: "Theater layout",
            requirements: requirements
        )
    }
}

public enum CaptureTaskRequirementStatus: String, Sendable, Equatable, Codable {
    case satisfied
    case partial
    case missing
    case satisfiedByAlternative = "satisfied_by_alternative"
    case skipped
    case optionalAbsent = "optional_absent"
    case overMaximum = "over_maximum"
}

public struct CaptureTaskRequirementOutcome: Sendable, Equatable, Codable {
    public let requirement: CaptureTaskRequirement
    public let status: CaptureTaskRequirementStatus
    public let observedCount: Int
    public let matchedRefs: [String]


    public init(
        requirement: CaptureTaskRequirement,
        status: CaptureTaskRequirementStatus,
        observedCount: Int,
        matchedRefs: [String]
    ) {
        self.requirement = requirement
        self.status = status
        self.observedCount = observedCount
        self.matchedRefs = matchedRefs
    }


    enum CodingKeys: String, CodingKey {
        case requirement
        case status
        case observedCount = "observed_count"
        case matchedRefs = "matched_refs"
    }
}

public enum CaptureTaskEvaluationState: String, Sendable, Equatable, Codable {
    case evaluated
    case noProfileSelected = "no_profile_selected"
    case noRequirementsConfigured = "no_requirements_configured"
}

public struct CaptureTaskCompletenessReport: Sendable, Equatable, Codable {
    public let profileIdentifier: String?
    public let profileTitle: String?
    public let evaluationState: CaptureTaskEvaluationState
    public let outcomes: [CaptureTaskRequirementOutcome]
    public let requiredUnsatisfiedCount: Int
    public let overallSatisfied: Bool


    public init(
        profileIdentifier: String?,
        profileTitle: String?,
        evaluationState: CaptureTaskEvaluationState,
        outcomes: [CaptureTaskRequirementOutcome],
        requiredUnsatisfiedCount: Int,
        overallSatisfied: Bool
    ) {
        self.profileIdentifier = profileIdentifier
        self.profileTitle = profileTitle
        self.evaluationState = evaluationState
        self.outcomes = outcomes
        self.requiredUnsatisfiedCount = requiredUnsatisfiedCount
        self.overallSatisfied = overallSatisfied
    }


    enum CodingKeys: String, CodingKey {
        case profileIdentifier = "profile_identifier"
        case profileTitle = "profile_title"
        case evaluationState = "evaluation_state"
        case outcomes
        case requiredUnsatisfiedCount = "required_unsatisfied_count"
        case overallSatisfied = "overall_satisfied"
    }
}

public enum CaptureTaskCompletenessEvaluator {
    /// Evaluates a task profile against the committed annotation and
    /// measurement collections. Duplicate records collapse to their own
    /// identity: each requirement counts only records matching its own
    /// clause, so one record cannot satisfy unrelated requirements
    /// unless the requirements intentionally share a match clause.
    public static func evaluate(
        profile: CaptureTaskProfile?,
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        skippedRequirementIDs: Set<String> = []
    ) -> CaptureTaskCompletenessReport {
        guard let profile else {
            return CaptureTaskCompletenessReport(
                profileIdentifier: nil,
                profileTitle: nil,
                evaluationState: .noProfileSelected,
                outcomes: [],
                requiredUnsatisfiedCount: 0,
                overallSatisfied: false
            )
        }
        guard !profile.requirements.isEmpty else {
            return CaptureTaskCompletenessReport(
                profileIdentifier: profile.identifier,
                profileTitle: profile.title,
                evaluationState: .noRequirementsConfigured,
                outcomes: [],
                requiredUnsatisfiedCount: 0,
                overallSatisfied: true
            )
        }

        let raw: [(requirement: CaptureTaskRequirement, count: Int, refs: [String])] =
            profile.requirements.map { requirement in
                let refs = matchedRefs(
                    for: requirement.match,
                    annotations: annotations,
                    measurements: measurements
                )
                return (requirement, refs.count, refs)
            }

        var satisfiedGroups: Set<String> = []
        for entry in raw where entry.count >= entry.requirement.minimumCount {
            if let group = entry.requirement.alternativeGroup {
                satisfiedGroups.insert(group)
            }
        }

        var outcomes: [CaptureTaskRequirementOutcome] = []
        var unsatisfied = 0
        for entry in raw {
            let requirement = entry.requirement
            var status: CaptureTaskRequirementStatus
            if skippedRequirementIDs.contains(requirement.identifier),
               requirement.allowsSkippedOutcome
            {
                status = .skipped
            } else if let maximum = requirement.maximumCount,
                      entry.count > maximum
            {
                status = .overMaximum
            } else if entry.count >= requirement.minimumCount {
                status = .satisfied
            } else if let group = requirement.alternativeGroup,
                      satisfiedGroups.contains(group)
            {
                status = .satisfiedByAlternative
            } else if requirement.isOptional {
                status = .optionalAbsent
            } else {
                status = entry.count > 0 ? .partial : .missing
            }

            switch status {
            case .satisfied, .satisfiedByAlternative, .skipped,
                 .optionalAbsent:
                break
            case .partial, .missing, .overMaximum:
                if !requirement.isOptional {
                    unsatisfied += 1
                }
            }
            outcomes.append(
                CaptureTaskRequirementOutcome(
                    requirement: requirement,
                    status: status,
                    observedCount: entry.count,
                    matchedRefs: entry.refs
                )
            )
        }

        return CaptureTaskCompletenessReport(
            profileIdentifier: profile.identifier,
            profileTitle: profile.title,
            evaluationState: .evaluated,
            outcomes: outcomes,
            requiredUnsatisfiedCount: unsatisfied,
            overallSatisfied: unsatisfied == 0
        )
    }

    private static func matchedRefs(
        for match: CaptureTaskMatch,
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement]
    ) -> [String] {
        switch match.kind {
        case .annotationEntityType:
            return annotations.compactMap { entity in
                entity.type.rawValue == match.value
                    ? "annotation:\(entity.entityID.description)"
                    : nil
            }.sorted()
        case .annotationChannelRole:
            return annotations.compactMap { entity in
                entity.channelRole?.rawValue == match.value
                    ? "annotation:\(entity.entityID.description)"
                    : nil
            }.sorted()
        case .measurementQuantityType:
            return measurements.compactMap { measurement in
                measurement.quantityType == match.value
                    ? "measurement:\(measurement.measurementID.description)"
                    : nil
            }.sorted()
        case .measurementEndpointPair:
            guard match.endpointRefs.count == 2 else { return [] }
            let wanted = Set(match.endpointRefs)
            return measurements.compactMap { measurement in
                guard measurement.quantityType == match.value,
                      Set(measurement.endpointRefs) == wanted
                else { return nil }
                return "measurement:\(measurement.measurementID.description)"
            }.sorted()
        }
    }
}
