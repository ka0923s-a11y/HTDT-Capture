import Foundation

public struct MeasurementID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum MeasurementAcquisitionMethod: String, Codable, Sendable {
    case tapeMeasure = "tape_measure"
    case laserDistanceMeter = "laser_distance_meter"
    case manufacturerSpecification = "manufacturer_specification"
    case lidarDerived = "lidar_derived"
    case roomPlanDerived = "roomplan_derived"
    case other
}

public enum MeasurementProvenanceClass: String, Codable, Sendable {
    case userAttestedMeasurement = "user_attested_measurement"
    case appleRoomPlanInference = "apple_roomplan_inference"
    case arkitMeshReconstruction = "arkit_mesh_reconstruction"
    case importedReference = "imported_reference"
}

public enum UserAttestationState: String, Codable, Sendable {
    case notAttested = "not_attested"
    case attested
}

public enum MeasurementUnit: String, Codable, Sendable {
    case meter = "m"
    case radian = "rad"
    case dimensionless = "1"
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
        case evidenceRefs = "evidence_refs"
    }
}

public struct CaptureMeasurementCollection: Codable, Sendable, Equatable {
    public let schema: String
    public let schemaVersion: String
    public let measurements: [CaptureMeasurement]

    public init(measurements: [CaptureMeasurement]) throws {
        let ids = measurements.map(\.measurementID)
        guard Set(ids).count == ids.count else {
            throw MeasurementModelError.duplicateMeasurementID
        }
        self.schema = "htdt.capture.measurements"
        self.schemaVersion = "1.0.0"
        self.measurements = measurements
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case measurements
    }
}
