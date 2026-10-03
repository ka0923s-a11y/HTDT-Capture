import Foundation
import Testing
@testable import HTDTCaptureCore

/// Coverage for issue bolph71656-ai/HTDT-Capture#268: the reference-object asset manifest,
/// per-mission selection policy, bounded observation buffer, and the
/// canonical `evidence/reference-object-observations.json` document.
struct ReferenceObjectCaptureTests {
    private func makeAsset(
        id: String = "pump_a",
        name: String = "pump_a_v1",
        roles: [ReferenceObjectAssetRole] = [.detection]
    ) throws -> ReferenceObjectAsset {
        try ReferenceObjectAsset(
            assetID: ReferenceObjectAssetID(validating: id)!,
            revision: 1,
            arkitObjectName: name,
            artifactFilename: "\(name).referenceobject",
            artifactSHA256: String(repeating: "a", count: 64),
            sourceUSDZ: ReferenceObjectSourceArtifact(
                uri: "models/pump_a.usdz",
                sha256: String(repeating: "b", count: 64),
                revision: "r1"
            ),
            physicalBinding: "Pump A — mechanical room east wall",
            measuredDimensionsM: SpatialVector3F(0.42, 0.31, 0.28),
            scaleValidationMethod:
                "caliper dims vs USDZ bounding box, ±2%",
            training: ReferenceObjectTrainingProvenance(
                createMLVersion: "27.0",
                xcodeVersion: "27.0",
                trainingMode: .standard,
                viewingAngleConfig: "all",
                negativeExampleSetRef: "negatives/mech-room-v1",
                referenceObjectStripUSDZ: true
            ),
            supportedRoles: roles,
            markerToEquipment: nil,
            licenseProvenance: "internal scan, no third-party model"
        )
    }

    private func makeObservation(
        anchor: UUID,
        session: CaptureSessionID,
        space: CoordinateSpaceID,
        timestamp: Double,
        mode: ReferenceObjectObservationMode = .tracking,
        event: ReferenceObjectLifecycleEvent = .updated,
        tracked: Bool? = true
    ) throws -> ReferenceObjectPoseObservation {
        try ReferenceObjectPoseObservation(
            captureSessionID: session,
            coordinateSpaceID: space,
            sessionTimestampSeconds: timestamp,
            arAnchorID: anchor,
            referenceObjectID: "pump_a",
            referenceObjectRevision: 1,
            referenceObjectDigestSHA256:
                String(repeating: "a", count: 64),
            tWorldFromReferenceObject: Matrix4x4F(
                values: [
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    0.1, 0.2, 0.3, 1,
                ]
            ),
            observationMode: mode,
            lifecycleEvent: event,
            isCurrentlyTracked: tracked
        )
    }

    @Test
    func assetManifestRoundTripsAndLooksUp() throws {
        let manifest = try ReferenceObjectAssetManifest(
            assets: [
                makeAsset(),
                makeAsset(
                    id: "valve_b",
                    name: "valve_b_v2",
                    roles: [.detection, .tracking]
                ),
            ]
        )
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(
            ReferenceObjectAssetManifest.self,
            from: data
        )
        #expect(decoded.schema == "htdt.capture.reference-object-assets")
        #expect(decoded.schemaVersion == "1.0.0")
        #expect(decoded.assets.count == 2)
        #expect(
            decoded.asset(
                for: ReferenceObjectAssetID(validating: "pump_a")!
            )?.arkitObjectName == "pump_a_v1"
        )
        #expect(
            decoded.asset(arkitObjectName: "valve_b_v2")?.assetID
                .rawValue == "valve_b"
        )
        #expect(decoded.asset(arkitObjectName: "absent") == nil)
    }

    @Test
    func assetValidationRejectsBadInputs() throws {
        #expect(ReferenceObjectAssetID(validating: "Pump_A") == nil)
        #expect(ReferenceObjectAssetID(validating: "1pump") == nil)
        #expect(throws: (any Error).self) {
            try ReferenceObjectAsset(
                assetID: ReferenceObjectAssetID(validating: "pump_a")!,
                revision: 1,
                arkitObjectName: "pump_a_v1",
                artifactFilename: "pump_a_v1.referenceobject",
                artifactSHA256: "nothex",
                sourceUSDZ: ReferenceObjectSourceArtifact(
                    uri: nil,
                    sha256: String(repeating: "b", count: 64),
                    revision: nil
                ),
                physicalBinding: "Pump A",
                measuredDimensionsM: SpatialVector3F(1, 1, 1),
                scaleValidationMethod: "x",
                training: ReferenceObjectTrainingProvenance(
                    createMLVersion: nil,
                    xcodeVersion: nil,
                    trainingMode: .standard,
                    viewingAngleConfig: "all",
                    negativeExampleSetRef: nil,
                    referenceObjectStripUSDZ: false
                ),
                supportedRoles: [.detection],
                markerToEquipment: nil,
                licenseProvenance: "internal"
            )
        }
    }

    @Test
    func selectionPolicyDedupesCapsAndRejects() throws {
        var assets = try (0..<12).map {
            try makeAsset(
                id: "obj_\($0)",
                name: "obj_\($0)_v1",
                roles: [.detection]
            )
        }
        // A detection-only asset whose tracking request is rejected
        // for the role — not deduped (it was never selected).
        assets.append(
            try makeAsset(
                id: "tracker_x",
                name: "tracker_x_v1",
                roles: [.detection]
            )
        )
        let manifest = try ReferenceObjectAssetManifest(assets: assets)
        var requests = assets.dropLast().map {
            ReferenceObjectSelectionRequest(
                assetID: $0.assetID,
                role: .detection
            )
        }
        // Duplicate of obj_0 and an unknown id and a role violation.
        requests.append(
            ReferenceObjectSelectionRequest(
                assetID: assets[0].assetID,
                role: .detection
            )
        )
        requests.append(
            ReferenceObjectSelectionRequest(
                assetID: ReferenceObjectAssetID(validating: "nope")!,
                role: .detection
            )
        )
        requests.append(
            ReferenceObjectSelectionRequest(
                assetID: assets[12].assetID,
                role: .tracking
            )
        )
        let plan = ReferenceObjectSelectionPolicy.resolve(
            requests: requests,
            manifest: manifest
        )
        #expect(plan.selected.count == 10)
        let reasons = plan.rejected.map(\.reason)
        #expect(reasons.contains(.duplicateAsset))
        #expect(reasons.contains(.unknownAsset))
        #expect(reasons.contains(.unsupportedRole))
        #expect(
            reasons.filter { $0 == .capExceeded }.count == 2
        )
        // Deterministic: first-seen order retained.
        #expect(plan.selected[0].assetID == assets[0].assetID)
    }

    @Test
    func observationValidatesAndStampsEvidenceToken() throws {
        let session = CaptureSessionID()
        let space = CoordinateSpaceID()
        let anchor = UUID()
        let observation = try makeObservation(
            anchor: anchor,
            session: session,
            space: space,
            timestamp: 12.5,
            event: .added
        )
        #expect(
            observation.evidenceRefToken
                == "reference_object_observation:"
                    + observation.observationID.description
        )
        #expect(throws: (any Error).self) {
            try makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: -1
            )
        }
        #expect(throws: (any Error).self) {
            try ReferenceObjectPoseObservation(
                captureSessionID: session,
                coordinateSpaceID: space,
                sessionTimestampSeconds: 1,
                arAnchorID: anchor,
                referenceObjectID: "",
                referenceObjectRevision: 1,
                referenceObjectDigestSHA256: nil,
                tWorldFromReferenceObject: Matrix4x4F(
                    values: [
                        1, 0, 0, 0, 0, 1, 0, 0,
                        0, 0, 1, 0, 0, 0, 0, 1,
                    ]
                ),
                observationMode: .detection,
                lifecycleEvent: .added,
                isCurrentlyTracked: nil
            )
        }
    }

    @Test
    func bufferCoalescesUpdatesAndRecordsTrackedFlips() throws {
        let session = CaptureSessionID()
        let space = CoordinateSpaceID()
        let anchor = UUID()
        var buffer = ReferenceObjectObservationBuffer()
        try buffer.record(
            makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: 1,
                event: .added
            ),
            kind: .added
        )
        for tick in 1...3 {
            try buffer.record(
                makeObservation(
                    anchor: anchor,
                    session: session,
                    space: space,
                    timestamp: Double(tick) + 0.5,
                    event: .updated,
                    tracked: true
                ),
                kind: .updated
            )
        }
        // isTracked loss: a lifecycle record, not anchor removal.
        try buffer.record(
            makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: 4.5,
                tracked: false
            ),
            kind: .updated
        )
        try buffer.record(
            makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: 5.0,
                tracked: true
            ),
            kind: .updated
        )
        try buffer.record(
            makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: 9,
                event: .removed,
                tracked: nil
            ),
            kind: .removed
        )
        let docs = buffer.documentObservations()
        let events = docs.map(\.lifecycleEvent)
        #expect(events.contains(.added))
        #expect(events.contains(.updated))
        #expect(events.contains(.trackingLost))
        #expect(events.contains(.trackingResumed))
        #expect(events.contains(.removed))
        // Three steady updates coalesced into one record.
        #expect(
            docs.filter { $0.lifecycleEvent == .updated }.count == 1
        )
        #expect(docs.count == 5)
        #expect(buffer.truncatedRecordCount == 0)
        // After removal a fresh update starts a new record.
        try buffer.record(
            makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: 10,
                tracked: true
            ),
            kind: .updated
        )
        #expect(buffer.documentObservations().count == 6)
    }

    @Test
    func bufferRestoresFromDocumentForReopenedDraft() throws {
        let session = CaptureSessionID()
        let space = CoordinateSpaceID()
        let anchor = UUID()
        var buffer = ReferenceObjectObservationBuffer()
        buffer.setConfiguration(
            selection: ReferenceObjectSelectionEcho(
                requested: [
                    ReferenceObjectSelectionRequest(
                        assetID: ReferenceObjectAssetID(
                            validating: "pump_a"
                        )!,
                        role: .tracking
                    ),
                ],
                dropped: []
            ),
            configuredAssets: [
                ReferenceObjectConfiguredAsset(
                    asset: try makeAsset(roles: [.tracking]),
                    role: .tracking,
                    loadOutcome: .loaded,
                    loadDetail: nil
                ),
            ]
        )
        try buffer.record(
            makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: 2,
                event: .added
            ),
            kind: .added
        )
        try buffer.record(
            makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: 3,
                tracked: true
            ),
            kind: .updated
        )
        let package = try ReferenceObjectObservationBuilder.build(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: session,
            coordinateSpaceID: space,
            appliedBeforeCoordinateBinding: true,
            selection: buffer.selection!,
            configuredAssets: buffer.configuredAssets,
            observations: buffer.documentObservations(),
            truncatedObservationCount: buffer.truncatedRecordCount
        )
        let document = try JSONDecoder().decode(
            ReferenceObjectObservationDocument.self,
            from: package.data
        )
        var restored = ReferenceObjectObservationBuffer(
            restoring: document
        )
        // The restored buffer still coalesces the same anchor's
        // steady updates instead of appending duplicates.
        try restored.record(
            makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: 4,
                tracked: true
            ),
            kind: .updated
        )
        #expect(restored.documentObservations().count == 2)
        // And it still detects tracked flips from restored state.
        try restored.record(
            makeObservation(
                anchor: anchor,
                session: session,
                space: space,
                timestamp: 5,
                tracked: false
            ),
            kind: .updated
        )
        #expect(
            restored.documentObservations().last?.lifecycleEvent
                == .trackingLost
        )
    }

    @Test
    func bufferTruncationCountsHonestly() throws {
        let session = CaptureSessionID()
        let space = CoordinateSpaceID()
        var buffer = ReferenceObjectObservationBuffer()
        let limit = ReferenceObjectObservationBuffer.recordLimit
        for tick in 0..<(limit + 3) {
            try buffer.record(
                makeObservation(
                    anchor: UUID(),
                    session: session,
                    space: space,
                    timestamp: Double(tick),
                    event: .added,
                    tracked: nil
                ),
                kind: .added
            )
        }
        #expect(buffer.records.count == limit)
        #expect(buffer.truncatedRecordCount == 3)
    }

    @Test
    func documentBuildValidatesAgainstPublishedSchema() throws {
        let session = CaptureSessionID()
        let space = CoordinateSpaceID()
        let revision = CaptureRevisionID()
        let anchor = UUID()
        let observation = try makeObservation(
            anchor: anchor,
            session: session,
            space: space,
            timestamp: 7.25,
            event: .added
        )
        let package = try ReferenceObjectObservationBuilder.build(
            captureRevisionID: revision,
            captureSessionID: session,
            coordinateSpaceID: space,
            appliedBeforeCoordinateBinding: true,
            selection: ReferenceObjectSelectionEcho(
                requested: [
                    ReferenceObjectSelectionRequest(
                        assetID: ReferenceObjectAssetID(
                            validating: "pump_a"
                        )!,
                        role: .tracking
                    ),
                ],
                dropped: [
                    ReferenceObjectRejectedSelection(
                        assetID: ReferenceObjectAssetID(
                            validating: "nope"
                        )!,
                        reason: .unknownAsset
                    ),
                ]
            ),
            configuredAssets: [
                ReferenceObjectConfiguredAsset(
                    asset: makeAsset(roles: [.tracking]),
                    role: .tracking,
                    loadOutcome: .loaded,
                    loadDetail: nil
                ),
            ],
            observations: [observation],
            truncatedObservationCount: 0
        )
        #expect(
            ReferenceObjectObservationPackage.path
                == "evidence/reference-object-observations.json"
        )
        #expect(
            CaptureBundleSchemaRegistry.schemaName(
                forPath: ReferenceObjectObservationPackage.path
            ) == "reference-object-observations"
        )
        let parsed = try StrictJSON.parse(package.data)
        let violation = JSONSchemaValidator.validate(
            parsed,
            schema: try CaptureBundleSchemaRegistry.compiledSchema(
                named: "reference-object-observations"
            )
        )
        #expect(violation == nil)
        let decoded = try JSONDecoder().decode(
            ReferenceObjectObservationDocument.self,
            from: package.data
        )
        #expect(decoded.appliedBeforeCoordinateBinding)
        #expect(decoded.observations == [observation])
        #expect(decoded.selection.dropped.count == 1)
    }

    @Test
    func reviewDiagnosticsSurfaceLoadAndSelectionProblems() throws {
        let document = try ReferenceObjectObservationDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            appliedBeforeCoordinateBinding: true,
            selection: ReferenceObjectSelectionEcho(
                requested: [],
                dropped: [
                    ReferenceObjectRejectedSelection(
                        assetID: ReferenceObjectAssetID(
                            validating: "obj_x"
                        )!,
                        reason: .capExceeded
                    ),
                ]
            ),
            configuredAssets: [
                ReferenceObjectConfiguredAsset(
                    asset: makeAsset(),
                    role: .detection,
                    loadOutcome: .unavailable,
                    loadDetail: "artifact not found in bundle"
                ),
            ],
            observations: [],
            truncatedObservationCount: 2
        )
        let diagnostics =
            ReferenceObjectObservationBuilder.reviewDiagnostics(
                for: document
            )
        let codes = diagnostics.map(\.code)
        #expect(codes.contains("reference_object_load_outcome"))
        #expect(codes.contains("reference_object_selection_dropped"))
        #expect(
            codes.contains("reference_object_observations_truncated")
        )
        #expect(
            diagnostics.first {
                $0.code == "reference_object_load_outcome"
            }?.severity == .warning
        )
    }

    /// The shipped `App/ReferenceObjects/manifest.json` must keep
    /// decoding — the same decode the app loader performs at setup
    /// time is the in-repo gate for the catalog file.
    @Test func shippedAssetManifestDecodes() throws {
        let url = URL(
            fileURLWithPath: "App/ReferenceObjects/manifest.json"
        )
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(
            ReferenceObjectAssetManifest.self,
            from: data
        )
        #expect(manifest.schema == "htdt.capture.reference-object-assets")
    }

    /// Store-level regression: every lifecycle record must reach the
    /// persisted document — the accumulating payload requires a
    /// replace-capable write, or the second record is dropped.
    @Test func storePersistsEveryLifecycleRecord() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let context = CaptureSessionContext()
        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistSessionFoundation(
            CaptureSessionFoundationPackageBuilder.build(
                context: context,
                capabilities: CaptureCapabilityMatrix(
                    roomPlanSupported: true,
                    worldTrackingSupported: true,
                    sceneReconstructionSupported: true,
                    sceneDepthSupported: true
                ),
                configurationProfile: CaptureConfigurationProfile(
                    captureMode: .roomPlanMesh,
                    worldAlignment: "gravity",
                    sceneReconstruction: "mesh"
                ),
                startedAtUTC: "2026-09-20T01:00:00Z",
                device: try CaptureDeviceDocument(
                    osVersion: "iOS 20.0",
                    hardwareModel: "iPhone99,1",
                    appVersion: "0.1.0",
                    appBuild: "1"
                )
            )
        )

        let anchor = UUID()
        try await store.recordReferenceObjectObservation(
            makeObservation(
                anchor: anchor,
                session: context.captureSessionID,
                space: context.coordinateSpaceID,
                timestamp: 1,
                event: .added
            ),
            kind: .added
        )
        try await store.recordReferenceObjectObservation(
            makeObservation(
                anchor: anchor,
                session: context.captureSessionID,
                space: context.coordinateSpaceID,
                timestamp: 2,
                event: .updated,
                tracked: false
            ),
            kind: .updated
        )

        let url = root.appendingPathComponent(
            ReferenceObjectObservationPackage.path
        )
        let decoded = try JSONDecoder().decode(
            ReferenceObjectObservationDocument.self,
            from: Data(contentsOf: url)
        )
        #expect(
            decoded.observations.map(\.lifecycleEvent)
                == [.added, .trackingLost]
        )
    }
}
