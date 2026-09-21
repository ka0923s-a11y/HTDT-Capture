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
    /// `priorEntities` is the collection committed earlier in this
    /// revision. When provided, any surviving entity whose record
    /// differs from its prior version is stamped with `updated_at_utc`
    /// so a pre-finalization correction revises lifecycle metadata
    /// explicitly rather than silently replacing it (#267).
    public static func build(
        entities: [CaptureAnnotationEntity],
        priorEntities: [CaptureAnnotationEntity]? = nil,
        revisedAt now: Date = Date()
    ) throws -> AnnotationEvidencePackage {
        var entities = entities
        if let priorEntities {
            let priorByID = Dictionary(
                priorEntities.map { ($0.entityID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let stamp = BundleTimestamp.utcString(from: now)
            entities = try entities.map { entity in
                guard let prior = priorByID[entity.entityID],
                      prior != entity
                else {
                    return entity
                }
                return try entity.revised(at: stamp)
            }
        }
        let sorted = entities.sorted {
            $0.entityID.description < $1.entityID.description
        }
        let collection = try CaptureAnnotationCollection(
            entities: sorted
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
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
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
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
