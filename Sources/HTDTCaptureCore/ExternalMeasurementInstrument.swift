import Foundation

public enum InstrumentAdapterError: Error, Sendable, Equatable {
    /// The instrument link dropped mid-read. Any staged pending
    /// measurement survives so the operator can still confirm or
    /// retype it manually.
    case disconnected
    /// The adapter path cannot serve readings at all.
    case unavailable
    /// The instrument produced bytes that do not decode to a reading.
    case invalidReading
}

public enum InstrumentMeasurementError: Error, Sendable, Equatable {
    case emptyField
    case invalidScalar
    case invalidObservedTimestamp
    case invalidCalibrationDate
    /// Derived/algorithmic acquisition methods cannot come from a
    /// physical instrument adapter.
    case invalidInstrumentMethod
    /// Calibration metadata supplied without the reading explicitly
    /// carrying it is never fabricated.
    case noPendingMeasurement
}

/// One scalar reading exactly as received from an external measurement
/// instrument (issue #226). The received value/unit text is preserved
/// verbatim alongside the parsed scalar so the committed measurement
/// always shows what the device reported.
public struct InstrumentReading: Sendable, Equatable {
    /// Exact instrument output text for the value (e.g. "4.215 m").
    public let receivedValueText: String
    public let value: Double
    public let unit: MeasurementUnit
    /// Device-side measurement/sample identifier, when supplied.
    public let deviceMeasurementID: String?
    /// Device-side UTC timestamp, when supplied.
    public let observedAtUTC: String?
    /// Calibration metadata — only present when the adapter explicitly
    /// reports it; never inferred.
    public let calibrationStatus: String?
    public let calibrationDate: String?

    public init(
        receivedValueText: String,
        value: Double,
        unit: MeasurementUnit,
        deviceMeasurementID: String? = nil,
        observedAtUTC: String? = nil,
        calibrationStatus: String? = nil,
        calibrationDate: String? = nil
    ) throws {
        let normalizedText = SchemaOwnedText.nfc(receivedValueText)
        guard !normalizedText.isEmpty else {
            throw InstrumentMeasurementError.emptyField
        }
        guard value.isFinite else {
            throw InstrumentMeasurementError.invalidScalar
        }
        if let observedAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(observedAtUTC)
            else {
                throw InstrumentMeasurementError
                    .invalidObservedTimestamp
            }
        }
        if let calibrationDate {
            guard SchemaTimestampText.isCalendarDate(calibrationDate)
            else {
                throw InstrumentMeasurementError
                    .invalidCalibrationDate
            }
        }
        self.receivedValueText = normalizedText
        self.value = value
        self.unit = unit
        self.deviceMeasurementID =
            SchemaOwnedText.nfc(deviceMeasurementID)
        self.observedAtUTC = observedAtUTC
        self.calibrationStatus = SchemaOwnedText.nfc(calibrationStatus)
        self.calibrationDate = calibrationDate
    }
}

/// Vendor-neutral description of a connected measurement instrument
/// adapter (issue #226).
public struct InstrumentAdapterDescriptor: Sendable, Equatable {
    /// Stable adapter identifier (e.g. "bosch-glm50-ble").
    public let adapterID: String
    /// Physical acquisition method the instrument performs. Limited to
    /// real instrument methods — never a derived/algorithmic one.
    public let acquisitionMethod: MeasurementAcquisitionMethod
    /// Instrument make/model as reported by the device or adapter.
    public let makeModel: String
    /// Transport the adapter speaks: "ble", "usb", "file", ...
    public let transport: String

    public init(
        adapterID: String,
        acquisitionMethod: MeasurementAcquisitionMethod,
        makeModel: String,
        transport: String
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(adapterID)
        let normalizedMake = SchemaOwnedText.nfc(makeModel)
        let normalizedTransport = SchemaOwnedText.nfc(transport)
        guard !normalizedID.isEmpty,
              !normalizedMake.isEmpty,
              !normalizedTransport.isEmpty
        else {
            throw InstrumentMeasurementError.emptyField
        }
        switch acquisitionMethod {
        case .tapeMeasure, .laserDistanceMeter,
             .manufacturerSpecification, .other:
            break
        case .lidarDerived, .roomPlanDerived:
            throw InstrumentMeasurementError.invalidInstrumentMethod
        }
        self.adapterID = normalizedID
        self.acquisitionMethod = acquisitionMethod
        self.makeModel = normalizedMake
        self.transport = normalizedTransport
    }
}

/// A vendor adapter produces one scalar reading per call. Adapters are
/// vendor-neutral: the store never sees transport details, only the
/// descriptor plus the exact received reading.
public protocol MeasurementInstrumentAdapter: Sendable {
    var descriptor: InstrumentAdapterDescriptor { get }
    func readScalar() async throws -> InstrumentReading
}

/// A reading staged for operator confirmation. Nothing here is
/// committed until `confirm` produces a `CaptureMeasurement`.
public struct PendingInstrumentMeasurement: Sendable, Equatable {
    public let reading: InstrumentReading
    public let descriptor: InstrumentAdapterDescriptor

    public init(
        reading: InstrumentReading,
        descriptor: InstrumentAdapterDescriptor
    ) {
        self.reading = reading
        self.descriptor = descriptor
    }
}

public enum InstrumentLinkState: String, Sendable, Equatable {
    case connected
    case disconnected
    case unavailable
}

/// Staging surface between an instrument adapter and a committed
/// `CaptureMeasurement` (issue #226). Readings land in `pending`
/// without touching the measurement collection; only an explicit
/// `confirm` produces a committed record. Disconnect or adapter
/// failure leaves the staged pending measurement untouched and the
/// manual entry path intact.
public struct InstrumentMeasurementSession: Sendable, Equatable {
    public private(set) var pending: PendingInstrumentMeasurement?
    public private(set) var linkState: InstrumentLinkState

    public init() {
        self.pending = nil
        self.linkState = .connected
    }

    /// Requests one reading and stages it. Errors update `linkState`
    /// but never clear a previously staged pending measurement.
    @discardableResult
    public mutating func stageReading(
        from adapter: any MeasurementInstrumentAdapter
    ) async throws -> PendingInstrumentMeasurement {
        do {
            let reading = try await adapter.readScalar()
            let staged = PendingInstrumentMeasurement(
                reading: reading,
                descriptor: adapter.descriptor
            )
            pending = staged
            linkState = .connected
            return staged
        } catch InstrumentAdapterError.disconnected {
            linkState = .disconnected
            throw InstrumentAdapterError.disconnected
        } catch InstrumentAdapterError.unavailable {
            linkState = .unavailable
            throw InstrumentAdapterError.unavailable
        }
    }

    public mutating func clearPending() {
        pending = nil
    }

    /// Operator confirmation: produce the committed measurement record.
    /// Preserves the exact received value text, the parsed value/unit,
    /// instrument make/model, device measurement id, and device
    /// timestamp. Calibration metadata lands only when the adapter
    /// explicitly supplied it.
    public func confirmMeasurement(
        _ pending: PendingInstrumentMeasurement,
        quantityType: String,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        endpointRefs: [String] = [],
        evidenceRefs: [String] = []
    ) throws -> CaptureMeasurement {
        let reading = pending.reading
        let descriptor = pending.descriptor
        var refs = evidenceRefs
        if let deviceMeasurementID = reading.deviceMeasurementID {
            refs.append("instrument_reading:\(deviceMeasurementID)")
        }
        return try CaptureMeasurement(
            quantityType: quantityType,
            value: .scalar(reading.value),
            unit: reading.unit,
            coordinateSpaceID: coordinateSpaceID,
            endpointRefs: endpointRefs,
            acquisitionMethod: descriptor.acquisitionMethod,
            instrument: MeasurementInstrument(
                instrumentClass: descriptor.acquisitionMethod.rawValue,
                makeModel: descriptor.makeModel,
                calibrationStatus: reading.calibrationStatus,
                calibrationDate: reading.calibrationDate
            ),
            observedAtUTC: reading.observedAtUTC,
            userAttestation: .attested,
            provenanceClass: .userAttestedMeasurement,
            sourceValueText: reading.receivedValueText,
            evidenceRefs: refs
        )
    }
}

/// Transport-independent import adapter: parses a reading from bytes
/// the operator imports from the instrument's own tooling (file
/// export, share sheet, paste). Accepts either plain "4.215 m" text or
/// a JSON object with `value`/`unit` plus optional
/// `device_measurement_id`, `observed_at`, `calibration_status`,
/// `calibration_date`.
public struct FileImportInstrumentAdapter: MeasurementInstrumentAdapter {
    public let descriptor: InstrumentAdapterDescriptor
    private let data: Data

    public init(
        descriptor: InstrumentAdapterDescriptor,
        data: Data
    ) {
        self.descriptor = descriptor
        self.data = data
    }

    private struct WireReading: Decodable {
        let value: Double
        let unit: String
        let deviceMeasurementID: String?
        let observedAt: String?
        let calibrationStatus: String?
        let calibrationDate: String?

        private enum CodingKeys: String, CodingKey {
            case value
            case unit
            case deviceMeasurementID = "device_measurement_id"
            case observedAt = "observed_at"
            case calibrationStatus = "calibration_status"
            case calibrationDate = "calibration_date"
        }
    }

    public func readScalar() async throws -> InstrumentReading {
        if let wire = try? JSONDecoder().decode(
            WireReading.self,
            from: data
        ) {
            guard let unit = MeasurementUnit(rawValue: wire.unit)
            else {
                throw InstrumentAdapterError.invalidReading
            }
            return try InstrumentReading(
                receivedValueText: "\(wire.value) \(wire.unit)",
                value: wire.value,
                unit: unit,
                deviceMeasurementID: wire.deviceMeasurementID,
                observedAtUTC: wire.observedAt,
                calibrationStatus: wire.calibrationStatus,
                calibrationDate: wire.calibrationDate
            )
        }

        guard let text = String(
            data: data,
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            throw InstrumentAdapterError.invalidReading
        }
        let parts = text.split(
            separator: " ",
            omittingEmptySubsequences: true
        )
        guard parts.count == 2,
              let value = Double(parts[0]),
              let unit = MeasurementUnit(rawValue: String(parts[1]))
        else {
            throw InstrumentAdapterError.invalidReading
        }
        return try InstrumentReading(
            receivedValueText: text,
            value: value,
            unit: unit
        )
    }
}
