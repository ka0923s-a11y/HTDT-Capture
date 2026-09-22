import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Theater-semantic authorities (#218, #228, #233, #234, #256, #262,
/// #264, #280, #281, #288, #289, #290): record invariants, collection
/// cross-reference resolution, canonical packaging, and the store's
/// three-file atomic commit.
final class TheaterAuthorityTests: XCTestCase {
    private let space = CoordinateSpaceID()

    private func binding(
        evidenceRefs: [String] = []
    ) throws -> SurfaceRegionBinding {
        try SurfaceRegionBinding(
            coordinateSpaceID: space,
            roomPlanSurfaceID: "wall-1",
            evidenceRefs: evidenceRefs
        )
    }

    private func speakerEntity(
        label: String = "L"
    ) throws -> CaptureAnnotationEntity {
        try ManualAuthorityBuilder.annotation(
            type: .speaker,
            label: label,
            xMeters: 1,
            yMeters: 1,
            zMeters: 2,
            coordinateSpaceID: space,
            speakerChannelRole: "L",
            speakerYawDegrees: 0
        )
    }

    private func entity(
        type: AnnotationEntityType,
        label: String
    ) throws -> CaptureAnnotationEntity {
        try CaptureAnnotationEntity(
            type: type,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: label,
            provenanceClass: .userAnnotation,
            placement: PlacementProvenance(method: .manualNumeric)
        )
    }

    // MARK: - #218 surface authority

    func testBindingRequiresLineageAnchor() throws {
        XCTAssertThrowsError(
            try SurfaceRegionBinding(coordinateSpaceID: space)
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testBindingPolygonRequiresThreeVertices() throws {
        XCTAssertThrowsError(
            try SurfaceRegionBinding(
                coordinateSpaceID: space,
                polygonWorld: [
                    try SpatialVector3F(0, 0, 0),
                    try SpatialVector3F(1, 0, 0),
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .invalidPatchGeometry
            )
        }
    }

    func testBindingTriangleIndicesRequireMeshAnchor() throws {
        XCTAssertThrowsError(
            try SurfaceRegionBinding(
                coordinateSpaceID: space,
                roomPlanSurfaceID: "wall-1",
                triangleIndices: [0, 1, 2]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .invalidPatchGeometry
            )
        }
    }

    func testTreatmentPlacementRequiresAMember() throws {
        XCTAssertThrowsError(
            try TreatmentPlacementAuthority()
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testSurfaceSemanticRoundTrips() throws {
        let record = try SurfaceSemanticAuthority(
            label: "front wall",
            binding: binding(),
            hostClassification: .roomBoundary,
            treatment: try TreatmentPlacementAuthority(
                footprintWidthMeters: 0.6,
                surfaceOffsetMeters: 0.02
            )
        )
        let collection = try TheaterAuthorityCollection(
            surfaceSemantics: [record]
        )
        let package = try TheaterAuthorityPackageBuilder.build(
            collection: collection
        )
        let decoded = try JSONDecoder().decode(
            TheaterAuthorityCollection.self,
            from: package.data
        )
        XCTAssertEqual(decoded, collection)
        XCTAssertEqual(
            decoded.surfaceSemantics.first?.hostClassification,
            .roomBoundary
        )
    }

    // MARK: - #233 construction observation

    func testConstructionObservationCarriesSource() throws {
        let record = try SurfaceConstructionObservation(
            binding: binding(),
            constructionKind: .gypsumDrywall,
            materialDetail: "12.5mm double layer",
            source: .installerOrBuildRecord
        )
        XCTAssertEqual(record.source, .installerOrBuildRecord)
        let collection = try TheaterAuthorityCollection(
            surfaceConstructions: [record]
        )
        XCTAssertNoThrow(
            try TheaterAuthorityPackageBuilder.build(
                collection: collection
            )
        )
    }

    // MARK: - #256 problem surfaces

    func testProblemSurfaceRecordsKindAndEvidence() throws {
        let record = try ProblemSurfaceObservation(
            binding: binding(evidenceRefs: ["note:mirror"]),
            kind: .mirror,
            notes: "wall-length mirror"
        )
        let collection = try TheaterAuthorityCollection(
            problemSurfaces: [record]
        )
        XCTAssertEqual(
            collection.problemSurfaces.first?.kind,
            .mirror
        )
    }

    // MARK: - #262 construction features

    func testConstructionFeatureKeepsConfirmationSource() throws {
        let record = try ConstructionFeatureCandidate(
            binding: binding(),
            kind: .slopedCeiling,
            confirmationSource: .captureAppSuggested
        )
        let collection = try TheaterAuthorityCollection(
            constructionFeatures: [record]
        )
        XCTAssertEqual(
            collection.constructionFeatures.first?
                .confirmationSource,
            .captureAppSuggested
        )
    }

    // MARK: - #264 room state snapshots

    func testSnapshotRequiresObservations() throws {
        XCTAssertThrowsError(
            try RoomStateSnapshot(
                label: "doors open",
                captureRevisionID: CaptureRevisionID(),
                observedAtUTC: "2026-09-21T00:00:00Z",
                observationIDs: [],
                stateDigest: try EvidenceSHA256(
                    String(repeating: "0", count: 64)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .snapshotWithoutObservations
            )
        }
    }

    func testSnapshotObservationMustResolveInCollection() throws {
        let snapshot = try TheaterAuthorityBuilder.roomStateSnapshot(
            label: "curtains closed",
            captureRevisionID: CaptureRevisionID(),
            observedAtUTC: "2026-09-21T00:00:00Z",
            observations: [
                try RoomStateObservation(
                    kind: .curtain,
                    state: .closed,
                    observedAtUTC: "2026-09-21T00:00:00Z"
                ),
            ]
        )
        // Collection without the observation rejects the snapshot.
        XCTAssertThrowsError(
            try TheaterAuthorityCollection(
                roomStateSnapshots: [snapshot]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedObservationReference
            )
        }
    }

    func testSnapshotDigestIsContentAddressed() throws {
        let observation = try RoomStateObservation(
            kind: .hvac,
            state: .on,
            observedAtUTC: "2026-09-21T00:00:00Z"
        )
        let a = try TheaterAuthorityBuilder.roomStateSnapshot(
            label: "hvac on",
            captureRevisionID: CaptureRevisionID(),
            observedAtUTC: "2026-09-21T00:00:00Z",
            observations: [observation]
        )
        let b = try TheaterAuthorityBuilder.roomStateSnapshot(
            label: "hvac on",
            captureRevisionID: a.captureRevisionID,
            observedAtUTC: "2026-09-21T00:00:00Z",
            observations: [observation]
        )
        XCTAssertEqual(a.stateDigest, b.stateDigest)

        let changed = try RoomStateObservation(
            kind: .hvac,
            state: .off,
            observedAtUTC: "2026-09-21T00:00:00Z"
        )
        let c = try TheaterAuthorityBuilder.roomStateSnapshot(
            label: "hvac off",
            captureRevisionID: a.captureRevisionID,
            observedAtUTC: "2026-09-21T00:00:00Z",
            observations: [changed]
        )
        XCTAssertNotEqual(a.stateDigest, c.stateDigest)
    }

    func testObservationEvidenceRequiresSpace() throws {
        XCTAssertThrowsError(
            try RoomStateObservation(
                kind: .door,
                state: .open,
                observedAtUTC: "2026-09-21T00:00:00Z",
                evidenceRefs: ["path:evidence/frames/x.json"]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    // MARK: - #281 inventory

    func testInventoryItemRequiresLabel() throws {
        XCTAssertThrowsError(
            try SystemInventoryItem(
                equipmentClass: .avReceiver,
                userLabel: ""
            )
        ) { error in
            XCTAssertEqual(
                error as? AnnotationModelError,
                .emptyLabel
            )
        }
    }

    func testInventoryPoseRequiresSpace() throws {
        XCTAssertThrowsError(
            try SystemInventoryItem(
                equipmentClass: .powerAmplifier,
                userLabel: "amp",
                worldFromItem: .identity
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    // MARK: - #288 furniture

    func testFurnitureRequiresEntityOrBinding() throws {
        XCTAssertThrowsError(
            try FurnitureSemanticConfirmation(
                category: .sofa,
                relevance: .movable,
                source: .userConfirmed
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    // MARK: - #280 speaker installation

    func testSpeakerInstallationRecord() throws {
        let speaker = try speakerEntity()
        let record = try SpeakerInstallationAuthority(
            speakerEntityID: speaker.entityID,
            mountingMode: .onWall,
            insertionDepthMeters: 0.1
        )
        let collection = try TheaterAuthorityCollection(
            speakerInstallations: [record]
        )
        XCTAssertEqual(
            collection.speakerInstallations.first?.mountingMode,
            .onWall
        )
    }

    // MARK: - #289 screen semantics

    func testScreenTransparencySourceRequiredWhenKnown() throws {
        let screen = try entity(
            type: .projectionScreen,
            label: "screen"
        )
        XCTAssertThrowsError(
            try ProjectionScreenSemantics(
                screenEntityID: screen.entityID,
                acousticallyTransparent: .transparent,
                transparencySource: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .missingSourceBinding
            )
        }
    }

    func testScreenBehindSpeakersCannotSelfReference() throws {
        let screen = try entity(
            type: .projectionScreen,
            label: "screen"
        )
        XCTAssertThrowsError(
            try ProjectionScreenSemantics(
                screenEntityID: screen.entityID,
                acousticallyTransparent: .unknown,
                behindScreenSpeakerEntityIDs: [screen.entityID]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedEntityReference
            )
        }
    }

    // MARK: - #290 seat layout

    func testSeatLayoutRiserLinkRequiresRiserFeature() throws {
        let seat = try entity(type: .seat, label: "seat 1")
        let nonRiser = try ConstructionFeatureCandidate(
            binding: binding(),
            kind: .beam,
            confirmationSource: .userConfirmed
        )
        let layout = try SeatLayoutAuthority(
            seatEntityID: seat.entityID,
            riserAuthorityID: nonRiser.authorityID
        )
        XCTAssertThrowsError(
            try TheaterAuthorityCollection(
                constructionFeatures: [nonRiser],
                seatLayouts: [layout]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .unresolvedFeatureReference
            )
        }
    }

    func testSeatLayoutRiserLinkAcceptsRiser() throws {
        let seat = try entity(type: .seat, label: "seat 1")
        let riser = try ConstructionFeatureCandidate(
            binding: binding(),
            kind: .riser,
            confirmationSource: .userConfirmed
        )
        let layout = try SeatLayoutAuthority(
            seatEntityID: seat.entityID,
            rowIdentifier: "A",
            seatOrdinal: 1,
            riserAuthorityID: riser.authorityID
        )
        let collection = try TheaterAuthorityCollection(
            constructionFeatures: [riser],
            seatLayouts: [layout]
        )
        XCTAssertEqual(
            collection.seatLayouts.first?.seatOrdinal,
            1
        )
    }

    func testAuthorityIDsUniqueAcrossSections() throws {
        let sharedID = AuthorityRecordID()
        let a = try SurfaceSemanticAuthority(
            authorityID: sharedID,
            binding: binding(),
            hostClassification: .unknown
        )
        let b = try ProblemSurfaceObservation(
            authorityID: sharedID,
            binding: binding(),
            kind: .mirror
        )
        XCTAssertThrowsError(
            try TheaterAuthorityCollection(
                surfaceSemantics: [a],
                problemSurfaces: [b]
            )
        ) { error in
            XCTAssertEqual(
                error as? TheaterAuthorityError,
                .duplicateAuthorityRecordID
            )
        }
    }

    // MARK: - #228 speaker 3D aim

    func testSpeakerAimZeroElevationMatchesYawOnly() throws {
        let axes = try ManualAuthorityBuilder
            .speakerOrientationAxes(
                azimuthDegrees: 0,
                elevationDegrees: 0
            )
        XCTAssertEqual(axes.frontAxisLocal.z, -1, accuracy: 0.001)
        XCTAssertEqual(axes.frontAxisLocal.x, 0, accuracy: 0.001)
        XCTAssertEqual(axes.upAxisLocal.y, 1, accuracy: 0.001)
    }

    func testSpeakerAimAzimuthNinetyFacesPositiveX() throws {
        let axes = try ManualAuthorityBuilder
            .speakerOrientationAxes(
                azimuthDegrees: 90,
                elevationDegrees: 0
            )
        XCTAssertEqual(axes.frontAxisLocal.x, 1, accuracy: 0.001)
        XCTAssertEqual(axes.frontAxisLocal.z, 0, accuracy: 0.001)
    }

    func testSpeakerAimElevationTiltsFrontAxis() throws {
        let axes = try ManualAuthorityBuilder
            .speakerOrientationAxes(
                azimuthDegrees: 0,
                elevationDegrees: 30
            )
        XCTAssertEqual(
            axes.frontAxisLocal.y,
            Float(sin(30 * Double.pi / 180)),
            accuracy: 0.001
        )
        // Up stays orthogonal to front.
        let dot =
            axes.frontAxisLocal.x * axes.upAxisLocal.x
            + axes.frontAxisLocal.y * axes.upAxisLocal.y
            + axes.frontAxisLocal.z * axes.upAxisLocal.z
        XCTAssertEqual(dot, 0, accuracy: 0.001)
    }

    func testSpeakerAimStraightUp() throws {
        let axes = try ManualAuthorityBuilder
            .speakerOrientationAxes(
                azimuthDegrees: 0,
                elevationDegrees: 90
            )
        XCTAssertEqual(axes.frontAxisLocal.y, 1, accuracy: 0.001)
        XCTAssertEqual(axes.frontAxisLocal.z, 0, accuracy: 0.001)
        XCTAssertEqual(axes.upAxisLocal.y, 0, accuracy: 0.001)
    }

    func testSpeakerAimRejectsNonFiniteElevation() throws {
        XCTAssertThrowsError(
            try ManualAuthorityBuilder.speakerOrientationAxes(
                azimuthDegrees: 0,
                elevationDegrees: .infinity
            )
        ) { error in
            XCTAssertEqual(
                error as? ManualAuthorityBuilderError,
                .invalidSpeakerElevation
            )
        }
    }

    func testSpeakerEntityCarriesElevation() throws {
        let entity = try ManualAuthorityBuilder.annotation(
            type: .speaker,
            label: "L",
            xMeters: 1,
            yMeters: 1.2,
            zMeters: 2,
            coordinateSpaceID: space,
            speakerChannelRole: "L",
            speakerYawDegrees: 0,
            speakerElevationDegrees: -15
        )
        let front = try XCTUnwrap(entity.orientation?.frontAxisLocal)
        XCTAssertEqual(
            front.y,
            Float(sin(-15 * Double.pi / 180)),
            accuracy: 0.001
        )
    }

    // MARK: - #234 acoustic center

    func testAcousticCenterOnlyOnLoudspeakers() throws {
        let center = try AcousticCenterOffsetAuthority(
            offsetLocalMeters: try SpatialVector3F(0, 0.05, 0),
            authorityRef: "spec:front-wall-lcr"
        )
        let speaker = try ManualAuthorityBuilder.annotation(
            type: .speaker,
            label: "L",
            xMeters: 0,
            yMeters: 1,
            zMeters: 0,
            coordinateSpaceID: space,
            speakerChannelRole: "L",
            speakerYawDegrees: 0,
            acousticCenter: center
        )
        XCTAssertEqual(speaker.acousticCenter, center)

        XCTAssertThrowsError(
            try ManualAuthorityBuilder.annotation(
                type: .listeningPosition,
                label: "MLP",
                xMeters: 0,
                yMeters: 1.1,
                zMeters: 3,
                coordinateSpaceID: space,
                acousticCenter: center
            )
        ) { error in
            XCTAssertEqual(
                error as? ManualAuthorityBuilderError,
                .acousticCenterRequiresLoudspeaker
            )
        }
    }

    // MARK: - schema contract

    func testAuthoritiesPackagePassesSchemaValidation() throws {
        let seat = try entity(type: .seat, label: "seat")
        let speaker = try speakerEntity()
        let screen = try entity(
            type: .projectionScreen,
            label: "screen"
        )
        let collection = try TheaterAuthorityCollection(
            surfaceSemantics: [
                try SurfaceSemanticAuthority(
                    label: "front wall",
                    binding: binding(),
                    hostClassification: .roomBoundary,
                    treatment: try TreatmentPlacementAuthority(
                        footprintWidthMeters: 0.6
                    )
                ),
            ],
            surfaceConstructions: [
                try SurfaceConstructionObservation(
                    binding: binding(),
                    constructionKind: .gypsumDrywall,
                    source: .userObservation
                ),
            ],
            problemSurfaces: [
                try ProblemSurfaceObservation(
                    binding: binding(),
                    kind: .mirror
                ),
            ],
            constructionFeatures: [
                try ConstructionFeatureCandidate(
                    binding: binding(),
                    kind: .riser,
                    confirmationSource: .userConfirmed
                ),
            ],
            inventoryItems: [
                try SystemInventoryItem(
                    equipmentClass: .avReceiver,
                    userLabel: "AVR"
                ),
            ],
            furnitureSemantics: [
                try FurnitureSemanticConfirmation(
                    targetEntityID: seat.entityID,
                    category: .sofa,
                    relevance: .movable,
                    source: .userConfirmed
                ),
            ],
            speakerInstallations: [
                try SpeakerInstallationAuthority(
                    speakerEntityID: speaker.entityID,
                    mountingMode: .standMounted,
                    insertionDepthMeters: 0
                ),
            ],
            screenSemantics: [
                try ProjectionScreenSemantics(
                    screenEntityID: screen.entityID,
                    visibleApertureWidthMeters: 2.4,
                    acousticallyTransparent: .transparent,
                    transparencySource: .userAttestation,
                    behindScreenSpeakerEntityIDs: [
                        speaker.entityID,
                    ]
                ),
            ],
            seatLayouts: [
                try SeatLayoutAuthority(
                    seatEntityID: seat.entityID,
                    rowIdentifier: "A",
                    seatOrdinal: 0
                ),
            ]
        )
        let package = try TheaterAuthorityPackageBuilder.build(
            collection: collection
        )
        XCTAssertNotNil(
            try CanonicalPayloadValidator.validateSchemaOwnedJSON(
                path: TheaterAuthorityPackage.path,
                data: package.data
            )
        )
    }

    func testAuthoritiesSchemaRejectsUnknownSection() throws {
        let value = try StrictJSON.parse(
            Data(
                """
                {"schema":"htdt.capture.authorities",
                 "schema_version":"1.0.0","bogus":[]}
                """.utf8
            )
        )
        let data = try CanonicalJSONProfile.canonicalBytes(
            of: value
        )
        do {
            _ = try CanonicalPayloadValidator
                .validateSchemaOwnedJSON(
                    path: TheaterAuthorityPackage.path,
                    data: data
                )
            XCTFail("expected schemaValidationFailed")
        } catch let error as BundleDirectoryValidationError {
            guard case .schemaValidationFailed = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    // MARK: - store commit

    private func annotationPackage(
        _ entities: [CaptureAnnotationEntity]
    ) throws -> AnnotationEvidencePackage {
        try AnnotationEvidencePackageBuilder.build(
            entities: entities
        )
    }

    private func measurementPackage()
        throws -> MeasurementEvidencePackage
    {
        try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: "x_wall_length",
                    value: .scalar(4.2),
                    unit: .meter,
                    acquisitionMethod: .laserDistanceMeter,
                    userAttestation: .attested,
                    provenanceClass: .userAttestedMeasurement
                ),
            ]
        )
    }

    private func makeStore() throws -> (
        store: CaptureWorkingSetStore, root: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        return (
            try CaptureWorkingSetStore(rootDirectory: root),
            root
        )
    }

    func testAuthoritiesCommitAtomicallyWithPair() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = try SurfaceSemanticAuthority(
            binding: binding(),
            hostClassification: .roomBoundary
        )
        let authorities = try TheaterAuthorityCollection(
            surfaceSemantics: [record]
        )
        let authorityPackage =
            try TheaterAuthorityPackageBuilder.build(
                collection: authorities
            )
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage([
                try entity(type: .referencePoint, label: "ref"),
            ]),
            measurementPackage: try measurementPackage(),
            authorityPackage: authorityPackage
        )

        let url = root.appendingPathComponent(
            TheaterAuthorityPackage.path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let decoded = try JSONDecoder().decode(
            TheaterAuthorityCollection.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(decoded, authorities)
    }

    func testAuthorityEntityReferenceMustResolve() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let dangling = try SpeakerInstallationAuthority(
            speakerEntityID: AnnotationEntityID(),
            mountingMode: .standMounted
        )
        let authorities = try TheaterAuthorityCollection(
            speakerInstallations: [dangling]
        )
        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage([
                    try entity(
                        type: .referencePoint,
                        label: "ref"
                    ),
                ]),
                measurementPackage: try measurementPackage(),
                authorityPackage:
                    try TheaterAuthorityPackageBuilder.build(
                        collection: authorities
                    )
            )
            XCTFail("expected unresolvedAuthorityReference")
        } catch let error as CaptureWorkingSetError {
            guard case .unresolvedAuthorityReference = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    func testAuthorityWrongEntityTypeRejected() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let seat = try entity(type: .seat, label: "seat")
        let install = try SpeakerInstallationAuthority(
            speakerEntityID: seat.entityID,
            mountingMode: .standMounted
        )
        let authorities = try TheaterAuthorityCollection(
            speakerInstallations: [install]
        )
        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage([seat]),
                measurementPackage: try measurementPackage(),
                authorityPackage:
                    try TheaterAuthorityPackageBuilder.build(
                        collection: authorities
                    )
            )
            XCTFail("expected unresolvedAuthorityReference")
        } catch let error as CaptureWorkingSetError {
            guard case .unresolvedAuthorityReference = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    func testReplaceCanAddAuthoritiesAfterFirstCommit() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let seat = try entity(type: .seat, label: "seat")
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage([seat]),
            measurementPackage: try measurementPackage()
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    TheaterAuthorityPackage.path
                ).path
            )
        )

        let layout = try SeatLayoutAuthority(
            seatEntityID: seat.entityID,
            rowIdentifier: "A"
        )
        let authorities = try TheaterAuthorityCollection(
            seatLayouts: [layout]
        )
        try await store.replaceAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage([seat]),
            measurementPackage: try measurementPackage(),
            authorityPackage:
                try TheaterAuthorityPackageBuilder.build(
                    collection: authorities
                )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    TheaterAuthorityPackage.path
                ).path
            )
        )
    }

    func testReplaceCannotOrphanCommittedAuthorityRefs() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let seat = try entity(type: .seat, label: "seat")
        let layout = try SeatLayoutAuthority(
            seatEntityID: seat.entityID
        )
        let authorities = try TheaterAuthorityCollection(
            seatLayouts: [layout]
        )
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage([seat]),
            measurementPackage: try measurementPackage(),
            authorityPackage:
                try TheaterAuthorityPackageBuilder.build(
                    collection: authorities
                )
        )

        // Replacing entities without the referenced seat and without
        // new authorities must fail instead of orphaning the record.
        do {
            try await store.replaceAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage([
                    try entity(type: .referencePoint, label: "ref"),
                ]),
                measurementPackage: try measurementPackage()
            )
            XCTFail("expected unresolvedAuthorityReference")
        } catch let error as CaptureWorkingSetError {
            guard case .unresolvedAuthorityReference = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    func testSnapshotRevisionMustMatchWorkingSet() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let observation = try RoomStateObservation(
            kind: .door,
            state: .open,
            observedAtUTC: "2026-09-21T00:00:00Z"
        )
        let snapshot = try TheaterAuthorityBuilder.roomStateSnapshot(
            label: "doors open",
            captureRevisionID: CaptureRevisionID(),
            observedAtUTC: "2026-09-21T00:00:00Z",
            observations: [observation]
        )
        let authorities = try TheaterAuthorityCollection(
            roomStateObservations: [observation],
            roomStateSnapshots: [snapshot]
        )
        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage([
                    try entity(
                        type: .referencePoint,
                        label: "ref"
                    ),
                ]),
                measurementPackage: try measurementPackage(),
                authorityPackage:
                    try TheaterAuthorityPackageBuilder.build(
                        collection: authorities
                    )
            )
            XCTFail("expected authorityMismatch")
        } catch let error as CaptureWorkingSetError {
            guard case .authorityMismatch = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }
}
