import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #186: manifest payload provenance is derived from the records in
/// each collection; mixed-provenance collections fail closed.
final class AnnotationMeasurementProvenanceTests: XCTestCase {
    func testImportedReferenceAnnotationDeclaresImportedProvenance()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let package = try AnnotationEvidencePackageBuilder.build(
            entities: [
                try CaptureAnnotationEntity(
                    type: .referencePoint,
                    coordinateSpaceID: CoordinateSpaceID(),
                    worldFromAnnotation: .identity,
                    referencePointSemantics: .userReferencePoint,
                    label: "imported",
                    provenanceClass: .importedReference,
                    placement: PlacementProvenance(
                        method: .importedReference
                    )
                ),
            ]
        )

        try await store.persistAnnotationPackage(package)

        let snapshot = await store.snapshot()
        let declaration = try XCTUnwrap(
            snapshot.payloadDeclarations.first {
                $0.path == AnnotationEvidencePackage.path
            }
        )
        XCTAssertEqual(
            declaration.provenanceClass,
            .importedReference
        )
    }

    func testRoomPlanDerivedMeasurementDeclaresRoomPlanProvenance()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let package = try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: "wall_length",
                    value: .scalar(4.2),
                    unit: .meter,
                    acquisitionMethod: .roomPlanDerived,
                    userAttestation: .notAttested,
                    provenanceClass: .appleRoomPlanInference
                ),
            ]
        )

        try await store.persistMeasurementPackage(package)

        let snapshot = await store.snapshot()
        let declaration = try XCTUnwrap(
            snapshot.payloadDeclarations.first {
                $0.path == MeasurementEvidencePackage.path
            }
        )
        XCTAssertEqual(
            declaration.provenanceClass,
            .appleRoomPlanInference
        )
    }

    func testMixedProvenanceAnnotationCollectionIsRejectedBeforeWrite()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let space = CoordinateSpaceID()
        let userEntity = try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "user",
            provenanceClass: .userAnnotation,
            placement: PlacementProvenance(method: .manualNumeric)
        )
        let importedEntity = try CaptureAnnotationEntity(
            type: .referencePoint,
            coordinateSpaceID: space,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "imported",
            provenanceClass: .importedReference,
            placement: PlacementProvenance(
                method: .importedReference
            )
        )
        let annotationPackage =
            try AnnotationEvidencePackageBuilder.build(
                entities: [userEntity, importedEntity]
            )
        let measurementPackage =
            try MeasurementEvidencePackageBuilder.build(
                measurements: [
                    try CaptureMeasurement(
                        quantityType: "room_width",
                        value: .scalar(3.4),
                        unit: .meter,
                        acquisitionMethod: .laserDistanceMeter,
                        userAttestation: .attested,
                        provenanceClass: .userAttestedMeasurement
                    ),
                ]
            )

        do {
            try await store
                .persistAnnotationAndMeasurementPackages(
                    annotationPackage: annotationPackage,
                    measurementPackage: measurementPackage
                )
            XCTFail("expected mixed-provenance rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .mixedProvenanceCollection(
                    AnnotationEvidencePackage.path
                )
            )
        }

        // Nothing was written or declared; the capture stays recoverable.
        let snapshot = await store.snapshot()
        XCTAssertTrue(snapshot.payloadDeclarations.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        AnnotationEvidencePackage.path
                    )
                    .path
            )
        )

        // A homogeneous retry succeeds after the rejection.
        let homogeneous =
            try AnnotationEvidencePackageBuilder.build(
                entities: [importedEntity]
            )
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: homogeneous,
            measurementPackage: measurementPackage
        )
        let recovered = await store.snapshot()
        let byPath = Dictionary(
            uniqueKeysWithValues: recovered.payloadDeclarations.map {
                ($0.path, $0)
            }
        )
        XCTAssertEqual(
            byPath[AnnotationEvidencePackage.path]?.provenanceClass,
            .importedReference
        )
        XCTAssertEqual(
            byPath[MeasurementEvidencePackage.path]?.provenanceClass,
            .userAttestedMeasurement
        )
    }

    func testMixedProvenanceMeasurementCollectionIsRejectedBeforeWrite()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let package = try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: "room_width",
                    value: .scalar(3.4),
                    unit: .meter,
                    acquisitionMethod: .laserDistanceMeter,
                    userAttestation: .attested,
                    provenanceClass: .userAttestedMeasurement
                ),
                try CaptureMeasurement(
                    quantityType: "wall_length",
                    value: .scalar(4.2),
                    unit: .meter,
                    acquisitionMethod: .roomPlanDerived,
                    userAttestation: .notAttested,
                    provenanceClass: .appleRoomPlanInference
                ),
            ]
        )

        do {
            try await store.persistMeasurementPackage(package)
            XCTFail("expected mixed-provenance rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .mixedProvenanceCollection(
                    MeasurementEvidencePackage.path
                )
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        MeasurementEvidencePackage.path
                    )
                    .path
            )
        )
    }

    func testEmptyCollectionsDeclareContainerProvenance() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try AnnotationEvidencePackageBuilder
                .build(entities: []),
            measurementPackage: try MeasurementEvidencePackageBuilder
                .build(measurements: [])
        )

        let snapshot = await store.snapshot()
        let byPath = Dictionary(
            uniqueKeysWithValues: snapshot.payloadDeclarations.map {
                ($0.path, $0)
            }
        )
        // An empty collection carries no record authority; the container
        // is honestly declared as capture-app derived.
        XCTAssertEqual(
            byPath[AnnotationEvidencePackage.path]?.provenanceClass,
            .captureAppDerived
        )
        XCTAssertEqual(
            byPath[MeasurementEvidencePackage.path]?.provenanceClass,
            .captureAppDerived
        )
    }
}
