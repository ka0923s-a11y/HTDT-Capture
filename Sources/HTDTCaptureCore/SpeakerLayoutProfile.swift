import Foundation

public enum SpeakerLayoutProfileError: Error, Sendable, Equatable {
    case emptyField
    case duplicateRoleID
    case unsupportedSchema
    case invalidCardinality
}

/// The exact logical-role binding an annotation carries (#315).
///
/// `channel_role` remains the physical-channel token emitted since v1;
/// `role_binding` adds the separate logical authority: which versioned
/// layout/profile the role was selected from and which role ID inside
/// that profile it names. Display names are presentation only — the
/// `(profile_id, profile_version, role_id)` triple is the identity
/// HTDT #505 consumes without heuristic normalization.
public struct SpeakerRoleBinding:
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    public let profileID: String
    public let profileVersion: String
    /// Logical role ID inside the named profile (e.g. `"L"`, `"LFE"`,
    /// or a custom `"ARRAY_LEFT"` the profile itself defines).
    public let roleID: String

    public init(
        profileID: String,
        profileVersion: String,
        roleID: String
    ) throws {
        let id = SchemaOwnedText.nfc(profileID)
        let version = SchemaOwnedText.nfc(profileVersion)
        let role = SchemaOwnedText.nfc(roleID)
        guard !id.isEmpty, !version.isEmpty, !role.isEmpty else {
            throw SpeakerLayoutProfileError.emptyField
        }
        self.profileID = id
        self.profileVersion = version
        self.roleID = role
    }

    private enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case profileVersion = "profile_version"
        case roleID = "role_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            profileID: container.decode(String.self, forKey: .profileID),
            profileVersion: container.decode(
                String.self,
                forKey: .profileVersion
            ),
            roleID: container.decode(String.self, forKey: .roleID)
        )
    }
}

/// Identity of a layout profile without its role list — what a
/// `SpeakerLayoutPlan` records so a batch flow states exactly which
/// profile its role order came from (#278).
public struct SpeakerLayoutProfileReference:
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    public let profileID: String
    public let profileVersion: String

    public init(profileID: String, profileVersion: String) throws {
        let id = SchemaOwnedText.nfc(profileID)
        let version = SchemaOwnedText.nfc(profileVersion)
        guard !id.isEmpty, !version.isEmpty else {
            throw SpeakerLayoutProfileError.emptyField
        }
        self.profileID = id
        self.profileVersion = version
    }

    private enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case profileVersion = "profile_version"
    }
}

/// One logical role inside a versioned layout profile (#315).
///
/// `roleID` is the logical identity — stable across display renames.
/// `channelRole` is the canonical `channel_role` token written for a
/// single-instance binding; multi-binding roles (`maximumCount` nil or
/// >1) may emit per-instance tokens (`LFE1`, `LFE2`, …) while all of
/// them still bind to this one logical role ID.
public struct SpeakerLayoutRoleDefinition:
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    public let roleID: String
    public let channelRole: ChannelRole
    /// Operator-facing name — never identity.
    public let displayName: String
    public let isSubwoofer: Bool
    /// Entities required to satisfy the profile for this role; 0 for
    /// optional roles.
    public let minimumCount: Int
    /// Binding cap; nil means unbounded (e.g. a logical bass role fed
    /// by several physical subs).
    public let maximumCount: Int?

    public init(
        roleID: String,
        channelRole: ChannelRole,
        displayName: String? = nil,
        isSubwoofer: Bool = false,
        minimumCount: Int = 0,
        maximumCount: Int? = 1
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(roleID)
        let normalizedName = SchemaOwnedText.nfc(displayName)
        guard !normalizedID.isEmpty,
              !(normalizedName?.isEmpty ?? false)
        else {
            throw SpeakerLayoutProfileError.emptyField
        }
        guard minimumCount >= 0,
              maximumCount == nil || maximumCount! >= 0,
              maximumCount == nil || minimumCount <= maximumCount!
        else {
            throw SpeakerLayoutProfileError.invalidCardinality
        }
        self.roleID = normalizedID
        self.channelRole = channelRole
        self.displayName = normalizedName ?? channelRole.rawValue
        self.isSubwoofer = isSubwoofer
        self.minimumCount = minimumCount
        self.maximumCount = maximumCount
    }

    /// Whether several physical entities may bind to this logical role
    /// (multi-sub / array requirement).
    public var allowsMultipleBindings: Bool {
        maximumCount == nil || maximumCount! > 1
    }

    private enum CodingKeys: String, CodingKey {
        case roleID = "role_id"
        case channelRole = "channel_role"
        case displayName = "display_name"
        case isSubwoofer = "is_subwoofer"
        case minimumCount = "minimum_count"
        case maximumCount = "maximum_count"
    }
}

/// A versioned speaker-layout profile (#315): the vocabulary a
/// capture task or built-in preset binds roles to. Custom profiles are
/// first-class — the contract stores `profile_id`/`profile_version`
/// and the role list, never a hard-coded Dolby/CEDIA enum.
public struct SpeakerLayoutProfile:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.speaker-layout-profile"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public let profileID: String
    public let profileVersion: String
    public let displayName: String?
    public let roles: [SpeakerLayoutRoleDefinition]

    public init(
        profileID: String,
        profileVersion: String,
        displayName: String? = nil,
        roles: [SpeakerLayoutRoleDefinition]
    ) throws {
        let id = SchemaOwnedText.nfc(profileID)
        let version = SchemaOwnedText.nfc(profileVersion)
        guard !id.isEmpty, !version.isEmpty,
              !(SchemaOwnedText.nfc(displayName)?.isEmpty ?? false)
        else {
            throw SpeakerLayoutProfileError.emptyField
        }
        var seen = Set<String>()
        for role in roles {
            guard seen.insert(role.roleID).inserted else {
                throw SpeakerLayoutProfileError.duplicateRoleID
            }
        }
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.profileID = id
        self.profileVersion = version
        self.displayName = SchemaOwnedText.nfc(displayName)
        self.roles = roles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schemaName)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersionValue
        )
        guard schema == Self.schema,
              schemaVersion == Self.schemaVersion
        else {
            throw SpeakerLayoutProfileError.unsupportedSchema
        }
        try self.init(
            profileID: container.decode(
                String.self,
                forKey: .profileID
            ),
            profileVersion: container.decode(
                String.self,
                forKey: .profileVersion
            ),
            displayName: container.decodeIfPresent(
                String.self,
                forKey: .displayName
            ),
            roles: container.decode(
                [SpeakerLayoutRoleDefinition].self,
                forKey: .roles
            )
        )
    }

    public var reference: SpeakerLayoutProfileReference {
        // Value construction is non-throwing once validated fields
        // exist; the reference re-validates defensively.
        try! SpeakerLayoutProfileReference(
            profileID: profileID,
            profileVersion: profileVersion
        )
    }

    /// Semantic digest over `(profile_id, profile_version)` plus every
    /// role definition — the portable pin an authority-dependency
    /// manifest declares (#337). Field order inside a role is fixed;
    /// role order inside the list is preserved in the digest.
    public var contentSHA256: EvidenceSHA256 {
        let canonical = try? CanonicalJSON.encode(
            .object([
                "profile_id": .string(profileID),
                "profile_version": .string(profileVersion),
                "roles": .array(roles.map { role in
                    var object: [String: CanonicalJSONValue] = [
                        "channel_role": .string(
                            role.channelRole.rawValue
                        ),
                        "display_name": .string(role.displayName),
                        "is_subwoofer": .boolean(role.isSubwoofer),
                        "minimum_count": .integer(role.minimumCount),
                        "role_id": .string(role.roleID),
                    ]
                    if let maximum = role.maximumCount {
                        object["maximum_count"] = .integer(maximum)
                    }
                    return .object(object)
                }),
            ])
        )
        return EvidenceIntegrity.sha256(of: canonical ?? Data())
    }

    public func roleDefinition(
        roleID: String
    ) -> SpeakerLayoutRoleDefinition? {
        roles.first { $0.roleID == roleID }
    }

    /// Resolves an entity's optional role binding against this profile.
    public func resolve(
        binding: SpeakerRoleBinding?,
        entityID: AnnotationEntityID? = nil
    ) -> SpeakerRoleBindingResolution {
        guard let binding else {
            return .unbound(entityID: entityID)
        }
        guard binding.profileID == profileID,
              binding.profileVersion == profileVersion
        else {
            return .foreignProfile(
                entityID: entityID,
                profileID: binding.profileID,
                profileVersion: binding.profileVersion
            )
        }
        guard let definition = roleDefinition(
            roleID: binding.roleID
        ) else {
            return .unknownRoleID(entityID: entityID, roleID: binding.roleID)
        }
        return .resolved(
            entityID: entityID,
            definition: definition
        )
    }

    /// Cardinality evaluation (#259): every role whose declared
    /// `minimum_count`/`maximum_count` the actual bindings violate.
    /// `bindings` carries `role_id`s of entities resolved against this
    /// exact profile — unbound/foreign entities never satisfy a count.
    public func evaluateCardinality(
        boundRoleIDs: [String]
    ) -> [SpeakerLayoutProfileFinding] {
        var findings: [SpeakerLayoutProfileFinding] = []
        var counts: [String: Int] = [:]
        for roleID in boundRoleIDs {
            counts[roleID, default: 0] += 1
        }
        for role in roles {
            let observed = counts[role.roleID] ?? 0
            if observed < role.minimumCount {
                findings.append(
                    .missingRequiredRole(
                        roleID: role.roleID,
                        expected: role.minimumCount,
                        observed: observed
                    )
                )
            }
            if let maximum = role.maximumCount, observed > maximum {
                findings.append(
                    .overMaximum(
                        roleID: role.roleID,
                        maximum: maximum,
                        observed: observed
                    )
                )
            }
        }
        return findings
    }

    /// A batch capture plan driven by this profile's exact role order
    /// (#278). Role order is declaration order; the plan records the
    /// profile reference so the staged flow states its vocabulary.
    public func makePlan(name: String? = nil) -> SpeakerLayoutPlan {
        SpeakerLayoutPlan(
            planName: name ?? displayName ?? profileID,
            roles: roles.map {
                SpeakerLayoutRole(
                    roleID: $0.roleID,
                    channelRole: $0.channelRole,
                    isSubwoofer: $0.isSubwoofer,
                    displayName: $0.displayName
                )
            },
            profileIdentity: reference
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case profileID = "profile_id"
        case profileVersion = "profile_version"
        case displayName = "display_name"
        case roles
    }
}

/// Resolution of one entity's `role_binding` against a profile (#315).
/// `unbound` is a first-class state — a physical speaker with no
/// logical assignment is representable, and a `channel_role` token
/// written before profiles existed decodes to `unbound` rather than
/// being invented.
public enum SpeakerRoleBindingResolution: Sendable, Equatable {
    /// No `role_binding` — legacy or deliberately unassigned.
    case unbound(entityID: AnnotationEntityID?)
    /// Bound to a role the named profile defines.
    case resolved(
        entityID: AnnotationEntityID?,
        definition: SpeakerLayoutRoleDefinition
    )
    /// The binding names a role ID the profile does not define.
    case unknownRoleID(
        entityID: AnnotationEntityID?,
        roleID: String
    )
    /// The binding names a different profile — resolvable only against
    /// that profile's exact ID/version.
    case foreignProfile(
        entityID: AnnotationEntityID?,
        profileID: String,
        profileVersion: String
    )
}

/// Cardinality finding from `SpeakerLayoutProfile.evaluateCardinality`
/// (#259): profile requirements are evaluated against bound role IDs,
/// never against arbitrary channel-token strings.
public enum SpeakerLayoutProfileFinding:
    Sendable,
    Equatable,
    Hashable
{
    case missingRequiredRole(roleID: String, expected: Int, observed: Int)
    case overMaximum(roleID: String, maximum: Int, observed: Int)
}

/// Built-in layout profiles (#315).
///
/// `generic` is the standalone-capture vocabulary: it declares the
/// canonical HTDT role IDs without layout cardinality, so ad-hoc and
/// legacy captures can bind a logical role without pretending a fixed
/// layout was surveyed. The numbered presets carry their own exact
/// role lists; selecting one is an explicit operator choice, and custom
/// profiles remain possible through the same contract.
public enum SpeakerLayoutProfiles {
    /// Generic HTDT role vocabulary — no required roles, unbounded
    /// multi-binding for the logical bass role.
    public static var generic: SpeakerLayoutProfile {
        // `try!` is safe: built-in definitions are constant and pass
        // validation by construction.
        try! SpeakerLayoutProfile(
            profileID: "htdt.generic-layout",
            profileVersion: "1.0.0",
            displayName: "Generic HTDT layout",
            roles: [
                speaker("L", .left, "Front left"),
                speaker("C", .center, "Center"),
                speaker("R", .right, "Front right"),
                speaker("SL", .surroundLeft, "Surround left"),
                speaker("SR", .surroundRight, "Surround right"),
                speaker("SBL", .surroundBackLeft, "Surround back left"),
                speaker("SBR", .surroundBackRight, "Surround back right"),
                speaker("TFL", .topFrontLeft, "Top front left"),
                speaker("TFR", .topFrontRight, "Top front right"),
                speaker("TML", .topMiddleLeft, "Top middle left"),
                speaker("TMR", .topMiddleRight, "Top middle right"),
                speaker("TRL", .topRearLeft, "Top rear left"),
                speaker("TRR", .topRearRight, "Top rear right"),
                bass(),
            ]
        )
    }

    /// 2.0 stereo layout.
    public static var stereo: SpeakerLayoutProfile {
        try! SpeakerLayoutProfile(
            profileID: "htdt.layout-stereo-2.0",
            profileVersion: "1.0.0",
            displayName: "2.0 stereo",
            roles: [
                required("L", .left, "Front left"),
                required("R", .right, "Front right"),
            ]
        )
    }

    /// 5.1 layout — the logical bass role may be served by several
    /// physical subwoofers (#244 composes, not renumbers).
    public static var surround5_1: SpeakerLayoutProfile {
        try! SpeakerLayoutProfile(
            profileID: "htdt.layout-5.1",
            profileVersion: "1.0.0",
            displayName: "5.1",
            roles: [
                required("L", .left, "Front left"),
                required("C", .center, "Center"),
                required("R", .right, "Front right"),
                required("SL", .surroundLeft, "Surround left"),
                required("SR", .surroundRight, "Surround right"),
                requiredBass(),
            ]
        )
    }

    /// 7.1 layout.
    public static var surround7_1: SpeakerLayoutProfile {
        try! SpeakerLayoutProfile(
            profileID: "htdt.layout-7.1",
            profileVersion: "1.0.0",
            displayName: "7.1",
            roles: [
                required("L", .left, "Front left"),
                required("C", .center, "Center"),
                required("R", .right, "Front right"),
                required("SL", .surroundLeft, "Surround left"),
                required("SR", .surroundRight, "Surround right"),
                required(
                    "SBL",
                    .surroundBackLeft,
                    "Surround back left"
                ),
                required(
                    "SBR",
                    .surroundBackRight,
                    "Surround back right"
                ),
                requiredBass(),
            ]
        )
    }

    /// 7.1.4 layout with four top roles.
    public static var surround7_1_4: SpeakerLayoutProfile {
        try! SpeakerLayoutProfile(
            profileID: "htdt.layout-7.1.4",
            profileVersion: "1.0.0",
            displayName: "7.1.4",
            roles: [
                required("L", .left, "Front left"),
                required("C", .center, "Center"),
                required("R", .right, "Front right"),
                required("SL", .surroundLeft, "Surround left"),
                required("SR", .surroundRight, "Surround right"),
                required(
                    "SBL",
                    .surroundBackLeft,
                    "Surround back left"
                ),
                required(
                    "SBR",
                    .surroundBackRight,
                    "Surround back right"
                ),
                requiredBass(),
                required("TFL", .topFrontLeft, "Top front left"),
                required("TFR", .topFrontRight, "Top front right"),
                required("TRL", .topRearLeft, "Top rear left"),
                required("TRR", .topRearRight, "Top rear right"),
            ]
        )
    }

    /// Every built-in profile, for the workspace's profile vocabulary
    /// offer and for resolving bindings on reopened entities.
    public static var all: [SpeakerLayoutProfile] {
        [generic, stereo, surround5_1, surround7_1, surround7_1_4]
    }

    /// Resolves `binding` against any built-in profile it names;
    /// nil when it names an external/custom profile.
    public static func resolveKnown(
        binding: SpeakerRoleBinding
    ) -> SpeakerLayoutProfile? {
        all.first {
            $0.profileID == binding.profileID
                && $0.profileVersion == binding.profileVersion
        }
    }

    private static func speaker(
        _ roleID: String,
        _ channelRole: ChannelRole,
        _ displayName: String
    ) -> SpeakerLayoutRoleDefinition {
        // Generic vocabulary: declared but unbounded.
        try! SpeakerLayoutRoleDefinition(
            roleID: roleID,
            channelRole: channelRole,
            displayName: displayName,
            minimumCount: 0,
            maximumCount: nil
        )
    }

    private static func required(
        _ roleID: String,
        _ channelRole: ChannelRole,
        _ displayName: String
    ) -> SpeakerLayoutRoleDefinition {
        try! SpeakerLayoutRoleDefinition(
            roleID: roleID,
            channelRole: channelRole,
            displayName: displayName,
            minimumCount: 1,
            maximumCount: 1
        )
    }

    private static func bass() -> SpeakerLayoutRoleDefinition {
        try! SpeakerLayoutRoleDefinition(
            roleID: "LFE",
            channelRole: .lfe,
            displayName: "Subwoofer",
            isSubwoofer: true,
            minimumCount: 0,
            maximumCount: nil
        )
    }

    private static func requiredBass() -> SpeakerLayoutRoleDefinition {
        try! SpeakerLayoutRoleDefinition(
            roleID: "LFE",
            channelRole: .lfe,
            displayName: "Subwoofer",
            isSubwoofer: true,
            minimumCount: 1,
            maximumCount: nil
        )
    }
}
