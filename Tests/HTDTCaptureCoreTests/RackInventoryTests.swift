import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Rack-inventory workflow authority (legacy bolph71656-ai/HTDT-Capture#402): placement observations
/// live apart from item identity, the collection enforces rack
/// membership consistency, and duplicate candidates warn without
/// merging.
final class RackInventoryTests: XCTestCase {
    private let space = CoordinateSpaceID()

    private func rack(label: String = "Rack A")
        throws -> CaptureAnnotationEntity
    {
        try CaptureAnnotationEntity(
            type: .equipmentRack,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: label,
            provenanceClass: .userAnnotation,
            placement: PlacementProvenance(method: .manualNumeric)
        )
    }

    private func item(
        label: String,
        rack: CaptureAnnotationEntity? = nil,
        equipmentRef: HTDTEquipmentReference? = nil,
        serialNumber: String? = nil
    ) throws -> SystemInventoryItem {
        try SystemInventoryItem(
            equipmentClass: .powerAmplifier,
            userLabel: label,
            equipmentRef: equipmentRef,
            serialNumber: serialNumber,
            hostRackEntityID: rack?.entityID
        )
    }

    private func reference(_ key: String)
        throws -> HTDTEquipmentReference
    {
        try HTDTEquipmentReference(
            equipmentID: key,
            equipmentVersion: "1",
            equipmentHash: try EvidenceSHA256(
                String(repeating: "ab", count: 32)
            ),
            authorityVersion:
                HTDTEquipmentCatalogSnapshot.expectedAuthorityVersion
        )
    }

    // MARK: - Placement invariants

    func testPlacementRequiresAnObservation() throws {
        let rack = try rack()
        let unit = try item(label: "amp", rack: rack)
        XCTAssertThrowsError(
            try RackPlacementObservation(
                itemID: unit.itemID,
                hostRackEntityID: rack.entityID
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .emptyPlacementObservation
            )
        }
    }

    func testPlacementRejectsZeroRackUnit() throws {
        let rack = try rack()
        let unit = try item(label: "amp", rack: rack)
        XCTAssertThrowsError(
            try RackPlacementObservation(
                itemID: unit.itemID,
                hostRackEntityID: rack.entityID,
                rackUnitPosition: 0
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .nonPositiveDimension
            )
        }
    }

    func testPlacementEvidenceNeedsSpace() throws {
        let rack = try rack()
        let unit = try item(label: "amp", rack: rack)
        XCTAssertThrowsError(
            try RackPlacementObservation(
                itemID: unit.itemID,
                hostRackEntityID: rack.entityID,
                evidenceRefs: ["path:evidence/frames/x.json"]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testPlacementMustMatchItemRack() throws {
        let rackA = try rack(label: "A")
        let rackB = try rack(label: "B")
        let unit = try item(label: "amp", rack: rackA)
        let placement = try RackPlacementObservation(
            itemID: unit.itemID,
            hostRackEntityID: rackB.entityID,
            rackUnitPosition: 3
        )
        XCTAssertThrowsError(
            try TheaterAuthorityCollection(
                inventoryItems: [unit],
                rackPlacements: [placement]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .rackPlacementRackMismatch
            )
        }
    }

    func testPlacementRequiresKnownItem() throws {
        let rack = try rack()
        let unit = try item(label: "amp", rack: rack)
        let orphan = try RackPlacementObservation(
            itemID: AuthorityRecordID(),
            hostRackEntityID: rack.entityID,
            rackUnitPosition: 1
        )
        XCTAssertThrowsError(
            try TheaterAuthorityCollection(
                inventoryItems: [unit],
                rackPlacements: [orphan]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedFeatureReference
            )
        }
    }

    func testPlacementIDsShareUniquenessBudget() throws {
        let rack = try rack()
        let unit = try item(label: "amp", rack: rack)
        let placement = try RackPlacementObservation(
            placementID: unit.itemID,
            itemID: unit.itemID,
            hostRackEntityID: rack.entityID,
            rackUnitPosition: 1
        )
        XCTAssertThrowsError(
            try TheaterAuthorityCollection(
                inventoryItems: [unit],
                rackPlacements: [placement]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .duplicateAuthorityRecordID
            )
        }
    }

    // MARK: - Collection helpers

    func testUpsertStagesItemAndPlacementAtomically() throws {
        let rack = try rack()
        let unit = try item(label: "amp", rack: rack)
        let placement = try RackPlacementObservation(
            itemID: unit.itemID,
            hostRackEntityID: rack.entityID,
            rackUnitPosition: 4,
            facing: .rear
        )
        var collection = TheaterAuthorityCollection.empty
        collection = try collection.upsertingInventoryItem(
            unit,
            placement: placement
        )
        XCTAssertEqual(collection.inventoryItems, [unit])
        XCTAssertEqual(collection.rackPlacements(for: unit.itemID).count, 1)
        XCTAssertEqual(
            collection.rackPlacements(for: unit.itemID).first?.facing,
            .rear
        )
    }

    func testRemovingItemCascadesPlacements() throws {
        let rack = try rack()
        let unit = try item(label: "amp", rack: rack)
        var collection = try TheaterAuthorityCollection(
            inventoryItems: [unit],
            rackPlacements: [
                try RackPlacementObservation(
                    itemID: unit.itemID,
                    hostRackEntityID: rack.entityID,
                    rackUnitPosition: 2
                )
            ]
        )
        collection = try collection.removingInventoryItem(unit.itemID)
        XCTAssertTrue(collection.inventoryItems.isEmpty)
        XCTAssertTrue(collection.rackPlacements.isEmpty)
    }

    func testRemovingPlacementKeepsItem() throws {
        let rack = try rack()
        let unit = try item(label: "amp", rack: rack)
        let placement = try RackPlacementObservation(
            itemID: unit.itemID,
            hostRackEntityID: rack.entityID,
            shelfSlotLabel: "top shelf"
        )
        var collection = try TheaterAuthorityCollection(
            inventoryItems: [unit],
            rackPlacements: [placement]
        )
        collection = try collection.removingRackPlacement(
            placement.placementID
        )
        XCTAssertEqual(collection.inventoryItems.count, 1)
        XCTAssertTrue(collection.rackPlacements.isEmpty)
    }

    // MARK: - Duplicate candidates

    func testDuplicateCandidatesMatchSerial() throws {
        let rack = try rack()
        let existing = try item(
            label: "amp 1",
            rack: rack,
            serialNumber: "SN-123"
        )
        let candidate = try item(
            label: "amp 2",
            rack: rack,
            serialNumber: "SN-123"
        )
        let collection = try TheaterAuthorityCollection(
            inventoryItems: [existing]
        )
        XCTAssertEqual(
            collection.inventoryDuplicateCandidates(for: candidate),
            [existing]
        )
    }

    func testDuplicateCandidatesMatchRefAndRack() throws {
        let rack = try rack()
        let ref = try reference("amp-def")
        let existing = try item(
            label: "amp 1",
            rack: rack,
            equipmentRef: ref
        )
        let sameRack = try item(
            label: "amp 2",
            rack: rack,
            equipmentRef: ref
        )
        let noRack = try item(
            label: "amp 3",
            equipmentRef: ref
        )
        let collection = try TheaterAuthorityCollection(
            inventoryItems: [existing]
        )
        XCTAssertEqual(
            collection.inventoryDuplicateCandidates(for: sameRack),
            [existing]
        )
        XCTAssertTrue(
            collection.inventoryDuplicateCandidates(for: noRack)
                .isEmpty
        )
    }

    func testDuplicateCandidatesNeverSelfMatch() throws {
        let unit = try item(label: "amp", serialNumber: "SN-1")
        let collection = try TheaterAuthorityCollection(
            inventoryItems: [unit]
        )
        XCTAssertTrue(
            collection.inventoryDuplicateCandidates(for: unit).isEmpty
        )
    }

    // MARK: - Wire round-trip

    func testCollectionRoundTripsPlacements() throws {
        let rack = try rack()
        let unit = try item(label: "amp", rack: rack)
        let placement = try RackPlacementObservation(
            itemID: unit.itemID,
            hostRackEntityID: rack.entityID,
            rackUnitPosition: 7,
            facing: .front,
            coordinateSpaceID: space,
            evidenceRefs: ["authority:label-scan-1"]
        )
        let collection = try TheaterAuthorityCollection(
            inventoryItems: [unit],
            rackPlacements: [placement]
        )
        let data = try JSONEncoder().encode(collection)
        let decoded = try JSONDecoder().decode(
            TheaterAuthorityCollection.self,
            from: data
        )
        XCTAssertEqual(decoded, collection)
        XCTAssertEqual(
            decoded.rackPlacements(for: unit.itemID).first,
            placement
        )
    }
}
