import Foundation

/// The physical dimension a measurement expresses. The quantity
/// registry (issue #287) binds each standardized quantity token to one
/// dimension so a syntactically valid record can still be rejected when
/// its unit is dimensionally impossible (e.g. `room_width` in radians).
/// Custom quantity tokens stay allowed: their unit declares their
/// dimension.
public enum MeasurementDimension: String, Codable, Sendable, CaseIterable {
    case length
    case angle
    case time
    case temperature
    case dimensionless
}

public enum MeasurementValueShape: String, Sendable, Equatable {
    case scalar
    case vector3
}

/// One entry of the versioned measurement quantity registry
/// (issue #287). Registered quantities pin down the physical dimension,
/// the canonical persisted unit, the value shape, and the endpoint
/// semantics so task templates and producers share one contract instead
/// of duplicating unit logic in views.
public struct MeasurementQuantityDefinition: Sendable, Equatable {
    /// Canonical `quantity_type` token, e.g. `"room_width"`.
    public let quantityType: String
    public let dimension: MeasurementDimension
    /// The unit a record must persist. Input/display units convert into
    /// this unit before authority creation.
    public let canonicalUnit: MeasurementUnit
    public let shape: MeasurementValueShape
    /// Endpoint semantics: `nil` = endpoints unconstrained; `0` =
    /// endpoints meaningless for this quantity and must be empty;
    /// `n > 0` = when endpoints are bound they must number exactly `n`
    /// (a spatially unbound manual value stays legal — issue #215).
    public let expectedEndpoints: Int?
    /// Practical input/display units offered for this quantity
    /// (issue #235); conversion to `canonicalUnit` is deterministic.
    public let inputUnits: [MeasurementInputUnit]

    public init(
        quantityType: String,
        dimension: MeasurementDimension,
        canonicalUnit: MeasurementUnit,
        shape: MeasurementValueShape,
        expectedEndpoints: Int?,
        inputUnits: [MeasurementInputUnit]
    ) {
        self.quantityType = quantityType
        self.dimension = dimension
        self.canonicalUnit = canonicalUnit
        self.shape = shape
        self.expectedEndpoints = expectedEndpoints
        self.inputUnits = inputUnits
    }
}

public enum MeasurementQuantityRegistry {
    /// Registry version: bump when entries are added or semantics change.
    /// Wire payloads reference quantities by token; the registry is the
    /// machine-readable meaning of those tokens (issue #269).
    public static let version = "1.0.0"

    private static let lengthInputUnits: [MeasurementInputUnit] = [
        .meter, .centimeter, .millimeter, .foot, .inch, .footAndInch,
    ]

    /// Standardized HTDT quantity tokens. Token order is presentation
    /// order for pickers.
    public static let definitions: [MeasurementQuantityDefinition] = [
        MeasurementQuantityDefinition(
            quantityType: "room_width",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "room_length",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "room_height",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "screen_width",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "screen_height",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "screen_diagonal",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "speaker_distance",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "speaker_spacing",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "listener_distance",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "endpoint_distance",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "displacement",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .vector3,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits
        ),
        MeasurementQuantityDefinition(
            quantityType: "azimuth",
            dimension: .angle,
            canonicalUnit: .radian,
            shape: .scalar,
            expectedEndpoints: nil,
            inputUnits: [.radian, .degree]
        ),
        MeasurementQuantityDefinition(
            quantityType: "signal_delay",
            dimension: .time,
            canonicalUnit: .second,
            shape: .scalar,
            expectedEndpoints: nil,
            inputUnits: [.second]
        ),
        // Room-condition quantities for the acoustic environment
        // authority (issue #253).
        MeasurementQuantityDefinition(
            quantityType: "air_temperature",
            dimension: .temperature,
            canonicalUnit: .degreeCelsius,
            shape: .scalar,
            expectedEndpoints: 0,
            inputUnits: [.celsius, .fahrenheit]
        ),
        MeasurementQuantityDefinition(
            quantityType: "relative_humidity",
            dimension: .dimensionless,
            canonicalUnit: .percent,
            shape: .scalar,
            expectedEndpoints: 0,
            inputUnits: [.percent, .fraction]
        ),
    ]

    public static func definition(
        for quantityType: String
    ) -> MeasurementQuantityDefinition? {
        let normalized = quantityType
            .precomposedStringWithCanonicalMapping
        return definitions.first(where: {
            $0.quantityType == normalized
        })
    }

    /// Contract check every production producer applies (issue #287).
    /// Registered quantities must persist their canonical unit and
    /// declared value shape/endpoint semantics; unregistered tokens are
    /// the explicit custom path and are allowed through — their unit
    /// declares their dimension.
    public static func validate(
        quantityType: String,
        value: MeasurementValue,
        unit: MeasurementUnit,
        endpointCount: Int
    ) throws {
        guard let definition = definition(for: quantityType) else {
            return
        }
        guard unit == definition.canonicalUnit,
              unit.dimension == definition.dimension
        else {
            throw MeasurementModelError.incompatibleUnitForQuantity
        }
        let valueShape: MeasurementValueShape =
            value.isSpatialVector ? .vector3 : .scalar
        guard valueShape == definition.shape else {
            throw MeasurementModelError
                .incompatibleValueShapeForQuantity
        }
        if let expected = definition.expectedEndpoints {
            if expected == 0 {
                guard endpointCount == 0 else {
                    throw MeasurementModelError
                        .invalidEndpointCountForQuantity
                }
            } else {
                guard endpointCount == 0 || endpointCount == expected
                else {
                    throw MeasurementModelError
                        .invalidEndpointCountForQuantity
                }
            }
        }
    }
}

/// Operator-facing input/display units (issue #235). These are never
/// persisted: `canonicalValue` normalizes to the canonical SI-aligned
/// `MeasurementUnit` before a measurement authority is written, and the
/// original operator text survives in `source_value_text`.
public enum MeasurementInputUnit: String, Sendable, Equatable, CaseIterable {
    case meter = "m"
    case centimeter = "cm"
    case millimeter = "mm"
    case foot = "ft"
    case inch = "in"
    /// Two-component `feet + inches` entry (e.g. "12 ft 8 in").
    case footAndInch = "ft_in"
    case radian = "rad"
    case degree = "deg"
    case second = "s"
    case celsius = "degC"
    case fahrenheit = "degF"
    case percent = "%"
    /// A plain 0–1 ratio; canonicalized to percent for humidity-style
    /// quantities.
    case fraction = "1"

    public var dimension: MeasurementDimension {
        switch self {
        case .meter, .centimeter, .millimeter, .foot, .inch,
             .footAndInch:
            return .length
        case .radian, .degree:
            return .angle
        case .second:
            return .time
        case .celsius, .fahrenheit:
            return .temperature
        case .percent, .fraction:
            return .dimensionless
        }
    }

    /// The canonical unit this input unit converts into.
    public var canonicalUnit: MeasurementUnit {
        switch self {
        case .meter, .centimeter, .millimeter, .foot, .inch,
             .footAndInch:
            return .meter
        case .radian, .degree:
            return .radian
        case .second:
            return .second
        case .celsius, .fahrenheit:
            return .degreeCelsius
        case .percent, .fraction:
            return .percent
        }
    }

    public var usesSecondaryComponent: Bool {
        self == .footAndInch
    }

    /// Short display token for pickers and summaries.
    public var displayToken: String {
        switch self {
        case .footAndInch:
            return "ft + in"
        case .celsius:
            return "°C"
        case .fahrenheit:
            return "°F"
        case .fraction:
            return "0–1"
        default:
            return rawValue
        }
    }

    /// Exact conversion into the canonical unit. `secondary` is only
    /// meaningful for `footAndInch` (the inches component) and ignored
    /// otherwise.
    public func canonicalValue(
        _ primary: Double,
        secondary: Double = 0
    ) -> Double {
        switch self {
        case .meter:
            return primary
        case .centimeter:
            return primary / 100
        case .millimeter:
            return primary / 1000
        case .foot:
            return primary * 0.3048
        case .inch:
            return primary * 0.0254
        case .footAndInch:
            return (primary * 12 + secondary) * 0.0254
        case .radian:
            return primary
        case .degree:
            return primary * .pi / 180
        case .second:
            return primary
        case .celsius:
            return primary
        case .fahrenheit:
            return (primary - 32) * 5 / 9
        case .percent:
            return primary
        case .fraction:
            return primary * 100
        }
    }
}

/// Deterministic numeric parsing for measurement input (issue #235).
/// Both `.` and `,` are accepted as the decimal separator so
/// decimal-comma locales work without locale-dependent `NumberFormatter`
/// behavior; mixing separators, repeated separators, exponents, or
/// stray characters all fail rather than guessing.
public enum MeasurementInputParser {
    public static func parse(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        var sign = ""
        if let first = text.first, first == "-" || first == "+" {
            sign = String(first)
            text = String(text.dropFirst())
        }
        guard !text.isEmpty else {
            return nil
        }
        var separator: Character?
        var digits = 0
        for character in text {
            if character.isNumber, character.isASCII {
                digits += 1
            } else if character == "." || character == "," {
                guard separator == nil else {
                    return nil
                }
                separator = character
            } else {
                return nil
            }
        }
        guard digits > 0 else {
            return nil
        }
        let normalized =
            sign + text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
