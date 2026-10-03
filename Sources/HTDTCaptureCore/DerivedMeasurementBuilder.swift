import Foundation

/// One spatial endpoint feeding a derived measurement (issue bolph71656-ai/HTDT-Capture#286): a
/// resolvable reference, the position used by the computation, the
/// authority class the geometry came from, and the lineage refs that
/// document it.
public struct MeasurementEndpointAuthority: Sendable, Equatable {
    /// Where the endpoint position's spatial authority comes from.
    /// `roomPlan` — the endpoint is bound to an accepted RoomPlan
    /// object/semantic entity; `mesh` — the endpoint rests on
    /// ARKit raycast/mesh evidence; `manual` — user authority only.
    public enum GeometryAuthority: String, Sendable, Equatable {
        case roomPlan
        case mesh
        case manual
    }

    /// Resolvable endpoint ref persisted in `endpoint_refs`
    /// (e.g. `"entity:<uuid>"`).
    public let ref: String
    public let xMeters: Double
    public let yMeters: Double
    public let zMeters: Double
    public let geometryAuthority: GeometryAuthority
    /// Lineage describing the endpoint (entity refs, mesh anchors,
    /// RoomPlan object IDs, frame refs) recorded in
    /// `derivation.source_refs`.
    public let sourceRefs: [String]

    public init(
        ref: String,
        xMeters: Double,
        yMeters: Double,
        zMeters: Double,
        geometryAuthority: GeometryAuthority,
        sourceRefs: [String] = []
    ) throws {
        let normalizedRef = SchemaOwnedText.nfc(ref)
        guard !normalizedRef.isEmpty else {
            throw MeasurementModelError.emptyEndpointReference
        }
        guard xMeters.isFinite, yMeters.isFinite, zMeters.isFinite
        else {
            throw MeasurementModelError.invalidVector
        }
        let normalizedSources = SchemaOwnedText.nfc(sourceRefs)
        guard normalizedSources.allSatisfy({ !$0.isEmpty }) else {
            throw MeasurementModelError.emptyEvidenceReference
        }
        self.ref = normalizedRef
        self.xMeters = xMeters
        self.yMeters = yMeters
        self.zMeters = zMeters
        self.geometryAuthority = geometryAuthority
        self.sourceRefs = normalizedSources
    }

    /// Adapts a staged annotation entity as a measurement endpoint. The
    /// endpoint ref is the entity's `entity:` authority link; the
    /// geometry authority is read from the placement provenance so a
    /// RoomPlan-bound point is never mislabeled as mesh authority.
    public init(entity: CaptureAnnotationEntity) throws {
        let values = entity.worldFromAnnotation.values
        let authority: GeometryAuthority
        switch entity.placement.method {
        case .roomPlanBinding:
            authority = .roomPlan
        case .meshHitTest, .raycast:
            authority = .mesh
        case .manualNumeric, .importedReference, .other:
            authority = .manual
        }
        // Lineage stays inside the evidence-ref grammar so every
        // source_ref is resolvable: the entity authority itself, the
        // backing mesh anchor, and the placement's evidence refs. The
        // entity record already carries its RoomPlan object / semantic
        // entity identity, so they are reachable through `entity:`.
        var lineage = ["entity:" + entity.entityID.description]
        if let meshAnchor = entity.placement.sourceMeshAnchorID {
            lineage.append(
                "mesh_anchor:" + meshAnchor.uuidString.lowercased()
            )
        }
        lineage.append(contentsOf: entity.placement.sourceEvidenceRefs)
        try self.init(
            ref: "entity:" + entity.entityID.description,
            xMeters: Double(values[12]),
            yMeters: Double(values[13]),
            zMeters: Double(values[14]),
            geometryAuthority: authority,
            sourceRefs: lineage
        )
    }
}

/// Produces provenance-correct derived `CaptureMeasurement` records
/// (issue bolph71656-ai/HTDT-Capture#286): a value the app computes from already-recorded spatial
/// authorities, carrying `roomplan_derived` / `lidar_derived` when both
/// endpoints share the corresponding geometry authority, or
/// `capture_app_derived` provenance when the computation rests on
/// manual/mixed authorities. The record is never user-attested —
/// attestations belong to operator-entered values, which stay separate
/// records for conflict review.
public enum DerivedMeasurementBuilder {
    public static let endpointDistanceAlgorithm =
        "endpoint_euclidean_distance"
    public static let endpointDisplacementAlgorithm =
        "endpoint_displacement_vector"
    public static let algorithmVersion = "1.0.0"

    public static func distance(
        quantityType: String = "endpoint_distance",
        endpointA: MeasurementEndpointAuthority,
        endpointB: MeasurementEndpointAuthority,
        coordinateSpaceID: CoordinateSpaceID,
        statedUncertainty: Double? = nil,
        observedAtUTC: String? = nil,
        evidenceRefs: [String] = []
    ) throws -> CaptureMeasurement {
        let dx = endpointB.xMeters - endpointA.xMeters
        let dy = endpointB.yMeters - endpointA.yMeters
        let dz = endpointB.zMeters - endpointA.zMeters
        return try build(
            quantityType: quantityType,
            value: .scalar((dx * dx + dy * dy + dz * dz).squareRoot()),
            unit: .meter,
            algorithm: endpointDistanceAlgorithm,
            endpointA: endpointA,
            endpointB: endpointB,
            coordinateSpaceID: coordinateSpaceID,
            statedUncertainty: statedUncertainty,
            observedAtUTC: observedAtUTC,
            evidenceRefs: evidenceRefs
        )
    }

    /// The displacement vector from endpoint A to endpoint B expressed
    /// in `coordinateSpaceID`.
    public static func displacement(
        quantityType: String = "displacement",
        endpointA: MeasurementEndpointAuthority,
        endpointB: MeasurementEndpointAuthority,
        coordinateSpaceID: CoordinateSpaceID,
        observedAtUTC: String? = nil,
        evidenceRefs: [String] = []
    ) throws -> CaptureMeasurement {
        try build(
            quantityType: quantityType,
            value: .vector3(
                endpointB.xMeters - endpointA.xMeters,
                endpointB.yMeters - endpointA.yMeters,
                endpointB.zMeters - endpointA.zMeters
            ),
            unit: .meter,
            algorithm: endpointDisplacementAlgorithm,
            endpointA: endpointA,
            endpointB: endpointB,
            coordinateSpaceID: coordinateSpaceID,
            statedUncertainty: nil,
            observedAtUTC: observedAtUTC,
            evidenceRefs: evidenceRefs
        )
    }

    private static func build(
        quantityType: String,
        value: MeasurementValue,
        unit: MeasurementUnit,
        algorithm: String,
        endpointA: MeasurementEndpointAuthority,
        endpointB: MeasurementEndpointAuthority,
        coordinateSpaceID: CoordinateSpaceID,
        statedUncertainty: Double?,
        observedAtUTC: String?,
        evidenceRefs: [String]
    ) throws -> CaptureMeasurement {
        guard endpointA.ref != endpointB.ref else {
            throw MeasurementModelError.duplicateEndpointReference
        }

        let acquisitionMethod: MeasurementAcquisitionMethod
        let provenanceClass: MeasurementProvenanceClass
        switch (
            endpointA.geometryAuthority,
            endpointB.geometryAuthority
        ) {
        case (.roomPlan, .roomPlan):
            acquisitionMethod = .roomPlanDerived
            provenanceClass = .appleRoomPlanInference
        case (.mesh, .mesh):
            acquisitionMethod = .lidarDerived
            provenanceClass = .arkitMeshReconstruction
        default:
            // Mixed or manual endpoint authorities can still produce an
            // honest computed value, but it must be labeled as capture-
            // app derivation rather than framework evidence (issue bolph71656-ai/HTDT-Capture#286).
            acquisitionMethod = .other
            provenanceClass = .captureAppDerived
        }

        let endpointRefs = [endpointA.ref, endpointB.ref]
        var sourceRefs: [String] = []
        for ref in
            endpointRefs + endpointA.sourceRefs + endpointB.sourceRefs
        where !sourceRefs.contains(ref) {
            sourceRefs.append(ref)
        }
        let derivation = try MeasurementDerivation(
            algorithm: algorithm,
            algorithmVersion: algorithmVersion,
            sourceRefs: sourceRefs
        )

        try MeasurementQuantityRegistry.validate(
            quantityType: quantityType,
            value: value,
            unit: unit,
            endpointCount: endpointRefs.count
        )
        return try CaptureMeasurement(
            quantityType: quantityType,
            value: value,
            unit: unit,
            coordinateSpaceID: coordinateSpaceID,
            endpointRefs: endpointRefs,
            acquisitionMethod: acquisitionMethod,
            statedUncertainty: statedUncertainty,
            observedAtUTC: observedAtUTC,
            userAttestation: .notAttested,
            provenanceClass: provenanceClass,
            derivation: derivation,
            evidenceRefs: evidenceRefs
        )
    }
}
