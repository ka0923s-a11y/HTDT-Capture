import Foundation
import Testing
@testable import HTDTCaptureCore

// MARK: - Fixtures

private struct MeshBundleFixture {
    let bundleDirectory: URL
    let captureRoot: URL
    let manifest: BundleManifest
    let geometryData: Data
    let geometryPath: String
}

private func makeManifest(entries: [BundleFileEntry]) throws -> BundleManifest {
    try BundleManifest(
        captureSeriesID: CaptureSeriesID(),
        captureRevisionID: CaptureRevisionID(),
        parentRevisionID: nil,
        captureSessionIDs: [
            CaptureSessionID(
                canonicalString: BundleValidationFixture.sessionUUID
            )!
        ],
        coordinateSpaceIDs: [
            CoordinateSpaceID(
                canonicalString: BundleValidationFixture.spaceUUID
            )!
        ],
        createdAtUTC: "2026-09-21T00:00:00Z",
        finalizedAtUTC: "2026-09-21T00:01:00Z",
        app: BundleAppIdentity(version: "0.1.0", build: "test"),
        files: entries
    )
}

private func makeMeshBundle(
    tamperGeometry: Bool = false,
    omitGeometryDeclaration: Bool = false,
    omitIndexDeclaration: Bool = false
) throws -> MeshBundleFixture {
    let root = try BundleValidationFixture.makeDirectory()
    let bundle = root.appendingPathComponent(
        "bundle", isDirectory: true
    )

    let anchorUUID = UUID(
        uuidString: BundleValidationFixture.anchorUUID
    )!
    let geometry = try MeshGeometryPayload(
        vertices: [
            Float3(0, 0, 0),
            Float3(1, 0, 0),
            Float3(0, 1, 0),
        ],
        normals: [
            Float3(0, 0, 1),
            Float3(0, 0, 1),
            Float3(0, 0, 1),
        ],
        triangleIndices: [0, 1, 2],
        faceClassifications: [3]
    )
    let geometryData = try MeshBinaryCodec.encode(geometry)
    let geometryPath =
        "mesh/geometry/\(anchorUUID.uuidString.lowercased()).meshbin"
    let record = try MeshAnchorEvidenceRecord(
        anchorID: anchorUUID,
        captureSessionID: CaptureSessionID(
            canonicalString: BundleValidationFixture.sessionUUID
        )!,
        coordinateSpaceID: CoordinateSpaceID(
            canonicalString: BundleValidationFixture.spaceUUID
        )!,
        worldFromAnchor: Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            2, 0, 1, 1,
        ]),
        sessionTimestampSeconds: 1.5,
        vertexCount: 3,
        faceCount: 1,
        geometryPath: geometryPath,
        geometrySHA256: EvidenceIntegrity.sha256(of: geometryData)
    )
    let index = MeshAnchorEvidenceIndex(anchors: [record])
    let indexEncoder = JSONEncoder()
    indexEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let indexData = try indexEncoder.encode(index)

    let onDiskGeometry = tamperGeometry
        ? Data("corrupted".utf8)
        : geometryData
    try BundleValidationFixture.write(
        onDiskGeometry, to: geometryPath, in: bundle
    )
    try BundleValidationFixture.write(
        indexData, to: MeshEvidencePackage.indexPath, in: bundle
    )

    var entries: [BundleFileEntry] = []
    if !omitGeometryDeclaration {
        entries.append(
            try BundleValidationFixture.entry(
                path: geometryPath,
                data: geometryData,
                mediaType: "application/vnd.htdt.meshbin"
            )
        )
    }
    if !omitIndexDeclaration {
        entries.append(
            try BundleValidationFixture.entry(
                path: MeshEvidencePackage.indexPath,
                data: indexData,
                mediaType: "application/json"
            )
        )
    }
    let manifest = try makeManifest(entries: entries)
    let manifestData = try JSONEncoder().encode(manifest)
    try BundleValidationFixture.write(
        manifestData, to: "manifest.json", in: bundle
    )
    return MeshBundleFixture(
        bundleDirectory: bundle,
        captureRoot: root,
        manifest: manifest,
        geometryData: geometryData,
        geometryPath: geometryPath
    )
}

// MARK: - Writers

@Test
func objWriterEmitsVerticesNormalsGroupsAndFaces() throws {
    let mesh = try MeshGeometryPayload(
        vertices: [
            Float3(0, 0, 0),
            Float3(1, 0, 0),
            Float3(0, 1, 0),
            Float3(9, 9, 9),
        ],
        normals: [
            Float3(0, 0, 1),
            Float3(0, 0, 1),
            Float3(0, 0, 1),
            Float3(0, 1, 0),
        ],
        triangleIndices: [0, 1, 2, 0, 1, 3]
    )
    let document = DerivedMeshDocument(
        mesh: mesh,
        objectName: "test-object",
        faceGroups: [
            DerivedMeshFaceGroup(name: "first", faceRange: 0..<1),
            DerivedMeshFaceGroup(name: "second", faceRange: 1..<2),
        ],
        provenance: DerivedExportProvenance(
            captureSeriesID: CaptureSeriesID(),
            captureRevisionID: CaptureRevisionID(),
            bundleDigest: EvidenceIntegrity.sha256(of: Data("x".utf8)),
            sourceCoordinateSpaceIDs: [],
            format: .obj,
            sourceKind: .arMeshAnchors,
            representation: .arMeshWorldGeometry,
            sourcePayloads: [],
            conversionTransform: "test",
            coordinateConvention: "test",
            unitConversion: "meters",
            producerApp: nil,
            generatedAtUTC: "2026-09-21T00:00:00Z"
        )
    )

    let text = String(
        decoding: try DerivedOBJWriter.write(document),
        as: UTF8.self
    )
    #expect(text.contains("# HTDTCapture derived export"))
    #expect(text.contains("o test-object"))
    #expect(text.contains("v 0 0 0"))
    #expect(text.contains("vn 0 0 1"))
    #expect(text.contains("g first"))
    #expect(text.contains("g second"))
    // OBJ faces are 1-indexed and reference position//normal pairs.
    #expect(text.contains("f 1//1 2//2 3//3"))
}

@Test
func plyWriterEmitsAsciiHeaderAndVertexRows() throws {
    let mesh = try MeshGeometryPayload(
        vertices: [
            Float3(0, 0, 0),
            Float3(1.5, 0, 0),
            Float3(0, 1, 0),
        ],
        normals: nil,
        triangleIndices: [0, 1, 2]
    )
    let document = DerivedMeshDocument(
        mesh: mesh,
        objectName: "plain",
        faceGroups: [],
        provenance: DerivedExportProvenance(
            captureSeriesID: CaptureSeriesID(),
            captureRevisionID: CaptureRevisionID(),
            bundleDigest: EvidenceIntegrity.sha256(of: Data("x".utf8)),
            sourceCoordinateSpaceIDs: [],
            format: .ply,
            sourceKind: .arMeshAnchors,
            representation: .arMeshWorldGeometry,
            sourcePayloads: [],
            conversionTransform: "test",
            coordinateConvention: "test",
            unitConversion: "meters",
            producerApp: nil,
            generatedAtUTC: "2026-09-21T00:00:00Z"
        )
    )

    let text = String(
        decoding: try DerivedPLYWriter.write(document),
        as: UTF8.self
    )
    #expect(text.hasPrefix("ply"))
    #expect(text.contains("format ascii 1.0"))
    #expect(text.contains("element vertex 3"))
    #expect(text.contains("element face 1"))
    #expect(text.contains("comment HTDTCapture derived export"))
    #expect(!text.contains("property float nx"))
    #expect(text.contains("1.5 0 0"))
    #expect(text.contains("3 0 1 2"))
}

@Test
func glbWriterEmitsValidGlTFContainer() throws {
    let mesh = try MeshGeometryPayload(
        vertices: [
            Float3(0, 0, 0),
            Float3(1, 0, 0),
            Float3(0, 1, 0),
        ],
        normals: [
            Float3(0, 0, 1),
            Float3(0, 0, 1),
            Float3(0, 0, 1),
        ],
        triangleIndices: [0, 1, 2]
    )
    let document = DerivedMeshDocument(
        mesh: mesh,
        objectName: "glb",
        faceGroups: [
            DerivedMeshFaceGroup(name: "only", faceRange: 0..<1)
        ],
        provenance: DerivedExportProvenance(
            captureSeriesID: CaptureSeriesID(),
            captureRevisionID: CaptureRevisionID(),
            bundleDigest: EvidenceIntegrity.sha256(of: Data("x".utf8)),
            sourceCoordinateSpaceIDs: [],
            format: .glb,
            sourceKind: .arMeshAnchors,
            representation: .arMeshWorldGeometry,
            sourcePayloads: [],
            conversionTransform: "test",
            coordinateConvention: "test",
            unitConversion: "meters",
            producerApp: nil,
            generatedAtUTC: "2026-09-21T00:00:00Z"
        )
    )

    let data = try DerivedGLBWriter.write(document)
    #expect(data.count > 20)
    #expect(data[0..<4] == Data([0x67, 0x6C, 0x54, 0x46])) // "glTF"
    let version = data[4..<8].withUnsafeBytes {
        $0.load(as: UInt32.self)
    }
    let total = data[8..<12].withUnsafeBytes {
        $0.load(as: UInt32.self)
    }
    #expect(version == 2)
    #expect(Int(total) == data.count)

    let jsonLength = Int(
        data[12..<16].withUnsafeBytes { $0.load(as: UInt32.self) }
    )
    #expect(data[16..<20] == Data([0x4A, 0x53, 0x4F, 0x4E])) // "JSON"
    let jsonData = data[20..<(20 + jsonLength)]
    let json = try JSONSerialization.jsonObject(
        with: jsonData
    ) as! [String: Any]
    let asset = json["asset"] as! [String: Any]
    #expect(asset["version"] as? String == "2.0")
    let extras = asset["extras"] as! [String: Any]
    let marker = extras["htdt_derived_export"]
        as? [String: Any]
    #expect(marker?["derivedArtifact"] as? Bool == true)
    #expect((json["nodes"] as? [Any])?.count == 1)
    #expect((json["meshes"] as? [Any])?.count == 1)
}

// MARK: - RoomPlan box builder

@Test
func roomPlanBoxBuilderEmitsNamedGroupPerObject() throws {
    let object = RoomPlanBindableObject(
        identifier: "obj-1",
        category: "speaker",
        isSurface: false,
        worldFromObject: Matrix4x4F.identity,
        dimensionsMeters: Float3(0.4, 0.6, 0.3)
    )
    let result = try RoomPlanBoxMeshBuilder.build(objects: [object])
    #expect(result.mesh.vertices.count == 24)
    #expect(result.mesh.triangleIndices.count == 36)
    #expect(result.groups.count == 1)
    #expect(result.groups[0].name == "obj-1 (speaker)")
    #expect(result.groups[0].faceRange == 0..<12)
}

@Test
func roomPlanBoxBuilderRejectsDegenerateInput() throws {
    #expect(throws: DerivedExportError.self) {
        try RoomPlanBoxMeshBuilder.build(objects: [])
    }
    let flat = RoomPlanBindableObject(
        identifier: "flat",
        category: "wall",
        isSurface: true,
        worldFromObject: Matrix4x4F.identity,
        dimensionsMeters: Float3(1, 0, 1)
    )
    #expect(throws: DerivedExportError.self) {
        try RoomPlanBoxMeshBuilder.build(objects: [flat])
    }
}

// MARK: - AR mesh merge + runner

@Test
func arMeshMergeAppliesWorldTransform() throws {
    let fixture = try makeMeshBundle()
    defer { BundleValidationFixture.remove(fixture.captureRoot) }

    let merged = try DerivedARMeshMerge.merge(
        bundleDirectory: fixture.bundleDirectory,
        manifest: fixture.manifest
    )
    #expect(merged.anchorCount == 1)
    #expect(merged.mesh.vertices.count == 3)
    // Identity rotation + translation (2, 0, 1).
    #expect(merged.mesh.vertices[1] == Float3(3, 0, 1))
    #expect(merged.payloads.count == 2)
    #expect(
        merged.coordinateSpaceIDs
            == fixture.manifest.coordinateSpaceIDs
    )
}

@Test
func arMeshMergeRejectsTamperedOrUndeclaredGeometry() throws {
    let tampered = try makeMeshBundle(tamperGeometry: true)
    defer { BundleValidationFixture.remove(tampered.captureRoot) }
    #expect(throws: DerivedExportError.self) {
        try DerivedARMeshMerge.merge(
            bundleDirectory: tampered.bundleDirectory,
            manifest: tampered.manifest
        )
    }

    let undeclared = try makeMeshBundle(omitGeometryDeclaration: true)
    defer { BundleValidationFixture.remove(undeclared.captureRoot) }
    #expect(throws: DerivedExportError.self) {
        try DerivedARMeshMerge.merge(
            bundleDirectory: undeclared.bundleDirectory,
            manifest: undeclared.manifest
        )
    }

    let noIndex = try makeMeshBundle(omitIndexDeclaration: true)
    defer { BundleValidationFixture.remove(noIndex.captureRoot) }
    #expect(throws: DerivedExportError.self) {
        try DerivedARMeshMerge.merge(
            bundleDirectory: noIndex.bundleDirectory,
            manifest: noIndex.manifest
        )
    }
}

@Test
func exportMeshWritesUnderDerivedExportsRoot() throws {
    let fixture = try makeMeshBundle()
    defer { BundleValidationFixture.remove(fixture.captureRoot) }
    let digest = EvidenceIntegrity.sha256(of: Data("bundle".utf8))

    let result = try DerivedExportRunner.exportMesh(
        bundleDirectory: fixture.bundleDirectory,
        bundleDigest: digest,
        captureRoot: fixture.captureRoot,
        format: .glb,
        source: .arMeshAnchors,
        generatedAtUTC: "2026-09-21T00:00:00Z"
    )

    let expectedDirectory = fixture.captureRoot
        .appendingPathComponent(
            "derived-exports/"
                + fixture.manifest.captureRevisionID.description,
            isDirectory: true
        )
    #expect(
        result.primaryFileURL.deletingLastPathComponent().path
            == expectedDirectory.path
    )
    #expect(FileManager.default.fileExists(
        atPath: result.primaryFileURL.path
    ))
    #expect(FileManager.default.fileExists(
        atPath: result.provenanceFileURL.path
    ))

    let provenance = try JSONDecoder().decode(
        DerivedExportProvenance.self,
        from: Data(contentsOf: result.provenanceFileURL)
    )
    #expect(provenance.format == .glb)
    #expect(provenance.sourceKind == .arMeshAnchors)
    #expect(provenance.bundleDigest == digest)
    #expect(
        provenance.captureRevisionID
            == fixture.manifest.captureRevisionID
    )
    #expect(provenance.derivedArtifact)
}

@Test
func exportMeshRejectsUSDZAndWrongSourceFormats() throws {
    let fixture = try makeMeshBundle()
    defer { BundleValidationFixture.remove(fixture.captureRoot) }
    let digest = EvidenceIntegrity.sha256(of: Data("bundle".utf8))

    #expect(throws: DerivedExportError.self) {
        try DerivedExportRunner.exportMesh(
            bundleDirectory: fixture.bundleDirectory,
            bundleDigest: digest,
            captureRoot: fixture.captureRoot,
            format: .usdz,
            source: .arMeshAnchors
        )
    }
}

@Test
func exportUSDZDelegatesToWriterAndWritesProvenance() throws {
    let fixture = try makeMeshBundle()
    defer { BundleValidationFixture.remove(fixture.captureRoot) }
    let digest = EvidenceIntegrity.sha256(of: Data("bundle".utf8))

    var writerSawDestination = false
    let result = try DerivedExportRunner.exportUSDZ(
        bundleDirectory: fixture.bundleDirectory,
        bundleDigest: digest,
        captureRoot: fixture.captureRoot,
        generatedAtUTC: "2026-09-21T00:00:00Z"
    ) { destination in
        writerSawDestination = true
        try Data("fake-usdz".utf8).write(to: destination)
    }

    #expect(writerSawDestination)
    #expect(FileManager.default.fileExists(
        atPath: result.primaryFileURL.path
    ))
    #expect(result.primaryFileURL.pathExtension == "usdz")
    let provenance = try JSONDecoder().decode(
        DerivedExportProvenance.self,
        from: Data(contentsOf: result.provenanceFileURL)
    )
    #expect(provenance.format == .usdz)
    #expect(provenance.sourceKind == .roomPlanProcessed)
    #expect(
        provenance.representation == .roomPlanNativeParametric
    )
}

// MARK: - Survey plan compositor + renderer

private func makeOpening(
    source: RoomOpeningSource,
    disposition: RoomOpeningDisposition,
    sourceRef: String,
    center: WorldPoint3D = WorldPoint3D(x: 1, y: 0, z: 2)
) throws -> RoomOpeningCandidate {
    try RoomOpeningCandidate(
        kind: .door,
        source: source,
        sourceRef: sourceRef,
        centerMeters: center,
        disposition: disposition
    )
}

@Test
func compositorAddsEntitiesOpeningsAndRoomFrame() throws {
    let revisionID = CaptureRevisionID()
    let sessionID = CaptureSessionID(
        canonicalString: BundleValidationFixture.sessionUUID
    )!
    let spaceID = CoordinateSpaceID(
        canonicalString: BundleValidationFixture.spaceUUID
    )!
    let entity = try CaptureAnnotationEntity(
        type: .seat,
        coordinateSpaceID: spaceID,
        worldFromAnnotation: Matrix4x4F.identity,
        referencePointSemantics: .seatReferencePoint,
        label: "L seat",
        placement: PlacementProvenance(method: .manualNumeric)
    )
    let openings = try OpeningReviewDocument(
        captureRevisionID: revisionID,
        captureSessionID: sessionID,
        coordinateSpaceID: spaceID,
        openings: [
            makeOpening(
                source: .userDeclared,
                disposition: .confirmed,
                sourceRef: "user:door-1"
            ),
            makeOpening(
                source: .userDeclared,
                disposition: .intentionallyIgnored,
                sourceRef: "user:ignored",
                center: WorldPoint3D(x: 5, y: 0, z: 5)
            ),
            makeOpening(
                source: .userDeclared,
                disposition: .unreviewed,
                sourceRef: "user:nogeo",
                center: WorldPoint3D(x: -1, y: 0, z: -1)
            ),
        ]
    )
    let roomFrame = try RoomReferenceFrameDocument(
        captureRevisionID: revisionID,
        captureSessionID: sessionID,
        coordinateSpaceID: spaceID,
        originMeters: WorldPoint3D(x: 0, y: 0, z: 0),
        frontDirection: WorldPoint3D(x: 0, y: 0, z: 1),
        confirmedAtUTC: "2026-09-21T00:00:00Z"
    )

    let model = SurveyPlanCompositor.model(
        base: RoomPlanPreviewModel(
            minX: 0, maxX: 4, minZ: 0, maxZ: 3,
            walls: [
                .init(startX: 0, startZ: 0, endX: 4, endZ: 0)
            ],
            markers: [
                .init(kind: .door, x: 1, z: 0)
            ]
        ),
        entities: [entity],
        openings: openings,
        roomReferenceFrame: roomFrame
    )
    #expect(model != nil)
    let result = try #require(model)
    #expect(result.walls.count == 1)
    // Base door + confirmed user door + unreviewed-with-geometry
    // door; annotation + room frame origin + front markers.
    let kinds = result.markers.map(\.kind)
    #expect(kinds.filter { $0 == .door }.count == 3)
    #expect(kinds.contains(.annotation))
    #expect(kinds.contains(.roomFrameOrigin))
    #expect(kinds.contains(.roomFrameFront))
    // The intentionally-ignored opening at (5,5) never appears.
    #expect(
        !result.markers.contains { $0.label == "user:ignored" }
    )
    // Annotation marker carries the entity label.
    #expect(
        result.markers.contains { $0.label == "L seat" }
    )
}

@Test
func compositorSkipsRoomPlanOpeningsWhenBasePlanPresent() throws {
    let revisionID = CaptureRevisionID()
    let sessionID = CaptureSessionID(
        canonicalString: BundleValidationFixture.sessionUUID
    )!
    let spaceID = CoordinateSpaceID(
        canonicalString: BundleValidationFixture.spaceUUID
    )!
    let openings = try OpeningReviewDocument(
        captureRevisionID: revisionID,
        captureSessionID: sessionID,
        coordinateSpaceID: spaceID,
        openings: [
            makeOpening(
                source: .roomplanInference,
                disposition: .confirmed,
                sourceRef: "roomplan:door:0"
            )
        ]
    )
    let withBase = SurveyPlanCompositor.model(
        base: RoomPlanPreviewModel(
            minX: 0, maxX: 1, minZ: 0, maxZ: 1,
            walls: [],
            markers: [.init(kind: .door, x: 1, z: 0)]
        ),
        entities: [],
        openings: openings,
        roomReferenceFrame: nil
    )
    #expect(withBase?.markers.count == 1)

    let withoutBase = SurveyPlanCompositor.model(
        base: nil,
        entities: [],
        openings: openings,
        roomReferenceFrame: nil
    )
    #expect(withoutBase?.markers.count == 1)
    #expect(withoutBase?.markers[0].kind == .door)
}

@Test
func surveyPlanRendererProducesStandaloneSVG() throws {
    let model = RoomPlanPreviewModel(
        minX: 0, maxX: 4, minZ: 0, maxZ: 3,
        walls: [.init(startX: 0, startZ: 0, endX: 4, endZ: 0)],
        markers: [
            .init(kind: .door, x: 1, z: 0, label: "door-1"),
            .init(kind: .annotation, x: 2, z: 1.5, label: "L spk"),
        ]
    )
    let svg = SurveyPlanRenderer.svg(
        model: model,
        language: .english
    )
    #expect(svg.hasPrefix("<svg"))
    #expect(svg.contains("<svg"))
    #expect(svg.contains("</svg>"))
    // Legend + scale bar + traceable marker labels.
    #expect(svg.contains("door-1"))
    #expect(svg.contains("L spk"))
    #expect(svg.contains("1 m"))
    #expect(svg.contains("Top-down"))
}

// MARK: - Survey report builder

private func makeContents(
    entries: [BundleFileEntry] = [],
    entities: [CaptureAnnotationEntity] = [],
    measurements: [CaptureMeasurement] = []
) throws -> PersistedCaptureContents {
    PersistedCaptureContents(
        manifest: try makeManifest(entries: entries),
        qualityReport: nil,
        roomMetadata: nil,
        sessionDocument: nil,
        coordinateSpacePolicy: nil,
        entities: entities,
        measurements: measurements,
        openingReview: nil,
        roomReferenceFrame: nil,
        frameDescriptors: [],
        issues: []
    )
}

@Test
func reportBuilderProducesSelfContainedBilingualHTML() throws {
    let digest = EvidenceIntegrity.sha256(of: Data("b".utf8))
    let contents = try makeContents()
    let input = SurveyReportInput(
        contents: contents,
        advisoryReport: nil,
        planPreview: nil,
        displayName: "Demo room",
        bundleDigest: digest,
        evidenceImages: [],
        language: .english,
        generatedAtUTC: "2026-09-21T00:00:00Z"
    )
    let html = SurveyReportBuilder.html(input: input)
    #expect(html.hasPrefix("<!DOCTYPE"))
    #expect(html.contains("Demo room"))
    #expect(html.contains("not canonical capture evidence"))
    #expect(html.contains(digest.description))
    #expect(!html.contains("<img src=\"http"))

    let jaInput = SurveyReportInput(
        contents: contents,
        advisoryReport: nil,
        planPreview: nil,
        displayName: nil,
        bundleDigest: digest,
        evidenceImages: [],
        language: .japanese,
        generatedAtUTC: "2026-09-21T00:00:00Z"
    )
    let jaHTML = SurveyReportBuilder.html(input: jaInput)
    #expect(jaHTML.contains("フィールド調査レポート"))
}

@Test
func reportBuilderEmbedsOnlySelectedEvidenceImages() throws {
    let frameID = EvidenceFrameID()
    let contents = try makeContents()
    let image = SurveyReportEvidenceImage(
        frameID: frameID,
        jpegData: Data([0xFF, 0xD8, 0xFF])
    )
    let input = SurveyReportInput(
        contents: contents,
        advisoryReport: nil,
        planPreview: nil,
        displayName: nil,
        bundleDigest: EvidenceIntegrity.sha256(of: Data()),
        evidenceImages: [image],
        language: .english,
        generatedAtUTC: "2026-09-21T00:00:00Z"
    )
    let html = SurveyReportBuilder.html(input: input)
    #expect(html.contains(frameID.description))
    #expect(html.contains("data:image/jpeg;base64"))
    #expect(html.contains("figcaption"))

    let noImages = SurveyReportInput(
        contents: contents,
        advisoryReport: nil,
        planPreview: nil,
        displayName: nil,
        bundleDigest: EvidenceIntegrity.sha256(of: Data()),
        evidenceImages: [],
        language: .english,
        generatedAtUTC: "2026-09-21T00:00:00Z"
    )
    let plain = SurveyReportBuilder.html(input: noImages)
    #expect(!plain.contains("data:image/jpeg;base64"))
}

@Test
func surveyReportRunnerWritesArtifactsForMinimalBundle() throws {
    let fixture = try makeMeshBundle()
    defer { BundleValidationFixture.remove(fixture.captureRoot) }
    let digest = EvidenceIntegrity.sha256(of: Data("bundle".utf8))

    let result = try SurveyReportRunner.export(
        bundleDirectory: fixture.bundleDirectory,
        bundleDigest: digest,
        captureRoot: fixture.captureRoot,
        displayName: nil,
        planPreview: RoomPlanPreviewModel(
            minX: 0, maxX: 2, minZ: 0, maxZ: 2,
            walls: [.init(startX: 0, startZ: 0, endX: 2, endZ: 0)],
            markers: []
        ),
        evidenceImages: [],
        language: .english,
        generatedAtUTC: "2026-09-21T00:00:00Z"
    )
    #expect(FileManager.default.fileExists(
        atPath: result.reportFileURL.path
    ))
    #expect(result.planFileURL != nil)
    #expect(FileManager.default.fileExists(
        atPath: result.provenanceFileURL.path
    ))
    let provenance = try JSONDecoder().decode(
        DerivedDocumentProvenance.self,
        from: Data(contentsOf: result.provenanceFileURL)
    )
    #expect(provenance.documentKind == "field_survey_report")
    #expect(provenance.bundleDigest == digest)
    #expect(provenance.language == "en")
}
