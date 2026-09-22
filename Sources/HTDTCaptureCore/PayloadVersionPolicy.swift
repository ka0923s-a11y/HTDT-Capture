import Foundation

/// How this build relates to a payload version it encounters (#332).
public enum CapturePayloadCompatibility:
    String,
    Codable,
    Sendable,
    Equatable
{
    /// The version this build emits.
    case native
    /// A listed version this build can still read but never emits.
    case supportedReadOnly = "supported_read_only"
    /// Declared newer than anything this build lists — not readable.
    case unsupportedNewer = "unsupported_newer"
    /// A listed-but-removed or never-listed older version.
    case unsupportedLegacy = "unsupported_legacy"
    /// Opaque external authority payload — no project schema applies.
    case external
}

/// One schema-owned payload family's version contract, decoded from
/// `schemas/capture-bundle-v1/support-matrix.json` — the same file the
/// reference validator dispatches on, so the two can never disagree.
public struct PayloadFamilyContract:
    Codable,
    Sendable,
    Equatable
{
    /// Wire `schema` const for versioned families.
    public let schemaID: String?
    /// Bundle paths the family owns.
    public let paths: [String]
    /// Registry document keys per payload version.
    public let documents: [String: String]
    /// The version this build emits ("unversioned" for unversioned
    /// families, nil for external payloads).
    public let emitted: String?
    /// Versions this build can read.
    public let read: [String]
    /// True when the payload carries no schema/schema_version envelope.
    public let unversioned: Bool
    /// True for opaque external authority payloads (RoomPlan).
    public let external: Bool
    public let description: String?

    private enum CodingKeys: String, CodingKey {
        case schemaID = "schema_id"
        case paths
        case documents
        case emitted
        case read
        case unversioned
        case external
        case description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaID = try container.decodeIfPresent(
            String.self,
            forKey: .schemaID
        )
        paths = try container.decodeIfPresent([String].self,
                                              forKey: .paths) ?? []
        documents = try container.decodeIfPresent(
            [String: String].self,
            forKey: .documents
        ) ?? [:]
        emitted = try container.decodeIfPresent(String.self,
                                                forKey: .emitted)
        read = try container.decodeIfPresent([String].self,
                                             forKey: .read) ?? []
        unversioned = try container.decodeIfPresent(
            Bool.self,
            forKey: .unversioned
        ) ?? false
        external = try container.decodeIfPresent(Bool.self,
                                                 forKey: .external)
            ?? false
        description = try container.decodeIfPresent(
            String.self,
            forKey: .description
        )
    }
}

/// The published payload-version contract (#332): every versioned
/// payload family maps one declared `schema_version` to exactly one
/// immutable schema document and one compatibility status. Additive
/// additions to a v1 family therefore can never silently keep the old
/// version's identity — a payload claiming an unlisted version gets an
/// explicit `unsupported_newer`/`unsupported_legacy` diagnostic.
public struct CapturePayloadSupportMatrix:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.capture.bundle-support-matrix"

    public let schema: String
    public let matrixVersion: String
    public let description: String?
    public let families: [String: PayloadFamilyContract]

    private enum CodingKeys: String, CodingKey {
        case schema
        case matrixVersion = "matrix_version"
        case description
        case families
    }

    /// Whether two `major.minor.patch` version strings order
    /// left-to-right — the matrix's semver comparison.
    public static func versionGreater(
        _ lhs: String,
        than rhs: String
    ) -> Bool {
        let a = lhs.split(separator: ".").compactMap {
            Int($0)
        }
        let b = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(a.count, b.count) {
            let av = index < a.count ? a[index] : 0
            let bv = index < b.count ? b[index] : 0
            if av != bv { return av > bv }
        }
        return false
    }

    /// The compatibility status of `version` under the named family.
    /// Unlisted versions never map to a readable contract: newer than
    /// the maximum readable version is `unsupported_newer`, otherwise
    /// `unsupported_legacy`.
    public func compatibility(
        family familyName: String,
        version: String?
    ) -> CapturePayloadCompatibility {
        guard let contract = families[familyName] else {
            return version == nil ? .external : .unsupportedNewer
        }
        if contract.external { return .external }
        if contract.unversioned { return .native }
        guard let version, !version.isEmpty else {
            return .unsupportedLegacy
        }
        if contract.documents[version] != nil {
            return version == contract.emitted
                ? .native
                : .supportedReadOnly
        }
        let newestReadable = contract.read.sorted(by: {
            Self.versionGreater($0, than: $1)
        }).last
        if let newestReadable,
           Self.versionGreater(version, than: newestReadable)
        {
            return .unsupportedNewer
        }
        return .unsupportedLegacy
    }

    /// True when `path` belongs to an opaque external authority family
    /// (e.g. RoomPlan captured-room payloads) — no project schema
    /// applies, but the path is a recognized, non-bypass payload slot.
    public func isExternalAuthorityPath(_ path: String) -> Bool {
        families.values.contains {
            $0.external && $0.paths.contains(path)
        }
    }

    /// The registry document key serving `version` of `family`, or
    /// nil when the version is not supported.
    public func schemaDocumentName(
        family familyName: String,
        version: String?
    ) -> String? {
        guard let contract = families[familyName] else { return nil }
        if contract.external { return nil }
        if contract.unversioned {
            return contract.documents["unversioned"]
        }
        guard let version else { return nil }
        return contract.documents[version]
    }
}
