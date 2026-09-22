import Foundation

/// The `htdt.field_return.*` document family (issue #419): typed
/// authority documents emitted inside a Field Return container. Each
/// envelope carries the owner contribution as an explicit
/// `contribution_ref` (`{kind, id}` — the `HTDTMissionContribution`
/// wire shape), so an embedded document is self-describing: a reader
/// answers "which contribution produced this record?" without
/// interpreting a `capture_revision_id` slot against container
/// ancestry.
///
/// Records reuse the capture bundle's field-authority payloads
/// verbatim. The three record models that carry a record-level
/// `capture_revision_id` slot (`FieldEvidenceRecord`,
/// `InstalledSettingsObservation`, `AsBuiltWiringRoute`) have that
/// slot stripped on encode and re-injected with the carrier id on
/// decode — the document-level envelope is the single owner truth.
public enum FieldContributionDocs {
    /// Envelope doc family.
    public enum Family: String, Sendable, CaseIterable {
        case operatorProfiles = "htdt.field_return.operator-profiles"
        case instrumentProfiles =
            "htdt.field_return.instrument-profiles"
        case fieldEvidence = "htdt.field_return.field-evidence"
        case settingsObservations =
            "htdt.field_return.settings-observations"
        case wiringRoutes = "htdt.field_return.wiring-routes"
        case inventoryItems = "htdt.field_return.inventory-items"
        case roomStateObservations =
            "htdt.field_return.room-state-observations"

        /// Records-collection key inside the envelope JSON.
        public var recordsKey: String {
            switch self {
            case .operatorProfiles: return "operators"
            case .instrumentProfiles: return "instruments"
            case .fieldEvidence: return "records"
            case .settingsObservations,
                 .roomStateObservations:
                return "observations"
            case .wiringRoutes: return "routes"
            case .inventoryItems: return "inventory_items"
            }
        }

        /// Canonical file name inside `authority/`.
        public var fileName: String {
            switch self {
            case .operatorProfiles:
                return "operator-profiles.json"
            case .instrumentProfiles:
                return "instrument-profiles.json"
            case .fieldEvidence:
                return "field-evidence.json"
            case .settingsObservations:
                return "settings-observations.json"
            case .wiringRoutes:
                return "wiring-routes.json"
            case .inventoryItems:
                return "inventory-items.json"
            case .roomStateObservations:
                return "room-state-observations.json"
            }
        }

        /// Whether this family's records carry a record-level
        /// `capture_revision_id` slot that is stripped on the wire.
        public var stripsRecordCarrier: Bool {
            switch self {
            case .fieldEvidence,
                 .settingsObservations,
                 .wiringRoutes:
                return true
            case .operatorProfiles,
                 .instrumentProfiles,
                 .inventoryItems,
                 .roomStateObservations:
                return false
            }
        }

        /// The v1 `htdt.capture.*` schema this family supersedes
        /// inside Field Return containers (capture bundles still
        /// emit the v1 docs — they are untouched).
        public var legacySchema: String {
            switch self {
            case .operatorProfiles:
                return "htdt.capture.operator-profiles"
            case .instrumentProfiles:
                return "htdt.capture.instrument-profiles"
            case .fieldEvidence:
                return "htdt.capture.field-evidence"
            case .settingsObservations:
                return "htdt.capture.installed-settings"
            case .wiringRoutes:
                return "htdt.capture.as-built-wiring"
            case .inventoryItems:
                return "htdt.capture.inventory-items"
            case .roomStateObservations:
                return "htdt.capture.room-state-observations"
            }
        }
    }

    /// Encodes one envelope document: `{schema, schema_version,
    /// contribution_ref, recorded_at_utc, <recordsKey>: [...]}`. The
    /// records encode via the canonical field-authority profile; a
    /// stripped record-carrier slot is removed after encoding so the
    /// wire form keeps exactly one owner truth.
    public static func encode<Record: Encodable>(
        family: Family,
        contributionRef: HTDTMissionContribution,
        recordedAtUTC: String,
        records: [Record]
    ) throws -> Data {
        var recordObjects: [[String: Any]] = []
        recordObjects.reserveCapacity(records.count)
        for record in records {
            let data = try FieldAuthorityCoding.encoder()
                .encode(record)
            guard var object = try JSONSerialization
                .jsonObject(with: data) as? [String: Any]
            else {
                throw HTDTFieldReturnError
                    .incompatibleAuthoritySchema(
                        family.rawValue
                    )
            }
            object.removeValue(forKey: "capture_revision_id")
            recordObjects.append(object)
        }
        let contributionObject: [String: String] = [
            "kind": contributionRef.kind,
            "id": contributionRef.idText,
        ]
        let envelope: [String: Any] = [
            "schema": family.rawValue,
            "schema_version": "1.0.0",
            "contribution_ref": contributionObject,
            "recorded_at_utc": recordedAtUTC,
            family.recordsKey: recordObjects,
        ]
        return try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys]
        )
    }

    /// The parsed envelope of one embedded authority document —
    /// schema, contribution binding, and raw record payloads (with
    /// the record-carrier slot re-injected for families that strip
    /// it, so typed record models decode unchanged).
    /// `@unchecked Sendable`: `recordObjects` holds JSONSerialization
    /// values (String/NSNumber/Bool/arrays/dicts) which are value
    /// types that are Sendable in practice but typed as `Any`.
    public struct ParsedEnvelope: @unchecked Sendable {
        public let family: Family
        public let contributionRef: HTDTMissionContribution
        public let recordedAtUTC: String?
        /// Record JSON objects as they appear on the wire plus the
        /// re-injected `capture_revision_id` for carrier families.
        public let recordObjects: [[String: Any]]

        /// Decodes the envelope's records into typed models —
        /// the carrier slot is re-injected with the contribution's
        /// carrier id first, so `capture_revision_id`-bound models
        /// validate exactly as they did in memory.
        public func records<Record: Decodable>(
            _ type: Record.Type,
            carrier: CaptureRevisionID
        ) throws -> [Record] {
            var objects = recordObjects
            if family.stripsRecordCarrier {
                for index in objects.indices {
                    objects[index]["capture_revision_id"] =
                        carrier.rawValue
                            .uuidString.lowercased()
                }
            }
            let data = try JSONSerialization.data(
                withJSONObject: objects,
                options: [.sortedKeys]
            )
            return try JSONDecoder().decode(
                [Record].self, from: data
            )
        }
    }

    /// Parses and validates one embedded `htdt.field_return.*`
    /// envelope against the root document's contribution ref.
    /// Rejects: unknown schemas, mismatched or absent
    /// `contribution_ref`, records that still carry a second
    /// `capture_revision_id` owner (dual-owner records).
    public static func parse(
        data: Data,
        path: String,
        expectedContribution: HTDTMissionContribution
    ) throws -> ParsedEnvelope {
        guard let object = try JSONSerialization
            .jsonObject(with: data) as? [String: Any],
              let schema = object["schema"] as? String,
              let family = Family(rawValue: schema)
        else {
            throw HTDTFieldReturnError
                .unknownAuthoritySchema(path)
        }
        guard let refObject = object["contribution_ref"]
            as? [String: String],
              let kind = refObject["kind"],
              let idText = refObject["id"],
              let ref = Self.contribution(
                  kind: kind, idText: idText
              )
        else {
            throw HTDTFieldReturnError
                .conflictingContributionRef(path)
        }
        guard ref == expectedContribution else {
            throw HTDTFieldReturnError
                .conflictingContributionRef(path)
        }
        let records = object[family.recordsKey]
            as? [[String: Any]] ?? []
        for record in records
        where record["capture_revision_id"] != nil {
            throw HTDTFieldReturnError.dualOwnerRecord(path)
        }
        return ParsedEnvelope(
            family: family,
            contributionRef: ref,
            recordedAtUTC: object["recorded_at_utc"] as? String,
            recordObjects: records
        )
    }

    /// Builds a typed contribution ref from envelope JSON text.
    static func contribution(
        kind: String,
        idText: String
    ) -> HTDTMissionContribution? {
        switch kind {
        case "capture_revision":
            guard let uuid = UUID(
                canonicalUUIDv4Text: idText
            ) else { return nil }
            return .captureRevision(
                CaptureRevisionID(rawValue: uuid)
            )
        case "field_return":
            guard let uuid = UUID(
                canonicalUUIDv4Text: idText
            ) else { return nil }
            return .fieldReturn(
                HTDTFieldReturnID(rawValue: uuid)
            )
        default:
            return nil
        }
    }
}

extension HTDTMissionContribution {
    /// The UUID text of whichever typed id this contribution
    /// carries — used by envelope codecs.
    var idText: String {
        switch self {
        case .captureRevision(let id):
            return id.rawValue.uuidString.lowercased()
        case .fieldReturn(let id):
            return id.rawValue.uuidString.lowercased()
        }
    }
}
