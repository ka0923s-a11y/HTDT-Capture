import Foundation
import Testing
@testable import HTDTCaptureCore

private func routerTempFile(
    named name: String,
    contents: Data = Data([0x50, 0x4b, 0x03, 0x04])
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    let file = url.appendingPathComponent(
        name,
        isDirectory: false
    )
    try contents.write(to: file)
    return file
}

@Test
func routerClassifiesTypedContainersByExtension() throws {
    // The ZIP containers carry their own validated manifests — the
    // router never opens them to guess (#393).
    let bundle = try routerTempFile(named: "cap.htdtcapture")
    defer {
        try? FileManager.default.removeItem(
            at: bundle.deletingLastPathComponent()
        )
    }
    #expect(
        InboundDocumentRouter.classify(url: bundle).kind
            == .captureBundle
    )

    let library = try routerTempFile(
        named: "lib.htdtcapturelibrary"
    )
    defer {
        try? FileManager.default.removeItem(
            at: library.deletingLastPathComponent()
        )
    }
    #expect(
        InboundDocumentRouter.classify(url: library).kind
            == .captureLibraryPackage
    )
}

@Test
func routerRoutesJSONByInspectedSchemaNotFilename() throws {
    // A `.json` file's declared schema routes it — the extension
    // never carries authority for inspectable documents (#393).
    let missionJSON = """
        {"schema": "htdt.capture-mission", "schema_version": "1.0.0"}
        """.data(using: .utf8)!
    let missionFile = try routerTempFile(
        named: "whatever.json",
        contents: missionJSON
    )
    defer {
        try? FileManager.default.removeItem(
            at: missionFile.deletingLastPathComponent()
        )
    }
    let mission = InboundDocumentRouter.classify(url: missionFile)
    #expect(mission.kind == .captureMission)
    #expect(mission.detectedSchemaID == "htdt.capture-mission")

    let taskPlanJSON = """
        {"schema": "htdt.capture-task-plan", "schema_version": "1.0.0"}
        """.data(using: .utf8)!
    let planFile = try routerTempFile(
        named: "plan.json",
        contents: taskPlanJSON
    )
    defer {
        try? FileManager.default.removeItem(
            at: planFile.deletingLastPathComponent()
        )
    }
    #expect(
        InboundDocumentRouter.classify(url: planFile).kind
            == .captureMission
    )

    let catalogJSON = """
        {"schema": "htdt.equipment.catalog-snapshot", "schemaVersion": 1}
        """.data(using: .utf8)!
    let catalogFile = try routerTempFile(
        named: "catalog.json",
        contents: catalogJSON
    )
    defer {
        try? FileManager.default.removeItem(
            at: catalogFile.deletingLastPathComponent()
        )
    }
    #expect(
        InboundDocumentRouter.classify(url: catalogFile).kind
            == .equipmentCatalog
    )

    // `.htdtmission` is the mission's dedicated extension.
    let dedicated = try routerTempFile(
        named: "op.htdtmission",
        contents: missionJSON
    )
    defer {
        try? FileManager.default.removeItem(
            at: dedicated.deletingLastPathComponent()
        )
    }
    #expect(
        InboundDocumentRouter.classify(url: dedicated).kind
            == .captureMission
    )
}

@Test
func routerRefusesUnidentifiedDocuments() throws {
    let json = """
        {"schema": "com.example.unknown", "value": 1}
        """.data(using: .utf8)!
    let unknown = try routerTempFile(
        named: "other.json",
        contents: json
    )
    defer {
        try? FileManager.default.removeItem(
            at: unknown.deletingLastPathComponent()
        )
    }
    let classified = InboundDocumentRouter.classify(url: unknown)
    #expect(classified.kind == .unsupported)
    #expect(classified.diagnostic != nil)

    let binary = try routerTempFile(
        named: "blob.bin",
        contents: Data([0x00, 0x01, 0x02])
    )
    defer {
        try? FileManager.default.removeItem(
            at: binary.deletingLastPathComponent()
        )
    }
    #expect(
        InboundDocumentRouter.classify(url: binary).kind
            == .unsupported
    )
}

@Test
func routerGatesAvailabilityByCaptureState() {
    // Bundles and library packages import only while idle; missions
    // and catalogs may be storable during an active capture (#393).
    #expect(
        InboundDocumentRouter.availability(
            kind: .captureBundle,
            captureState: .idle
        ) == .allowed
    )
    #expect(
        InboundDocumentRouter.availability(
            kind: .captureBundle,
            captureState: .scanning
        ) == .idleOnly
    )
    #expect(
        InboundDocumentRouter.availability(
            kind: .captureLibraryPackage,
            captureState: .reviewing
        ) == .idleOnly
    )
    #expect(
        InboundDocumentRouter.availability(
            kind: .captureMission,
            captureState: .scanning
        ) == .storableDuringActiveCapture
    )
    #expect(
        InboundDocumentRouter.availability(
            kind: .equipmentCatalog,
            captureState: .scanning
        ) == .storableDuringActiveCapture
    )
    #expect(
        InboundDocumentRouter.availability(
            kind: .unsupported,
            captureState: .idle
        ) == .unsupported
    )
}
