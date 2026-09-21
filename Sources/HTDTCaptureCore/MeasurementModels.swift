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
    /// distinguishable from bare manual entry (issue #253).
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
/// (issue #235). `degreeCelsius` uses explicit semantics:
/// `K = degC + 273.15` exactly (issue #269).
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

/// Structured source identity for `manufacturer_specification`
/// measurements (issue #275). A datasheet/catalog value must be able to
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

/// Algorithmic lineage of a derived measurement (issue #286): which
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
    /// `manufacturer_specification` values (issue #275). Never used for
    /// on-site instrument provenance — that lives in `instrument`.
    public let sourceAuthority: MeasurementSourceAuthority?
    /// Algorithmic lineage for derived/app-computed values
    /// (issue #286). Never present on raw user-entered values.
    public let derivation: MeasurementDerivation?
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
        // reading is not a datasheet value (issue #275).
        if sourceAuthority != nil,
           acquisitionMethod != .manufacturerSpecification
        {
            throw MeasurementModelError
                .sourceAuthorityRequiresManufacturerSpecification
        }

        // Provenance mapping for computed values (issue #286): a
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
        self.evidenceRefs = normalizedEvidence
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
            evidenceRefs: container.decode(
                [String].self,
                forKey: .evidenceRefs
            )
        )
    }
}

public struct CaptureMeasurementCollection: Codable, Sendable, Equatable {
    public static let expectedSchema = "htdt.capture.measurements"
    public static let expectedSchemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let measurements: [CaptureMeasurement]

    public init(measurements: [CaptureMeasurement]) throws {
        let ids = measurements.map(\.measurementID)
        guard Set(ids).count == ids.count else {
            throw MeasurementModelError.duplicateMeasurementID
        }
        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.measurements = measurements
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
        guard schema == Self.expectedSchema,
              schemaVersion == Self.expectedSchemaVersion
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "Unsupported measurement collection schema"
            )
        }
        try self.init(
            measurements: container.decode(
                [CaptureMeasurement].self,
                forKey: .measurements
            )
        )
    }
}
