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
        identityKind: .userDefined,
        userLabel: "Speaker A"
    )
    let second = try HTDTEquipmentCatalogEntry(
        definitionID: "speaker",
        version: "1",
        semanticSHA256: hashB,
        identityKind: .userDefined,
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

// MARK: - Entry-level decoder validation (#201)
//
// Synthesized Decodable used to assign entry fields directly, so JSON
// the pinned HTDT producer could never emit (empty identity fields,
// unknown `identity_kind`, empty-when-present display strings) decoded
// successfully. The decoder now routes through the validating
// initializer and must reject each violation with a typed catalog
// error before the entry reaches the picker.

private func catalogEntryJSON(
    definitionID: String = "\"example-monitor\"",
    version: String = "\"2026-09\"",
    identityKind: String = "\"manufacturer\"",
    manufacturer: String = "null",
    model: String = "null",
    userLabel: String = "null"
) -> String {
    """
    {
      "definition_id":\(definitionID),
      "version":\(version),
      "semantic_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "identity_kind":\(identityKind),
      "manufacturer":\(manufacturer),
      "model":\(model),
      "user_label":\(userLabel)
    }
    """
}

private func decodeCatalogEntry(
    _ entryJSON: String
) throws -> HTDTEquipmentCatalogEntry {
    let data = Data(
        """
        {
          "schema":"htdt.equipment.catalog-snapshot",
          "schema_version":1,
          "authority_version":"o100c-equipment-definition-1",
          "definitions":[\(entryJSON)]
        }
        """.utf8
    )
    return try JSONDecoder()
        .decode(HTDTEquipmentCatalogSnapshot.self, from: data)
        .definitions[0]
}

@Test
func equipmentCatalogEntryDecodesUserDefinedKind() throws {
    let entry = try decodeCatalogEntry(
        catalogEntryJSON(
            identityKind: "\"user_defined\"",
            userLabel: "\"Rack DAC\""
        )
    )
    #expect(entry.identityKind == .userDefined)
    #expect(entry.displayName == "Rack DAC")
}

@Test
func equipmentCatalogEntryDecodeRejectsEmptyDefinitionID() {
    #expect(throws: HTDTEquipmentCatalogError.emptyIdentity) {
        try decodeCatalogEntry(
            catalogEntryJSON(definitionID: "\"\"")
        )
    }
}

@Test
func equipmentCatalogEntryDecodeRejectsEmptyVersion() {
    #expect(throws: HTDTEquipmentCatalogError.emptyIdentity) {
        try decodeCatalogEntry(
            catalogEntryJSON(version: "\"\"")
        )
    }
}

@Test
func equipmentCatalogEntryDecodeRejectsEmptyIdentityKind() {
    #expect(
        throws: HTDTEquipmentCatalogError.unsupportedIdentityKind
    ) {
        try decodeCatalogEntry(
            catalogEntryJSON(identityKind: "\"\"")
        )
    }
}

@Test
func equipmentCatalogEntryDecodeRejectsUnknownIdentityKind() {
    // Unknown kinds must fail loudly; silently mapping them onto a
    // supported kind would let unresolvable tuples reach the picker.
    #expect(
        throws: HTDTEquipmentCatalogError.unsupportedIdentityKind
    ) {
        try decodeCatalogEntry(
            catalogEntryJSON(identityKind: "\"future_or_typo\"")
        )
    }
}

@Test
func equipmentCatalogEntryDecodeRejectsEmptyDisplayMetadata() {
    // The backend model applies min_length=1 to each optional display
    // field, so a present-but-empty string is out of contract.
    #expect(
        throws: HTDTEquipmentCatalogError.emptyDisplayMetadata
    ) {
        try decodeCatalogEntry(
            catalogEntryJSON(manufacturer: "\"\"")
        )
    }
    #expect(
        throws: HTDTEquipmentCatalogError.emptyDisplayMetadata
    ) {
        try decodeCatalogEntry(
            catalogEntryJSON(model: "\"\"")
        )
    }
    #expect(
        throws: HTDTEquipmentCatalogError.emptyDisplayMetadata
    ) {
        try decodeCatalogEntry(
            catalogEntryJSON(userLabel: "\"\"")
        )
    }
}

@Test
func equipmentCatalogEntryInitRejectsEmptyIdentity() throws {
    let hash = try EvidenceSHA256(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    )
    #expect(throws: HTDTEquipmentCatalogError.emptyIdentity) {
        try HTDTEquipmentCatalogEntry(
            definitionID: "",
            version: "1",
            semanticSHA256: hash,
            identityKind: .manufacturer
        )
    }
    #expect(throws: HTDTEquipmentCatalogError.emptyIdentity) {
        try HTDTEquipmentCatalogEntry(
            definitionID: "speaker",
            version: "",
            semanticSHA256: hash,
            identityKind: .manufacturer
        )
    }
}

@Test
func equipmentCatalogEntryRoundTripsIdentityKind() throws {
    let entry = try HTDTEquipmentCatalogEntry(
        definitionID: "speaker",
        version: "1",
        semanticSHA256: try EvidenceSHA256(
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        ),
        identityKind: .userDefined,
        userLabel: "Speaker A"
    )
    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(
        HTDTEquipmentCatalogEntry.self,
        from: data
    )
    #expect(decoded == entry)
    #expect(decoded.identityKind == .userDefined)
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
