import Foundation
import XCTest
@testable import HTDTCaptureCore

/// TEMPORARY dynamic-verification harness (not for commit): drives a
/// maximal realistic working set through seal + BundleRevisionFinalizer
/// and leaves the produced bundle on disk for the Python validator,
/// reference ingestor, and HTDT contract checks.
final class ZZSeedRecoveredDraftTests: XCTestCase {
    private let outputRoot = URL(fileURLWithPath:
        "/tmp/draft-seed")

    func testSeedEndAcceptedDraft() async throws {
        try? FileManager.default.removeItem(at: outputRoot)
        try FileManager.default.createDirectory(
            at: outputRoot, withIntermediateDirectories: true)
        let working = outputRoot.appendingPathComponent(
            "working", isDirectory: true)

        let context = CaptureSessionContext()
        let sessionID = context.captureSessionID
        let coordinateID = context.coordinateSpaceID
        let store = try CaptureWorkingSetStore(rootDirectory: working)
        let revisionID = try await {
            let s = await store.snapshot()
            return s.identity.captureRevisionID
        }()

        // ---- capture session (foundation + observation stream) ----
        let foundation = try CaptureSessionFoundationPackageBuilder.build(
            context: context,
            capabilities: CaptureCapabilityMatrix(
                roomPlanSupported: true,
                worldTrackingSupported: true,
                sceneReconstructionSupported: true,
                sceneDepthSupported: true,
                smoothedSceneDepthSupported: true,
                highResolutionFrameSupported: false,
                combinedRoomPlanSceneDepthVerified: nil,
                sameSessionDepthAfterRoomPlanStopVerified: nil
            ),
            configurationProfile: CaptureConfigurationProfile(
                captureMode: .roomPlanMesh,
                worldAlignment: "gravity",
                planeDetection: ["vertical", "horizontal"],
                sceneReconstruction: "mesh_with_classification",
                frameSemantics: ["scene_depth"],
                videoFormat: VideoFormatDescriptor(
                    width: 1920, height: 1440, framesPerSecond: 60),
                autofocusEnabled: true,
                roomPlanOptions: [:]
            ),
            startedAtUTC: "2026-10-01T01:00:00Z",
            device: try CaptureDeviceDocument(
                osVersion: "iOS 20.0",
                hardwareModel: "iPhone99,1",
                appVersion: "0.1.0",
                appBuild: "1"
            )
        )
        try await store.persistSessionFoundation(foundation)

        // Observation stream: normal → unavailable(7s) → recovered,
        // ≥10s stable after → 1.2.0 recovery policy emits a warning
        // and still passes.
        for event in [
            TrackingQualityEvent(sessionTimestampSeconds: 1, state: .normal),
            TrackingQualityEvent(sessionTimestampSeconds: 5, state: .unavailable,
                                 reason: "excessive_motion"),
            TrackingQualityEvent(sessionTimestampSeconds: 12, state: .normal),
            TrackingQualityEvent(sessionTimestampSeconds: 25, state: .normal),
        ] {
            await store.recordTrackingEvent(event)
        }
        let meshAnchorID = UUID()
        await store.recordMeshAnchorLifecycle(
            .added, anchorID: meshAnchorID, sessionTimestampSeconds: 1)
        await store.recordResourceEvent(CaptureResourceEvent(
            kind: .memoryPressure, severity: .warning,
            detail: "transient memory pressure at second 30"))

        let runtime = CaptureRuntimeProvenance(
            osVersion: "test-os", appVersion: "0.1.0", appBuild: "test")
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data(#"{"raw":true}"#.utf8),
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            runtime: runtime)
        let lineage = RoomPlanEvidenceArtifactBuilder.attachProcessed(
            data: Data(#"{"processed":true}"#.utf8), to: raw)

        await store.recordAdvisoryEndContext(
            CaptureEndCoverageSummary(
                algorithm: "fixture",
                algorithmVersion: "1.0.0",
                endSessionTimestampSeconds: 26,
                sectorCount: 12,
                minimumSamplesPerCell: 2,
                cellSampleCounts: Array(repeating: 2, count: 36),
                coverageFraction: 1,
                pitchBandFractions: [:],
                weakCells: [],
                latestTrackingState: .normal,
                latestTrackingReason: nil,
                latestMeshAnchorCount: 1,
                latestHasSceneDepth: true,
                spatialCellSizeMeters: 0.5,
                observedRegionCount: 1,
                weakRegionCount: 0,
                displayUnknownRegionCount: 0,
                usesDepthFallback: false,
                meshAvailabilityState: "anchorsObserved",
                weakRegionKeys: [],
                geometryEvidenceMode: "mesh_and_depth",
                movementCapability: "unrestricted",
                guidanceCompletedAttempts: 0,
                guidanceMaximumAttempts: 4,
                actionableWeakRegionCount: 0,
                saturatedWeakRegionCount: 0,
                guidanceComplete: true,
                viewpointDiversitySemantics: "azimuth_elevation_3d",
                verticalCellSizeMeters: 0.3,
                verticalVoxelCount: 8,
                verticalObservedVoxelCount: 8,
                verticalWeakVoxelCount: 0,
                verticalWeakVoxelKeys: [],
                verticalBandSummaries: [
                    "middle": CaptureVerticalBandSummary(
                        voxelCount: 8, observedCount: 8, weakCount: 0
                    ),
                ],
                guidanceCompletionSource:
                    ScanGuidanceCompletionSource.observed.rawValue,
                remoteWeakRegionCount: 0,
                spatialMaxRegionCount: 256,
                spatialPeakRegionCount: 1,
                spatialRegionEvictionCount: 0,
                spatialCapacitySaturated: false,
                directionReference: StartRelativeDirection.convention
            ))
        try await store.persistEndRoomPlanTransaction(
            timingPackage: try CaptureTimingPackageBuilder.build(
                start: try CaptureTimingCorrelation(
                    monotonicSeconds: 1.0,
                    utc: "2026-10-01T01:00:00Z", method: "fixture"),
                end: try CaptureTimingCorrelation(
                    monotonicSeconds: 26.0,
                    utc: "2026-10-01T01:00:25Z", method: "fixture")),
            roomPlanLineage: lineage)

        // ---- spatial evidence ----
        let geometry = try MeshGeometryPayload(
            vertices: [
                Float3(0, 0, 0), Float3(1, 0, 0), Float3(0, 1, 0),
            ],
            triangleIndices: [0, 1, 2])
        let mesh = try MeshEvidencePackageBuilder.build(snapshots: [
            MeshAnchorSnapshot(
                anchorID: meshAnchorID,
                captureSessionID: sessionID,
                coordinateSpaceID: coordinateID,
                worldFromAnchor: .identity,
                sessionTimestampSeconds: 1,
                geometry: geometry),
        ])
        try await store.persistMeshPackage(mesh)

        // Frame 1: full pixel+depth+confidence.
        let pixel = try BundleValidationFixture.pixelPayload(
            width: 1, height: 1)
        let depth = try BundleValidationFixture.depthPayload(
            width: 32, height: 32)
        let confidence = try BundleValidationFixture.confidencePayload(
            width: 32, height: 32)
        let frameID = EvidenceFrameID()
        let depthPath = "evidence/depth/\(frameID).depthbin"
        let confidencePath = "evidence/depth/\(frameID).confidencebin"
        let descriptor1 = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            sessionTimestampSeconds: 3,
            worldFromCamera: .identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [1, 0, 0, 0, 1, 0, 0, 0, 1]),
            imageWidth: 1, imageHeight: 1,
            pixelFormatFourCC: 0x34323066,
            pixelRelativePath: "evidence/frames/\(frameID).pixelbin",
            pixelByteCount: pixel.count,
            pixelSHA256: EvidenceIntegrity.sha256(of: pixel),
            depthStatus: .capturedSmoothed,
            depth: try DepthEvidenceReference(
                kind: .smoothedSceneDepth,
                depthRelativePath: depthPath,
                depthByteCount: depth.count,
                depthSHA256: EvidenceIntegrity.sha256(of: depth),
                confidenceRelativePath: confidencePath,
                confidenceByteCount: confidence.count,
                confidenceSHA256:
                    EvidenceIntegrity.sha256(of: confidence)))
        try await store.persistFramePackage(
            try FrameEvidencePackageBuilder.build(
                descriptor: descriptor1,
                pixelPayload: pixel,
                depthPayload: depth,
                confidencePayload: confidence))

        // Frame 2: pixel only.
        let pixel2 = try BundleValidationFixture.pixelPayload(
            width: 1, height: 1)
        let frameID2 = EvidenceFrameID()
        let descriptor2 = try FrameEvidenceDescriptor(
            frameID: frameID2,
            captureSessionID: sessionID,
            coordinateSpaceID: coordinateID,
            sessionTimestampSeconds: 9,
            worldFromCamera: .identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [1, 0, 0, 0, 1, 0, 0, 0, 1]),
            imageWidth: 1, imageHeight: 1,
            pixelFormatFourCC: 0x34323066,
            pixelRelativePath: "evidence/frames/\(frameID2).pixelbin",
            pixelByteCount: pixel2.count,
            pixelSHA256: EvidenceIntegrity.sha256(of: pixel2),
            depthStatus: .unavailable)
        try await store.persistFramePackage(
            try FrameEvidencePackageBuilder.build(
                descriptor: descriptor2,
                pixelPayload: pixel2,
                depthPayload: nil,
                confidencePayload: nil))

        // ---- semantic / derived payloads (Review-time app order) ----
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try AnnotationEvidencePackageBuilder.build(
                entities: [
                    try CaptureAnnotationEntity(
                        type: .speaker,
                        coordinateSpaceID: coordinateID,
                        worldFromAnnotation: .identity,
                        referencePointSemantics: .cabinetReferencePoint,
                        label: "speaker:L",
                        provenanceClass: .userAnnotation,
                        placement: PlacementProvenance(
                            method: .manualNumeric),
                        channelRole: ChannelRole(rawValue: "L")),
                    try CaptureAnnotationEntity(
                        type: .speaker,
                        coordinateSpaceID: coordinateID,
                        worldFromAnnotation: .identity,
                        referencePointSemantics: .cabinetReferencePoint,
                        label: "speaker:C",
                        provenanceClass: .userAnnotation,
                        placement: PlacementProvenance(
                            method: .manualNumeric),
                        channelRole: ChannelRole(rawValue: "C")),
                    try CaptureAnnotationEntity(
                        type: .speaker,
                        coordinateSpaceID: coordinateID,
                        worldFromAnnotation: .identity,
                        referencePointSemantics: .cabinetReferencePoint,
                        label: "speaker:R",
                        provenanceClass: .userAnnotation,
                        placement: PlacementProvenance(
                            method: .manualNumeric),
                        channelRole: ChannelRole(rawValue: "R")),
                    try CaptureAnnotationEntity(
                        type: .listeningPosition,
                        coordinateSpaceID: coordinateID,
                        worldFromAnnotation: .identity,
                        referencePointSemantics: .earCenter,
                        label: "listening_position:MLP",
                        provenanceClass: .userAnnotation,
                        placement: PlacementProvenance(
                            method: .manualNumeric),
                        listeningRole: .primary),
                ]),
            measurementPackage: try MeasurementEvidencePackageBuilder
                .build(measurements: [
                    try CaptureMeasurement(
                        quantityType: "room_width",
                        value: .scalar(4.2),
                        unit: .meter,
                        acquisitionMethod: .laserDistanceMeter,
                        userAttestation: .attested,
                        provenanceClass: .userAttestedMeasurement),
                ]))

        try await store.persistOrReplaceAuthorityDependencies(
            try ExternalAuthorityDependencyPackage(
                manifest: try ExternalAuthorityDependencyBuilder.manifest(
                    entities: [],
                    catalog: nil,
                    generatedAtUTC: "2026-10-01T01:00:30Z")))

        try await store.persistCaptureStrategy(
            try CaptureStrategyPackageBuilder.build(
                document: CaptureStrategyDocument(
                    captureRevisionID: revisionID,
                    captureSessionID: sessionID,
                    coordinateSpaceID: coordinateID,
                    profile: CaptureStrategyCatalog.profile(for: .standard),
                    source: .operatorSelected,
                    selectedAtUTC: "2026-10-01T01:00:31Z")))

        try await store.recordTaskProfile(.theaterLayout)
        try await store.recordBenchmarkReferences([])
        // ZZTEST: advisory notes intentionally omitted — the canonical
        // `advisory/operator-advisories.json` writer is write-once
        // (AtomicCaptureFileWriter.writeIfIdentical throws
        // alreadyExists on differing bytes), so pre-seeding any note
        // would prevent observing legacy bolph71656-ai/HTDT-Capture#275 highResolutionStill notes
        // landing on disk during simulator verification.
        try await store.recordFieldNote(try CaptureFieldNote(
            captureRevisionID: revisionID,
            category: .roomCondition,
            text: "Glass wall on the north side"))

        // ---- bound capture mission (plan + status docs) ----
        let planJSON = #"""
        {
          "schema": "htdt.capture-task-plan",
          "schema_version": "1.0.0",
          "plan_id": "plan-verify-001",
          "plan_version": "1.0.0",
          "project_ref": "proj-deep-verify",
          "room_name": "Theater Room",
          "issued_at": "2026-10-01T00:30:00Z",
          "entity_checklist": [
            {"item_id":"e1","entity_type":"speaker","requirement":"required","channel_role":"L"},
            {"item_id":"e2","entity_type":"subwoofer","requirement":"optional"}
          ],
          "measurement_requests": [
            {"item_id":"m1","quantity_type":"room_width","requirement":"required","expected_unit":"m"}
          ],
          "surface_review_tasks": [
            {"item_id":"s1","surface_kind":"screen_wall","requirement":"optional"}
          ],
          "evidence_targets": [],
          "expected_channel_roles": ["L","C","R"]
        }
        """#
        let planData = Data(planJSON.utf8)
        try await store.persistSupplementalDocument(
            WorkingSetSupplementalDocument(
                path: CaptureTaskPlanImport.path,
                data: planData,
                declaration: BundlePayloadDeclaration(
                    path: CaptureTaskPlanImport.path,
                    mediaType: "application/json",
                    producer: "htdt_plan",
                    provenanceClass: .importedReference,
                    role: .canonical),
                coordinateSpaceIDs: [coordinateID],
                captureSessionIDs: [sessionID]))
        let taskPlanStatus = CaptureTaskPlanStatus(
            planImport: try CaptureTaskPlanImport(data: planData))
        try await store.persistSupplementalDocument(
            WorkingSetSupplementalDocument(
                path: CaptureTaskPlanStatusDocument.path,
                data: try taskPlanStatus.statusPackage(
                    captureRevisionID: revisionID,
                    captureSessionID: sessionID,
                    annotations: [],
                    measurements: []),
                declaration: BundlePayloadDeclaration(
                    path: CaptureTaskPlanStatusDocument.path,
                    mediaType: "application/json",
                    producer: "capture_session",
                    provenanceClass: .captureAppDerived,
                    role: .canonical),
                coordinateSpaceIDs: [coordinateID],
                captureSessionIDs: [sessionID]))

        // Revisit-flags canonical supplemental doc (app writes on flag ops).
        var flagStore = CaptureRevisitFlagStore()
        _ = flagStore.add(ScanRevisitFlag(
            coordinateSpaceID: coordinateID,
            captureSessionID: sessionID,
            targetPointWorld: ScanRevisitFlagVector(x: 1, y: 1, z: 1),
            targetFromRaycast: true,
            cameraPositionWorld: ScanRevisitFlagVector(x: 0, y: 1.5, z: 0),
            cameraForwardWorld: ScanRevisitFlagVector(x: 0, y: 0, z: -1),
            coverageCell: "2,3",
            category: .geometry,
            note: "Dark corner",
            createdSessionTimestampSeconds: 21))
        let flagDoc = flagStore.document(captureRevisionID: revisionID)
        try await store.persistSupplementalDocument(
            WorkingSetSupplementalDocument(
                path: CaptureRevisitFlagDocument.path,
                data: try flagDoc.encoded(),
                declaration: BundlePayloadDeclaration(
                    path: CaptureRevisitFlagDocument.path,
                    mediaType: "application/json",
                    producer: "capture_session",
                    provenanceClass: .captureAppDerived,
                    role: .canonical),
                coordinateSpaceIDs: [coordinateID],
                captureSessionIDs: [sessionID]))

        // Derived geometry candidates (derived role + path: refs).
        let proxy = DerivedShapeProxy(
            resolution: .resolved,
            selected: DerivedShapeCandidate(
                geometry: .orientedRectangle(
                    DerivedOrientedRectangle(
                        center: DerivedPoint2D(x: 1, y: 2),
                        width: 3, depth: 4, headingRadians: 0.5)),
                metrics: DerivedShapeFitMetrics(
                    normalizedResidual: 0.1,
                    supportScore: 0.8,
                    fitScore: 0.9)),
            candidates: [],
            provenance: DerivedShapeProvenance(
                sourceEvidenceRefs: ["mesh_anchor:\(meshAnchorID)"],
                sourceCoordinateSpaceID: coordinateID,
                derivationAlgorithm: "wall-fit",
                derivationVersion: "1.0.0",
                fitScore: 0.9,
                normalizedResidual: 0.1,
                observationStartSeconds: 1,
                observationEndSeconds: 5),
            observationSample: [
                DerivedObservationPoint(
                    position: DerivedPoint2D(x: 0, y: 0),
                    evidenceRef: "mesh_anchor:\(meshAnchorID)",
                    evidenceKind: .mesh),
            ])
        let circular = DerivedShapeProxy(
            resolution: .resolved,
            selected: DerivedShapeCandidate(
                geometry: .circle(
                    DerivedCircle(
                        center: DerivedPoint2D(x: 2, y: 2),
                        radius: 0.4)),
                metrics: DerivedShapeFitMetrics(
                    normalizedResidual: 0.15,
                    supportScore: 0.75,
                    fitScore: 0.85)),
            candidates: [],
            provenance: DerivedShapeProvenance(
                sourceEvidenceRefs: ["path:\(depthPath)"],
                sourceCoordinateSpaceID: coordinateID,
                derivationAlgorithm: "targeted-object-fit",
                derivationVersion: "1.0.0",
                fitScore: 0.85,
                normalizedResidual: 0.15,
                observationStartSeconds: 10,
                observationEndSeconds: 14),
            observationSample: [
                DerivedObservationPoint(
                    position: DerivedPoint2D(x: 2, y: 2),
                    evidenceRef: "path:\(depthPath)",
                    evidenceKind: .sceneDepth),
            ])
        let snapshot = await store.snapshot()
        var sourceRefs = snapshot.payloadDeclarations
            .map(\.path)
            .filter {
                $0 == MeshEvidencePackage.indexPath
                    || ($0.hasPrefix("evidence/depth/")
                            && $0.hasSuffix(".depthbin"))
            }
            .sorted(by: BundleLogicalPath.utf8Less)
            .map { "path:" + $0 }
        if sourceRefs.count > BundleManifest.maxSourceRefsPerEntry {
            sourceRefs = Array(sourceRefs.prefix(
                BundleManifest.maxSourceRefsPerEntry))
        }
        XCTAssertFalse(sourceRefs.isEmpty)
        let built = try DerivedGeometryCandidatePackageBuilder.build(
            snapshot: DerivedShapePreviewSnapshot(
                objectProxies: [proxy, circular]),
            captureRevisionID: revisionID,
            captureSessionID: sessionID,
            sourcePayloadRefs: sourceRefs)
        try await store.persistSupplementalDocument(
            try WorkingSetSupplementalDocument(
                path: DerivedGeometryCandidatePackage.path,
                data: built.package.data,
                declaration: built.declaration,
                coordinateSpaceIDs: [coordinateID],
                captureSessionIDs: [sessionID]))

        // Draft stays in `end_accepted` — NOT sealed/finalized — so the
        // app sees a recoverable working revision on next launch.
        let snap = await store.snapshot()
        NSLog("ZZ-SEED draft revision \(snap.identity.captureRevisionID) at \(working.path)")
    }
}
