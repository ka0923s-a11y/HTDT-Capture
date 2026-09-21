import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #199: an evidence-linked annotation's spatial authority must
/// be congruent with the coordinate space of the frame/mesh evidence
/// it references. The builder rejects captured authorities expressed
/// in a different space than the annotation, and the working-set store
/// resolves `path:evidence/frames/...json`, `frame:<uuid>`, and
/// `mesh_anchor:<uuid>` links against committed authority — manifest
/// membership alone never satisfies congruence, and unresolvable or
/// cross-space links fail closed because v1 defines no alignment
/// authority that could bridge spaces.
final class SpatialEvidenceCongruenceTests: XCTestCase {
    private func makeFramePackage(
        sessionID: CaptureSessionID,
        spaceID: CoordinateSpaceID
    ) throws -> FrameEvidencePackage {
        let frameID = EvidenceFrameID()
        let pixel = Data([1, 2, 3, 4])
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: spaceID,
            sessionTimestampSeconds: 2,
            worldFromCamera: .identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [
                    1, 0, 0,
                    0, 1, 0,
                    0, 0, 1,
                ]
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
        return try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: nil,
            confidencePayload: nil
        )
    }

    private func entity(
        space: CoordinateSpaceID,
        evidenceRefs: [String] = [],
        placement: PlacementProvenance? = nil
    ) throws -> CaptureAnnotationEntity {
        try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "note",
            provenanceClass: .userAnnotation,
            placement: placement
                ?? PlacementProvenance(method: .manualNumeric),
            evidenceRefs: evidenceRefs
        )
    }

    // MARK: - Builder-level authority congruence

    /// A placement authority captured from a space-B frame cannot back
    /// a space-A annotation: the transform and evidence refs are not
    /// geometrically comparable, and no alignment authority exists to
    /// bridge them.
    func testCrossSpacePlacementAuthorityRejected() throws {
        let authority = try AnnotationPlacementAuthority(
            worldFromAnnotation: .identity,
            placement: PlacementProvenance(
                method: .raycast,
                sourceEvidenceRefs: [
                    "path:evidence/frames/"
                        + "30000000-0000-4000-8000-000000000010.json",
                ]
            ),
            coordinateSpaceID: CoordinateSpaceID(),
            evidenceRefs: [
                "path:evidence/frames/"
                    + "30000000-0000-4000-8000-000000000010.json",
            ]
        )
        XCTAssertThrowsError(
            try ManualAuthorityBuilder.annotation(
                type: .referencePoint,
                label: "note",
                xMeters: 0,
                yMeters: 0,
                zMeters: 0,
                coordinateSpaceID: CoordinateSpaceID(),
                placementAuthority: authority
            )
        ) { error in
            XCTAssertEqual(
                error as? ManualAuthorityBuilderError,
                .authorityCoordinateSpaceMismatch
            )
        }
    }

    /// The same rule binds a captured speaker orientation: the frame
    /// that produced the heading must live in the annotation's space.
    func testCrossSpaceOrientationAuthorityRejected() throws {
        let authority = try AnnotationOrientationAuthority(
            orientation: OrientationAxes(
                frontAxisLocal: .unit(0, 0, -1),
                upAxisLocal: .unit(0, 1, 0)
            ),
            coordinateSpaceID: CoordinateSpaceID(),
            evidenceRefs: ["path:evidence/frames/a.json"]
        )
        XCTAssertThrowsError(
            try ManualAuthorityBuilder.annotation(
                type: .speaker,
                label: "Left",
                xMeters: 0,
                yMeters: 0,
                zMeters: 1,
                coordinateSpaceID: CoordinateSpaceID(),
                speakerChannelRole: "L",
                orientationAuthority: authority
            )
        ) { error in
            XCTAssertEqual(
                error as? ManualAuthorityBuilderError,
                .authorityCoordinateSpaceMismatch
            )
        }
    }

    /// Authorities expressed in the annotation's own space remain
    /// accepted and mark the record evidence-linked.
    func testSameSpaceAuthoritiesAccepted() throws {
        let space = CoordinateSpaceID()
        let ref =
            "path:evidence/frames/"
            + "30000000-0000-4000-8000-000000000011.json"
        let placement = try AnnotationPlacementAuthority(
            worldFromAnnotation: .identity,
            placement: PlacementProvenance(
                method: .raycast,
                sourceEvidenceRefs: [ref]
            ),
            coordinateSpaceID: space,
            evidenceRefs: [ref]
        )
        let orientation = try AnnotationOrientationAuthority(
            orientation: OrientationAxes(
                frontAxisLocal: .unit(0, 0, -1),
                upAxisLocal: .unit(0, 1, 0)
            ),
            coordinateSpaceID: space,
            evidenceRefs: [ref]
        )
        let entity = try ManualAuthorityBuilder.annotation(
            type: .speaker,
            label: "Left",
            xMeters: 0,
            yMeters: 0,
            zMeters: 1,
            coordinateSpaceID: space,
            speakerChannelRole: "L",
            referencePointConstruction: .surfaceHitConfirmed,
            placementAuthority: placement,
            orientationAuthority: orientation
        )
        XCTAssertEqual(entity.coordinateSpaceID, space)
        XCTAssertEqual(entity.evidenceRefs, [ref])
        XCTAssertEqual(
            entity.verificationState,
            .evidenceLinked
        )
    }

    // MARK: - Store-level evidence link resolution

    /// A `path:evidence/frames/...json` reference that resolves to a
    /// committed descriptor in the record's own space persists.
    func testSameSpaceFrameEvidenceLinkPersists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let sessionID = CaptureSessionID()
        let space = CoordinateSpaceID()
        let framePackage = try makeFramePackage(
            sessionID: sessionID,
            spaceID: space
        )
        try await store.persistFramePackage(framePackage)

        let ref = "path:" + framePackage.descriptorPath
        let package = try AnnotationEvidencePackageBuilder.build(
            entities: [
                try entity(
                    space: space,
                    evidenceRefs: [ref],
                    placement: PlacementProvenance(
                        method: .raycast,
                        sourceEvidenceRefs: [ref]
                    )
                ),
            ]
        )
        try await store.persistAnnotationPackage(package)

        let snapshot = await store.snapshot()
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == AnnotationEvidencePackage.path
            }
        )
    }

    /// A canonical frame-path reference to a frame that was never
    /// committed fails closed. The record's space is bound and the
    /// link is well-formed — manifest membership is not sufficient;
    /// the link itself must resolve to committed spatial authority.
    func testUncommittedFrameEvidenceLinkRejected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let space = CoordinateSpaceID()
        try await store.persistFramePackage(
            try makeFramePackage(
                sessionID: CaptureSessionID(),
                spaceID: space
            )
        )

        let ghostRef =
            "path:evidence/frames/"
            + EvidenceFrameID().description
            + ".json"
        let package = try AnnotationEvidencePackageBuilder.build(
            entities: [
                try entity(space: space, evidenceRefs: [ghostRef]),
            ]
        )
        do {
            try await store.persistAnnotationPackage(package)
            XCTFail("expected unresolvable spatial link rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .unresolvableSpatialEvidenceLink(ghostRef)
            )
        }

        let snapshot = await store.snapshot()
        XCTAssertFalse(
            snapshot.payloadDeclarations.contains {
                $0.path == AnnotationEvidencePackage.path
            }
        )
    }

    /// The `frame:<uuid>` link form resolves through the same path.
    func testUncommittedFramePrefixLinkRejected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let space = CoordinateSpaceID()
        let ghostRef =
            "frame:" + EvidenceFrameID().description
        let package = try AnnotationEvidencePackageBuilder.build(
            entities: [
                try entity(space: space, evidenceRefs: [ghostRef]),
            ]
        )
        do {
            try await store.persistAnnotationPackage(package)
            XCTFail("expected unresolvable spatial link rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .unresolvableSpatialEvidenceLink(ghostRef)
            )
        }
    }

    /// A placement's mesh-anchor claim must resolve to a committed
    /// anchor record in the same space.
    func testUncommittedMeshAnchorLinkRejected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let space = CoordinateSpaceID()
        let anchorID = UUID(
            uuidString:
                "30000000-0000-4000-8000-000000000099"
        )!
        let package = try AnnotationEvidencePackageBuilder.build(
            entities: [
                try entity(
                    space: space,
                    placement: PlacementProvenance(
                        method: .meshHitTest,
                        sourceMeshAnchorID: anchorID
                    )
                ),
            ]
        )
        do {
            try await store.persistAnnotationPackage(package)
            XCTFail("expected unresolvable spatial link rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .unresolvableSpatialEvidenceLink(
                    "mesh_anchor:" + anchorID.uuidString.lowercased()
                )
            )
        }
    }

    /// Spatial measurements resolve endpoint/evidence links through
    /// the same rule; non-spatial links stay out of scope.
    func testMeasurementSpatialEvidenceLinkResolved() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let space = CoordinateSpaceID()
        let framePackage = try makeFramePackage(
            sessionID: CaptureSessionID(),
            spaceID: space
        )
        try await store.persistFramePackage(framePackage)
        let ref = "path:" + framePackage.descriptorPath

        let good = try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: "anchor_point",
                    value: .vector3(1, 2, 3),
                    unit: .meter,
                    coordinateSpaceID: space,
                    endpointRefs: [ref],
                    acquisitionMethod: .laserDistanceMeter,
                    userAttestation: .attested,
                    provenanceClass: .userAttestedMeasurement
                ),
            ]
        )
        try await store.persistMeasurementPackage(good)
    }

    /// A spatial measurement whose endpoint link cannot resolve to a
    /// committed frame fails closed.
    func testMeasurementUnresolvableEndpointRejected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let space = CoordinateSpaceID()
        let ghostRef =
            "path:evidence/frames/"
            + EvidenceFrameID().description
            + ".json"
        let package = try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: "anchor_point",
                    value: .vector3(1, 2, 3),
                    unit: .meter,
                    coordinateSpaceID: space,
                    endpointRefs: [ghostRef],
                    acquisitionMethod: .laserDistanceMeter,
                    userAttestation: .attested,
                    provenanceClass: .userAttestedMeasurement
                ),
            ]
        )
        do {
            try await store.persistMeasurementPackage(package)
            XCTFail("expected unresolvable spatial link rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .unresolvableSpatialEvidenceLink(ghostRef)
            )
        }
    }

    /// Coordinate-space transition fixture (issue #199): a recorded
    /// discontinuity is provenance only — v1 keeps exactly one bound
    /// space per revision, so records in the announced next space
    /// still fail closed on `authorityMismatch` rather than acquiring
    /// congruence to the previous space's evidence.
    func testRecordedTransitionDoesNotAdvanceBoundSpace() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let spaceA = CoordinateSpaceID()
        let spaceB = CoordinateSpaceID()
        let framePackage = try makeFramePackage(
            sessionID: CaptureSessionID(),
            spaceID: spaceA
        )
        try await store.persistFramePackage(framePackage)

        try await store.recordCoordinateDiscontinuity(
            to: spaceB,
            reason: .arSessionRestart
        )

        // The space-A frame link remains congruent for space-A
        // records; an entity claiming the announced next space is
        // still rejected by the binding rule.
        let ref = "path:" + framePackage.descriptorPath
        try await store.persistAnnotationPackage(
            try AnnotationEvidencePackageBuilder.build(
                entities: [
                    try entity(space: spaceA, evidenceRefs: [ref]),
                ]
            )
        )
        do {
            try await store.persistAnnotationPackage(
                try AnnotationEvidencePackageBuilder.build(
                    entities: [
                        try entity(
                            space: spaceB,
                            evidenceRefs: [ref]
                        ),
                    ]
                )
            )
            XCTFail("expected authority mismatch for next space")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .authorityMismatch)
        }
    }

    /// A manual numeric annotation carrying no spatial claims remains
    /// unaffected by the congruence checks.
    func testManualNumericAnnotationWithoutEvidencePersists()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let space = CoordinateSpaceID()
        let package = try AnnotationEvidencePackageBuilder.build(
            entities: [try entity(space: space)]
        )
        try await store.persistAnnotationPackage(package)

        let snapshot = await store.snapshot()
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == AnnotationEvidencePackage.path
            }
        )
    }
}
