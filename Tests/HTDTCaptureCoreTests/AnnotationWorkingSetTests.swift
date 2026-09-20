import Foundation
import XCTest
@testable import HTDTCaptureCore

final class AnnotationWorkingSetTests: XCTestCase {
    func testPackagesAreDeterministicAndFeedQualityCompleteness() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        let space = CoordinateSpaceID()

        let left = try speaker(
            role: .left,
            label: "Left",
            space: space
        )
        let mlp = try CaptureAnnotationEntity(
            type: .listeningPosition,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .earCenter,
            label: "MLP",
            placement: PlacementProvenance(
                method: .manualNumeric
            )
        )

        let annotationPackage =
            try AnnotationEvidencePackageBuilder.build(
                entities: [mlp, left]
            )
        XCTAssertEqual(
            annotationPackage.collection.entities.map(
                \.entityID.description
            ),
            annotationPackage.collection.entities
                .map(\.entityID.description)
                .sorted()
        )
        try await store.persistAnnotationPackage(
            annotationPackage
        )

        let width = try CaptureMeasurement(
            quantityType: "room_width",
            value: .scalar(3.4),
            unit: .meter,
            acquisitionMethod: .laserDistanceMeter,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement,
            sourceValueText: "3.4 m"
        )
        let measurementPackage =
            try MeasurementEvidencePackageBuilder.build(
                measurements: [width]
            )
        try await store.persistMeasurementPackage(
            measurementPackage
        )

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                requireCompletedRoomPlan: false,
                minimumActiveMeshAnchors: 0,
                minimumEvidenceFrames: 0,
                requiredAnnotationKeys: [
                    "speaker:L",
                    "listening_position:MLP",
                ],
                requiredMeasurementQuantityTypes: [
                    "room_width",
                ]
            )
        )

        XCTAssertTrue(
            quality.annotationCompleteness.missing.isEmpty
        )
        XCTAssertTrue(
            quality.measurementCompleteness.missing.isEmpty
        )
        XCTAssertEqual(quality.integrityStatus, .pass)

        let snapshot = await store.snapshot()
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == "annotations/entities.json"
            }
        )
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == "annotations/measurements.json"
            }
        )
    }

    func testAnnotationCoordinateMustMatchWorkingSetAuthority() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        let session = CaptureSessionID()
        let firstSpace = CoordinateSpaceID()
        let raw = RoomPlanEvidenceArtifactBuilder.buildRaw(
            data: Data("raw".utf8),
            captureSessionID: session,
            coordinateSpaceID: firstSpace,
            runtime: CaptureRuntimeProvenance(
                osVersion: "test",
                appVersion: "test",
                appBuild: "test"
            )
        )
        try await store.persistRawRoomPlan(raw)

        let mismatched = try speaker(
            role: .left,
            label: "Left",
            space: CoordinateSpaceID()
        )
        let package = try AnnotationEvidencePackageBuilder.build(
            entities: [mismatched]
        )

        do {
            try await store.persistAnnotationPackage(package)
            XCTFail("expected coordinate mismatch")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .authorityMismatch)
        }
    }

    func testAnnotationTamperFailsWorkingSetPreflight() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(
            rootDirectory: root
        )
        let package = try AnnotationEvidencePackageBuilder.build(
            entities: [
                try CaptureAnnotationEntity(
                    type: .listeningPosition,
                    coordinateSpaceID: CoordinateSpaceID(),
                    worldFromAnnotation: .identity,
                    referencePointSemantics: .earCenter,
                    label: "MLP",
                    placement: PlacementProvenance(
                        method: .manualNumeric
                    )
                ),
            ]
        )
        try await store.persistAnnotationPackage(package)

        try Data(#"{"tampered":true}"#.utf8).write(
            to: root.appendingPathComponent(
                AnnotationEvidencePackage.path
            ),
            options: .atomic
        )

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                requireCompletedRoomPlan: false,
                minimumActiveMeshAnchors: 0,
                minimumEvidenceFrames: 0
            )
        )
        XCTAssertEqual(quality.integrityStatus, .fail)
    }

    private func speaker(
        role: ChannelRole,
        label: String,
        space: CoordinateSpaceID
    ) throws -> CaptureAnnotationEntity {
        try CaptureAnnotationEntity(
            type: .speaker,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .cabinetReferencePoint,
            label: label,
            placement: PlacementProvenance(
                method: .manualNumeric
            ),
            orientation: OrientationAxes(
                frontAxisLocal:
                    SpatialVector3F.unit(0, 0, -1),
                upAxisLocal:
                    SpatialVector3F.unit(0, 1, 0)
            ),
            channelRole: role
        )
    }
}
