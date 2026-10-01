import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #138: the combined annotation+measurement persistence must be
/// one atomic transaction — both canonical files durable before any
/// declaration commits, rollback removes only attempt-owned bytes, and
/// conflicting canonical bytes fail closed with no partial authority.
final class AnnotationMeasurementTransactionTests: XCTestCase {
    private let space = CoordinateSpaceID()

    private func annotationPackage(
        label: String = "note"
    ) throws -> AnnotationEvidencePackage {
        try AnnotationEvidencePackageBuilder.build(
            entities: [
                try CaptureAnnotationEntity(
                    type: .referencePoint,
                    coordinateSpaceID: space,
                    worldFromAnnotation: .identity,
                    referencePointSemantics: .userReferencePoint,
                    label: label,
                    provenanceClass: .userAnnotation,
                    placement: PlacementProvenance(
                        method: .manualNumeric
                    )
                ),
            ]
        )
    }

    private func measurementPackage(
        quantityType: String = "x_wall_length"
    ) throws -> MeasurementEvidencePackage {
        try MeasurementEvidencePackageBuilder.build(
            measurements: [
                try CaptureMeasurement(
                    quantityType: quantityType,
                    value: .scalar(4.2),
                    unit: .meter,
                    acquisitionMethod: .laserDistanceMeter,
                    userAttestation: .attested,
                    provenanceClass: .userAttestedMeasurement
                ),
            ]
        )
    }

    /// The writer batch commits annotation bytes before it reaches the
    /// conflicting measurement path, so this exercises the exact
    /// "second-file write failure rolls back the first file" path.
    func testSecondFileConflictRollsBackFirstFileAtomically()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let conflictBytes = Data("conflicting-measurements".utf8)

        // Pre-seed a conflicting canonical measurement payload through
        // an independent writer so the transaction's second file write
        // fails after the first file has already been created.
        let writer = try AtomicCaptureFileWriter(
            rootDirectory: root
        )
        try await writer.write(
            conflictBytes,
            to: try CaptureStorePath(
                MeasurementEvidencePackage.path
            )
        )

        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage(),
                measurementPackage: try measurementPackage()
            )
            XCTFail("expected conflicting canonical bytes rejection")
        } catch let error as CaptureFileWriterError {
            guard case .alreadyExists = error else {
                XCTFail("unexpected writer error: \(error)")
                return
            }
        }

        // The annotation file written earlier in the same batch is
        // rolled back; the pre-existing conflicting bytes are never
        // touched.
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        AnnotationEvidencePackage.path
                    )
                    .path
            ),
            "first-file bytes survived a failed transaction"
        )
        XCTAssertEqual(
            try Data(
                contentsOf: root.appendingPathComponent(
                    MeasurementEvidencePackage.path
                )
            ),
            conflictBytes,
            "conflicting canonical bytes were overwritten"
        )

        // No partial declarations or in-memory authority survive.
        let snapshot = await store.snapshot()
        XCTAssertFalse(
            snapshot.payloadDeclarations.contains {
                $0.path == AnnotationEvidencePackage.path
                    || $0.path == MeasurementEvidencePackage.path
            }
        )

        // The failed transaction is recoverable: removing the conflict
        // and retrying commits both files and both declarations.
        try await writer.removeIfPresent(
            try CaptureStorePath(
                MeasurementEvidencePackage.path
            )
        )
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage(),
            measurementPackage: try measurementPackage()
        )
        let recovered = await store.snapshot()
        XCTAssertTrue(
            recovered.payloadDeclarations.contains {
                $0.path == AnnotationEvidencePackage.path
            }
        )
        XCTAssertTrue(
            recovered.payloadDeclarations.contains {
                $0.path == MeasurementEvidencePackage.path
            }
        )
        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testConflictingCanonicalCollectionFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage(label: "first"),
            measurementPackage: try measurementPackage()
        )

        // A different annotation collection targeting the same
        // canonical path is a true authority conflict and must fail
        // closed without disturbing the committed collection.
        do {
            try await store.persistAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage(
                    label: "different"
                ),
                measurementPackage: try measurementPackage()
            )
            XCTFail("expected duplicatePayloadDeclaration")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(
                error,
                .duplicatePayloadDeclaration(
                    AnnotationEvidencePackage.path
                )
            )
        }

        let snapshot = await store.snapshot()
        let annotationData = try Data(
            contentsOf: root.appendingPathComponent(
                AnnotationEvidencePackage.path
            )
        )
        let decoded = try JSONDecoder().decode(
            CaptureAnnotationCollection.self,
            from: annotationData
        )
        XCTAssertEqual(decoded.entities.first?.label, "first")
        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    func testIdenticalReplayIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        let annotation = try annotationPackage()
        let measurement = try measurementPackage()

        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: annotation,
            measurementPackage: measurement
        )
        // Byte-identical replay of the same transaction must succeed
        // and commit exactly one declaration per canonical path.
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: annotation,
            measurementPackage: measurement
        )

        let snapshot = await store.snapshot()
        let annotationDeclarations =
            snapshot.payloadDeclarations.filter {
                $0.path == AnnotationEvidencePackage.path
            }
        let measurementDeclarations =
            snapshot.payloadDeclarations.filter {
                $0.path == MeasurementEvidencePackage.path
            }
        XCTAssertEqual(annotationDeclarations.count, 1)
        XCTAssertEqual(measurementDeclarations.count, 1)

        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    /// Issue #163: a re-opened editor commits a corrected
    /// annotation+measurement pair over the earlier commit. The replace
    /// is one atomic batch — both canonical files carry the new bytes,
    /// declarations re-derive, and in-memory authority matches the new
    /// collections.
    func testReplaceCommitsCorrectedPairAtomically() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage(label: "first"),
            measurementPackage: try measurementPackage(
                quantityType: "x_wall_length"
            )
        )

        try await store.replaceAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage(label: "corrected"),
            measurementPackage: try measurementPackage(
                quantityType: "room_width"
            )
        )

        let annotationData = try Data(
            contentsOf: root.appendingPathComponent(
                AnnotationEvidencePackage.path
            )
        )
        let decodedAnnotations = try JSONDecoder().decode(
            CaptureAnnotationCollection.self,
            from: annotationData
        )
        XCTAssertEqual(
            decodedAnnotations.entities.first?.label,
            "corrected"
        )

        let measurementData = try Data(
            contentsOf: root.appendingPathComponent(
                MeasurementEvidencePackage.path
            )
        )
        let decodedMeasurements = try JSONDecoder().decode(
            CaptureMeasurementCollection.self,
            from: measurementData
        )
        XCTAssertEqual(
            decodedMeasurements.measurements.first?.quantityType,
            "room_width"
        )

        let snapshot = await store.snapshot()
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == AnnotationEvidencePackage.path
            }
        )
        XCTAssertTrue(
            snapshot.payloadDeclarations.contains {
                $0.path == MeasurementEvidencePackage.path
            }
        )
        let quality = await store.evaluateQuality(
            requirements: CaptureQualityRequirements(
                rulesetVersion: "1.0.0")
        )
        XCTAssertEqual(quality.integrityStatus, .pass)
    }

    /// A failed second replacement restores the first file's exact
    /// prior bytes — the working set never retains a mixed pair.
    func testFailedSecondReplacementRestoresFirstFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage(label: "first"),
            measurementPackage: try measurementPackage()
        )
        let originalAnnotationBytes = try Data(
            contentsOf: root.appendingPathComponent(
                AnnotationEvidencePackage.path
            )
        )

        // A directory at the measurement target makes the second
        // replace fail after the first file was already swapped.
        let measurementTarget = root.appendingPathComponent(
            MeasurementEvidencePackage.path
        )
        try FileManager.default.removeItem(at: measurementTarget)
        try FileManager.default.createDirectory(
            at: measurementTarget,
            withIntermediateDirectories: true
        )

        do {
            try await store.replaceAnnotationAndMeasurementPackages(
                annotationPackage: try annotationPackage(
                    label: "corrected"
                ),
                measurementPackage: try measurementPackage(
                    quantityType: "room_width"
                )
            )
            XCTFail("expected replacement failure")
        } catch {
            // Any failure is acceptable; the guarantee under test is
            // the exact-byte restoration of the first file.
        }

        XCTAssertEqual(
            try Data(
                contentsOf: root.appendingPathComponent(
                    AnnotationEvidencePackage.path
                )
            ),
            originalAnnotationBytes,
            "first-file bytes were not restored after batch failure"
        )
    }

    /// A replacement cannot move the committed pair into a different
    /// coordinate space than the authority already bound.
    func testReplaceCannotMoveCoordinateAuthority() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try CaptureWorkingSetStore(rootDirectory: root)
        try await store.persistAnnotationAndMeasurementPackages(
            annotationPackage: try annotationPackage(),
            measurementPackage: try measurementPackage()
        )

        let foreignSpace = CoordinateSpaceID()
        do {
            try await store.replaceAnnotationAndMeasurementPackages(
                annotationPackage:
                    AnnotationEvidencePackageBuilder.build(
                        entities: [
                            try CaptureAnnotationEntity(
                                type: .referencePoint,
                                coordinateSpaceID: foreignSpace,
                                worldFromAnnotation: .identity,
                                referencePointSemantics:
                                    .userReferencePoint,
                                label: "foreign",
                                provenanceClass: .userAnnotation,
                                placement: PlacementProvenance(
                                    method: .manualNumeric
                                )
                            ),
                        ]
                    ),
                measurementPackage: try measurementPackage()
            )
            XCTFail("expected coordinate authority rejection")
        } catch let error as CaptureWorkingSetError {
            XCTAssertEqual(error, .authorityMismatch)
        }
    }
}
