import Foundation

/// "This capture needs" — the operator-facing mission item list
/// (#364 §4). Human-readable needs derived from the bound mission
/// authority (task profile or imported HTDT plan) without exposing
/// schema identifiers: "2 speakers", "Listening position",
/// "Display or projection screen". Completeness stays in Review;
/// this list is a setup-time statement of intent.
public struct CaptureMissionNeed: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Equatable {
        /// Room surfaces/geometry — the baseline every capture needs.
        case roomGeometry = "room_geometry"
        case annotationEntity = "annotation_entity"
        case speakerRole = "speaker_role"
        case measurement
        case semanticTask = "semantic_task"
        case surfaceReview = "surface_review"
    }

    public let kind: Kind
    /// Human label — never a raw schema identifier.
    public let title: String
    /// How many of this item the mission needs (at least 1).
    public let count: Int
    /// Optional items are nice-to-have and never gate completeness.
    public let isOptional: Bool

    public init(
        kind: Kind,
        title: String,
        count: Int,
        isOptional: Bool
    ) {
        self.kind = kind
        self.title = title
        self.count = max(1, count)
        self.isOptional = isOptional
    }
}

public enum CaptureMissionNeeds {
    /// Baseline need shown for every capture: room geometry.
    public static var roomGeometry: CaptureMissionNeed {
        CaptureMissionNeed(
            kind: .roomGeometry,
            title: String(localized: "Room surfaces and geometry"),
            count: 1,
            isOptional: false
        )
    }

    /// Needs derived from a generic task profile (#352). Alternative-
    /// group members merge into a single "A or B" row.
    public static func needs(
        for profile: CaptureTaskProfile
    ) -> [CaptureMissionNeed] {
        var needs: [CaptureMissionNeed] = [roomGeometry]
        var grouped: [String: [CaptureTaskRequirement]] = [:]
        var ungrouped: [CaptureTaskRequirement] = []
        for requirement in profile.requirements {
            if let group = requirement.alternativeGroup {
                grouped[group, default: []].append(requirement)
            } else {
                ungrouped.append(requirement)
            }
        }
        for requirement in ungrouped {
            needs.append(need(for: requirement))
        }
        for (_, members) in grouped.sorted(by: { $0.key < $1.key }) {
            let titles = members.compactMap { title(for: $0.match) }
            let isOptional = members.allSatisfy(\.isOptional)
            let count = members.map(\.minimumCount).max() ?? 1
            let mergedTitle: String
            switch titles.count {
            case 0:
                continue
            case 1:
                mergedTitle = titles[0]
            case 2:
                mergedTitle = String(
                    format: String(localized: "%@ or %@"),
                    titles[0], titles[1]
                )
            default:
                mergedTitle = titles.dropLast().joined(
                    separator: ", "
                ) + String(
                    format: String(localized: ", or %@"),
                    titles.last ?? ""
                )
            }
            needs.append(
                CaptureMissionNeed(
                    kind: kind(for: members[0].match),
                    title: mergedTitle,
                    count: count,
                    isOptional: isOptional
                )
            )
        }
        return needs
    }

    /// Needs derived from an imported HTDT task plan (#240): each
    /// checklist family is aggregated into counted rows — never the
    /// raw `item_id` strings.
    public static func needs(
        for plan: HTDTCaptureTaskPlan
    ) -> [CaptureMissionNeed] {
        var needs: [CaptureMissionNeed] = [roomGeometry]

        // Entity checklist: aggregate by (entity type, role, label
        // hint, required/optional) into counted rows.
        var entityCounts: [String: (title: String, count: Int)] = [:]
        for item in plan.entityChecklist {
            var title = entityTypeTitle(item.entityType)
            if let role = item.channelRole {
                title += " — " + humanizedToken(role.rawValue)
            } else if let hint = item.labelHint, !hint.isEmpty {
                title += " — " + hint
            }
            let key = title + "\u{0}"
                + (item.requirement == .optional ? "o" : "r")
            var entry = entityCounts[key]
                ?? (title: title, count: 0)
            entry.count += 1
            entityCounts[key] = entry
        }
        for key in entityCounts.keys.sorted() {
            let entry = entityCounts[key]!
            needs.append(
                CaptureMissionNeed(
                    kind: .annotationEntity,
                    title: entry.title,
                    count: entry.count,
                    isOptional: key.hasSuffix("\u{0}o")
                )
            )
        }

        var measurementCounts: [String: (Int, Bool)] = [:]
        for item in plan.measurementRequests {
            let title = humanizedToken(item.quantityType)
            var entry = measurementCounts[title] ?? (0, true)
            entry.0 += 1
            entry.1 = entry.1 && item.requirement == .optional
            measurementCounts[title] = entry
        }
        for title in measurementCounts.keys.sorted() {
            let (count, allOptional) = measurementCounts[title]!
            needs.append(
                CaptureMissionNeed(
                    kind: .measurement,
                    title: title,
                    count: count,
                    isOptional: allOptional
                )
            )
        }

        var semanticCounts: [String: (Int, Bool)] = [:]
        for item in plan.semanticTasks {
            let title = item.label?.isEmpty == false
                ? item.label!
                : humanizedToken(item.semanticKind.rawValue)
            var entry = semanticCounts[title] ?? (0, true)
            entry.0 += 1
            entry.1 = entry.1 && item.requirement == .optional
            semanticCounts[title] = entry
        }
        for title in semanticCounts.keys.sorted() {
            let (count, allOptional) = semanticCounts[title]!
            needs.append(
                CaptureMissionNeed(
                    kind: .semanticTask,
                    title: title,
                    count: count,
                    isOptional: allOptional
                )
            )
        }

        let requiredReviews = plan.surfaceReviewTasks.filter {
            $0.requirement == .required
        }.count
        let optionalReviews = plan.surfaceReviewTasks.count
            - requiredReviews
        if requiredReviews > 0 {
            needs.append(
                CaptureMissionNeed(
                    kind: .surfaceReview,
                    title: String(localized: "Surface review"),
                    count: requiredReviews,
                    isOptional: false
                )
            )
        }
        if optionalReviews > 0 {
            needs.append(
                CaptureMissionNeed(
                    kind: .surfaceReview,
                    title: String(localized: "Surface review"),
                    count: optionalReviews,
                    isOptional: true
                )
            )
        }

        return needs
    }

    private static func need(
        for requirement: CaptureTaskRequirement
    ) -> CaptureMissionNeed {
        CaptureMissionNeed(
            kind: kind(for: requirement.match),
            title: title(for: requirement.match)
                ?? humanizedToken(requirement.identifier),
            count: requirement.minimumCount,
            isOptional: requirement.isOptional
        )
    }

    private static func kind(
        for match: CaptureTaskMatch
    ) -> CaptureMissionNeed.Kind {
        switch match.kind {
        case .annotationEntityType:
            return .annotationEntity
        case .annotationChannelRole, .annotationRoleBinding:
            return .speakerRole
        case .measurementQuantityType, .measurementEndpointPair:
            return .measurement
        }
    }

    private static func title(
        for match: CaptureTaskMatch
    ) -> String? {
        switch match.kind {
        case .annotationEntityType:
            guard let type = AnnotationEntityType(
                rawValue: match.value
            ) else {
                return nil
            }
            return entityTypeTitle(type)
        case .annotationChannelRole:
            return String(
                format: String(localized: "Speaker — %@"),
                humanizedToken(match.value)
            )
        case .annotationRoleBinding:
            // Resolve through the built-in profile vocabulary when
            // the role ID is known there; otherwise humanize the
            // token — never the raw role_id (#315). A role that only
            // echoes its channel token ("L", "LFE") keeps that letter
            // — installers read it — while an authored display name
            // ("Front left") goes through the localized channel-role
            // vocabulary instead of staying development-language
            // English.
            let roleID = match.value
            if let profile = match.profileID.flatMap({ id in
                SpeakerLayoutProfiles.all.first {
                    $0.profileID == id
                }
            }), let definition = profile.roleDefinition(
                roleID: roleID
            ) {
                if definition.displayName
                    != definition.channelRole.rawValue {
                    return String(
                        format: String(localized: "Speaker — %@"),
                        channelRoleTitle(
                            definition.channelRole.rawValue
                        )
                    )
                }
                return String(
                    format: String(localized: "Speaker — %@"),
                    humanizedToken(roleID)
                )
            }
            return String(
                format: String(localized: "Speaker — %@"),
                humanizedToken(roleID)
            )
        case .measurementQuantityType:
            return humanizedToken(match.value)
        case .measurementEndpointPair:
            return String(localized: "Endpoint-pair measurement")
        }
    }

    /// Human name for an annotation entity type (#364): the label a
    /// checklist row shows, never the raw `entity_type` token.
    public static func entityTypeTitle(
        _ type: AnnotationEntityType
    ) -> String {
        switch type {
        case .speaker:
            return String(localized: "Speaker")
        case .subwoofer:
            return String(localized: "Subwoofer")
        case .display:
            return String(localized: "Display")
        case .projectionScreen:
            return String(localized: "Projection screen")
        case .projector:
            return String(localized: "Projector")
        case .listeningPosition:
            return String(localized: "Listening position")
        case .seat:
            return String(localized: "Seat")
        case .acousticTreatment:
            return String(localized: "Acoustic treatment")
        case .equipmentRack:
            return String(localized: "Equipment rack")
        case .referencePoint:
            return String(localized: "Reference point")
        case .measurementPoint:
            return String(localized: "Measurement point")
        case .custom:
            return String(localized: "Custom item")
        }
    }

    /// Human name for a channel-role token (#364 family): the label
    /// a checklist row or picker shows, never the raw `SL`/`LFE1`
    /// token. Built-in vocabulary maps to a localized name; custom
    /// equipment tokens humanize so they read as words, not code.
    public static func channelRoleTitle(_ token: String) -> String {
        switch token {
        case "L":
            return String(localized: "Front left")
        case "C":
            return String(localized: "Center")
        case "R":
            return String(localized: "Front right")
        case "SL":
            return String(localized: "Surround left")
        case "SR":
            return String(localized: "Surround right")
        case "SBL":
            return String(localized: "Surround back left")
        case "SBR":
            return String(localized: "Surround back right")
        case "TFL":
            return String(localized: "Top front left")
        case "TFR":
            return String(localized: "Top front right")
        case "TML":
            return String(localized: "Top middle left")
        case "TMR":
            return String(localized: "Top middle right")
        case "TRL":
            return String(localized: "Top rear left")
        case "TRR":
            return String(localized: "Top rear right")
        case "LFE":
            return String(localized: "Subwoofer (LFE)")
        case "LFE1":
            return String(localized: "Subwoofer 1")
        case "LFE2":
            return String(localized: "Subwoofer 2")
        case "LFE3":
            return String(localized: "Subwoofer 3")
        case "LFE4":
            return String(localized: "Subwoofer 4")
        default:
            return humanizedToken(token)
        }
    }

    /// Operator-facing name for one task requirement — derives the
    /// localized phrase from the requirement's match clause so raw
    /// identifiers like `speaker_role_SL` never reach the UI. The
    /// stored identifier stays available as a technical detail via
    /// `requirement.identifier`.
    public static func requirementName(
        _ requirement: CaptureTaskRequirement
    ) -> String {
        title(for: requirement.match)
            ?? humanizedToken(requirement.identifier)
    }

    /// Localized display name for a task profile. Built-in profile
    /// `title`s are development-language strings, so the stable
    /// identifier maps to the operator-facing name; custom host
    /// profiles keep their own title.
    public static func taskProfileName(
        _ profile: CaptureTaskProfile
    ) -> String {
        taskProfileName(
            identifier: profile.identifier,
            fallbackTitle: profile.title
        )
    }

    public static func taskProfileName(
        identifier: String,
        fallbackTitle: String? = nil
    ) -> String {
        switch identifier {
        case "geometry_only":
            return String(localized: "Geometry only")
        case "room_and_listening_position":
            return String(
                localized: "Room + listening position"
            )
        case "theater_layout":
            return String(localized: "Theater layout")
        default:
            return fallbackTitle ?? humanizedToken(identifier)
        }
    }

    /// One-line explanation of what a task profile requires — the
    /// option caption under each task-profile picker choice.
    public static func taskProfileDescription(
        identifier: String
    ) -> String {
        switch identifier {
        case "geometry_only":
            return String(
                localized: "Captures room geometry only; no task requirements are checked."
            )
        case "room_and_listening_position":
            return String(
                localized: "Requires the room shape plus one primary listening position (MLP)."
            )
        case "theater_layout":
            return String(
                localized: "Home-theater capture: requires a listening position, a screen or display, and each speaker role in the plan."
            )
        default:
            return String(
                localized: "Custom task profile supplied by the host app."
            )
        }
    }

    /// "FRONT_LEFT" becomes "Front left"; terse all-caps tokens and
    /// tokens carrying digits ("L", "LFE1", "LTF") pass through
    /// unchanged since they are already operator vocabulary (#364).
    public static func humanizedToken(_ token: String) -> String {
        let words = token.split(separator: "_").map { word -> String in
            let w = String(word)
            let isAllCaps = w.uppercased() == w
                && w.lowercased() != w
            if isAllCaps,
               w.count <= 3
                   || w.contains(where: \.isNumber)
            {
                return w
            }
            return w.prefix(1).uppercased()
                + w.dropFirst().lowercased()
        }
        return words.joined(separator: " ")
    }
}
