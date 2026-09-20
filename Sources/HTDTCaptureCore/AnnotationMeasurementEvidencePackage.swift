import Foundation

public enum AnnotationMeasurementPackageError:
    Error,
    Sendable,
    Equatable
{
    case encodedCollectionMismatch
}

public struct AnnotationEvidencePackage: Sendable, Equatable {
    public static let path = "annotations/entities.json"

    public let collection: CaptureAnnotationCollection
    public let data: Data

    public init(
        collection: CaptureAnnotationCollection,
        data: Data
    ) {
        self.collection = collection
        self.data = data
    }
}

public struct MeasurementEvidencePackage: Sendable, Equatable {
    public static let path = "annotations/measurements.json"

    public let collection: CaptureMeasurementCollection
    public let data: Data

    public init(
        collection: CaptureMeasurementCollection,
        data: Data
    ) {
        self.collection = collection
        self.data = data
    }
}

public enum AnnotationEvidencePackageBuilder {
    public static func build(
        entities: [CaptureAnnotationEntity]
    ) throws -> AnnotationEvidencePackage {
        let sorted = entities.sorted {
            $0.entityID.description < $1.entityID.description
        }
        let collection = try CaptureAnnotationCollection(
            entities: sorted
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(collection)

        guard
            let decoded = try? JSONDecoder().decode(
                CaptureAnnotationCollection.self,
                from: data
            ),
            decoded == collection
        else {
            throw AnnotationMeasurementPackageError
                .encodedCollectionMismatch
        }

        return AnnotationEvidencePackage(
            collection: collection,
            data: data
        )
    }
}

public enum MeasurementEvidencePackageBuilder {
    public static func build(
        measurements: [CaptureMeasurement]
    ) throws -> MeasurementEvidencePackage {
        let sorted = measurements.sorted {
            $0.measurementID.description
                < $1.measurementID.description
        }
        let collection = try CaptureMeasurementCollection(
            measurements: sorted
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(collection)

        guard
            let decoded = try? JSONDecoder().decode(
                CaptureMeasurementCollection.self,
                from: data
            ),
            decoded == collection
        else {
            throw AnnotationMeasurementPackageError
                .encodedCollectionMismatch
        }

        return MeasurementEvidencePackage(
            collection: collection,
            data: data
        )
    }
}
