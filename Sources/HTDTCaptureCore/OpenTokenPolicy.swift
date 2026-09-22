import Foundation

/// Namespace policy for open vocabulary tokens (issue #344).
///
/// Several bundle fields are deliberately open token vocabularies —
/// `quantity_type`, `channel_role`, `reference_point_semantics`, and
/// semantic `relation_type` — so deployments can record quantities and
/// roles the capture stack does not yet know. Open vocabularies create
/// a collision hazard: a deployment-specific token authored today could
/// accidentally become a different *standard* token in a future
/// contract revision. The policy here makes the three classes machine-
/// distinguishable:
///
///   * **standard** — the token is registered in the vocabulary pinned
///     to the emitting contract version. Its meaning is fixed by that
///     vocabulary version forever.
///   * **custom-scoped** — the token carries the reserved extension
///     prefix (`x_` for lowercase vocabularies, `X_` for uppercase
///     channel roles). The standard registry will never assign tokens
///     in the extension prefix, so a scoped custom token can never
///     silently acquire a future standard meaning.
///   * **legacy custom unscoped** — an unscoped token that is not in
///     the standard vocabulary, seen on a pre-namespace-policy
///     (schema_version 1.0.0) payload. It is readable and classified,
///     but it can never be interpreted as a standard token — its
///     original meaning is only recoverable through the vocabulary
///     data that was in force when the payload was authored.
///
/// Payloads emitted at schema_version 1.1.0 or newer must carry only
/// standard or custom-scoped tokens in these fields; legacy payloads
/// remain readable and their unscoped tokens are classified
/// `legacy_custom_unscoped`.
public enum OpenTokenVocabulary: String, Sendable, Equatable, CaseIterable {
    /// `quantity_type` on measurement records.
    case measurementQuantity = "htdt.measurement.quantity"
    /// `channel_role` on loudspeaker entities.
    case channelRole = "htdt.annotation.channel_role"
    /// `reference_point_semantics` on annotated entities.
    case referencePointSemantics =
        "htdt.annotation.reference_point_semantics"
    /// `relation_type` on semantic relation records.
    case relationType = "htdt.capture.relation_type"

    /// Reserved prefix marking a custom-scoped token in this
    /// vocabulary. Standard registries never assign tokens carrying
    /// this prefix.
    public var customPrefix: String {
        switch self {
        case .channelRole:
            return "X_"
        case .measurementQuantity, .referencePointSemantics,
             .relationType:
            return "x_"
        }
    }

    /// The standard-token pattern (without the reserved prefix) for
    /// this vocabulary.
    public var tokenPattern: String {
        switch self {
        case .channelRole:
            return "^[A-Z0-9_]+$"
        case .measurementQuantity, .referencePointSemantics,
             .relationType:
            return "^[a-z0-9_]+$"
        }
    }

    /// Whether `token` is a standard token in the vocabulary pinned to
    /// this contract version. Only tokens the contract itself defines
    /// qualify — a token no contract version has defined can never
    /// become "standard" retroactively.
    ///
    /// `asOf` pins the check to a payload's declared `schema_version`
    /// (#332): tokens added by a later contract version are not
    /// standard vocabulary for older payloads. nil means this build's
    /// latest known vocabulary.
    public func isStandard(
        _ token: String,
        asOf schemaVersion: String? = nil
    ) -> Bool {
        switch self {
        case .measurementQuantity:
            return MeasurementQuantityRegistry.definition(
                for: token
            ) != nil
        case .channelRole:
            return ChannelRole.standardSet.contains(token)
        case .referencePointSemantics:
            return ReferencePointSemantics.standardSet.contains(token)
        case .relationType:
            return SemanticRelationType
                .standardSet(asOf: schemaVersion)
                .contains(token)
        }
    }
}

/// How an open-vocabulary token is classified under the #344
/// namespace policy.
public enum TokenNamespaceClass: String, Sendable, Equatable, Codable {
    /// Standard token — meaning pinned by the contract's vocabulary
    /// version.
    case standard
    /// Custom token carrying the reserved extension prefix — immune
    /// to future standard-token collisions.
    case customScoped = "custom_scoped"
    /// Unscoped, non-standard token on a legacy payload — readable,
    /// never interpretable as a future standard token.
    case legacyCustomUnscoped = "legacy_custom_unscoped"
}

public enum OpenTokenPolicy {
    /// Classify an open-vocabulary token under the namespace policy.
    public static func classify(
        _ token: String,
        vocabulary: OpenTokenVocabulary
    ) -> TokenNamespaceClass {
        if vocabulary.isStandard(token) {
            return .standard
        }
        if token.hasPrefix(vocabulary.customPrefix) {
            return .customScoped
        }
        return .legacyCustomUnscoped
    }

    /// Whether a token is wire-legal in a payload claiming
    /// schema_version 1.1.0 or newer: standard (as pinned to
    /// `schemaVersion`, or this build's latest when nil) or
    /// custom-scoped.
    public static func isWireLegal(
        _ token: String,
        vocabulary: OpenTokenVocabulary,
        asOf schemaVersion: String? = nil
    ) -> Bool {
        if vocabulary.isStandard(token, asOf: schemaVersion) {
            return true
        }
        return token.hasPrefix(vocabulary.customPrefix)
    }

    /// Normalize an authored token for new payloads: standard and
    /// already-scoped tokens pass through verbatim; any other token
    /// gains the reserved extension prefix so it can never collide
    /// with future standard vocabulary (#344). Returns nil when the
    /// token is empty or cannot be normalized into the vocabulary's
    /// character set.
    public static func scopedForAuthoring(
        _ token: String,
        vocabulary: OpenTokenVocabulary
    ) -> String? {
        let trimmed = token.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return nil }
        if vocabulary.isStandard(trimmed)
            || trimmed.hasPrefix(vocabulary.customPrefix)
        {
            return trimmed
        }
        let prefix = vocabulary.customPrefix
        let scoped = prefix + trimmed
        guard scoped.range(
            of: vocabulary.tokenPattern,
            options: .regularExpression
        ) != nil
        else {
            return nil
        }
        return scoped
    }
}
