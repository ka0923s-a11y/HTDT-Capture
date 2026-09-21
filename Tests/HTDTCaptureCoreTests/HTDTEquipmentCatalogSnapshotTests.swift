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

// MARK: - Equipment catalog cache (#211)

private let catalogFixtureData = Data(
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

private func catalogCacheInTempRoot() throws
    -> (cache: HTDTEquipmentCatalogCache, cleanup: () -> Void)
{
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cache = HTDTEquipmentCatalogCache(
        fileURL: root.appendingPathComponent(
            "imported-equipment-catalog.json",
            isDirectory: false
        )
    )
    return (cache, {
        try? FileManager.default.removeItem(at: root)
    })
}

@Test
func equipmentCatalogCacheStoreThenLoadRoundtrips() throws {
    let (cache, cleanup) = try catalogCacheInTempRoot()
    defer {
        cleanup()
    }

    let stored = try cache.store(catalogFixtureData)
    #expect(stored.definitions.count == 1)

    let loaded = try #require(cache.load())
    #expect(loaded == stored)
}

@Test
func equipmentCatalogCacheLoadMissesCleanly() throws {
    let (cache, cleanup) = try catalogCacheInTempRoot()
    defer {
        cleanup()
    }

    #expect(cache.load() == nil)
}

@Test
func equipmentCatalogCacheRejectsInvalidCandidateWithoutReplacing()
    throws
{
    let (cache, cleanup) = try catalogCacheInTempRoot()
    defer {
        cleanup()
    }

    _ = try cache.store(catalogFixtureData)

    // A candidate that fails schema/authority validation throws and
    // must not replace or remove the previously stored snapshot.
    let unsupported = Data(
        """
        {
          "schema":"htdt.equipment.catalog-snapshot",
          "schema_version":1,
          "authority_version":"unsupported-authority",
          "definitions":[]
        }
        """.utf8
    )
    #expect(
        throws:
            HTDTEquipmentCatalogError.unsupportedAuthorityVersion
    ) {
        try cache.store(unsupported)
    }
    #expect(cache.load() != nil)
}

@Test
func equipmentCatalogCacheDropsStaleAuthorityVersion() throws {
    let (cache, cleanup) = try catalogCacheInTempRoot()
    defer {
        cleanup()
    }

    // Simulate a snapshot persisted by an older/newer authority
    // version: it must never be silently substituted, and the stale
    // file is removed so a re-import is explicit.
    let stale = Data(
        """
        {
          "schema":"htdt.equipment.catalog-snapshot",
          "schema_version":1,
          "authority_version":"unsupported-authority",
          "definitions":[]
        }
        """.utf8
    )
    try FileManager.default.createDirectory(
        at: cache.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try stale.write(to: cache.fileURL)

    #expect(cache.load() == nil)
    #expect(
        !FileManager.default.fileExists(
            atPath: cache.fileURL.path
        )
    )
}
