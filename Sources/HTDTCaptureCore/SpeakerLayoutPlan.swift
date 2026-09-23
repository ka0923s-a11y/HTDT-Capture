import Foundation

/// One role in a guided speaker-layout capture plan (#278). Roles come
/// from an explicit plan — a named preset the operator selected, or a
/// task/profile supplied list — never an assumed fixed layout.
public struct SpeakerLayoutRole: Codable, Sendable, Equatable, Identifiable {
    /// Unique token inside the plan (e.g. `"L"`, `"LFE_2"`). Equals the
    /// channel-role token when unambiguous.
    public let roleID: String
    /// Canonical channel-role token written into the speaker entity.
    public let channelRole: ChannelRole
    /// Whether this role is a subwoofer — the entity is created with
    /// `type == .subwoofer` and no channel role requirement.
    public let isSubwoofer: Bool
    /// Display name for the checklist (e.g. "Front left").
    public let displayName: String

    public init(
        roleID: String,
        channelRole: ChannelRole,
        isSubwoofer: Bool = false,
        displayName: String? = nil
    ) {
        self.roleID = roleID
        self.channelRole = channelRole
        self.isSubwoofer = isSubwoofer
        self.displayName = displayName ?? channelRole.description
    }

    /// Channel-token match used when rebuilding progress from unbound
    /// staged entities: exact for speakers; the whole LFE instance
    /// family (`LFE`, `LFE1`…`LFE4`) for sub roles, so a staged
    /// `LFE2` still completes the plan's generic `LFE` role.
    public func matches(channelRole other: ChannelRole?) -> Bool {
        guard let other else { return false }
        if isSubwoofer {
            return other == .lfe
                || ChannelRole.subwooferRoles.contains(other)
        }
        return other == channelRole
    }

    public var id: String { roleID }

    private enum CodingKeys: String, CodingKey {
        case roleID = "role_id"
        case channelRole = "channel_role"
        case isSubwoofer = "is_subwoofer"
        case displayName = "display_name"
    }
}

/// An ordered role list for the guided batch speaker capture flow
/// (#278). The plan is explicit operator/task authority: the flow steps
/// through `roles` one at a time, tracks per-role completion against
/// the staged annotations, and never invents extra roles.
public struct SpeakerLayoutPlan: Codable, Sendable, Equatable {
    public static let schema = "htdt.speaker-layout-plan"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    /// Plan label, e.g. the preset name or a task-plan identifier.
    public let planName: String
    /// Exact layout profile this plan's role order comes from (#315);
    /// nil on plans written before profile authority existed.
    public let profileIdentity: SpeakerLayoutProfileReference?
    public var roles: [SpeakerLayoutRole]

    public init(
        planName: String,
        roles: [SpeakerLayoutRole],
        profileIdentity: SpeakerLayoutProfileReference? = nil
    ) {
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.planName = planName
        self.profileIdentity = profileIdentity
        self.roles = roles
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case planName = "plan_name"
        case profileIdentity = "profile_identity"
        case roles
    }
}

/// Named presets the operator can pick when no external task plan
/// (#240) is supplied. Selecting a preset is an explicit choice — the
/// plan lists every role it will ask for, and the operator can still
/// add/remove roles or skip them inside the flow.
public enum SpeakerLayoutPresets {
    /// Each preset plan is derived from its exact `SpeakerLayoutProfile`
    /// (#315): the role order is the profile's declaration order and the
    /// plan carries the profile identity so entities authored through
    /// the flow can record a `role_binding` against it.
    public static var stereo: SpeakerLayoutPlan {
        SpeakerLayoutProfiles.stereo.makePlan()
    }

    public static var surround5_1: SpeakerLayoutPlan {
        SpeakerLayoutProfiles.surround5_1.makePlan()
    }

    public static var surround7_1: SpeakerLayoutPlan {
        SpeakerLayoutProfiles.surround7_1.makePlan()
    }

    public static var surround7_1_4: SpeakerLayoutPlan {
        SpeakerLayoutProfiles.surround7_1_4.makePlan()
    }

    public static var all: [SpeakerLayoutPlan] {
        [stereo, surround5_1, surround7_1, surround7_1_4]
    }
}

/// Per-role capture state inside a running layout flow (#278).
/// `skipped` and `notInstalled` are kept distinct from `pending` so a
/// deliberately skipped role is never confused with a forgotten one.
public enum SpeakerLayoutRoleState: String, Codable, Sendable, Equatable {
    case pending
    case completed
    case skipped
    case notInstalled = "not_installed"
}

/// Live progress of a layout flow against the staged annotations.
public struct SpeakerLayoutProgress: Sendable, Equatable {
    /// Entity produced for the role, when completed.
    public private(set) var states: [String: SpeakerLayoutRoleState]
    /// Entity ID per completed role, for review/jump-back.
    public private(set) var entityByRole: [String: AnnotationEntityID]

    public init(plan: SpeakerLayoutPlan) {
        var states: [String: SpeakerLayoutRoleState] = [:]
        for role in plan.roles {
            states[role.roleID] = .pending
        }
        self.states = states
        self.entityByRole = [:]
    }

    /// Rebuilds progress for `plan` against already-staged annotations
    /// (used when reopening a draft or continuing after edits). An
    /// entity explicitly bound to a role via `role_binding` wins; an
    /// unbound entity completes a role through the channel-token
    /// match. One entity claims at most one role, so two roles
    /// sharing a channel token never complete each other off a
    /// single speaker, and an entity bound to a different role is
    /// never silently re-counted.
    public init(
        plan: SpeakerLayoutPlan,
        annotations: [CaptureAnnotationEntity]
    ) {
        self.init(plan: plan)
        var claimed = Set<AnnotationEntityID>()
        for role in plan.roles {
            if let entity = annotations.first(where: { entity in
                guard !claimed.contains(entity.entityID),
                      let binding = entity.roleBinding,
                      binding.roleID == role.roleID
                else {
                    return false
                }
                guard let identity = plan.profileIdentity else {
                    return true
                }
                return binding.profileID == identity.profileID
                    && binding.profileVersion
                        == identity.profileVersion
            }) {
                states[role.roleID] = .completed
                entityByRole[role.roleID] = entity.entityID
                claimed.insert(entity.entityID)
                continue
            }
            if let entity = annotations.first(where: {
                !claimed.contains($0.entityID)
                    && $0.roleBinding == nil
                    && role.matches(channelRole: $0.channelRole)
            }) {
                states[role.roleID] = .completed
                entityByRole[role.roleID] = entity.entityID
                claimed.insert(entity.entityID)
            }
        }
    }

    public func state(for roleID: String) -> SpeakerLayoutRoleState {
        states[roleID] ?? .pending
    }

    public mutating func markCompleted(
        roleID: String,
        entityID: AnnotationEntityID
    ) {
        states[roleID] = .completed
        entityByRole[roleID] = entityID
    }

    public mutating func markSkipped(roleID: String) {
        states[roleID] = .skipped
    }

    public mutating func markNotInstalled(roleID: String) {
        states[roleID] = .notInstalled
    }

    public mutating func markPending(roleID: String) {
        states[roleID] = .pending
        entityByRole[roleID] = nil
    }

    /// First role still needing attention: pending roles first, then
    /// none — skipped/not-installed stay out of the auto-advance queue.
    public func nextPendingRole(
        in plan: SpeakerLayoutPlan
    ) -> SpeakerLayoutRole? {
        plan.roles.first { states[$0.roleID] == .pending }
    }
}
