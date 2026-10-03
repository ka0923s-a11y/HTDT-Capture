import Foundation

public struct MeasurementID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum MeasurementAcquisitionMethod: String, Codable, Sendable {
    case tapeMeasure = "tape_measure"
    case laserDistanceMeter = "laser_distance_meter"
    case manufacturerSpecification = "manufacturer_specification"
    /// A value read from a connected or standalone external instrument
    /// (thermometer, hygrometer, SPL meter, ...) that is neither a tape
    /// nor a laser distance measurement. Keeps external-meter readings
    /// distinguishable from bare manual entry (issue bolph71656-ai/HTDT-Capture#253).
    case externalInstrument = "external_instrument"
    case lidarDerived = "lidar_derived"
    case roomPlanDerived = "roomplan_derived"
    case other
}

public enum MeasurementProvenanceClass: String, Codable, Sendable {
    case userAttestedMeasurement = "user_attested_measurement"
    case appleRoomPlanInference = "apple_roomplan_inference"
    case arkitMeshReconstruction = "arkit_mesh_reconstruction"
    case importedReference = "imported_reference"
    /// The capture app itself computed the value from other recorded
    /// authorities (e.g. a displacement between user-placed endpoints).
    /// Distinct from `user_attested_measurement` because the stored
    /// number was not operator-entered, and distinct from the
    /// framework-derived classes because the source geometry is not a
    /// RoomPlan/ARKit artifact.
    case captureAppDerived = "capture_app_derived"
}

public enum UserAttestationState: String, Codable, Sendable {
    case notAttested = "not_attested"
    case attested
}

/// Canonical persisted unit tokens (Capture Bundle v1). Only canonical
/// units are stored; practical input units (cm/mm/ft/in/degF/...) are a
/// presentation concern and are normalized before a record is written
/// (issue bolph71656-ai/HTDT-Capture#235). `degreeCelsius` uses explicit semantics:
/// `K = degC + 273.15` exactly (issue bolph71656-ai/HTDT-Capture#269).
public enum MeasurementUnit: String, Codable, Sendable {
    case meter = "m"
    case radian = "rad"
    case second = "s"
    case degreeCelsius = "degC"
    case percent = "%"
    case dimensionless = "1"

    /// The physical dimension this unit measures. `percent` is a
    /// hundredths-scaled dimensionless ratio.
    public var dimension: MeasurementDimension {
        switch self {
        case .meter:
            return .length
        case .radian:
            return .angle
        case .second:
            return .time
        case .degreeCelsius:
            return .temperature
        case .percent, .dimensionless:
            return .dimensionless
        }
    }
}

public enum MeasurementModelError: Error, Sendable, Equatable {
    case emptyQuantityType
    case invalidScalar
    case invalidVector
    case emptyEndpointReference
    case emptyEvidenceReference
    case duplicateEndpointReference
    case duplicateEvidenceReference
    case negativeUncertainty
    case missingSpatialCoordinateAuthority
    case userAttestationRequired
    case derivedAcquisitionNotUserAttestable
    case invalidObservedTimestamp
    case invalidCalibrationDate
    case duplicateMeasurementID
    case incompatibleUnitForQuantity
    case incompatibleValueShapeForQuantity
    case invalidEndpointCountForQuantity
    case emptySourceAuthority
    case sourceAuthorityRequiresManufacturerSpecification
    case nonDerivedDerivation
    case derivedProvenanceMismatch
    case missingDerivationAuthority
    /// An unregistered `quantity_type` token lacks the reserved `x_`
    /// custom namespace prefix on a v1.1.0+ payload (legacy bolph71656-ai/HTDT-Capture#344).
    case unscopedCustomQuantity
    /// The value lies outside the quantity's physical domain (legacy bolph71656-ai/HTDT-Capture#334).
    case valueOutsideQuantityDomain
    /// Structured uncertainty fields are contradictory or malformed
    /// (legacy bolph71656-ai/HTDT-Capture#334).
    case invalidUncertainty
    /// Lineage fields are contradictory or malformed (legacy bolph71656-ai/HTDT-Capture#304).
    case invalidMeasurementLineage
    /// The document claims a schema_version this contract does not
    /// support (legacy bolph71656-ai/HTDT-Capture#332).
    case unsupportedSchemaVersion
}

public enum MeasurementValue: Codable, Sendable, Equatable {
    case scalar(Double)
    case vector3(Double, Double, Double)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let scalar = try? container.decode(Double.self) {
            guard scalar.isFinite else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Measurement scalar must be finite"
                )
            }
            self = .scalar(scalar)
            return
        }

        let values = try container.decode([Double].self)
        guard values.count == 3,
              values.allSatisfy(\.isFinite)
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Measurement vector must contain three finite values"
            )
        }
        self = .vector3(values[0], values[1], values[2])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .scalar(value):
            guard value.isFinite else {
                throw MeasurementModelError.invalidScalar
            }
            try container.encode(value)
        case let .vector3(x, y, z):
            guard x.isFinite, y.isFinite, z.isFinite else {
                throw MeasurementModelError.invalidVector
            }
            try container.encode([x, y, z])
        }
    }

    public var isSpatialVector: Bool {
        if case .vector3 = self { return true }
        return false
    }

    public var allFinite: Bool {
        switch self {
        case let .scalar(value):
            return value.isFinite
        case let .vector3(x, y, z):
            return x.isFinite && y.isFinite && z.isFinite
        }
    }
}

/// What the stated `value` number means (legacy bolph71656-ai/HTDT-Capture#334). The kind never
/// conflates measurement uncertainty with an installation
/// tolerance or a fit residual — those live on their own records.
public enum MeasurementUncertaintyKind: String, Codable, Sendable {
    /// Hard bound: |error| <= value.
    case absoluteBound = "absolute_bound"
    /// Manufacturer-specified instrument accuracy.
    case manufacturerAccuracy = "manufacturer_accuracy"
    /// One standard deviation of the observation distribution.
    case standardUncertainty = "standard_uncertainty"
    /// Expanded uncertainty: value = k * u, `coverage_factor`
    /// records k.
    case expandedUncertainty = "expanded_uncertainty"
    /// Instrument display/reading resolution.
    case resolution
    /// Spread estimated from repeated observations.
    case repeatabilityEstimate = "repeatability_estimate"
    /// A bare number whose semantics the author did not declare —
    /// the explicit marker, not an omission.
    case unknownStated = "unknown_stated"
}

/// Typed uncertainty authority for a measurement record (legacy bolph71656-ai/HTDT-Capture#334).
/// Replaces the semantics-free `stated_uncertainty` scalar with a
/// declared kind, declared unit (or same-as-quantity), optional
/// coverage metadata, and a provenance basis. `coverage_factor` and
/// `confidence_level` are never fabricated — they are recorded
/// only when the author supplied them.
public struct MeasurementUncertainty: Codable, Sendable, Equatable {
    /// The uncertainty magnitude; non-negative, finite.
    public let value: Double
    /// The unit `value` is expressed in; nil means the
    /// measurement's own unit (`same_as_quantity`).
    public let unit: MeasurementUnit?
    public let kind: MeasurementUncertaintyKind
    /// Coverage factor k for `expanded_uncertainty` — the only
    /// kind it may accompany.
    public let coverageFactor: Double?
    /// Declared confidence level in (0, 1]; only meaningful with a
    /// declared statistical kind (standard/expanded).
    public let confidenceLevel: Double?
    /// Where the number came from — user/instrument-stated,
    /// app-estimated, or other.
    public let source: SpatialUncertaintyBasis
    /// Evidence backing the stated value (datasheet, calibration
    /// certificate, repeatability series).
    public let evidenceRefs: [String]

    public init(
        value: Double,
        unit: MeasurementUnit? = nil,
        kind: MeasurementUncertaintyKind,
        coverageFactor: Double? = nil,
        confidenceLevel: Double? = nil,
        source: SpatialUncertaintyBasis,
        evidenceRefs: [String] = []
    ) throws {
        guard value.isFinite, value >= 0 else {
            throw MeasurementModelError.invalidUncertainty
        }
        if let coverageFactor {
            guard kind == .expandedUncertainty,
                  coverageFactor.isFinite,
                  coverageFactor > 0
            else {
                throw MeasurementModelError.invalidUncertainty
            }
        }
        if let confidenceLevel {
            guard kind == .expandedUncertainty
                    || kind == .standardUncertainty,
                  confidenceLevel.isFinite,
                  confidenceLevel > 0,
                  confidenceLevel <= 1
            else {
                throw MeasurementModelError.invalidUncertainty
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty })
        else {
            throw MeasurementModelError.emptyEvidenceReference
        }
        self.value = value
        self.unit = unit
        self.kind = kind
        self.coverageFactor = coverageFactor
        self.confidenceLevel = confidenceLevel
        self.source = source
        self.evidenceRefs = normalizedEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case unit
        case kind
        case coverageFactor = "coverage_factor"
        case confidenceLevel = "confidence_level"
        case source
        case evidenceRefs = "evidence_refs"
    }
}

/// A pointer to a measurement record in this or an earlier
/// capture revision (legacy bolph71656-ai/HTDT-Capture#304). `capture_revision_id` nil means the
/// same revision — same-session retakes never need to know the
/// revision id at authoring time.
public struct MeasurementLineageReference:
    Codable, Sendable, Equatable
{
    public let captureRevisionID: CaptureRevisionID?
    public let measurementID: MeasurementID

    public init(
        captureRevisionID: CaptureRevisionID? = nil,
        measurementID: MeasurementID
    ) {
        self.captureRevisionID = captureRevisionID
        self.measurementID = measurementID
    }

    private enum CodingKeys: String, CodingKey {
        case captureRevisionID = "capture_revision_id"
        case measurementID = "measurement_id"
    }
}

/// How a measurement observation relates to a prior record
/// (legacy bolph71656-ai/HTDT-Capture#304). Repeat vs retake is a semantic distinction the wire
/// must carry — it is not derivable from equal type/unit.
public enum MeasurementLineageRelation: String, Codable, Sendable {
    /// An independent repeated observation of the same quantity —
    /// retained alongside the parent as corroborating evidence.
    case independentRepeat = "independent_repeat"
    /// A re-observation replacing a flawed attempt of the same
    /// observation identity.
    case retakeOf = "retake_of"
    /// This record supersedes the parent's claim.
    case supersedes
    /// This record verifies the parent's value (e.g. an as-built
    /// check against a nominal).
    case verificationOf = "verification_of"
}

/// Disposition of a measurement record inside the working set
/// (legacy bolph71656-ai/HTDT-Capture#304). `superseded` is a declared state, never deletion: prior
/// evidence is never removed or rewritten.
public enum MeasurementDisposition: String, Codable, Sendable {
    /// Authoritative current value.
    case active
    /// A later record supersedes this one; retained as evidence.
    case superseded
    /// Rejected at authoring; `disposition_reason` carries why.
    case rejectedWithReason = "rejected_with_reason"
    /// Retained as an independent repeat corroborating record.
    case retainedRepeat = "retained_repeat"
}

/// Typed binding from a measurement to the task-plan item it was
/// captured to satisfy (legacy bolph71656-ai/HTDT-Capture#354) — the stronger endpoint contract that
/// replaces generic type/unit matching when a plan item declares
/// `endpoint_semantics`.
public struct MeasurementTaskRef: Codable, Sendable, Equatable {
    public let planID: String
    public let itemID: String

    public init(planID: String, itemID: String) throws {
        let normalizedPlan = SchemaOwnedText.nfc(planID)
        let normalizedItem = SchemaOwnedText.nfc(itemID)
        guard !normalizedPlan.isEmpty, !normalizedItem.isEmpty
        else {
            throw MeasurementModelError.invalidMeasurementLineage
        }
        self.planID = normalizedPlan
        self.itemID = normalizedItem
    }

    private enum CodingKeys: String, CodingKey {
        case planID = "plan_id"
        case itemID = "item_id"
    }
}

/// Measurement observation lineage (legacy bolph71656-ai/HTDT-Capture#304): requested-observation
/// identity, prior-record relation, and disposition. Nil on a
/// legacy record means lineage was never asserted — the record is
/// treated as an active independent observation.
public struct MeasurementLineage: Codable, Sendable, Equatable {
    /// Relation to a prior observation; absent means this is an
    /// independent observation (no parent).
    public let relation: MeasurementLineageRelation?
    /// The parent observation for retake/supersedes/verification
    /// relations; required exactly when `relation` claims one.
    public let parentMeasurementRef: MeasurementLineageReference?
    public let disposition: MeasurementDisposition
    /// Required iff `disposition == .rejectedWithReason`.
    public let dispositionReason: String?
    /// The task-plan item this observation was requested to
    /// satisfy (legacy bolph71656-ai/HTDT-Capture#354).
    public let taskRef: MeasurementTaskRef?

    public init(
        relation: MeasurementLineageRelation? = nil,
        parentMeasurementRef: MeasurementLineageReference? = nil,
        disposition: MeasurementDisposition = .active,
        dispositionReason: String? = nil,
        taskRef: MeasurementTaskRef? = nil
    ) throws {
        switch relation {
        case .retakeOf, .supersedes, .verificationOf:
            guard parentMeasurementRef != nil else {
                throw MeasurementModelError
                    .invalidMeasurementLineage
            }
        case .independentRepeat, nil:
            guard parentMeasurementRef == nil else {
                throw MeasurementModelError
                    .invalidMeasurementLineage
            }
        }
        let normalizedReason =
            SchemaOwnedText.nfc(dispositionReason)
        switch disposition {
        case .rejectedWithReason:
            guard let normalizedReason,
                  !normalizedReason.isEmpty
            else {
                throw MeasurementModelError
                    .invalidMeasurementLineage
            }
        case .active, .superseded, .retainedRepeat:
            guard normalizedReason == nil else {
                throw MeasurementModelError
                    .invalidMeasurementLineage
            }
        }
        self.relation = relation
        self.parentMeasurementRef = parentMeasurementRef
        self.disposition = disposition
        self.dispositionReason = normalizedReason
        self.taskRef = taskRef
    }

    private enum CodingKeys: String, CodingKey {
        case relation
        case parentMeasurementRef = "parent_measurement_ref"
        case disposition
        case dispositionReason = "disposition_reason"
        case taskRef = "task_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        try self.init(
            relation: container.decodeIfPresent(
                MeasurementLineageRelation.self,
                forKey: .relation
            ),
            parentMeasurementRef: container.decodeIfPresent(
                MeasurementLineageReference.self,
                forKey: .parentMeasurementRef
            ),
            disposition: container.decodeIfPresent(
                MeasurementDisposition.self,
                forKey: .disposition
            ) ?? .active,
            dispositionReason: container.decodeIfPresent(
                String.self,
                forKey: .dispositionReason
            ),
            taskRef: container.decodeIfPresent(
                MeasurementTaskRef.self,
                forKey: .taskRef
            )
        )
    }
}

/// Structured source identity for `manufacturer_specification`
/// measurements (issue bolph71656-ai/HTDT-Capture#275). A datasheet/catalog value must be able to
/// point at the exact external authority it came from rather than
/// leaning on free-text notes. All fields optional, but at least one
/// must be present — an empty source authority carries no identity.
public struct MeasurementSourceAuthority: Codable, Sendable, Equatable {
    /// Exact HTDT equipment definition the measured property belongs to.
    public let equipmentRef: HTDTEquipmentReference?
    /// Identifies the manufacturer document/catalog entry
    /// (e.g. `"datasheet:<doc-id>"`, an imported document asset ref).
    public let documentRef: String?
    /// Document version/revision text when the source declares one.
    public let documentRevision: String?
    /// Which property the value represents inside the source
    /// (e.g. `"width"`, `"panel_dimensions_mm"`).
    public let propertyKey: String?
    /// SHA-256 of the retained source asset when the document is kept.
    public let sourceSHA256: EvidenceSHA256?

    public init(
        equipmentRef: HTDTEquipmentReference? = nil,
        documentRef: String? = nil,
        documentRevision: String? = nil,
        propertyKey: String? = nil,
        sourceSHA256: EvidenceSHA256? = nil
    ) throws {
        let normalizedDocument = SchemaOwnedText.nfc(documentRef)
        let normalizedRevision = SchemaOwnedText.nfc(documentRevision)
        let normalizedProperty = SchemaOwnedText.nfc(propertyKey)
        guard equipmentRef != nil
                || !(normalizedDocument ?? "").isEmpty
                || !(normalizedRevision ?? "").isEmpty
                || !(normalizedProperty ?? "").isEmpty
                || sourceSHA256 != nil
        else {
            throw MeasurementModelError.emptySourceAuthority
        }
        self.equipmentRef = equipmentRef
        self.documentRef = normalizedDocument
        self.documentRevision = normalizedRevision
        self.propertyKey = normalizedProperty
        self.sourceSHA256 = sourceSHA256
    }

    private enum CodingKeys: String, CodingKey {
        case equipmentRef = "equipment_ref"
        case documentRef = "document_ref"
        case documentRevision = "document_revision"
        case propertyKey = "property_key"
        case sourceSHA256 = "source_sha256"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            equipmentRef: container.decodeIfPresent(
                HTDTEquipmentReference.self,
                forKey: .equipmentRef
            ),
            documentRef: container.decodeIfPresent(
                String.self,
                forKey: .documentRef
            ),
            documentRevision: container.decodeIfPresent(
                String.self,
                forKey: .documentRevision
            ),
            propertyKey: container.decodeIfPresent(
                String.self,
                forKey: .propertyKey
            ),
            sourceSHA256: container.decodeIfPresent(
                EvidenceSHA256.self,
                forKey: .sourceSHA256
            )
        )
    }
}

/// Algorithmic lineage of a derived measurement (issue bolph71656-ai/HTDT-Capture#286): which
/// deterministic computation produced the value, its version, and the
/// exact source authorities it consumed (endpoint/geometry refs).
public struct MeasurementDerivation: Codable, Sendable, Equatable {
    public let algorithm: String
    public let algorithmVersion: String
    public let sourceRefs: [String]

    public init(
        algorithm: String,
        algorithmVersion: String,
        sourceRefs: [String]
    ) throws {
        let normalizedAlgorithm = SchemaOwnedText.nfc(algorithm)
        let normalizedVersion = SchemaOwnedText.nfc(algorithmVersion)
        guard !normalizedAlgorithm.isEmpty,
              !normalizedVersion.isEmpty
        else {
            throw MeasurementModelError.missingDerivationAuthority
        }
        let normalizedRefs = SchemaOwnedText.nfc(sourceRefs)
        guard normalizedRefs.allSatisfy({ !$0.isEmpty }) else {
            throw MeasurementModelError.emptyEndpointReference
        }
        guard Set(normalizedRefs).count == normalizedRefs.count else {
            throw MeasurementModelError.duplicateEndpointReference
        }
        self.algorithm = normalizedAlgorithm
        self.algorithmVersion = normalizedVersion
        self.sourceRefs = normalizedRefs
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case algorithmVersion = "algorithm_version"
        case sourceRefs = "source_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            algorithm: container.decode(String.self, forKey: .algorithm),
            algorithmVersion: container.decode(
                String.self,
                forKey: .algorithmVersion
            ),
            sourceRefs: container.decode(
                [String].self,
                forKey: .sourceRefs
            )
        )
    }
}

public struct MeasurementInstrument: Codable, Sendable, Equatable {
    public let instrumentClass: String?
    public let makeModel: String?
    public let calibrationStatus: String?
    public let calibrationDate: String?

    public init(
        instrumentClass: String? = nil,
        makeModel: String? = nil,
        calibrationStatus: String? = nil,
        calibrationDate: String? = nil
    ) {
        self.instrumentClass = SchemaOwnedText.nfc(instrumentClass)
        self.makeModel = SchemaOwnedText.nfc(makeModel)
        self.calibrationStatus = SchemaOwnedText.nfc(calibrationStatus)
        self.calibrationDate = SchemaOwnedText.nfc(calibrationDate)
    }

    private enum CodingKeys: String, CodingKey {
        case instrumentClass = "instrument_class"
        case makeModel = "make_model"
        case calibrationStatus = "calibration_status"
        case calibrationDate = "calibration_date"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            instrumentClass: container.decodeIfPresent(
                String.self,
                forKey: .instrumentClass
            ),
            makeModel: container.decodeIfPresent(
                String.self,
                forKey: .makeModel
            ),
            calibrationStatus: container.decodeIfPresent(
                String.self,
                forKey: .calibrationStatus
            ),
            calibrationDate: container.decodeIfPresent(
                String.self,
                forKey: .calibrationDate
            )
        )
    }
}

public struct CaptureMeasurement: Codable, Sendable, Equatable {
    public let measurementID: MeasurementID
    public let quantityType: String
    public let value: MeasurementValue
    public let unit: MeasurementUnit
    public let coordinateSpaceID: CoordinateSpaceID?
    public let endpointRefs: [String]
    public let acquisitionMethod: MeasurementAcquisitionMethod
    public let instrument: MeasurementInstrument?
    public let statedUncertainty: Double?
    public let observedAtUTC: String?
    public let userAttestation: UserAttestationState
    public let provenanceClass: MeasurementProvenanceClass
    public let sourceValueText: String?
    /// Exact external source authority for
    /// `manufacturer_specification` values (issue bolph71656-ai/HTDT-Capture#275). Never used for
    /// on-site instrument provenance — that lives in `instrument`.
    public let sourceAuthority: MeasurementSourceAuthority?
    /// Algorithmic lineage for derived/app-computed values
    /// (issue bolph71656-ai/HTDT-Capture#286). Never present on raw user-entered values.
    public let derivation: MeasurementDerivation?
    /// Typed uncertainty authority (legacy bolph71656-ai/HTDT-Capture#334); supersedes the bare
    /// `stated_uncertainty` scalar on v1.1.0 payloads. When both are
    /// present `stated_uncertainty` must equal `uncertainty.value` —
    /// the legacy field only mirrors the structured record.
    public let uncertainty: MeasurementUncertainty?
    /// Observation lineage (legacy bolph71656-ai/HTDT-Capture#304): repeat/retake/supersession
    /// relation to a prior record, disposition, and optional
    /// task-plan binding (legacy bolph71656-ai/HTDT-Capture#354). Nil on legacy records = independent
    /// observation, lineage unknown.
    public let lineage: MeasurementLineage?
    /// Exact instrument profile version this value relied on
    /// (issue bolph71656-ai/HTDT-Capture#331). When present it is the instrument authority; the
    /// legacy free-text `instrument` field stays populated for
    /// readability and remains loadable on its own.
    public let instrumentAuthority: MeasurementInstrumentReference?
    /// Optional app-local author/operator binding (issue bolph71656-ai/HTDT-Capture#310):
    /// `operator_id` from `derived/operator-profiles.json`. Anonymous
    /// records remain valid — identity is claimed, never assumed.
    public let authorOperatorID: OperatorProfileID?
    public let evidenceRefs: [String]

    public init(
        measurementID: MeasurementID = MeasurementID(),
        quantityType: String,
        value: MeasurementValue,
        unit: MeasurementUnit,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        endpointRefs: [String] = [],
        acquisitionMethod: MeasurementAcquisitionMethod,
        instrument: MeasurementInstrument? = nil,
        statedUncertainty: Double? = nil,
        observedAtUTC: String? = nil,
        userAttestation: UserAttestationState,
        provenanceClass: MeasurementProvenanceClass,
        sourceValueText: String? = nil,
        sourceAuthority: MeasurementSourceAuthority? = nil,
        derivation: MeasurementDerivation? = nil,
        uncertainty: MeasurementUncertainty? = nil,
        lineage: MeasurementLineage? = nil,
        instrumentAuthority: MeasurementInstrumentReference? = nil,
        authorOperatorID: OperatorProfileID? = nil,
        evidenceRefs: [String] = []
    ) throws {
        let normalizedQuantityType = SchemaOwnedText.nfc(quantityType)
        guard !normalizedQuantityType.isEmpty else {
            throw MeasurementModelError.emptyQuantityType
        }
        guard value.allFinite else {
            throw MeasurementModelError.invalidScalar
        }
        let normalizedEndpoints = SchemaOwnedText.nfc(endpointRefs)
        guard normalizedEndpoints.allSatisfy({ !$0.isEmpty }) else {
            throw MeasurementModelError.emptyEndpointReference
        }
        guard Set(normalizedEndpoints).count == normalizedEndpoints.count
        else {
            throw MeasurementModelError.duplicateEndpointReference
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw MeasurementModelError.emptyEvidenceReference
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw MeasurementModelError.duplicateEvidenceReference
        }
        if let statedUncertainty {
            guard statedUncertainty.isFinite,
                  statedUncertainty >= 0
            else {
                throw MeasurementModelError.negativeUncertainty
            }
        }
        // The structured uncertainty record is dimensionally coherent
        // with the measurement and, when the legacy mirror is also
        // present, identical to it (legacy bolph71656-ai/HTDT-Capture#334).
        if let uncertainty {
            if let uncertaintyUnit = uncertainty.unit {
                guard uncertaintyUnit.dimension == unit.dimension
                else {
                    throw MeasurementModelError.invalidUncertainty
                }
            }
            if let statedUncertainty {
                guard statedUncertainty == uncertainty.value else {
                    throw MeasurementModelError.invalidUncertainty
                }
            }
        }
        // `observed_at` is `date-time` authority: canonical UTC RFC3339
        // with a mandatory Z designator.
        if let observedAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(observedAtUTC)
            else {
                throw MeasurementModelError.invalidObservedTimestamp
            }
        }
        // `instrument.calibration_date` is `date` authority: a valid
        // YYYY-MM-DD calendar date.
        if let calibrationDate = instrument?.calibrationDate {
            guard SchemaTimestampText.isCalendarDate(calibrationDate)
            else {
                throw MeasurementModelError.invalidCalibrationDate
            }
        }
        if value.isSpatialVector || !normalizedEndpoints.isEmpty {
            guard coordinateSpaceID != nil else {
                throw MeasurementModelError.missingSpatialCoordinateAuthority
            }
        }
        if provenanceClass == .userAttestedMeasurement {
            guard userAttestation == .attested else {
                throw MeasurementModelError.userAttestationRequired
            }
            // User-attested records must not claim a derived acquisition
            // method; derived values carry their own provenance class.
            switch acquisitionMethod {
            case .lidarDerived, .roomPlanDerived:
                throw MeasurementModelError
                    .derivedAcquisitionNotUserAttestable
            case .tapeMeasure, .laserDistanceMeter,
                 .manufacturerSpecification, .externalInstrument,
                 .other:
                break
            }
        }

        // Manufacturer-specification source identity may only decorate
        // a `manufacturer_specification` record; an on-site instrument
        // reading is not a datasheet value (issue bolph71656-ai/HTDT-Capture#275).
        if sourceAuthority != nil,
           acquisitionMethod != .manufacturerSpecification
        {
            throw MeasurementModelError
                .sourceAuthorityRequiresManufacturerSpecification
        }

        // Provenance mapping for computed values (issue bolph71656-ai/HTDT-Capture#286): a
        // RoomPlan-derived value is apple_roomplan_inference authority,
        // a LiDAR/mesh-derived value is arkit_mesh_reconstruction, and a
        // value the capture app computed from other authorities is
        // capture_app_derived. A derivation record may only decorate
        // those classes — a user-entered scalar is never a derivation.
        switch acquisitionMethod {
        case .roomPlanDerived:
            guard provenanceClass == .appleRoomPlanInference else {
                throw MeasurementModelError.derivedProvenanceMismatch
            }
        case .lidarDerived:
            guard provenanceClass == .arkitMeshReconstruction else {
                throw MeasurementModelError.derivedProvenanceMismatch
            }
        case .tapeMeasure, .laserDistanceMeter,
             .manufacturerSpecification, .externalInstrument, .other:
            break
        }
        if provenanceClass == .captureAppDerived {
            guard acquisitionMethod == .other else {
                throw MeasurementModelError.derivedProvenanceMismatch
            }
            guard derivation != nil else {
                throw MeasurementModelError.missingDerivationAuthority
            }
        }
        if derivation != nil {
            let derivedMethod: Bool
            switch acquisitionMethod {
            case .lidarDerived, .roomPlanDerived:
                derivedMethod = true
            case .tapeMeasure, .laserDistanceMeter,
                 .manufacturerSpecification, .externalInstrument, .other:
                derivedMethod = false
            }
            guard derivedMethod
                    || provenanceClass == .captureAppDerived
            else {
                throw MeasurementModelError.nonDerivedDerivation
            }
        }

        self.measurementID = measurementID
        self.quantityType = normalizedQuantityType
        self.value = value
        self.unit = unit
        self.coordinateSpaceID = coordinateSpaceID
        self.endpointRefs = normalizedEndpoints
        self.acquisitionMethod = acquisitionMethod
        self.instrument = instrument
        self.statedUncertainty = statedUncertainty
        self.observedAtUTC = observedAtUTC
        self.userAttestation = userAttestation
        self.provenanceClass = provenanceClass
        self.sourceValueText = SchemaOwnedText.nfc(sourceValueText)
        self.sourceAuthority = sourceAuthority
        self.derivation = derivation
        self.uncertainty = uncertainty
        self.lineage = lineage
        self.instrumentAuthority = instrumentAuthority
        self.authorOperatorID = authorOperatorID
        self.evidenceRefs = normalizedEvidence
    }

    /// A copy of this measurement with `author_operator_id` set to
    /// `operatorID` — used when the workspace applies the selected
    /// operator profile to a newly authored record (issue bolph71656-ai/HTDT-Capture#310).
    public func withAuthorOperator(
        _ operatorID: OperatorProfileID?
    ) throws -> CaptureMeasurement {
        try CaptureMeasurement(
            measurementID: measurementID,
            quantityType: quantityType,
            value: value,
            unit: unit,
            coordinateSpaceID: coordinateSpaceID,
            endpointRefs: endpointRefs,
            acquisitionMethod: acquisitionMethod,
            instrument: instrument,
            statedUncertainty: statedUncertainty,
            observedAtUTC: observedAtUTC,
            userAttestation: userAttestation,
            provenanceClass: provenanceClass,
            sourceValueText: sourceValueText,
            sourceAuthority: sourceAuthority,
            derivation: derivation,
            uncertainty: uncertainty,
            lineage: lineage,
            instrumentAuthority: instrumentAuthority,
            authorOperatorID: operatorID,
            evidenceRefs: evidenceRefs
        )
    }

    /// A copy of this measurement with `endpoint_refs` replaced —
    /// used when a referenced entity is deleted so the staged record
    /// never dangles against the entity graph.
    public func withEndpointRefs(
        _ refs: [String]
    ) throws -> CaptureMeasurement {
        try CaptureMeasurement(
            measurementID: measurementID,
            quantityType: quantityType,
            value: value,
            unit: unit,
            coordinateSpaceID: coordinateSpaceID,
            endpointRefs: refs,
            acquisitionMethod: acquisitionMethod,
            instrument: instrument,
            statedUncertainty: statedUncertainty,
            observedAtUTC: observedAtUTC,
            userAttestation: userAttestation,
            provenanceClass: provenanceClass,
            sourceValueText: sourceValueText,
            sourceAuthority: sourceAuthority,
            derivation: derivation,
            uncertainty: uncertainty,
            lineage: lineage,
            instrumentAuthority: instrumentAuthority,
            authorOperatorID: authorOperatorID,
            evidenceRefs: evidenceRefs
        )
    }

    /// A copy of this measurement with `instrument_authority` set —
    /// the legacy `instrument` text is preserved verbatim so older
    /// readers keep working (issue bolph71656-ai/HTDT-Capture#331).
    public func withInstrumentAuthority(
        _ reference: MeasurementInstrumentReference?
    ) throws -> CaptureMeasurement {
        try CaptureMeasurement(
            measurementID: measurementID,
            quantityType: quantityType,
            value: value,
            unit: unit,
            coordinateSpaceID: coordinateSpaceID,
            endpointRefs: endpointRefs,
            acquisitionMethod: acquisitionMethod,
            instrument: instrument,
            statedUncertainty: statedUncertainty,
            observedAtUTC: observedAtUTC,
            userAttestation: userAttestation,
            provenanceClass: provenanceClass,
            sourceValueText: sourceValueText,
            sourceAuthority: sourceAuthority,
            derivation: derivation,
            uncertainty: uncertainty,
            lineage: lineage,
            instrumentAuthority: reference,
            authorOperatorID: authorOperatorID,
            evidenceRefs: evidenceRefs
        )
    }

    private enum CodingKeys: String, CodingKey {
        case measurementID = "measurement_id"
        case quantityType = "quantity_type"
        case value
        case unit
        case coordinateSpaceID = "coordinate_space_id"
        case endpointRefs = "endpoint_refs"
        case acquisitionMethod = "acquisition_method"
        case instrument
        case statedUncertainty = "stated_uncertainty"
        case observedAtUTC = "observed_at"
        case userAttestation = "user_attestation"
        case provenanceClass = "provenance_class"
        case sourceValueText = "source_value_text"
        case sourceAuthority = "source_authority"
        case derivation
        case uncertainty
        case lineage
        case instrumentAuthority = "instrument_authority"
        case authorOperatorID = "author_operator_id"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            measurementID: container.decode(
                MeasurementID.self,
                forKey: .measurementID
            ),
            quantityType: container.decode(
                String.self,
                forKey: .quantityType
            ),
            value: container.decode(MeasurementValue.self, forKey: .value),
            unit: container.decode(MeasurementUnit.self, forKey: .unit),
            coordinateSpaceID: container.decodeIfPresent(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            endpointRefs: container.decode(
                [String].self,
                forKey: .endpointRefs
            ),
            acquisitionMethod: container.decode(
                MeasurementAcquisitionMethod.self,
                forKey: .acquisitionMethod
            ),
            instrument: container.decodeIfPresent(
                MeasurementInstrument.self,
                forKey: .instrument
            ),
            statedUncertainty: container.decodeIfPresent(
                Double.self,
                forKey: .statedUncertainty
            ),
            observedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .observedAtUTC
            ),
            userAttestation: container.decode(
                UserAttestationState.self,
                forKey: .userAttestation
            ),
            provenanceClass: container.decode(
                MeasurementProvenanceClass.self,
                forKey: .provenanceClass
            ),
            sourceValueText: container.decodeIfPresent(
                String.self,
                forKey: .sourceValueText
            ),
            sourceAuthority: container.decodeIfPresent(
                MeasurementSourceAuthority.self,
                forKey: .sourceAuthority
            ),
            derivation: container.decodeIfPresent(
                MeasurementDerivation.self,
                forKey: .derivation
            ),
            uncertainty: container.decodeIfPresent(
                MeasurementUncertainty.self,
                forKey: .uncertainty
            ),
            lineage: container.decodeIfPresent(
                MeasurementLineage.self,
                forKey: .lineage
            ),
            instrumentAuthority: container.decodeIfPresent(
                MeasurementInstrumentReference.self,
                forKey: .instrumentAuthority
            ),
            authorOperatorID: container.decodeIfPresent(
                OperatorProfileID.self,
                forKey: .authorOperatorID
            ),
            evidenceRefs: container.decode(
                [String].self,
                forKey: .evidenceRefs
            )
        )
    }
}

public struct CaptureMeasurementCollection: Codable, Sendable, Equatable {
    public static let expectedSchema = "htdt.capture.measurements"
    /// The payload version this build emits (legacy bolph71656-ai/HTDT-Capture#332). v1.1.0 adds
    /// structured uncertainty (legacy bolph71656-ai/HTDT-Capture#334), observation lineage/disposition
    /// (legacy bolph71656-ai/HTDT-Capture#304), and the open-token namespace policy for `quantity_type`
    /// (legacy bolph71656-ai/HTDT-Capture#344).
    public static let expectedSchemaVersion = "1.1.0"
    /// Every payload version this build can decode (legacy bolph71656-ai/HTDT-Capture#332).
    public static let supportedSchemaVersions: [String] = [
        "1.0.0", "1.1.0",
    ]

    public let schema: String
    public let schemaVersion: String
    public let measurements: [CaptureMeasurement]

    public init(measurements: [CaptureMeasurement]) throws {
        try self.init(
            measurements: measurements,
            declaredSchemaVersion: Self.expectedSchemaVersion
        )
    }

    /// Validates a collection under the contract pinned to
    /// `declaredSchemaVersion`. v1.1.0 payloads enforce the quantity
    /// registry in full — canonical unit/shape/endpoint semantics,
    /// physical value domain (legacy bolph71656-ai/HTDT-Capture#334), and the `x_` custom-token
    /// namespace policy (legacy bolph71656-ai/HTDT-Capture#344). v1.0.0 payloads stay readable with
    /// unscoped custom quantities and unrestricted values.
    init(
        measurements: [CaptureMeasurement],
        declaredSchemaVersion: String
    ) throws {
        let ids = measurements.map(\.measurementID)
        guard Set(ids).count == ids.count else {
            throw MeasurementModelError.duplicateMeasurementID
        }
        if declaredSchemaVersion != "1.0.0" {
            for measurement in measurements {
                try MeasurementQuantityRegistry.validate(
                    quantityType: measurement.quantityType,
                    value: measurement.value,
                    unit: measurement.unit,
                    endpointCount: measurement.endpointRefs.count
                )
            }
        }
        self.schema = Self.expectedSchema
        self.schemaVersion = declaredSchemaVersion
        self.measurements = measurements
    }

    /// Records carrying unscoped custom `quantity_type` tokens —
    /// only possible on legacy v1.0.0 payloads; they classify
    /// `legacy_custom_unscoped` (legacy bolph71656-ai/HTDT-Capture#344) and are surfaced for Review
    /// rather than silently reinterpreted.
    public var legacyUnscopedQuantityMeasurements: [CaptureMeasurement]
    {
        measurements.filter {
            OpenTokenPolicy.classify(
                $0.quantityType,
                vocabulary: .measurementQuantity
            ) == .legacyCustomUnscoped
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case measurements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.expectedSchema else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "Unsupported measurement collection schema"
            )
        }
        guard Self.supportedSchemaVersions.contains(schemaVersion)
        else {
            throw MeasurementModelError.unsupportedSchemaVersion
        }
        try self.init(
            measurements: container.decode(
                [CaptureMeasurement].self,
                forKey: .measurements
            ),
            declaredSchemaVersion: schemaVersion
        )
    }
}
