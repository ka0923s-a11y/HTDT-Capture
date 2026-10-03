import CryptoKit
import Foundation

/// Physical-equipment identity bridge (legacy bolph71656-ai/HTDT-Capture#403) and rack-membership
/// canonicalization (legacy bolph71656-ai/HTDT-Capture#333).
///
/// `CaptureAnnotationEntity` remains the spatial/semantic placement
/// authority and `SystemInventoryItem` the field inventory / unit
/// identity authority. The `same_physical_equipment` relation asserts
/// that the two records describe the same physical installed unit —
/// identity equivalence is explicit or evidence-backed, never inferred
/// from label, model or proximity equality.
///
/// Rack membership composes with that bridge: `member_of_rack` from an
/// `inventory_item:` subject is the canonical form; the legacy
/// `SystemInventoryItem.hostRackEntityID` field remains decodable as
/// a denormalized convenience and commit-time validation proves the
/// two agree when both are present.

/// Deterministic relation ids for *derived* relation views: the same
/// logical membership always derives the same identifier, so two
/// derived relations compare equal. The version-4 bit pattern keeps
/// derived ids canonical if a caller ever serializes one.
private enum DerivedRelationID {
    /// Random namespace UUID minted for derived relation ids.
    private static let namespace = UUID(
        uuidString: "8E48D9F1-6B21-4A94-9E32-2E2F53B5A29D"
    )!

    /// RFC 4122 name-based derivation (UUIDv5 hash, v4 bit pattern).
    static func v5(name: String) -> SemanticRelationID {
        var data = Data()
        withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }
        data.append(contentsOf: name.utf8)
        var digest = [UInt8](Insecure.SHA1.hash(data: data).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x40   // version 4
        digest[8] = (digest[8] & 0x3F) | 0x80   // variant 10xx
        return SemanticRelationID(
            rawValue: UUID(uuid: (
                digest[0], digest[1], digest[2], digest[3],
                digest[4], digest[5], digest[6], digest[7],
                digest[8], digest[9], digest[10], digest[11],
                digest[12], digest[13], digest[14], digest[15]
            ))
        )
    }
}

extension CaptureSemanticRelation {
    /// Whether this relation asserts `same_physical_equipment` and
    /// touches `entityID` (legacy bolph71656-ai/HTDT-Capture#403).
    public func isIdentityBinding(
        touching entityID: AnnotationEntityID
    ) -> Bool {
        relationType == .samePhysicalEquipment
            && references(entityID: entityID)
    }

    /// Whether this relation asserts `same_physical_equipment` and
    /// touches `itemID` (legacy bolph71656-ai/HTDT-Capture#403).
    public func isIdentityBinding(
        touching itemID: AuthorityRecordID
    ) -> Bool {
        relationType == .samePhysicalEquipment
            && references(itemID: itemID)
    }
}

extension SystemInventoryItem {
    /// Canonical rack membership (legacy bolph71656-ai/HTDT-Capture#333/legacy bolph71656-ai/HTDT-Capture#403): the `member_of_rack`
    /// relation is authoritative; `hostRackEntityID` is the legacy
    /// denormalized convenience read only when no relation exists.
    /// Commit-time validation proves the two agree when both are
    /// present.
    public func rackMembershipEntity(
        relations: [CaptureSemanticRelation]
    ) -> AnnotationEntityID? {
        if let relation = relations.first(where: {
            $0.relationType == .memberOfRack
                && $0.subjectRef.inventoryItemID == itemID
        }) {
            return relation.objectRefs.first?.entityID
        }
        return hostRackEntityID
    }

    /// The canonical `member_of_rack` relation for this item: the
    /// committed relation when present, else a deterministic derived
    /// view of the legacy `hostRackEntityID` field so pre-relation
    /// bundles expose the same canonical identity without guessing
    /// equivalence (legacy bolph71656-ai/HTDT-Capture#333/legacy bolph71656-ai/HTDT-Capture#403).
    public func canonicalRackMembership(
        relations: [CaptureSemanticRelation]
    ) -> CaptureSemanticRelation? {
        if let committed = relations.first(where: {
            $0.relationType == .memberOfRack
                && $0.subjectRef.inventoryItemID == itemID
        }) {
            return committed
        }
        guard let hostRackEntityID else { return nil }
        return try? CaptureSemanticRelation(
            relationID: DerivedRelationID.v5(
                name:
                    "member_of_rack:\(itemID):\(hostRackEntityID)"
            ),
            relationType: .memberOfRack,
            subjectRef: SemanticRelationEndpoint(
                inventoryItemID: itemID
            ),
            objectRefs: [
                SemanticRelationEndpoint(entityID: hostRackEntityID)
            ],
            provenanceClass: .captureAppDerived,
            verificationState: .unverified
        )
    }
}

/// Advisory review signal over the physical-equipment identity graph
/// (legacy bolph71656-ai/HTDT-Capture#403 §18): findings surface probable candidates and conflicts —
/// they are review aids, never automatic merges.
public struct PhysicalEquipmentFinding:
    Sendable, Equatable, Hashable
{
    public enum Severity: String, Sendable {
        case info
        case warning
        case error
    }

    public enum Code: String, Sendable {
        /// A spatial equipment entity (projector/display) carries no
        /// `same_physical_equipment` binding where a physical-unit
        /// identity is expected downstream.
        case unboundSpatialEquipment = "unbound_spatial_equipment"
        /// An inventory item has a likely but unconfirmed spatial
        /// counterpart — a binding candidate requiring operator
        /// confirmation, never an automatic merge.
        case unboundInventoryUnit = "unbound_inventory_unit"
        /// A bound entity/item pair carries two different exact
        /// `equipment_ref` tuples — the same physical unit cannot
        /// resolve to two catalog definitions.
        case conflictingEquipmentDefinition =
            "conflicting_equipment_definition"
        /// Two distinct inventory items record the same serial.
        case duplicateSerialNumber = "duplicate_serial_number"
        /// A bound entity/item pair reports different rack
        /// memberships — semantic installation state must not
        /// conflict silently with scene placement (legacy bolph71656-ai/HTDT-Capture#403 §15).
        case conflictingRackMembership =
            "conflicting_rack_membership"
    }

    /// The annotation entity involved, when the finding has one.
    public let entityID: AnnotationEntityID?
    /// The inventory item involved, when the finding has one.
    public let itemID: AuthorityRecordID?
    public let code: Code
    public let severity: Severity
    public let detail: String

    public init(
        entityID: AnnotationEntityID? = nil,
        itemID: AuthorityRecordID? = nil,
        code: Code,
        severity: Severity,
        detail: String
    ) {
        self.entityID = entityID
        self.itemID = itemID
        self.code = code
        self.severity = severity
        self.detail = detail
    }
}

/// Cross-collection review over entities, inventory and the relation
/// graph (legacy bolph71656-ai/HTDT-Capture#403 §18/§19). Bounded and deterministic — warnings aid the
/// operator review; they never mutate or merge identity.
public enum PhysicalEquipmentReview {
    /// Inventory classes that normally also appear as spatial entities
    /// — used only to flag *candidate* bindings for operator review.
    private static let spatiallyExpectedClasses:
        Set<InventoryEquipmentClass> = [.projector, .display]

    /// Entity types matching `spatiallyExpectedClasses`.
    private static func matchesInventoryClass(
        _ klass: InventoryEquipmentClass,
        entityType: AnnotationEntityType
    ) -> Bool {
        switch (klass, entityType) {
        case (.projector, .projector), (.display, .display):
            return true
        default:
            return false
        }
    }

    public static func findings(
        entities: [CaptureAnnotationEntity],
        inventoryItems: [SystemInventoryItem],
        relations: [CaptureSemanticRelation]
    ) -> [PhysicalEquipmentFinding] {
        var findings: [PhysicalEquipmentFinding] = []
        let entitiesByID = Dictionary(
            entities.map { ($0.entityID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let itemsByID = Dictionary(
            inventoryItems.map { ($0.itemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Entity-side rack memberships first so bound-pair checks
        // below never depend on relation ordering.
        var boundRackByEntity: [AnnotationEntityID: AnnotationEntityID] =
            [:]
        for relation in relations
        where relation.relationType == .memberOfRack
        {
            if let subject = relation.subjectRef.entityID,
               let rack = relation.objectRefs.first?.entityID
            {
                boundRackByEntity[subject] = rack
            }
        }

        var boundEntityIDs = Set<AnnotationEntityID>()
        var boundItemIDs = Set<AuthorityRecordID>()
        for relation in relations {
            guard relation.relationType == .samePhysicalEquipment
            else { continue }
            let pair: (CaptureAnnotationEntity?, SystemInventoryItem?) = {
                if let entityID = relation.subjectRef.entityID,
                   let itemID = relation.objectRefs.first?
                       .inventoryItemID
                {
                    return (entitiesByID[entityID], itemsByID[itemID])
                }
                if let itemID = relation.subjectRef.inventoryItemID,
                   let entityID = relation.objectRefs.first?.entityID
                {
                    return (entitiesByID[entityID], itemsByID[itemID])
                }
                return (nil, nil)
            }()
            if let entity = pair.0 {
                boundEntityIDs.insert(entity.entityID)
            }
            if let item = pair.1 {
                boundItemIDs.insert(item.itemID)
            }
            guard let entity = pair.0, let item = pair.1 else {
                continue
            }
            if let entityRef = entity.equipmentRef,
               let itemRef = item.equipmentRef,
               entityRef != itemRef
            {
                findings.append(
                    PhysicalEquipmentFinding(
                        entityID: entity.entityID,
                        itemID: item.itemID,
                        code: .conflictingEquipmentDefinition,
                        severity: .warning,
                        detail:
                            "bound records resolve to different "
                            + "equipment_ref tuples "
                            + "(\(entityRef.equipmentID)@\(entityRef.equipmentVersion) vs "
                            + "\(itemRef.equipmentID)@\(itemRef.equipmentVersion))"
                    )
                )
            }
            let entityRack = boundRackByEntity[entity.entityID]
            let itemRack = item.rackMembershipEntity(
                relations: relations
            )
            if let entityRack, let itemRack, entityRack != itemRack {
                findings.append(
                    PhysicalEquipmentFinding(
                        entityID: entity.entityID,
                        itemID: item.itemID,
                        code: .conflictingRackMembership,
                        severity: .warning,
                        detail:
                            "bound records report different rack "
                            + "memberships"
                    )
                )
            }
        }

        var serialsSeen:
            [String: SystemInventoryItem] = [:]
        for item in inventoryItems {
            guard let serial = item.serialNumber else { continue }
            if let first = serialsSeen[serial],
               first.itemID != item.itemID
            {
                findings.append(
                    PhysicalEquipmentFinding(
                        itemID: item.itemID,
                        code: .duplicateSerialNumber,
                        severity: .warning,
                        detail:
                            "serial \(serial) also recorded on "
                            + "item \(first.itemID)"
                    )
                )
            } else {
                serialsSeen[serial] = item
            }
        }

        for entity in entities
        where spatiallyExpectedClasses.contains(where: {
            matchesInventoryClass($0, entityType: entity.type)
        }) && !boundEntityIDs.contains(entity.entityID)
        {
            findings.append(
                PhysicalEquipmentFinding(
                    entityID: entity.entityID,
                    code: .unboundSpatialEquipment,
                    severity: .info,
                    detail:
                        "\(entity.type.rawValue) entity has no "
                        + "same_physical_equipment binding"
                )
            )
        }
        for item in inventoryItems
        where spatiallyExpectedClasses.contains(item.equipmentClass)
            && !boundItemIDs.contains(item.itemID)
            && entities.contains(where: {
                matchesInventoryClass(
                    item.equipmentClass,
                    entityType: $0.type
                )
            })
        {
            findings.append(
                PhysicalEquipmentFinding(
                    itemID: item.itemID,
                    code: .unboundInventoryUnit,
                    severity: .info,
                    detail:
                        "inventory \(item.equipmentClass.rawValue) has "
                        + "a spatial counterpart but no confirmed "
                        + "same_physical_equipment binding"
                )
            )
        }
        return findings
    }
}
