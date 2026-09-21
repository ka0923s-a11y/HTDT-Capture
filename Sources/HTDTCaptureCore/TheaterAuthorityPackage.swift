import Foundation

public struct TheaterAuthorityPackage: Sendable, Equatable {
    public static let path = "annotations/authorities.json"

    public let collection: TheaterAuthorityCollection
    public let data: Data

    public init(
        collection: TheaterAuthorityCollection,
        data: Data
    ) {
        self.collection = collection
        self.data = data
    }
}

public enum TheaterAuthorityPackageBuilder {
    public static func build(
        collection: TheaterAuthorityCollection
    ) throws -> TheaterAuthorityPackage {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(collection)

        guard
            let decoded = try? JSONDecoder().decode(
                TheaterAuthorityCollection.self,
                from: data
            ),
            decoded == collection
        else {
            throw AnnotationMeasurementPackageError
                .encodedCollectionMismatch
        }

        return TheaterAuthorityPackage(
            collection: collection,
            data: data
        )
    }
}

/// Authoring helpers for authority records that must derive state from
/// other records — kept deterministic so the persisted bytes carry no
/// ambient input beyond what the caller supplied.
public enum TheaterAuthorityBuilder {
    /// Content digest for `RoomStateSnapshot.stateDigest`: SHA-256 over
    /// the sortedKeys JSON encoding of the resolved observations sorted
    /// by `observation_id`, so the snapshot identity is
    /// content-addressed rather than a bag of identifiers.
    public static func stateDigest(
        for observations: [RoomStateObservation]
    ) throws -> EvidenceSHA256 {
        let sorted = observations.sorted {
            $0.observationID.description < $1.observationID.description
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(sorted)
        return EvidenceIntegrity.sha256(of: data)
    }

    public static func roomStateSnapshot(
        snapshotID: RoomStateSnapshotID = RoomStateSnapshotID(),
        label: String,
        captureRevisionID: CaptureRevisionID,
        observedAtUTC: String,
        observations: [RoomStateObservation],
        campaignID: String? = nil
    ) throws -> RoomStateSnapshot {
        try RoomStateSnapshot(
            snapshotID: snapshotID,
            label: label,
            captureRevisionID: captureRevisionID,
            observedAtUTC: observedAtUTC,
            observationIDs: observations.map(\.observationID),
            campaignID: campaignID,
            stateDigest: stateDigest(for: observations)
        )
    }
}
