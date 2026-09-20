import Foundation
import Testing
@testable import HTDTCaptureCore

@Test
func equipmentCatalogSnapshotDecodesExactBackendReference()
    throws
{
    let data = Data(
        """
        {
          "schema":"htdt.equipment.catalog-snapshot",
          "schema_version":1,
          "authority_version":"o100c-equipment-definition-1",
          "definitions":[
            {
              "definition_id":"example-monitor",
              "version":"2026-09",
              "semantic_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "identity_kind":"manufacturer",
              "manufacturer":"Example Audio",
              "model":"Monitor X",
              "user_label":null
            }
          ]
        }
        """.utf8
    )

    let snapshot = try JSONDecoder().decode(
        HTDTEquipmentCatalogSnapshot.self,
        from: data
    )
    let entry = try #require(snapshot.definitions.first)
    let reference = try entry.equipmentReference()

    #expect(entry.displayName == "Example Audio Monitor X")
    #expect(reference.equipmentID == "example-monitor")
    #expect(reference.equipmentVersion == "2026-09")
    #expect(
        reference.equipmentHash.description
            == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    )
}

@Test
func equipmentCatalogRejectsDuplicateExactIdentity() throws {
    let hashA = try EvidenceSHA256(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    )
    let hashB = try EvidenceSHA256(
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    )
    let first = try HTDTEquipmentCatalogEntry(
        definitionID: "speaker",
        version: "1",
        semanticSHA256: hashA,
        identityKind: "user_defined",
        userLabel: "Speaker A"
    )
    let second = try HTDTEquipmentCatalogEntry(
        definitionID: "speaker",
        version: "1",
        semanticSHA256: hashB,
        identityKind: "user_defined",
        userLabel: "Speaker B"
    )

    #expect(
        throws:
            HTDTEquipmentCatalogError.duplicateDefinitionIdentity
    ) {
        try HTDTEquipmentCatalogSnapshot(
            definitions: [first, second]
        )
    }
}
