import Foundation

public enum EquipmentIdentityEvidenceError: Error, Sendable, Equatable {
    case unboundRecord(String)
    case duplicateEntityID(AnnotationEntityID)
    case attestationRequired
}

/// One physical-device identity attestation bound to an annotation's
/// selected equipment reference (#239). Identity evidence is kept
/// separate from spatial placement evidence: it is reported through the
/// derived `derived/equipment-identity.json` document, keyed by the
/// exact entity it attests, and never merged into the entity's spatial
/// authority.
///
/// `serialOrAssetTag` is optional privacy-sensitive metadata: the app
/// records only what the operator explicitly types; nothing is scanned
/// or recognized automatically.
public struct EquipmentIdentityRecord: Codable, Sendable, Equatable {
    /// Annotation entity the attestation binds to. On a revision commit
    /// the host rewrites the document to the entities actually
    /// persisted, so a deleted entity can never keep a stale record.
    public let entityID: AnnotationEntityID
    /// The exact equipment tuple the user matched the physical unit to.
    public let equipment: HTDTEquipmentReference
    /// Canonical `path:` refs of close-up label/model evidence frames
    /// captured during the binding.
    public let identityEvidenceRefs: [String]
    /// Optional operator-entered serial/asset identifier.
    public let serialOrAssetTag: String?
    /// Provenance of the label-scan suggestion the operator confirmed
    /// (#345): algorithm/version + the persisted source frame. Nil on
    /// records whose fields were keyed in manually — the field's
    /// presence is what marks the suggestion-confirmed path versus
    /// the authority-attested one.
    public let labelScan: EquipmentLabelScanProvenance?
    /// Explicit operator attestation that the selected catalog
    /// definition matches the physical unit. Required: a record without
    /// attestation carries no identity authority and is rejected.
    public let attestedPhysicalMatch: Bool
    public let recordedAtUTC: String

    public init(
        entityID: AnnotationEntityID,
        equipment: HTDTEquipmentReference,
        identityEvidenceRefs: [String] = [],
        serialOrAssetTag: String? = nil,
        labelScan: EquipmentLabelScanProvenance? = nil,
        attestedPhysicalMatch: Bool,
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        guard attestedPhysicalMatch else {
            throw EquipmentIdentityEvidenceError.attestationRequired
        }
        let normalizedSerial = SchemaOwnedText
            .nfc(serialOrAssetTag)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.entityID = entityID
        self.equipment = equipment
        self.identityEvidenceRefs = SchemaOwnedText
            .nfc(identityEvidenceRefs)
            .sorted()
        self.serialOrAssetTag = normalizedSerial?.isEmpty == true
            ? nil
            : normalizedSerial
        self.labelScan = labelScan
        self.attestedPhysicalMatch = attestedPhysicalMatch
        self.recordedAtUTC = recordedAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case equipment
        case identityEvidenceRefs = "identity_evidence_refs"
        case serialOrAssetTag = "serial_or_asset_tag"
        case labelScan = "label_scan"
        case attestedPhysicalMatch = "attested_physical_match"
        case recordedAtUTC = "recorded_at_utc"
    }
}

/// Derived `derived/equipment-identity.json` payload document (#239):
/// the Review-inspectable record of which physical-device evidence and
/// attestations back each equipment reference selection.
public struct EquipmentIdentityDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.equipment-identity"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public let captureRevisionID: CaptureRevisionID
    public let coordinateSpaceID: CoordinateSpaceID?
    public let recordedAtUTC: String
    public let records: [EquipmentIdentityRecord]

    /// Validates that every record binds to an entity present in
    /// `entities` (the committed annotation collection) so a removal or
    /// stale draft can never leave an unattached attestation.
    public init(
        captureRevisionID: CaptureRevisionID,
        coordinateSpaceID: CoordinateSpaceID?,
        records: [EquipmentIdentityRecord],
        entities: [CaptureAnnotationEntity],
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        let knownIDs = Set(entities.map(\.entityID))
        var seenIDs = Set<AnnotationEntityID>()
        for record in records {
            guard seenIDs.insert(record.entityID).inserted else {
                throw EquipmentIdentityEvidenceError.duplicateEntityID(
                    record.entityID
                )
            }
            guard knownIDs.contains(record.entityID) else {
                throw EquipmentIdentityEvidenceError.unboundRecord(
                    record.entityID.rawValue.uuidString.lowercased()
                )
            }
            // An attestation must refer to the same equipment tuple the
            // entity itself carries; a mismatch would let a stale
            // binding survive an equipment re-selection.
            guard entities.first(where: {
                $0.entityID == record.entityID
            })?.equipmentRef == record.equipment else {
                throw EquipmentIdentityEvidenceError.unboundRecord(
                    record.entityID.rawValue.uuidString.lowercased()
                )
            }
        }
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.coordinateSpaceID = coordinateSpaceID
        self.recordedAtUTC = recordedAtUTC
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case coordinateSpaceID = "coordinate_space_id"
        case recordedAtUTC = "recorded_at_utc"
        case records
    }
}

/// Encoded `EquipmentIdentityDocument` ready for the working-set store.
/// The payload is a `derived`-role file so the manifest declaration
/// always carries non-empty `source_refs`: every identity evidence
/// frame plus the canonical annotation collection it binds to.
public struct EquipmentIdentityEvidencePackage: Sendable, Equatable {
    public static let path = "derived/equipment-identity.json"

    public let document: EquipmentIdentityDocument
    public let data: Data
    /// Manifest `source_refs`: sorted union of all identity frame refs
    /// plus the annotation collection path.
    public let sourceRefs: [String]

    public init(
        document: EquipmentIdentityDocument
    ) throws {
        var refs = Set<String>(
            document.records.flatMap(\.identityEvidenceRefs)
        )
        refs.insert("path:" + AnnotationEvidencePackage.path)
        self.document = document
        self.sourceRefs = refs.sorted()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        self.data = try encoder.encode(document)
    }
}
