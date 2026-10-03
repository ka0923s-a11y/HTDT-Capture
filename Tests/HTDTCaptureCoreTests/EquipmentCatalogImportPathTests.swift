import Foundation
import Testing
@testable import HTDTCaptureCore

/// legacy bolph71656-ai/HTDT-Capture#281: the sample catalog under `samples/equipment-catalog/` is the
/// in-repo document the import path is exercised with end-to-end —
/// inbound routing, state gating, snapshot validation, and the
/// library store/activate/list cycle all run against the same fixture
/// bytes a picker would hand to the app.
private func sampleCatalogURL() -> URL {
    let testFile = URL(fileURLWithPath: #filePath)
    return testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("samples")
        .appendingPathComponent("equipment-catalog")
        .appendingPathComponent(
            "equipment-catalog-snapshot.json",
            isDirectory: false
        )
}

private func catalogLibraryInTempRoot() throws
    -> (library: HTDTEquipmentCatalogLibrary, cleanup: () -> Void)
{
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let library = HTDTEquipmentCatalogLibrary(
        directory: root.appendingPathComponent(
            "equipment-catalogs",
            isDirectory: true
        )
    )
    return (library, {
        try? FileManager.default.removeItem(at: root)
    })
}

@Test
func sampleCatalogRoutesAsEquipmentCatalogBySchemaSniff() throws {
    let url = sampleCatalogURL()
    #expect(FileManager.default.fileExists(atPath: url.path))

    let classification = InboundDocumentRouter.classify(url: url)
    #expect(classification.kind == .equipmentCatalog)
    #expect(
        classification.detectedSchemaID
            == HTDTEquipmentCatalogSnapshot.expectedSchema
    )
}

@Test
func sampleCatalogIsStorableDuringActiveCaptureAndIdle() throws {
    // Missions and catalogs may always be stored — adoption when a
    // capture is active stays an explicit operator action (legacy bolph71656-ai/HTDT-Capture#393), so
    // no state yields plain `.allowed`.
    for state in CaptureState.allCases {
        let availability = InboundDocumentRouter.availability(
            kind: .equipmentCatalog,
            captureState: state
        )
        #expect(availability == .storableDuringActiveCapture)
    }
}

@Test
func sampleCatalogDecodesAndExposesSelectionContext() throws {
    let data = try Data(contentsOf: sampleCatalogURL())
    let snapshot = try JSONDecoder().decode(
        HTDTEquipmentCatalogSnapshot.self,
        from: data
    )

    #expect(snapshot.definitions.count == 3)
    #expect(
        snapshot.authorityVersion
            == HTDTEquipmentCatalogSnapshot.expectedAuthorityVersion
    )
    #expect(
        snapshot.compatibleAnnotationTypes
            == [.speaker, .subwoofer]
    )
    let identity = snapshot.identity
    #expect(identity.snapshotID == "cat-sample-2026-09")
    #expect(identity.label == "Sample home-theater catalog")
    #expect(identity.definitionCount == 3)

    let entry = try #require(
        snapshot.definitions.first {
            $0.definitionID == "example-bookshelf-speaker"
        }
    )
    let reference = try entry.equipmentReference(
        authorityVersion: snapshot.authorityVersion
    )
    #expect(entry.displayName == "Example Audio Bookshelf B-100")
    #expect(reference.equipmentID == "example-bookshelf-speaker")
    #expect(
        HTDTEquipmentCompatibility.check(
            reference: reference,
            entityType: .speaker
        ) == .compatible
    )
}

@Test
func sampleCatalogImportStoresActivatesAndLists() throws {
    let (library, cleanup) = try catalogLibraryInTempRoot()
    defer {
        cleanup()
    }
    let data = try Data(contentsOf: sampleCatalogURL())

    // The idle-state import path: store + activate in one step, the
    // active snapshot reads back through the same validating decoder.
    let stored = try library.storeAndActivate(data)
    #expect(library.list().count == 1)
    #expect(library.activeContentKey() == stored.contentKey)

    let active = try #require(library.active())
    #expect(active.snapshot == stored.snapshot)
    #expect(active.contentKey == stored.contentKey)

    // The stored file itself routes back through the inbound
    // classifier — bytes the library wrote are exactly the validated
    // document, so a second import of the same file dedupes onto the
    // same content key.
    let classification = InboundDocumentRouter.classify(
        url: stored.fileURL
    )
    #expect(classification.kind == .equipmentCatalog)
    let restored = try library.store(
        try Data(contentsOf: stored.fileURL)
    )
    #expect(restored.contentKey == stored.contentKey)
    #expect(library.list().count == 1)
}

@Test
func sampleCatalogDocumentIsStableAcrossReencode() throws {
    // `importEquipmentCatalog` re-encodes the validated snapshot and
    // stores those bytes — the fixture must round-trip without drift
    // so the stored document's semantic digest is reproducible.
    let data = try Data(contentsOf: sampleCatalogURL())
    let decoded = try JSONDecoder().decode(
        HTDTEquipmentCatalogSnapshot.self,
        from: data
    )
    let reencoded = try JSONEncoder().encode(decoded)
    let redecoded = try JSONDecoder().decode(
        HTDTEquipmentCatalogSnapshot.self,
        from: reencoded
    )
    #expect(redecoded == decoded)
    #expect(redecoded.contentSHA256 == decoded.contentSHA256)
}
