import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Unit coverage for the workflow/storage stragglers: capture
/// strategy profiles (legacy bolph71656-ai/HTDT-Capture#307), active-capture storage advisory (legacy bolph71656-ai/HTDT-Capture#308),
/// acquisition origin records (legacy bolph71656-ai/HTDT-Capture#317), semantic child revisions
/// (legacy bolph71656-ai/HTDT-Capture#319), and plan reference underlays (legacy bolph71656-ai/HTDT-Capture#322).
final class StragglerWorkflowTests: XCTestCase {

    // MARK: legacy bolph71656-ai/HTDT-Capture#307 capture strategy profiles

    func testStrategyCatalogPublishesAllProfiles() {
        XCTAssertEqual(
            CaptureStrategyIdentifier.allCases,
            [.quickScan, .standard, .detailed, .commissioning]
        )
        XCTAssertEqual(
            CaptureStrategyCatalog.orderedProfiles.map(
                \.identifier
            ),
            CaptureStrategyIdentifier.allCases
        )
        for identifier in CaptureStrategyIdentifier.allCases {
            let profile = CaptureStrategyCatalog.profile(
                for: identifier
            )
            XCTAssertEqual(profile.identifier, identifier)
            XCTAssertFalse(profile.policyVersion.isEmpty)
            XCTAssertFalse(profile.displayName.isEmpty)
        }
        XCTAssertEqual(
            CaptureStrategyCatalog.identifier(
                forPersistedValue: "quick_scan"
            ),
            .quickScan
        )
        XCTAssertNil(
            CaptureStrategyCatalog.identifier(
                forPersistedValue: "no_such_strategy"
            )
        )
    }

    func testStrategyDocumentEchoesPublishedPolicy() throws {
        let revision = CaptureRevisionID(rawValue: UUID())
        let session = CaptureSessionID(rawValue: UUID())
        let space = CoordinateSpaceID(rawValue: UUID())
        let profile = CaptureStrategyCatalog.profile(
            for: .commissioning
        )
        let document = try CaptureStrategyDocument(
            captureRevisionID: revision,
            captureSessionID: session,
            coordinateSpaceID: space,
            profile: profile,
            source: .operatorSelected,
            selectedAtUTC: "2026-09-22T00:00:00Z"
        )
        XCTAssertEqual(document.policyVersion, profile.policyVersion)
        XCTAssertEqual(
            document.resolvedPolicy.maximumRetainedFrames,
            profile.automaticKeyframes.maximumRetainedFrames
        )
        XCTAssertEqual(
            document.strategyID,
            CaptureStrategyIdentifier.commissioning.rawValue
        )

        let package = try CaptureStrategyPackageBuilder.build(
            document: document
        )
        let decoded = try JSONDecoder().decode(
            CaptureStrategyDocument.self,
            from: package.data
        )
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(
            CaptureStrategyPackage.path,
            "session/capture-strategy.json"
        )
    }

    func testStrategyDocumentRejectsNonUTCTimestamp() {
        let profile = CaptureStrategyCatalog.profile(for: .standard)
        XCTAssertThrowsError(
            try CaptureStrategyDocument(
                captureRevisionID: CaptureRevisionID(rawValue: UUID()),
                captureSessionID: CaptureSessionID(rawValue: UUID()),
                coordinateSpaceID: CoordinateSpaceID(rawValue: UUID()),
                profile: profile,
                source: .operatorSelected,
                selectedAtUTC: "not-a-timestamp"
            )
        )
    }

    func testPersistCaptureStrategyBindsRevisionIdentity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let identity = await store.identity
        let session = CaptureSessionID(rawValue: UUID())
        let space = CoordinateSpaceID(rawValue: UUID())
        let document = try CaptureStrategyDocument(
            captureRevisionID: identity.captureRevisionID,
            captureSessionID: session,
            coordinateSpaceID: space,
            profile: CaptureStrategyCatalog.profile(for: .detailed),
            source: .taskPlanRecommended,
            selectedAtUTC: "2026-09-22T00:00:00Z"
        )
        try await store.persistCaptureStrategy(
            try CaptureStrategyPackageBuilder.build(
                document: document
            )
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.captureStrategy, document)
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == CaptureStrategyPackage.path
            }
        )

        let foreign = try CaptureStrategyDocument(
            captureRevisionID: CaptureRevisionID(rawValue: UUID()),
            captureSessionID: session,
            coordinateSpaceID: space,
            profile: CaptureStrategyCatalog.profile(for: .detailed),
            source: .taskPlanRecommended,
            selectedAtUTC: "2026-09-22T00:00:00Z"
        )
        do {
            try await store.persistCaptureStrategy(
                try CaptureStrategyPackageBuilder.build(
                    document: foreign
                )
            )
            XCTFail("foreign revision must not bind")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .authorityMismatch)
        }
    }

    func testTaskPlanStrategyRecommendationAndPin() throws {
        let plan = try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "project",
            roomName: "room",
            recommendedCaptureStrategy: "detailed",
            captureStrategyPinned: true
        )
        XCTAssertEqual(plan.recommendedCaptureStrategy, "detailed")
        XCTAssertTrue(plan.captureStrategyPinned)

        let unpinned = try HTDTCaptureTaskPlan(
            planID: "plan-2",
            planVersion: "1",
            projectRef: "project",
            roomName: "room",
            captureStrategyPinned: true
        )
        XCTAssertNil(unpinned.recommendedCaptureStrategy)
        XCTAssertFalse(
            unpinned.captureStrategyPinned,
            "pin without a recommendation is meaningless"
        )

        XCTAssertThrowsError(
            try HTDTCaptureTaskPlan(
                planID: "plan-3",
                planVersion: "1",
                projectRef: "project",
                roomName: "room",
                recommendedCaptureStrategy: "not-a-strategy"
            )
        )
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#308 storage advisory

    func testStorageProfileAccumulatesEvidenceBytes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let session = CaptureSessionID(rawValue: UUID())
        let space = CoordinateSpaceID(rawValue: UUID())

        let pixel = Data([1, 2, 3, 4])
        let frameID = EvidenceFrameID(rawValue: UUID())
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: session,
            coordinateSpaceID: space,
            sessionTimestampSeconds: 1,
            worldFromCamera: .identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [1, 0, 0, 0, 1, 0, 0, 0, 1]
            ),
            imageWidth: 1,
            imageHeight: 1,
            pixelFormatFourCC: 0,
            pixelRelativePath:
                "evidence/frames/\(frameID).pixelbin",
            pixelByteCount: pixel.count,
            pixelSHA256: EvidenceIntegrity.sha256(of: pixel),
            depthStatus: .unavailable
        )
        try await store.persistFramePackage(
            try FrameEvidencePackageBuilder.build(
                descriptor: descriptor,
                pixelPayload: pixel,
                depthPayload: nil,
                confidencePayload: nil
            )
        )

        let geometry = try MeshGeometryPayload(
            vertices: [
                Float3(0, 0, 0),
                Float3(1, 0, 0),
                Float3(0, 1, 0),
            ],
            triangleIndices: [0, 1, 2]
        )
        try await store.persistMeshPackage(
            try MeshEvidencePackageBuilder.build(
                snapshots: [
                    MeshAnchorSnapshot(
                        anchorID: UUID(),
                        captureSessionID: session,
                        coordinateSpaceID: space,
                        worldFromAnchor: .identity,
                        sessionTimestampSeconds: 1,
                        geometry: geometry
                    ),
                ]
            )
        )

        let profile = try await store.storageProfile()
        // The pixel payload and its descriptor both land in the
        // frame bucket; mesh bytes live under mesh/.
        XCTAssertGreaterThanOrEqual(
            profile.framePixelBytes, Int64(pixel.count)
        )
        XCTAssertGreaterThan(profile.totalBytes, Int64(pixel.count))
        XCTAssertEqual(
            profile.totalBytes,
            profile.framePixelBytes + profile.depthConfidenceBytes
                + profile.meshBytes + profile.roomPlanBytes
                + profile.previewAndDerivedBytes + profile.documentBytes
        )
    }

    func testKeyframeBudgetStatusReportsRemaining() {
        var tracker = AutomaticKeyframeTracker(
            configuration: .standard
        )
        let configuration = AutomaticKeyframeConfiguration.standard
        for index in 0 ..< 3 {
            tracker.markRetained(
                AutomaticKeyframeSample(
                    timestampSeconds: Double(index) * 10,
                    cameraX: Double(index),
                    cameraZ: 0,
                    trackingState: .normal,
                    hasSceneDepth: true,
                    estimatedBytes: 100
                ),
                actualBytes: 100
            )
        }
        let status = AutomaticKeyframeBudgetStatus(tracker: tracker)
        XCTAssertEqual(status.retainedFrameCount, 3)
        XCTAssertEqual(
            status.maximumRetainedFrames,
            configuration.maximumRetainedFrames
        )
        XCTAssertEqual(status.retainedEstimatedBytes, 300)
        XCTAssertEqual(
            status.maximumRetainedBytes,
            configuration.maximumRetainedBytes
        )
        XCTAssertEqual(status.policyVersion,
                       configuration.policyVersion)
        XCTAssertEqual(
            status.remainingFrames,
            configuration.maximumRetainedFrames - 3
        )
        XCTAssertEqual(
            status.remainingBytes,
            configuration.maximumRetainedBytes - 300
        )
    }

    func testStorageAdvisoryReportsBandsAndMargins() {
        let profile = CaptureWorkingSetStorageProfile()
        let warning: Int64 = 1_000
        let critical: Int64 = 500
        let nominal = CaptureEvidenceStorageAdvisory(
            profile: profile,
            evidenceFrameCount: 2,
            depthEvidenceCount: 1,
            deviceAvailableBytes: 10_000,
            pressureBand: .nominal,
            storageWarningBytes: warning,
            storageCriticalBytes: critical
        )
        XCTAssertEqual(nominal.marginToWarningBytes, 9_000)
        XCTAssertEqual(nominal.marginToCriticalBytes, 9_500)

        let unmeasured = CaptureEvidenceStorageAdvisory(
            profile: profile,
            evidenceFrameCount: 0,
            depthEvidenceCount: 0,
            deviceAvailableBytes: nil,
            pressureBand: .unknown,
            storageWarningBytes: warning,
            storageCriticalBytes: critical
        )
        XCTAssertNil(unmeasured.marginToWarningBytes)
        XCTAssertNil(unmeasured.marginToCriticalBytes)
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#317 acquisition origins

    func testOriginRecordValidation() throws {
        let revision = CaptureRevisionID(rawValue: UUID())
        XCTAssertThrowsError(
            try CaptureAcquisitionOriginRecord(
                captureRevisionID: revision,
                kind: .importedFile,
                transport: .fileImport,
                acquiredAtUTC: "not-utc",
                bundleDigestSHA256: String(repeating: "a", count: 64)
            )
        )
        XCTAssertThrowsError(
            try CaptureAcquisitionOriginRecord(
                captureRevisionID: revision,
                kind: .importedFile,
                transport: .fileImport,
                acquiredAtUTC: "2026-09-22T00:00:00Z",
                originalFilename: "room.zip",
                sourceLabel: "partner archive",
                bundleDigestSHA256: "not-hex"
            )
        )
        let record = try CaptureAcquisitionOriginRecord(
            captureRevisionID: revision,
            kind: .importedFile,
            transport: .fileImport,
            acquiredAtUTC: "2026-09-22T00:00:00Z",
            originalFilename: " room.zip ",
            sourceLabel: " ",
            bundleDigestSHA256: String(repeating: "a", count: 64)
        )
        XCTAssertEqual(record.originalFilename, "room.zip")
        XCTAssertNil(record.sourceLabel)
    }

    func testOriginStoreRoundTripConflictsAndBatch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CaptureAcquisitionOriginStore(captureRoot: root)
        let revisionA = CaptureRevisionID(rawValue: UUID())
        let recordA = try CaptureAcquisitionOriginRecord(
            captureRevisionID: revisionA,
            kind: .importedFile,
            transport: .fileImport,
            acquiredAtUTC: "2026-09-22T00:00:00Z",
            originalFilename: "room.htdtbundle",
            sourceLabel: "partner send",
            bundleDigestSHA256: String(repeating: "b", count: 64)
        )
        try store.record(recordA)
        XCTAssertEqual(try store.origin(for: revisionA), recordA)

        // Identical re-record is a no-op.
        try store.record(recordA)
        XCTAssertEqual(try store.origin(for: revisionA), recordA)

        let conflicting = try CaptureAcquisitionOriginRecord(
            captureRevisionID: revisionA,
            kind: .createdOnThisDevice,
            transport: .localCapture,
            acquiredAtUTC: "2026-09-22T00:01:00Z",
            bundleDigestSHA256: String(repeating: "b", count: 64)
        )
        XCTAssertThrowsError(try store.record(conflicting)) { error in
            XCTAssertEqual(
                error as? CaptureAcquisitionOriginError,
                .conflictingOrigin(revisionA)
            )
        }
        XCTAssertEqual(try store.origin(for: revisionA), recordA)

        let revisionB = CaptureRevisionID(rawValue: UUID())
        let recordB = try CaptureAcquisitionOriginRecord(
            captureRevisionID: revisionB,
            kind: .receivedFromHTDT,
            transport: .htdtExchange,
            acquiredAtUTC: "2026-09-22T00:02:00Z",
            originalFilename: "peer.htdtbundle",
            bundleDigestSHA256: String(repeating: "c", count: 64)
        )
        // Batch backfill fills only missing entries.
        try store.recordIfAbsent([conflicting, recordB])
        XCTAssertEqual(try store.origin(for: revisionB), recordB)
        XCTAssertEqual(try store.load().entries.count, 2)
        XCTAssertNil(
            try store.origin(
                for: CaptureRevisionID(rawValue: UUID())
            )
        )

        // Survives a fresh store instance on the same root.
        let reopened = CaptureAcquisitionOriginStore(captureRoot: root)
        XCTAssertEqual(try reopened.origin(for: revisionA), recordA)
        XCTAssertEqual(try reopened.origin(for: revisionB), recordB)
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#319 semantic child revisions

    func testSemanticChildPreservesEvidenceAndWritesIntent()
        async throws
    {
        let parent = try BundleValidationFixture.makeDirectory()
        let stagingRoot = try BundleValidationFixture.makeDirectory()
        let destinationRoot = try BundleValidationFixture
            .makeDirectory()
        let staging = stagingRoot.appendingPathComponent(
            "staging",
            isDirectory: true
        )
        let destination = destinationRoot.appendingPathComponent(
            "destination",
            isDirectory: true
        )
        defer {
            BundleValidationFixture.remove(parent)
            BundleValidationFixture.remove(stagingRoot)
            BundleValidationFixture.remove(destinationRoot)
        }

        let pixel = Data([9, 9, 9])
        let framePath = "evidence/frames/raw.pixelbin"
        let spaceID = CoordinateSpaceID(
            canonicalString: BundleValidationFixture.spaceUUID
        )!
        let entity = try CaptureAnnotationEntity(
            entityID: AnnotationEntityID(rawValue: UUID()),
            type: .equipmentRack,
            coordinateSpaceID: spaceID,
            worldFromAnnotation: .identity,
            referencePointSemantics: ReferencePointSemantics(
                rawValue: "x_equipment_origin"
            )!,
            label: "Old label",
            provenanceClass: .userAnnotation,
            verificationState: .unverified,
            placement: try PlacementProvenance(
                method: .manualNumeric
            ),
            evidenceRefs: []
        )
        let entityPackage = try AnnotationEvidencePackageBuilder.build(
            entities: [entity]
        )
        try BundleValidationFixture.stage(
            parent,
            payloads: [
                (framePath, pixel, "application/octet-stream"),
                (
                    AnnotationEvidencePackage.path,
                    entityPackage.data,
                    "application/json"
                ),
            ]
        )

        let context = try SemanticChildRevisionBuilder.loadContext(
            parentDirectory: parent
        )
        XCTAssertEqual(context.entities.count, 1)
        XCTAssertNil(context.parentIntent)

        let childID = CaptureRevisionID(rawValue: UUID())
        let edits = SemanticChildRevisionEdits(
            entities: [
                try CaptureAnnotationEntity(
                    entityID: entity.entityID,
                    type: .equipmentRack,
                    coordinateSpaceID: spaceID,
                    worldFromAnnotation: entity.worldFromAnnotation,
                    referencePointSemantics:
                        entity.referencePointSemantics,
                    label: "Corrected label",
                    provenanceClass: .userAnnotation,
                    verificationState: .userAttested,
                    placement: try PlacementProvenance(
                        method: .manualNumeric
                    ),
                    evidenceRefs: []
                ),
            ],
            correctionNote: "label typo"
        )
        let result = try await SemanticChildRevisionBuilder.build(
            context: context,
            childRevisionID: childID,
            edits: edits,
            stagingDirectory: staging,
            destinationDirectory: destination,
            app: BundleAppIdentity(version: "1.0.0", build: "t"),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(
            result.intent.revisionKind, .semanticCorrection
        )
        XCTAssertEqual(result.bundleDirectory.path, destination.path)

        let childManifest = try JSONDecoder().decode(
            BundleManifest.self,
            from: Data(
                contentsOf: destination.appendingPathComponent(
                    "manifest.json"
                )
            )
        )
        XCTAssertEqual(childManifest.captureRevisionID, childID)
        XCTAssertEqual(
            childManifest.parentRevisionID,
            context.manifest.captureRevisionID
        )
        XCTAssertEqual(
            childManifest.captureSessionIDs,
            context.manifest.captureSessionIDs
        )
        XCTAssertEqual(
            childManifest.coordinateSpaceIDs,
            context.manifest.coordinateSpaceIDs
        )

        // Sensor evidence copies byte-for-byte; only the edited
        // records and regenerated payloads diverge.
        XCTAssertEqual(
            try Data(
                contentsOf: destination.appendingPathComponent(
                    framePath
                )
            ),
            pixel
        )
        XCTAssertNotEqual(
            try Data(
                contentsOf: destination.appendingPathComponent(
                    AnnotationEvidencePackage.path
                )
            ),
            entityPackage.data
        )

        let intent = try JSONDecoder().decode(
            CaptureRevisionIntentDocument.self,
            from: Data(
                contentsOf: destination.appendingPathComponent(
                    CaptureRevisionIntentPackage.path
                )
            )
        )
        XCTAssertEqual(intent.revisionKind, .semanticCorrection)
        XCTAssertEqual(
            intent.parentRevisionID,
            context.manifest.captureRevisionID
        )
        XCTAssertEqual(intent.correctionNote, "label typo")
        XCTAssertEqual(intent.changedRecordRefs.count, 1)
        XCTAssertEqual(
            intent.changedRecordRefs.first?.payloadPath,
            AnnotationEvidencePackage.path
        )
        XCTAssertEqual(
            intent.changedRecordRefs.first?.recordID,
            entity.entityID.description
        )
        XCTAssertTrue(intent.addedRecordRefs.isEmpty)
        XCTAssertTrue(intent.supersededRecordRefs.isEmpty)
        XCTAssertFalse(intent.reusedEvidenceRefs.isEmpty)

        // The finalized child validates and surfaces the semantic
        // diff through the comparison workspace (legacy bolph71656-ai/HTDT-Capture#221).
        let report = try BundleDirectoryValidator.validate(
            root: destination
        )
        XCTAssertTrue(report.valid, "\(report)")

        let contents = try PersistedCaptureContentsLoader.load(
            directory: destination
        )
        XCTAssertEqual(
            contents.revisionIntent?.revisionKind,
            .semanticCorrection
        )
        let parentContents = try PersistedCaptureContentsLoader.load(
            directory: parent
        )
        let comparison = CaptureRevisionComparator.compare(
            parent: parentContents,
            child: contents
        )
        XCTAssertTrue(comparison.fields.contains {
            $0.field == "revision_kind"
                && $0.child == "semantic_correction"
        })
        XCTAssertTrue(comparison.fields.contains {
            $0.field == "correction_note"
                && $0.child == "label typo"
        })
        XCTAssertTrue(comparison.fields.contains {
            $0.field.contains(AnnotationEvidencePackage.path)
                && $0.child == "changed"
        })
        XCTAssertTrue(comparison.fields.contains {
            $0.field == "reused_evidence_refs"
        })
    }

    func testSemanticChildRequiresValidatedParent() throws {
        let root = try BundleValidationFixture.makeDirectory()
        defer { BundleValidationFixture.remove(root) }
        XCTAssertThrowsError(
            try SemanticChildRevisionBuilder.loadContext(
                parentDirectory: root
            )
        )
    }

    // MARK: legacy bolph71656-ai/HTDT-Capture#322 plan reference underlay

    func testPlanUnderlayValidationAndPersistence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let revision = CaptureRevisionID(rawValue: UUID())
        let space = CoordinateSpaceID(rawValue: UUID())
        let digest = String(repeating: "d", count: 64)
        let alignment = try PlanUnderlayAlignment(
            method: .knownDistanceAxis,
            knownDistance: try PlanUnderlayKnownDistance(
                fromX: 0, fromY: 0, toX: 8.4, toY: 0,
                meters: 8.4, axis: "x"
            ),
            residualMeters: 0.11,
            alignedAtUTC: "2026-09-22T00:00:00Z"
        )
        let document = try PlanUnderlayDocument(
            captureRevisionID: revision,
            coordinateSpaceID: space,
            sourceKind: .imageFile,
            sourceFilename: "floorplan.png",
            sourceMediaType: "image/png",
            sourceSHA256: digest,
            alignment: alignment,
            importedAtUTC: "2026-09-22T00:00:00Z"
        )

        // File-source underlays must name the imported file and its
        // hash; scale authority is never inferred.
        XCTAssertThrowsError(
            try PlanUnderlayDocument(
                captureRevisionID: revision,
                coordinateSpaceID: space,
                sourceKind: .imageFile,
                sourceFilename: nil,
                sourceMediaType: "image/png",
                sourceSHA256: digest,
                alignment: alignment,
                importedAtUTC: "2026-09-22T00:00:00Z"
            )
        )
        XCTAssertThrowsError(
            try PlanUnderlayAlignment(
                method: .knownDistanceAxis,
                alignedAtUTC: "2026-09-22T00:00:00Z"
            )
        )
        XCTAssertThrowsError(
            try PlanUnderlayAlignment(
                method: .referencePointPair,
                alignedAtUTC: "2026-09-22T00:00:00Z"
            )
        )

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let identity = await store.identity
        let boundDocument = try PlanUnderlayDocument(
            captureRevisionID: identity.captureRevisionID,
            coordinateSpaceID: space,
            sourceKind: document.sourceKind,
            sourceFilename: document.sourceFilename,
            sourceMediaType: document.sourceMediaType,
            sourceSHA256: document.sourceSHA256,
            alignment: alignment,
            importedAtUTC: document.importedAtUTC
        )
        try await store.persistPlanUnderlay(
            try PlanUnderlayPackageBuilder.build(
                document: boundDocument
            )
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.planUnderlay, boundDocument)
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == PlanUnderlayPackage.path
            }
        )

        // A conflicting second underlay fails closed like every
        // other canonical payload.
        let other = try PlanUnderlayDocument(
            captureRevisionID: identity.captureRevisionID,
            coordinateSpaceID: space,
            sourceKind: .htdtReference,
            htdtReferenceID: "room-a",
            alignment: try PlanUnderlayAlignment(
                method: .htdtDatum,
                alignedAtUTC: "2026-09-22T00:00:00Z"
            ),
            importedAtUTC: "2026-09-22T00:05:00Z"
        )
        do {
            try await store.persistPlanUnderlay(
                try PlanUnderlayPackageBuilder.build(
                    document: other
                )
            )
            XCTFail("conflicting underlay must fail closed")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .duplicatePayloadDeclaration(
                    PlanUnderlayPackage.path
                )
            )
        }
    }

    func testPlanUnderlaySupportEvaluation() throws {
        let revision = CaptureRevisionID(rawValue: UUID())
        let space = CoordinateSpaceID(rawValue: UUID())
        let alignment = try PlanUnderlayAlignment(
            method: .referencePointPair,
            referencePoints: [
                try PlanUnderlayReferencePoint(
                    label: "a",
                    planXMeters: 0,
                    planYMeters: 0,
                    capturePoint: WorldPoint3D(x: 0, y: 0, z: 0)
                ),
                try PlanUnderlayReferencePoint(
                    label: "b",
                    planXMeters: 2,
                    planYMeters: 0,
                    capturePoint: WorldPoint3D(x: 1.35, y: 0, z: 0.25)
                ),
                try PlanUnderlayReferencePoint(
                    label: "c",
                    planXMeters: 4,
                    planYMeters: 0,
                    capturePoint: WorldPoint3D(x: 10, y: 0, z: 10)
                ),
            ],
            residualMeters: 0.02,
            alignedAtUTC: "2026-09-22T00:00:00Z"
        )
        let document = try PlanUnderlayDocument(
            captureRevisionID: revision,
            coordinateSpaceID: space,
            sourceKind: .htdtReference,
            htdtReferenceID: "room-a",
            alignment: alignment,
            importedAtUTC: "2026-09-22T00:00:00Z"
        )

        let regions = [
            SpatialCoverageRegion(
                key: SpatialCoverageCellKey(x: 0, z: 0),
                observationCount: 5,
                normalTrackingObservationCount: 5,
                limitedTrackingObservationCount: 0,
                lastObservedTimestampSeconds: 1,
                viewAngleBucketMask: 1,
                elevationBucketMask: 0,
                latestDistanceBucket: .near,
                depthObservationCount: 1,
                meshSupportCount: 4,
                classification: .observed
            ),
            SpatialCoverageRegion(
                key: SpatialCoverageCellKey(x: 1, z: 0),
                observationCount: 1,
                normalTrackingObservationCount: 0,
                limitedTrackingObservationCount: 1,
                lastObservedTimestampSeconds: 1,
                viewAngleBucketMask: 1,
                elevationBucketMask: 0,
                latestDistanceBucket: .near,
                depthObservationCount: 0,
                meshSupportCount: 0,
                classification: .weak
            ),
        ]
        let empty = SpatialScanCoverageSummary.empty
        let summary = SpatialScanCoverageSummary(
            cellSizeMeters: empty.cellSizeMeters,
            maxRegionCount: empty.maxRegionCount,
            referenceOriginWorld: nil,
            referenceYawRadians: nil,
            currentCameraPosition: nil,
            currentRelativeHeadingRadians: nil,
            latestTrackingState: .normal,
            latestHasSceneDepth: true,
            meshAvailability: MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: true,
                activeMeshAnchorCount: 1
            ),
            regions: regions,
            displayBounds: nil
        )

        let findings = PlanUnderlaySupportEvaluator.evaluate(
            underlay: document,
            coverage: summary
        )
        XCTAssertEqual(findings.count, 3)
        XCTAssertEqual(
            findings.first { $0.pointLabel == "a" }?.state,
            .observed
        )
        XCTAssertEqual(
            findings.first { $0.pointLabel == "b" }?.state,
            .weaklySupported
        )
        XCTAssertEqual(
            findings.first { $0.pointLabel == "c" }?.state,
            .unsupported
        )
        XCTAssertNil(
            findings.first { $0.pointLabel == "c" }?
                .nearestCoverageDistanceMeters
        )

        // No coverage at all: every plan anchor is unsupported and
        // none is silently adopted as observed truth.
        let noCoverage = PlanUnderlaySupportEvaluator.evaluate(
            underlay: document,
            coverage: .empty
        )
        XCTAssertEqual(noCoverage.count, 3)
        XCTAssertTrue(
            noCoverage.allSatisfy { $0.state == .unsupported }
        )
    }

    // MARK: bundle contract coverage for the new payloads

    func testNewPayloadsPassBundleValidation() throws {
        let root = try BundleValidationFixture.makeDirectory()
        defer { BundleValidationFixture.remove(root) }

        let revision = CaptureRevisionID(rawValue: UUID())
        let session = CaptureSessionID(
            canonicalString: BundleValidationFixture.sessionUUID
        )!
        let space = CoordinateSpaceID(
            canonicalString: BundleValidationFixture.spaceUUID
        )!

        let strategy = try CaptureStrategyPackageBuilder.build(
            document: try CaptureStrategyDocument(
                captureRevisionID: revision,
                captureSessionID: session,
                coordinateSpaceID: space,
                profile: CaptureStrategyCatalog.profile(
                    for: .commissioning
                ),
                source: .taskPlanPinned,
                selectedAtUTC: "2026-09-22T00:00:00Z"
            )
        )
        let intent = try CaptureRevisionIntentPackageBuilder.build(
            document: try CaptureRevisionIntentDocument(
                captureRevisionID: revision,
                parentRevisionID: CaptureRevisionID(rawValue: UUID()),
                parentBundleSHA256: String(
                    repeating: "e",
                    count: 64
                ),
                revisionKind: .semanticCorrection,
                reusedCaptureSessionIDs: [session],
                reusedCoordinateSpaceIDs: [space],
                changedRecordRefs: [
                    try CaptureRevisionRecordRef(
                        payloadPath: AnnotationEvidencePackage.path,
                        recordID: UUID().uuidString
                    ),
                ],
                reusedEvidenceRefs: ["evidence/frames/a.pixelbin"],
                correctionNote: "labels",
                createdAtUTC: "2026-09-22T00:00:00Z"
            )
        )
        let underlay = try PlanUnderlayPackageBuilder.build(
            document: try PlanUnderlayDocument(
                captureRevisionID: revision,
                coordinateSpaceID: space,
                sourceKind: .imageFile,
                sourceFilename: "plan.png",
                sourceMediaType: "image/png",
                sourceSHA256: String(repeating: "f", count: 64),
                alignment: try PlanUnderlayAlignment(
                    method: .knownDistanceAxis,
                    knownDistance: try PlanUnderlayKnownDistance(
                        fromX: 0, fromY: 0, toX: 4, toY: 0,
                        meters: 4, axis: "x"
                    ),
                    residualMeters: 0.05,
                    alignedAtUTC: "2026-09-22T00:00:00Z"
                ),
                importedAtUTC: "2026-09-22T00:00:00Z"
            )
        )

        try BundleValidationFixture.stage(
            root,
            payloads: [
                (
                    CaptureStrategyPackage.path,
                    strategy.data,
                    "application/json"
                ),
                (
                    CaptureRevisionIntentPackage.path,
                    intent.data,
                    "application/json"
                ),
                (
                    PlanUnderlayPackage.path,
                    underlay.data,
                    "application/json"
                ),
            ]
        )
        let report = try BundleDirectoryValidator.validate(root: root)
        XCTAssertTrue(report.valid, "\(report)")
    }

    func testSchemaOwnedPayloadRejectsNonConformingDocument() throws {
        let root = try BundleValidationFixture.makeDirectory()
        defer { BundleValidationFixture.remove(root) }

        // Same shape as a real strategy payload but an unpublished
        // strategy identifier — schema-owned paths fail closed.
        let bogus = try BundleValidationFixture.canonical(
            .object([
                ("schema", .string("htdt.capture.strategy")),
                ("schema_version", .string("1.0.0")),
                (
                    "capture_revision_id",
                    .string(
                        "00000000-0000-4000-8000-0000000000aa"
                    )
                ),
                (
                    "capture_session_id",
                    .string(BundleValidationFixture.sessionUUID)
                ),
                (
                    "coordinate_space_id",
                    .string(BundleValidationFixture.spaceUUID)
                ),
                ("strategy_id", .string("not_a_strategy")),
                ("policy_version", .string("1.0.0")),
                ("source", .string("operator_selected")),
                ("review_expectation", .string("standard")),
                ("complex_object_prompts", .boolean(false)),
                ("loop_closure_prompts", .boolean(false)),
                ("resolved_policy", .object([])),
                ("selected_at", .string("2026-09-22T00:00:00Z")),
            ])
        )
        try BundleValidationFixture.stage(
            root,
            payloads: [
                (
                    CaptureStrategyPackage.path,
                    bogus,
                    "application/json"
                ),
            ]
        )
        XCTAssertThrowsError(
            try BundleDirectoryValidator.validate(root: root)
        ) { error in
            guard
                case .schemaValidationFailed =
                    error as? BundleDirectoryValidationError
            else {
                XCTFail("expected schemaValidationFailed, got \(error)")
                return
            }
        }
    }
}
