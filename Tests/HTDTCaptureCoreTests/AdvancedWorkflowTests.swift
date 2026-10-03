import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue-cluster coverage for the advanced workflow payloads:
/// supplemental-document persistence, connected spaces (legacy bolph71656-ai/HTDT-Capture#222),
/// instrument adapters (legacy bolph71656-ai/HTDT-Capture#226), reference targets (legacy bolph71656-ai/HTDT-Capture#227), task-plan
/// import (legacy bolph71656-ai/HTDT-Capture#240), derived-geometry candidates (legacy bolph71656-ai/HTDT-Capture#249), post-scan
/// authoring (legacy bolph71656-ai/HTDT-Capture#282), and as-built verification (legacy bolph71656-ai/HTDT-Capture#293).
final class AdvancedWorkflowTests: XCTestCase {
    private var relaxedRequirements: CaptureQualityRequirements {
        CaptureQualityRequirements(
            rulesetVersion: "0.0.0-test",
            requireCompletedRoomPlan: false,
            minimumActiveMeshAnchors: 0,
            minimumEvidenceFrames: 0
        )
    }

    private let sessionID = CaptureSessionID(
        rawValue: UUID(
            uuidString: "20000000-0000-4000-8000-000000000003"
        )!
    )
    private let spaceID = CoordinateSpaceID(
        rawValue: UUID(
            uuidString: "20000000-0000-4000-8000-000000000004"
        )!
    )

    private func makeStore() throws -> (CaptureWorkingSetStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        return (store, root)
    }

    private func supplemental(
        path: String,
        data: Data,
        spaces: [CoordinateSpaceID] = [],
        sessions: [CaptureSessionID] = []
    ) throws -> WorkingSetSupplementalDocument {
        let binding = BundleReservedPaths.binding(for: path)
        return try WorkingSetSupplementalDocument(
            path: path,
            data: data,
            declaration: BundlePayloadDeclaration(
                path: path,
                mediaType: "application/json",
                producer: binding?.producer ?? "test",
                provenanceClass: binding?.provenanceClass
                    ?? .captureAppDerived,
                role: binding?.role ?? .canonical,
                sourceRefs: binding?.role == .derived
                    ? ["capture_session:\(sessionID)"]
                    : nil
            ),
            coordinateSpaceIDs: spaces,
            captureSessionIDs: sessions
        )
    }

    // MARK: - supplemental-document store path

    func testSupplementalDocumentWriteOnceAndSeal() async throws {
        let (store, root) = try makeStore()
        defer { BundleValidationFixture.remove(root) }

        let doc = try supplemental(
            path: "session/connected-spaces.json",
            data: Data(#"{"ok":1}"#.utf8)
        )
        try await store.persistSupplementalDocument(doc)

        // Identical replay is idempotent.
        try await store.persistSupplementalDocument(doc)

        // A different payload at the same path fails closed.
        do {
            try await store.persistSupplementalDocument(
                supplemental(
                    path: "session/connected-spaces.json",
                    data: Data(#"{"ok":2}"#.utf8)
                )
            )
            XCTFail("expected duplicatePayloadDeclaration")
        } catch CaptureWorkingSetError.duplicatePayloadDeclaration {
        }

        let snapshot = await store.snapshot()
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == "session/connected-spaces.json"
            }
        )

        let sealed = try await store.sealForFinalization(
            requirements: relaxedRequirements
        )
        XCTAssertTrue(
            sealed.snapshot.payloadDeclarations.contains {
                $0.path == "session/connected-spaces.json"
            }
        )
    }

    func testSupplementalDocumentReplaceAndBindingMismatch()
        async throws
    {
        let (store, root) = try makeStore()
        defer { BundleValidationFixture.remove(root) }

        // Reserved-path binding mismatch is rejected at construction.
        XCTAssertThrowsError(
            try WorkingSetSupplementalDocument(
                path: "session/connected-spaces.json",
                data: Data(#"{"ok":1}"#.utf8),
                declaration: BundlePayloadDeclaration(
                    path: "session/connected-spaces.json",
                    mediaType: "application/json",
                    producer: "wrong_producer",
                    provenanceClass: .captureAppDerived,
                    role: .canonical
                )
            )
        )

        let doc = try supplemental(
            path: "session/task-plan-status.json",
            data: Data(#"{"v":1}"#.utf8)
        )
        try await store.replaceSupplementalDocument(doc)
        let replaced = try supplemental(
            path: "session/task-plan-status.json",
            data: Data(#"{"v":2}"#.utf8)
        )
        try await store.replaceSupplementalDocument(replaced)

        let onDisk = try Data(
            contentsOf: root.appendingPathComponent(
                "session/task-plan-status.json"
            )
        )
        XCTAssertEqual(onDisk, replaced.data)

        // After replace, plain persist of different bytes still fails.
        do {
            try await store.persistSupplementalDocument(
                supplemental(
                    path: "session/task-plan-status.json",
                    data: Data(#"{"v":3}"#.utf8)
                )
            )
            XCTFail("expected duplicatePayloadDeclaration")
        } catch CaptureWorkingSetError.duplicatePayloadDeclaration {
        }
    }

    /// A `.derived` path is regenerated state, not committed authority:
    /// a re-End legitimately re-declares the same path with an evolved
    /// source-ref set (new depthbins, rolled-back mesh). Refusing that
    /// re-declare left every re-End stuck with the first run's stale
    /// candidates document.
    func testDerivedDocumentRedeclareAndRemove() async throws {
        let (store, root) = try makeStore()
        defer { BundleValidationFixture.remove(root) }

        func derivedDoc(_ bytes: String, refs: [String]) throws
            -> WorkingSetSupplementalDocument
        {
            try WorkingSetSupplementalDocument(
                path: DerivedGeometryCandidatePackage.path,
                data: Data(bytes.utf8),
                declaration: BundlePayloadDeclaration(
                    path: DerivedGeometryCandidatePackage.path,
                    mediaType: "application/json",
                    producer: "derived_geometry",
                    provenanceClass: .captureAppDerived,
                    role: .derived,
                    sourceRefs: refs
                ),
                coordinateSpaceIDs: [],
                captureSessionIDs: []
            )
        }

        // `path:` refs must resolve at commit — the mesh package is
        // persisted first so `mesh/anchors.json` is declared.
        try await store.persistMeshPackage(
            MeshEvidencePackageBuilder.build(
                snapshots: [try makeMeshAnchor()]
            )
        )
        try await store.replaceSupplementalDocument(
            derivedDoc(#"{"v":1}"#, refs: ["path:mesh/anchors.json"])
        )
        try await store.replaceSupplementalDocument(
            derivedDoc(
                #"{"v":2}"#,
                refs: [
                    "path:mesh/anchors.json",
                    "capture_session:\(sessionID)",
                ]
            )
        )
        var snapshot = await store.snapshot()
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == DerivedGeometryCandidatePackage.path
                    && $0.sourceRefs?.count == 2
            }
        )

        // The same declaration shift on a canonical path still fails
        // closed — committed authority is immutable.
        let canonical = try supplemental(
            path: "session/task-plan-status.json",
            data: Data(#"{"v":1}"#.utf8)
        )
        try await store.replaceSupplementalDocument(canonical)
        do {
            try await store.replaceSupplementalDocument(
                WorkingSetSupplementalDocument(
                    path: "session/task-plan-status.json",
                    data: Data(#"{"v":1}"#.utf8),
                    declaration: BundlePayloadDeclaration(
                        path: "session/task-plan-status.json",
                        mediaType: "application/json",
                        producer: "capture_session",
                        provenanceClass: .captureAppDerived,
                        role: .canonical,
                        sourceRefs: ["capture_session:\(sessionID)"]
                    ),
                    coordinateSpaceIDs: [],
                    captureSessionIDs: []
                )
            )
            XCTFail("canonical re-declare must fail")
        } catch CaptureWorkingSetError.duplicatePayloadDeclaration {
        }

        try await store.removeSupplementalDocument(
            path: DerivedGeometryCandidatePackage.path
        )
        snapshot = await store.snapshot()
        XCTAssertFalse(
            snapshot.payloadDeclarations.contains {
                $0.path == DerivedGeometryCandidatePackage.path
            }
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    DerivedGeometryCandidatePackage.path
                ).path
            )
        )
    }

    /// `derived/authority-dependencies.json` is a `.derived` commit
    /// point too: a package whose source refs cannot resolve must be
    /// rejected before any bytes or declaration land.
    func testAuthorityDependenciesRejectUnresolvableSourceRef()
        async throws
    {
        let (store, root) = try makeStore()
        defer { BundleValidationFixture.remove(root) }

        let manifest = try ExternalAuthorityDependencyManifest(
            generatedAtUTC: "2026-10-02T00:00:00Z",
            dependencies: []
        )
        let package = try ExternalAuthorityDependencyPackage(
            manifest: manifest,
            extraSourceRefs: ["path:aaa/never-committed.json"]
        )
        do {
            try await store.persistOrReplaceAuthorityDependencies(
                package
            )
            XCTFail("expected unresolvedDerivedSourceRef")
        } catch CaptureWorkingSetError.unresolvedDerivedSourceRef(
            let cited
        ) {
            XCTAssertEqual(cited, "aaa/never-committed.json")
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    ExternalAuthorityDependencyPackage.path
                ).path
            )
        )
        let snapshot = await store.snapshot()
        XCTAssertFalse(
            snapshot.payloadDeclarations.contains {
                $0.path == ExternalAuthorityDependencyPackage.path
            }
        )
    }

    func testSupplementalDocumentCoordinateSpaceEnforced() async throws {
        let (store, root) = try makeStore()
        defer { BundleValidationFixture.remove(root) }

        let otherSpace = CoordinateSpaceID(
            rawValue: UUID(
                uuidString: "20000000-0000-4000-8000-000000000099"
            )!
        )
        // First claim binds the space.
        try await store.persistSupplementalDocument(
            supplemental(
                path: "session/connected-spaces.json",
                data: Data(#"{"ok":1}"#.utf8),
                spaces: [spaceID]
            )
        )
        // A second doc claiming another space must fail — independent
        // coordinate spaces never merge silently.
        do {
            try await store.persistSupplementalDocument(
                supplemental(
                    path: "session/task-plan-status.json",
                    data: Data(#"{"v":1}"#.utf8),
                    spaces: [otherSpace]
                )
            )
            XCTFail("expected authorityMismatch")
        } catch CaptureWorkingSetError.authorityMismatch {
        }
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#249 derived geometry candidates

    private func provenance(
        algorithm: String = "wall-fit",
        version: String = "1.0.0"
    ) -> DerivedShapeProvenance {
        DerivedShapeProvenance(
            sourceEvidenceRefs: ["path:evidence/frames/f.json"],
            sourceCoordinateSpaceID: spaceID,
            derivationAlgorithm: algorithm,
            derivationVersion: version,
            fitScore: 0.9,
            normalizedResidual: 0.1,
            observationStartSeconds: 1,
            observationEndSeconds: 5
        )
    }

    func testDerivedGeometryCandidateBuildAndEnumerate() throws {
        let proxy = DerivedShapeProxy(
            resolution: .resolved,
            selected: DerivedShapeCandidate(
                geometry: .orientedRectangle(
                    DerivedOrientedRectangle(
                        center: DerivedPoint2D(x: 1, y: 2),
                        width: 3,
                        depth: 4,
                        headingRadians: 0.5
                    )
                ),
                metrics: DerivedShapeFitMetrics(
                    normalizedResidual: 0.1,
                    supportScore: 0.8,
                    fitScore: 0.9
                )
            ),
            candidates: [],
            provenance: provenance(),
            observationSample: [
                DerivedObservationPoint(
                    position: DerivedPoint2D(x: 0, y: 0),
                    evidenceRef: "mesh_anchor:a",
                    evidenceKind: .mesh
                ),
            ]
        )
        let ambiguous = DerivedShapeProxy(
            resolution: .ambiguousEvidence,
            selected: nil,
            candidates: [
                DerivedShapeCandidate(
                    geometry: .circle(
                        DerivedCircle(
                            center: DerivedPoint2D(x: 0, y: 0),
                            radius: 1
                        )
                    ),
                    metrics: DerivedShapeFitMetrics(
                        normalizedResidual: 0.4,
                        supportScore: 0.4,
                        fitScore: 0.4
                    )
                ),
                DerivedShapeCandidate(
                    geometry: .ellipse(
                        DerivedEllipse(
                            center: DerivedPoint2D(x: 0, y: 0),
                            semiMajorAxis: 2,
                            semiMinorAxis: 1,
                            headingRadians: 0
                        )
                    ),
                    metrics: DerivedShapeFitMetrics(
                        normalizedResidual: 0.5,
                        supportScore: 0.3,
                        fitScore: 0.3
                    )
                ),
            ],
            provenance: DerivedShapeProvenance(
                sourceEvidenceRefs: ["path:evidence/frames/f.json"],
                sourceCoordinateSpaceID: spaceID,
                derivationAlgorithm: "wall-fit",
                derivationVersion: "1.0.0",
                fitScore: nil,
                normalizedResidual: nil,
                observationStartSeconds: nil,
                observationEndSeconds: nil
            ),
            observationSample: [
                DerivedObservationPoint(
                    position: DerivedPoint2D(x: 1, y: 1),
                    evidenceRef: "frame:f",
                    evidenceKind: .sceneDepth
                ),
            ]
        )
        let snapshot = DerivedShapePreviewSnapshot(
            objectProxies: [proxy, ambiguous]
        )
        let revisionID = CaptureRevisionID()
        let (package, declaration) =
            try DerivedGeometryCandidatePackageBuilder.build(
                snapshot: snapshot,
                captureRevisionID: revisionID,
                captureSessionID: sessionID,
                sourcePayloadRefs: [
                    "capture_session:\(sessionID)",
                ]
            )

        XCTAssertEqual(declaration.role, .derived)
        XCTAssertEqual(
            declaration.provenanceClass,
            .captureAppDerived
        )
        XCTAssertEqual(package.document.candidates.count, 2)

        // HTDT enumerates the candidates after ingestion by decoding
        // the committed payload.
        let decoded = try JSONDecoder().decode(
            DerivedGeometryCandidateDocument.self,
            from: package.data
        )
        let resolved = decoded.candidates.first {
            $0.resolution == .resolved
        }
        XCTAssertEqual(resolved?.shapeKind, .orientedRectangle)
        XCTAssertEqual(resolved?.sourceMode, .classifiedMesh)
        XCTAssertEqual(
            resolved?.derivationAlgorithm,
            "wall-fit"
        )
        let unresolved = decoded.candidates.first {
            $0.resolution == .ambiguousEvidence
        }
        // Unresolved candidates stay explicitly unresolved.
        XCTAssertNil(unresolved?.geometry)
        XCTAssertNil(unresolved?.shapeKind)
        XCTAssertEqual(
            unresolved?.ambiguityShapeKinds,
            [.circle, .ellipse]
        )
        XCTAssertEqual(unresolved?.sourceMode, .sceneDepth)
    }

    func testDerivedGeometryRecordInvariants() throws {
        // Resolved without geometry fails.
        XCTAssertThrowsError(
            try DerivedGeometryCandidateRecord(
                resolution: .resolved,
                coordinateSpaceID: spaceID,
                sourceMode: .fused,
                sourceEvidenceRefs: ["a"],
                derivationAlgorithm: "alg",
                derivationVersion: "1"
            )
        )
        // Unresolved carrying geometry fails.
        XCTAssertThrowsError(
            try DerivedGeometryCandidateRecord(
                resolution: .insufficientEvidence,
                shapeKind: .circle,
                geometry: .circle(
                    DerivedCircle(
                        center: DerivedPoint2D(x: 0, y: 0),
                        radius: 1
                    )
                ),
                coordinateSpaceID: spaceID,
                sourceMode: .fused,
                sourceEvidenceRefs: ["a"],
                derivationAlgorithm: "alg",
                derivationVersion: "1"
            )
        )
        // Contour bound enforced.
        XCTAssertThrowsError(
            try DerivedGeometryCandidateRecord(
                resolution: .resolved,
                shapeKind: .circle,
                geometry: .circle(
                    DerivedCircle(
                        center: DerivedPoint2D(x: 0, y: 0),
                        radius: 1
                    )
                ),
                coordinateSpaceID: spaceID,
                sourceMode: .fused,
                sourceEvidenceRefs: ["a"],
                derivationAlgorithm: "alg",
                derivationVersion: "1",
                contourPoints: (0...256).map {
                    DerivedObservationPoint(
                        position: DerivedPoint2D(x: 0, y: 0),
                        evidenceRef: "e\($0)",
                        evidenceKind: .mesh
                    )
                }
            )
        )
        // Empty source payload refs rejected at the package level —
        // role .derived requires lineage.
        XCTAssertThrowsError(
            try DerivedGeometryCandidatePackageBuilder.build(
                snapshot: DerivedShapePreviewSnapshot(),
                captureRevisionID: CaptureRevisionID(),
                captureSessionID: sessionID,
                sourcePayloadRefs: []
            )
        )
    }

    func testDerivedGeometryPackagePersistsAndSeals() async throws {
        let (store, root) = try makeStore()
        defer { BundleValidationFixture.remove(root) }

        let proxy = DerivedShapeProxy(
            resolution: .resolved,
            selected: DerivedShapeCandidate(
                geometry: .circle(
                    DerivedCircle(
                        center: DerivedPoint2D(x: 0, y: 0),
                        radius: 1
                    )
                ),
                metrics: DerivedShapeFitMetrics(
                    normalizedResidual: 0.1,
                    supportScore: 0.9,
                    fitScore: 0.9
                )
            ),
            candidates: [],
            provenance: provenance(),
            observationSample: []
        )
        let (package, declaration) =
            try DerivedGeometryCandidatePackageBuilder.build(
                snapshot: DerivedShapePreviewSnapshot(
                    objectProxies: [proxy]
                ),
                captureRevisionID: await store.identity.captureRevisionID,
                captureSessionID: sessionID,
                sourcePayloadRefs: [
                    "capture_session:\(sessionID)",
                ]
            )
        try await store.persistSupplementalDocument(
            try WorkingSetSupplementalDocument(
                path: DerivedGeometryCandidatePackage.path,
                data: package.data,
                declaration: declaration,
                coordinateSpaceIDs: [spaceID]
            )
        )
        _ = try await store.sealForFinalization(
            requirements: relaxedRequirements
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    DerivedGeometryCandidatePackage.path
                ).path
            )
        )
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#227 reference targets

    func testReferenceTargetResidualsAndDiagnostics() throws {
        let target = try ReferenceTargetDeclaration(
            targetType: "apriltag_36h11_100mm",
            knownDimensionMeters: 0.1,
            dimensionAuthority: .manufacturerSpecification,
            authorityRef: "vendor datasheet rev 3"
        )
        let initial = try ReferenceTargetObservation(
            targetID: target.targetID,
            coordinateSpaceID: spaceID,
            observationIndex: 0,
            positionWorld: try SpatialVector3F(1, 0, 1),
            measuredDimensionMeters: 0.11,
            sessionTimestampSeconds: 2
        )
        let revisit = try ReferenceTargetObservation(
            targetID: target.targetID,
            coordinateSpaceID: spaceID,
            observationIndex: 1,
            positionWorld: try SpatialVector3F(1.5, 0, 1),
            sessionTimestampSeconds: 90,
            evidenceRefs: ["frame:abc"]
        )
        let package = try ReferenceTargetCaptureBuilder.build(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: sessionID,
            targets: [target],
            observations: [initial, revisit]
        )
        let diagnostics = package.document.diagnostics
        XCTAssertEqual(diagnostics.count, 1)
        // 0.11 observed vs 0.1 known -> 10% residual.
        XCTAssertEqual(
            diagnostics[0].scaleResidualFraction ?? 0,
            0.1,
            accuracy: 1e-9
        )
        // Revisit displaced 0.5 m along X.
        XCTAssertEqual(
            diagnostics[0].revisitDisplacementMeters ?? 0,
            0.5,
            accuracy: 1e-6
        )
        // Review-surface diagnostics are advisory only.
        let review = ReferenceTargetCaptureBuilder
            .reviewDiagnostics(for: package.document)
        XCTAssertEqual(review.count, 2)
        XCTAssertTrue(
            review.allSatisfy { $0.severity == .info }
        )
    }

    func testReferenceTargetValidation() throws {
        let target = try ReferenceTargetDeclaration(
            targetType: "checkerboard",
            knownDimensionMeters: 0.1,
            dimensionAuthority: .userSupplied,
            authorityRef: "measured by operator"
        )
        // Observations must reference a declared target.
        let stray = try ReferenceTargetObservation(
            targetID: ReferenceTargetID(),
            coordinateSpaceID: spaceID,
            observationIndex: 0
        )
        XCTAssertThrowsError(
            try ReferenceTargetCaptureBuilder.build(
                captureRevisionID: CaptureRevisionID(),
                captureSessionID: sessionID,
                targets: [target],
                observations: [stray]
            )
        )
        // Non-positive known dimension is rejected.
        XCTAssertThrowsError(
            try ReferenceTargetDeclaration(
                targetType: "checkerboard",
                knownDimensionMeters: 0,
                dimensionAuthority: .userSupplied,
                authorityRef: "x"
            )
        )
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#226 external measurement instruments

    private func makeDescriptor(
    ) throws -> InstrumentAdapterDescriptor {
        try InstrumentAdapterDescriptor(
            adapterID: "test-laser",
            acquisitionMethod: .laserDistanceMeter,
            makeModel: "Acme L-100",
            transport: "ble"
        )
    }

    func testInstrumentReadingConfirmPreservesProvenance()
        async throws
    {
        let descriptor = try makeDescriptor()
        let json = Data(
            #"{"value": 4.215, "unit": "m", "device_measurement_id": "dm-42", "observed_at": "2026-09-21T10:00:00Z", "calibration_status": "calibrated", "calibration_date": "2026-01-15"}"#
                .utf8
        )
        var session = InstrumentMeasurementSession()
        let pending = try await session.stageReading(
            from: FileImportInstrumentAdapter(
                descriptor: descriptor,
                data: json
            )
        )
        XCTAssertEqual(pending.reading.value, 4.215)

        let measurement = try session.confirmMeasurement(
            pending,
            quantityType: "wall_width",
            coordinateSpaceID: spaceID,
            endpointRefs: ["a", "b"]
        )
        XCTAssertEqual(measurement.value, .scalar(4.215))
        XCTAssertEqual(measurement.unit, .meter)
        XCTAssertEqual(
            measurement.acquisitionMethod,
            .laserDistanceMeter
        )
        XCTAssertEqual(
            measurement.instrument?.makeModel,
            "Acme L-100"
        )
        // Exact received value/unit text is preserved.
        XCTAssertEqual(
            measurement.sourceValueText,
            "4.215 m"
        )
        // Device measurement id + timestamp preserved.
        XCTAssertTrue(
            measurement.evidenceRefs.contains(
                "instrument_reading:dm-42"
            )
        )
        XCTAssertEqual(
            measurement.observedAtUTC,
            "2026-09-21T10:00:00Z"
        )
        // Calibration metadata only flows because it was supplied.
        XCTAssertEqual(
            measurement.instrument?.calibrationStatus,
            "calibrated"
        )
        XCTAssertEqual(
            measurement.instrument?.calibrationDate,
            "2026-01-15"
        )
    }

    func testInstrumentDisconnectKeepsPendingAndManualPath()
        async throws
    {
        struct FailingAdapter: MeasurementInstrumentAdapter {
            let descriptor: InstrumentAdapterDescriptor
            func readScalar() async throws -> InstrumentReading {
                throw InstrumentAdapterError.disconnected
            }
        }
        let descriptor = try makeDescriptor()
        var session = InstrumentMeasurementSession()

        // Stage one reading, then disconnect mid-session.
        _ = try await session.stageReading(
            from: FileImportInstrumentAdapter(
                descriptor: descriptor,
                data: Data("3.5 m".utf8)
            )
        )
        do {
            _ = try await session.stageReading(
                from: FailingAdapter(descriptor: descriptor)
            )
            XCTFail("expected disconnected")
        } catch InstrumentAdapterError.disconnected {
        }
        XCTAssertEqual(session.linkState, .disconnected)
        // Staged pending measurement survives the disconnect.
        XCTAssertEqual(session.pending?.reading.value, 3.5)

        // Manual entry stays supported: a measurement without any
        // instrument authority.
        let manual = try ManualAuthorityBuilder.scalarMeasurement(
            quantityType: "wall_width",
            value: 3.5,
            unit: .meter,
            acquisitionMethod: .tapeMeasure
        )
        XCTAssertEqual(manual.acquisitionMethod, .tapeMeasure)
    }

    func testInstrumentAdapterValidation() async throws {
        // Derived acquisition methods cannot come from a physical
        // instrument adapter.
        XCTAssertThrowsError(
            try InstrumentAdapterDescriptor(
                adapterID: "x",
                acquisitionMethod: .roomPlanDerived,
                makeModel: "m",
                transport: "file"
            )
        )
        // Plain text import path.
        let adapter = FileImportInstrumentAdapter(
            descriptor: try makeDescriptor(),
            data: Data("2.75 rad".utf8)
        )
        let reading = try await adapter.readScalar()
        XCTAssertEqual(reading.value, 2.75)
        XCTAssertEqual(reading.unit, .radian)
        XCTAssertEqual(reading.receivedValueText, "2.75 rad")
        // Malformed bytes fail closed.
        let bad = FileImportInstrumentAdapter(
            descriptor: try makeDescriptor(),
            data: Data("not-a-reading".utf8)
        )
        do {
            _ = try await bad.readScalar()
            XCTFail("expected invalidReading")
        } catch InstrumentAdapterError.invalidReading {
        }
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#240 capture task plan

    private func makePlanData() throws -> Data {
        let planJSON = """
            {
              "schema": "htdt.capture-task-plan",
              "schema_version": "1.0.0",
              "plan_id": "plan-7",
              "plan_version": "2026.09.1",
              "project_ref": "proj-77/doc-9",
              "room_name": "Theater A",
              "issued_at": "2026-09-20T08:00:00Z",
              "entity_checklist": [
                {
                  "item_id": "speaker-left",
                  "entity_type": "speaker",
                  "requirement": "required",
                  "channel_role": "L",
                  "label_hint": "Left main"
                }
              ],
              "measurement_requests": [
                {
                  "item_id": "room-width",
                  "quantity_type": "width",
                  "requirement": "required",
                  "endpoint_semantics": "wall-to-wall",
                  "expected_unit": "m"
                }
              ],
              "surface_review_tasks": [
                {
                  "item_id": "window-review",
                  "surface_kind": "window",
                  "requirement": "optional"
                }
              ],
              "evidence_targets": ["frame:north-wall"],
              "expected_channel_roles": ["L", "R"]
            }
            """
        return Data(planJSON.utf8)
    }

    func testTaskPlanImportAndStatus() async throws {
        let planImport = try CaptureTaskPlanImport(
            data: makePlanData()
        )
        XCTAssertEqual(planImport.plan.planID, "plan-7")
        XCTAssertEqual(
            planImport.planSHA256,
            EvidenceIntegrity.sha256(
                of: planImport.data
            )
        )

        var status = CaptureTaskPlanStatus(
            planImport: planImport
        )
        // All items pending before any evidence.
        var outcomes = status.itemOutcomes(
            annotations: [],
            measurements: []
        )
        XCTAssertEqual(
            Set(outcomes.map(\.outcome)),
            [.pending]
        )

        // Committing a matching entity completes the item — the plan
        // never pre-populated it.
        let entity = try CaptureAnnotationEntity(
            type: .speaker,
            coordinateSpaceID: spaceID,
            worldFromAnnotation: .identity,
            referencePointSemantics: .cabinetReferencePoint,
            label: "Left main",
            placement: try PlacementProvenance(
                method: .manualNumeric
            ),
            orientation: try OrientationAxes(
                frontAxisLocal: .unit(0, 0, -1),
                upAxisLocal: .unit(0, 1, 0)
            ),
            channelRole: ChannelRole(rawValue: "L")
        )
        outcomes = status.itemOutcomes(
            annotations: [entity],
            measurements: []
        )
        XCTAssertEqual(
            outcomes.first { $0.itemID == "speaker-left" }?.outcome,
            .completed
        )
        XCTAssertEqual(
            outcomes.first { $0.itemID == "room-width" }?.outcome,
            .pending
        )

        // Operator marks the surface review completed and the
        // measurement unavailable.
        try status.mark(
            itemID: "window-review",
            as: .completed
        )
        try status.mark(
            itemID: "room-width",
            as: .unavailable
        )
        outcomes = status.itemOutcomes(
            annotations: [entity],
            measurements: []
        )
        XCTAssertEqual(
            outcomes.first { $0.itemID == "window-review" }?.outcome,
            .completed
        )
        XCTAssertEqual(
            outcomes.first { $0.itemID == "room-width" }?.outcome,
            .unavailable
        )

        // Unknown items and premature completed marks on evidence-
        // backed items are rejected.
        XCTAssertThrowsError(
            try status.mark(itemID: "nope", as: .skipped)
        )
        XCTAssertThrowsError(
            try status.mark(
                itemID: "speaker-left",
                as: .completed
            )
        )

        // Status document links back to the exact plan identity.
        let doc = try status.statusDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: sessionID,
            annotations: [entity],
            measurements: []
        )
        XCTAssertEqual(doc.planID, "plan-7")
        XCTAssertEqual(doc.planSHA256, planImport.planSHA256)
        let data = try status.statusPackage(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: sessionID,
            annotations: [entity],
            measurements: []
        )
        let decoded = try JSONDecoder().decode(
            CaptureTaskPlanStatusDocument.self,
            from: data
        )
        XCTAssertEqual(decoded.items.count, 3)
    }

    func testTaskPlanRejectsMalformed() throws {
        XCTAssertThrowsError(
            try CaptureTaskPlanImport(data: Data("[]".utf8))
        )
        XCTAssertThrowsError(
            try CaptureTaskPlanImport(
                data: Data(
                    #"{"schema":"other","schema_version":"1.0.0"}"#
                        .utf8
                )
            )
        )
        // Duplicate item ids rejected.
        let dupJSON = """
            {
              "schema": "htdt.capture-task-plan",
              "schema_version": "1.0.0",
              "plan_id": "p",
              "plan_version": "1",
              "project_ref": "proj",
              "room_name": "r",
              "entity_checklist": [
                {"item_id": "x", "entity_type": "seat",
                 "requirement": "required"},
                {"item_id": "x", "entity_type": "seat",
                 "requirement": "optional"}
              ]
            }
            """
        XCTAssertThrowsError(
            try CaptureTaskPlanImport(data: Data(dupJSON.utf8))
        )
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#222 connected spaces

    func testConnectedSpaceWorkflow() throws {
        var tracker = ConnectedSpaceTracker(
            coordinateSpaceID: spaceID,
            captureSessionID: sessionID
        )
        let living = try tracker.beginSegment(
            label: "Living Room",
            kind: .room
        )
        XCTAssertEqual(tracker.activeSegment?.regionID, living.regionID)

        // Second begin while active fails.
        XCTAssertThrowsError(
            try tracker.beginSegment(label: "x", kind: .room)
        )

        try tracker.completeActiveSegment()
        XCTAssertNil(tracker.activeSegment)

        let kitchen = try tracker.beginSegment(
            label: "Kitchen",
            kind: .openPlanArea
        )
        // Explicit portal relationship between the two segments.
        let portal = try tracker.recordPortal(
            toRegionID: living.regionID,
            kind: .openPassage,
            evidenceRefs: ["frame:f1"]
        )
        XCTAssertEqual(portal.regionAID, kitchen.regionID)
        XCTAssertEqual(portal.regionBID, living.regionID)

        try tracker.completeActiveSegment()

        // Revisit before finalization re-activates a completed segment.
        try tracker.revisitRegion(living.regionID)
        XCTAssertEqual(
            tracker.activeSegment?.regionID,
            living.regionID
        )
        XCTAssertEqual(
            tracker.activeSegment?.revisitCount,
            1
        )
        try tracker.appendEvidence(
            to: living.regionID,
            refs: ["frame:f2"]
        )
        try tracker.completeActiveSegment()

        let doc = try tracker.document(
            captureRevisionID: CaptureRevisionID()
        )
        XCTAssertEqual(doc.segments.count, 2)
        XCTAssertEqual(doc.portals.count, 1)
        XCTAssertEqual(
            doc.segments.first { $0.regionID == living.regionID }?
                .evidenceRefs,
            ["frame:f2"]
        )
        XCTAssertEqual(doc.coordinateSpaceID, spaceID)

        // Round-trips through the supplemental-document encoder.
        let data = try tracker.package(
            captureRevisionID: CaptureRevisionID()
        )
        let decoded = try JSONDecoder().decode(
            ConnectedSpaceDocument.self,
            from: data
        )
        XCTAssertEqual(decoded.segments.count, 2)
    }

    func testConnectedSpaceValidation() throws {
        var tracker = ConnectedSpaceTracker(
            coordinateSpaceID: spaceID,
            captureSessionID: sessionID
        )
        // Portal requires an active segment.
        XCTAssertThrowsError(
            try tracker.recordPortal(
                toRegionID: CaptureRegionID(),
                kind: .doorway
            )
        )
        // Portal to an unknown region fails.
        let segment = try tracker.beginSegment(
            label: "A",
            kind: .room
        )
        XCTAssertThrowsError(
            try tracker.recordPortal(
                toRegionID: CaptureRegionID(),
                kind: .doorway
            )
        )
        // Self-portal rejected.
        XCTAssertThrowsError(
            try tracker.recordPortal(
                toRegionID: segment.regionID,
                kind: .doorway
            )
        )
        // A segment in another space cannot enter the document.
        let otherSpace = CoordinateSpaceID(
            rawValue: UUID(
                uuidString: "20000000-0000-4000-8000-0000000000aa"
            )!
        )
        let foreign = try CaptureRegionSegment(
            regionID: CaptureRegionID(),
            label: "B",
            kind: .room,
            state: .completed,
            coordinateSpaceID: otherSpace,
            captureSessionID: sessionID
        )
        XCTAssertThrowsError(
            try ConnectedSpaceDocument(
                captureRevisionID: CaptureRevisionID(),
                captureSessionID: sessionID,
                coordinateSpaceID: spaceID,
                segments: tracker.segments + [foreign],
                portals: []
            )
        ) { error in
            XCTAssertEqual(
                error as? ConnectedSpaceError,
                .crossSpacePortal
            )
        }
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#282 post-scan authoring

    private func makeMeshAnchor() throws -> MeshAnchorSnapshot {
        try MeshAnchorSnapshot(
            anchorID: UUID(
                uuidString:
                    "20000000-0000-4000-8000-000000000005"
            )!,
            captureSessionID: sessionID,
            coordinateSpaceID: spaceID,
            worldFromAnchor: .identity,
            sessionTimestampSeconds: 1,
            geometry: MeshGeometryPayload(
                vertices: [
                    Float3(0, 0, -2),
                    Float3(2, 0, -2),
                    Float3(0, 2, -2),
                ],
                triangleIndices: [0, 1, 2]
            )
        )
    }

    func testPostScanMeshHitTestAndAuthorities() throws {
        var session = PostScanGeometryAuthoringSession(
            coordinateSpaceID: spaceID,
            meshAnchors: [try makeMeshAnchor()]
        )
        let ray = try AcceptedGeometryRay(
            origin: Float3(0.5, 0.5, 0),
            direction: Float3(0, 0, -1)
        )
        let selection = session.hitTestMesh(ray: ray)
        XCTAssertNotNil(selection)
        XCTAssertEqual(selection?.source, .meshAnchor)
        XCTAssertTrue(selection?.isCanonicalSource == true)
        XCTAssertEqual(
            selection?.positionWorld.z ?? 0,
            -2,
            accuracy: 1e-5
        )

        // Placement authority carries mesh-hit-test provenance bound
        // to the anchor.
        let authority = try session.placementAuthority(
            for: selection!.selectionID
        )
        XCTAssertEqual(
            authority.placement.method,
            .meshHitTest
        )
        XCTAssertEqual(
            authority.placement.sourceMeshAnchorID,
            UUID(
                uuidString:
                    "20000000-0000-4000-8000-000000000005"
            )
        )
        XCTAssertEqual(authority.coordinateSpaceID, spaceID)

        // Endpoint refs reuse the same selection.
        let endpoint = try session.endpointRef(
            for: selection!.selectionID
        )
        XCTAssertEqual(
            endpoint,
            "geometry_point:\(selection!.selectionID)"
        )

        // Miss produces no selection.
        let miss = session.hitTestMesh(
            ray: try AcceptedGeometryRay(
                origin: Float3(10, 10, 10),
                direction: Float3(0, 1, 0)
            )
        )
        XCTAssertNil(miss)
    }

    func testPostScanStaleSelectionOnGeometryChange() throws {
        var session = PostScanGeometryAuthoringSession(
            coordinateSpaceID: spaceID,
            meshAnchors: [try makeMeshAnchor()]
        )
        let selection = try XCTUnwrap(
            session.hitTestMesh(
                ray: try AcceptedGeometryRay(
                    origin: Float3(0.5, 0.5, 0),
                    direction: Float3(0, 0, -1)
                )
            )
        )
        // Continue-scanning replaces geometry: prior selections go
        // stale explicitly instead of being reprojected.
        session.noteGeometryChanged(
            meshAnchors: [try makeMeshAnchor()]
        )
        XCTAssertTrue(session.isStale(selection.selectionID))
        XCTAssertThrowsError(
            try session.placementAuthority(
                for: selection.selectionID
            )
        ) { error in
            XCTAssertEqual(
                error as? PostScanAuthoringError,
                .staleSelection
            )
        }
    }

    func testPostScanDerivedCandidateSelection() throws {
        let record = try DerivedGeometryCandidateRecord(
            resolution: .resolved,
            shapeKind: .polygon,
            geometry: .polygon(
                DerivedPolygon(
                    vertices: [
                        SupportedPolygonVertex(
                            position: DerivedPoint2D(x: 1, y: 1),
                            supportEvidenceRefs: ["e"]
                        ),
                    ],
                    isConcave: false
                )
            ),
            coordinateSpaceID: spaceID,
            sourceMode: .classifiedMesh,
            sourceEvidenceRefs: ["path:mesh/anchors.json"],
            derivationAlgorithm: "alg",
            derivationVersion: "1",
            contourPoints: [
                DerivedObservationPoint(
                    position: DerivedPoint2D(x: 1, y: 1),
                    evidenceRef: "e",
                    evidenceKind: .mesh
                ),
            ]
        )
        var session = PostScanGeometryAuthoringSession(
            coordinateSpaceID: spaceID,
            derivedCandidates: [record]
        )
        let selection = try session.selectDerivedCandidatePoint(
            candidateID: record.candidateID,
            pointIndex: 0
        )
        // Derived selections are visibly distinct from canonical.
        XCTAssertFalse(selection.isCanonicalSource)
        XCTAssertEqual(
            selection.source,
            .derivedCandidate
        )
        let authority = try session.placementAuthority(
            for: selection.selectionID
        )
        XCTAssertEqual(authority.placement.method, .other)
        XCTAssertTrue(
            authority.evidenceRefs.contains(
                "derived_candidate:\(record.candidateID)"
            )
        )

        // Unknown candidates and out-of-range points fail.
        XCTAssertThrowsError(
            try session.selectDerivedCandidatePoint(
                candidateID: DerivedGeometryCandidateID(),
                pointIndex: 0
            )
        )
        XCTAssertThrowsError(
            try session.selectDerivedCandidatePoint(
                candidateID: record.candidateID,
                pointIndex: 9
            )
        )
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#293 as-built verification

    private func makeSpec(
        id: String = "speaker-l",
        tolerance: Double? = 0.05
    ) throws -> PlannedAsBuiltSpec {
        try PlannedAsBuiltSpec(
            plannedEntityID: id,
            entityType: .speaker,
            channelRole: ChannelRole(rawValue: "L"),
            positionScene: try SpatialVector3F(1, 1, 0),
            orientationScene: try OrientationAxes(
                frontAxisLocal: .unit(0, 0, -1),
                upAxisLocal: .unit(0, 1, 0)
            ),
            toleranceMeters: tolerance
        )
    }

    private func makeAlignment(
        dx: Float = 0,
        residualMeters: Double? = nil
    ) throws -> PlanAlignmentAuthority {
        try PlanAlignmentAuthority(
            mechanism: .referenceTarget,
            sceneFromCapture: Matrix4x4F(values: [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                dx, 0, 0, 1,
            ]),
            authorityRef: "reference_target:00000000-0000-4000-8000-0000000000ff",
            establishedAtUTC: "2026-09-21T11:00:00Z",
            residualMeters: residualMeters
        )
    }

    func testAsBuiltVerifiedAndDeviated() throws {
        var session = try AsBuiltVerificationSession(
            planID: "plan-9",
            planVersion: "1",
            planSHA256: EvidenceIntegrity.sha256(
                of: Data("plan".utf8)
            ),
            tolerancePolicyRef: "policy-v1",
            coordinateSpaceID: spaceID,
            specs: [try makeSpec()]
        )
        // No alignment: no ghost overlay, no spatial verdict.
        XCTAssertFalse(session.ghostOverlayEnabled)
        let item = try session.item(for: try makeSpec())
        XCTAssertEqual(item.state, .pending)

        session.installAlignment(
            try makeAlignment(residualMeters: 0.005)
        )
        XCTAssertTrue(session.ghostOverlayEnabled)

        // Actual lands 2 cm off the planned spot (alignment shifts
        // world->scene by +0 already applied). Observation uncertainty
        // plus the alignment residual bounds well below tolerance.
        try session.recordActual(
            AsBuiltObservation(
                plannedEntityID: "speaker-l",
                positionWorld: try SpatialVector3F(1.02, 1, 0),
                orientationWorld: try OrientationAxes(
                    frontAxisLocal: .unit(0, 0, -1),
                    upAxisLocal: .unit(0, 1, 0)
                ),
                coordinateSpaceID: spaceID,
                observedAtUTC: "2026-09-21T11:05:00Z",
                uncertainty: try SpatialUncertaintyAuthority(
                    isotropicMeters: 0.005,
                    basis: .instrumentStated
                )
            )
        )
        let verified = try XCTUnwrap(
            try session.items().first
        )
        XCTAssertEqual(verified.state, .verified)
        XCTAssertEqual(
            verified.deviation?.distanceMeters ?? 0,
            0.02,
            accuracy: 1e-4
        )

        // A second item out of tolerance reports deviated.
        var session2 = try AsBuiltVerificationSession(
            planID: "plan-9",
            planVersion: "1",
            planSHA256: EvidenceIntegrity.sha256(
                of: Data("plan".utf8)
            ),
            tolerancePolicyRef: "policy-v1",
            coordinateSpaceID: spaceID,
            specs: [try makeSpec()]
        )
        session2.installAlignment(
            try makeAlignment(residualMeters: 0.005)
        )
        try session2.recordActual(
            AsBuiltObservation(
                plannedEntityID: "speaker-l",
                positionWorld: try SpatialVector3F(1.3, 1, 0),
                coordinateSpaceID: spaceID,
                uncertainty: try SpatialUncertaintyAuthority(
                    isotropicMeters: 0.005,
                    basis: .instrumentStated
                )
            )
        )
        XCTAssertEqual(
            try session2.items().first?.state,
            .deviated
        )
    }

    func testAsBuiltChecklistFallbackWithoutAlignment() throws {
        var session = try AsBuiltVerificationSession(
            planID: "plan-9",
            planVersion: "1",
            planSHA256: EvidenceIntegrity.sha256(
                of: Data("plan".utf8)
            ),
            coordinateSpaceID: spaceID,
            specs: [try makeSpec()]
        )
        try session.recordActual(
            AsBuiltObservation(
                plannedEntityID: "speaker-l",
                positionWorld: try SpatialVector3F(5, 5, 5),
                coordinateSpaceID: spaceID
            )
        )
        // Failed/absent alignment degrades to non-spatial checklist:
        // the observation is preserved but no deviation is produced.
        let item = try XCTUnwrap(try session.items().first)
        XCTAssertEqual(item.state, .captured)
        XCTAssertNotNil(item.observation)
        XCTAssertNil(item.deviation)

        try session.markUnavailable("speaker-l")
        let marked = try XCTUnwrap(try session.items().first)
        XCTAssertEqual(marked.state, .unavailable)
        XCTAssertNil(marked.observation)

        // Document encodes and keeps plan identity immutable.
        let data = try session.package(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: sessionID
        )
        let decoded = try JSONDecoder().decode(
            AsBuiltVerificationDocument.self,
            from: data
        )
        XCTAssertEqual(decoded.planID, "plan-9")
        XCTAssertNil(decoded.alignment)
        XCTAssertEqual(decoded.items.first?.state, .unavailable)
    }

    func testAsBuiltRejectsUnknownAndCrossSpace() throws {
        var session = try AsBuiltVerificationSession(
            planID: "p",
            planVersion: "1",
            planSHA256: EvidenceIntegrity.sha256(
                of: Data("p".utf8)
            ),
            coordinateSpaceID: spaceID,
            specs: [try makeSpec()]
        )
        XCTAssertThrowsError(
            try session.recordActual(
                AsBuiltObservation(
                    plannedEntityID: "nope",
                    positionWorld: try SpatialVector3F(0, 0, 0),
                    coordinateSpaceID: spaceID
                )
            )
        )
        // An observation in another space is rejected — never
        // silently mixed.
        XCTAssertThrowsError(
            try session.recordActual(
                AsBuiltObservation(
                    plannedEntityID: "speaker-l",
                    positionWorld: try SpatialVector3F(0, 0, 0),
                    coordinateSpaceID: CoordinateSpaceID(
                        rawValue: UUID(
                            uuidString:
                                "20000000-0000-4000-8000-0000000000bb"
                        )!
                    )
                )
            )
        )
    }

    // MARK: - legacy bolph71656-ai/HTDT-Capture#293 ghost overlay plan model

    func testAsBuiltOverlayRequiresAlignment() throws {
        let session = try AsBuiltVerificationSession(
            planID: "plan-9",
            planVersion: "1",
            planSHA256: EvidenceIntegrity.sha256(
                of: Data("plan".utf8)
            ),
            coordinateSpaceID: spaceID,
            specs: [try makeSpec()]
        )
        // No explicit authority -> no overlay may be produced; the
        // surface degrades to the non-spatial checklist.
        XCTAssertNil(
            AsBuiltPlanOverlay.model(
                items: try session.items(),
                alignment: session.alignment
            )
        )
    }

    func testAsBuiltOverlayProjectsGhostsAndActuals() throws {
        var session = try AsBuiltVerificationSession(
            planID: "plan-9",
            planVersion: "1",
            planSHA256: EvidenceIntegrity.sha256(
                of: Data("plan".utf8)
            ),
            tolerancePolicyRef: "policy-v1",
            coordinateSpaceID: spaceID,
            specs: [try makeSpec()]
        )
        // sceneFromCapture shifts world -> scene by +0.5 on X, so the
        // planned scene point (1,1,0) lands at world (0.5,1,0).
        session.installAlignment(
            try makeAlignment(dx: 0.5, residualMeters: 0.005)
        )
        try session.recordActual(
            AsBuiltObservation(
                plannedEntityID: "speaker-l",
                positionWorld: try SpatialVector3F(0.53, 1, 0.01),
                coordinateSpaceID: spaceID,
                uncertainty: try SpatialUncertaintyAuthority(
                    isotropicMeters: 0.005,
                    basis: .instrumentStated
                )
            )
        )
        let overlay = try XCTUnwrap(
            AsBuiltPlanOverlay.model(
                items: try session.items(),
                alignment: session.alignment
            )
        )
        let planned = overlay.markers.first {
            $0.kind == .plannedTarget
        }
        let ghost = try XCTUnwrap(planned)
        XCTAssertEqual(ghost.x, 0.5, accuracy: 1e-4)
        XCTAssertEqual(ghost.z, 0, accuracy: 1e-4)
        // Verified state carries the confirmed badge.
        XCTAssertEqual(ghost.reviewStatus, .confirmed)
        XCTAssertTrue(ghost.selectable)
        XCTAssertEqual(
            ghost.identifier, "asbuilt:planned:speaker-l"
        )

        let actual = overlay.markers.first {
            $0.identifier == "asbuilt:actual:speaker-l"
        }
        let actualMarker = try XCTUnwrap(actual)
        // The actual glyph follows the entity-type grammar — a
        // speaker stays a speaker triangle.
        XCTAssertEqual(actualMarker.kind, .speaker)
        XCTAssertEqual(actualMarker.x, 0.53, accuracy: 1e-4)
        XCTAssertEqual(actualMarker.z, 0.01, accuracy: 1e-4)
        XCTAssertEqual(actualMarker.reviewStatus, .nominal)

        // Exactly one planned -> actual deviation connector.
        let connector = try XCTUnwrap(overlay.connectors.first)
        XCTAssertEqual(overlay.connectors.count, 1)
        XCTAssertEqual(connector.startX, ghost.x, accuracy: 1e-6)
        XCTAssertEqual(connector.startZ, ghost.z, accuracy: 1e-6)
        XCTAssertEqual(connector.endX, actualMarker.x, accuracy: 1e-6)
        XCTAssertEqual(connector.endZ, actualMarker.z, accuracy: 1e-6)
        XCTAssertEqual(connector.status, .confirmed)

        // Bounds cover both endpoints with padding.
        XCTAssertLessThanOrEqual(overlay.minX, 0.5)
        XCTAssertGreaterThanOrEqual(overlay.maxX, 0.53)
        XCTAssertTrue(overlay.walls.isEmpty)
    }

    func testAsBuiltOverlayPendingItemHasNoConnector() throws {
        var session = try AsBuiltVerificationSession(
            planID: "plan-9",
            planVersion: "1",
            planSHA256: EvidenceIntegrity.sha256(
                of: Data("plan".utf8)
            ),
            coordinateSpaceID: spaceID,
            specs: [try makeSpec()]
        )
        session.installAlignment(try makeAlignment())
        let overlay = try XCTUnwrap(
            AsBuiltPlanOverlay.model(
                items: try session.items(),
                alignment: session.alignment
            )
        )
        // A pending item renders its ghost marker only — no actual,
        // no connector.
        XCTAssertEqual(overlay.markers.count, 1)
        XCTAssertEqual(
            overlay.markers.first?.kind, .plannedTarget
        )
        XCTAssertEqual(
            overlay.markers.first?.reviewStatus, .pending
        )
        XCTAssertTrue(overlay.connectors.isEmpty)
    }

    // MARK: - manifest integration

    func testSupplementalPathsCarryReservedBindings() throws {
        for path in [
            "derived/geometry-candidates.json",
            "evidence/reference-targets.json",
            "session/capture-task-plan.json",
            "session/connected-spaces.json",
            "session/task-plan-status.json",
            "verification/as-built.json",
        ] {
            let data = Data(#"{"x":1}"#.utf8)
            let binding = BundleReservedPaths.binding(for: path)!
            let entry = try BundleFileEntry(
                path: path,
                bytes: data.count,
                mediaType: "application/json",
                sha256: EvidenceIntegrity.sha256(of: data),
                producer: binding.producer,
                provenanceClass: binding.provenanceClass,
                role: binding.role,
                sourceRefs: binding.role == .derived
                    ? [
                        "capture_session:"
                            + BundleValidationFixture.sessionUUID,
                    ]
                    : nil
            )
            // Manifest accepts the pinned metadata for each path.
            let manifest = try BundleValidationFixture.manifest(
                entries: [entry]
            )
            XCTAssertEqual(manifest.files.count, 1)
        }

        // The derived-candidates path requires non-empty source_refs
        // (role .derived) — an entry without them fails the manifest.
        let data = Data(#"{"x":1}"#.utf8)
        let entry = try BundleFileEntry(
            path: "derived/geometry-candidates.json",
            bytes: data.count,
            mediaType: "application/json",
            sha256: EvidenceIntegrity.sha256(of: data),
            producer: "derived_geometry",
            provenanceClass: .captureAppDerived,
            role: .derived,
            sourceRefs: nil
        )
        XCTAssertThrowsError(
            try BundleValidationFixture.manifest(entries: [entry])
        )
    }
}
