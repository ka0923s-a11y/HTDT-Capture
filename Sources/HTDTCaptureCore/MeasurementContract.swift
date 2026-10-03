import Foundation

/// The physical dimension a measurement expresses. The quantity
/// registry (issue bolph71656-ai/HTDT-Capture#287) binds each standardized quantity token to one
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

/// The physical value domain a quantity admits (issue bolph71656-ai/HTDT-Capture#334). A
/// syntactically-valid number is not automatically a physically-
/// possible one — negative room widths or humidities above 100% are
/// contract violations at authoring time, not quirks to discover in
/// HTDT.
public enum MeasurementValueDomain: Sendable, Equatable {
    /// Real-valued and sign-bearing (e.g. displacement components,
    /// azimuth).
    case signedUnbounded
    /// Zero or positive (e.g. distances).
    case nonNegative
    /// Strictly positive (e.g. a room cannot have zero width).
    case strictlyPositive
    /// Closed interval `[lower, upper]`; `nil` bounds are open ends.
    case interval(lowerBound: Double?, upperBound: Double?)
    /// A normalized 0...1 fraction.
    case normalizedFraction

    /// Whether a scalar component is inside the domain.
    public func allows(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        switch self {
        case .signedUnbounded:
            return true
        case .nonNegative:
            return value >= 0
        case .strictlyPositive:
            return value > 0
        case let .interval(lowerBound, upperBound):
            if let lowerBound, value < lowerBound { return false }
            if let upperBound, value > upperBound { return false }
            return true
        case .normalizedFraction:
            return value >= 0 && value <= 1
        }
    }

    /// Whether every scalar component of the value is in-domain.
    public func allows(_ value: MeasurementValue) -> Bool {
        switch value {
        case let .scalar(v):
            return allows(v)
        case let .vector3(x, y, z):
            return allows(x) && allows(y) && allows(z)
        }
    }
}

/// One entry of the versioned measurement quantity registry
/// (issue bolph71656-ai/HTDT-Capture#287). Registered quantities pin down the physical dimension,
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
    /// (a spatially unbound manual value stays legal — issue bolph71656-ai/HTDT-Capture#215).
    public let expectedEndpoints: Int?
    /// Practical input/display units offered for this quantity
    /// (issue bolph71656-ai/HTDT-Capture#235); conversion to `canonicalUnit` is deterministic.
    public let inputUnits: [MeasurementInputUnit]
    /// The physical domain the value must lie in (legacy bolph71656-ai/HTDT-Capture#334).
    public let domain: MeasurementValueDomain

    public init(
        quantityType: String,
        dimension: MeasurementDimension,
        canonicalUnit: MeasurementUnit,
        shape: MeasurementValueShape,
        expectedEndpoints: Int?,
        inputUnits: [MeasurementInputUnit],
        domain: MeasurementValueDomain = .signedUnbounded
    ) {
        self.quantityType = quantityType
        self.dimension = dimension
        self.canonicalUnit = canonicalUnit
        self.shape = shape
        self.expectedEndpoints = expectedEndpoints
        self.inputUnits = inputUnits
        self.domain = domain
    }
}

public enum MeasurementQuantityRegistry {
    /// Registry version: bump when entries are added or semantics change.
    /// Wire payloads reference quantities by token; the registry is the
    /// machine-readable meaning of those tokens (issue bolph71656-ai/HTDT-Capture#269). v1.1.0
    /// adds `speaker_to_mlp` and pins a physical value domain per
    /// standard quantity (legacy bolph71656-ai/HTDT-Capture#334); it ships with the schema_version 1.1.0
    /// payloads (legacy bolph71656-ai/HTDT-Capture#332).
    public static let version = "1.1.0"

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
            inputUnits: lengthInputUnits,
            domain: .strictlyPositive
        ),
        MeasurementQuantityDefinition(
            quantityType: "room_length",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits,
            domain: .strictlyPositive
        ),
        MeasurementQuantityDefinition(
            quantityType: "room_height",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits,
            domain: .strictlyPositive
        ),
        MeasurementQuantityDefinition(
            quantityType: "screen_width",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits,
            domain: .strictlyPositive
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
            inputUnits: lengthInputUnits,
            domain: .strictlyPositive
        ),
        MeasurementQuantityDefinition(
            quantityType: "speaker_distance",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits,
            domain: .nonNegative
        ),
        MeasurementQuantityDefinition(
            quantityType: "speaker_spacing",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits,
            domain: .nonNegative
        ),
        /// Speaker-to-primary-listener (MLP) distance — the value the
        /// speaker_to_mlp task template writes (legacy bolph71656-ai/HTDT-Capture#344: a token used by
        /// the capture UI must be standard, never an unscoped custom).
        MeasurementQuantityDefinition(
            quantityType: "speaker_to_mlp",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits,
            domain: .nonNegative
        ),
        MeasurementQuantityDefinition(
            quantityType: "listener_distance",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits,
            domain: .nonNegative
        ),
        MeasurementQuantityDefinition(
            quantityType: "endpoint_distance",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .scalar,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits,
            domain: .nonNegative
        ),
        MeasurementQuantityDefinition(
            quantityType: "displacement",
            dimension: .length,
            canonicalUnit: .meter,
            shape: .vector3,
            expectedEndpoints: 2,
            inputUnits: lengthInputUnits,
            domain: .signedUnbounded
        ),
        MeasurementQuantityDefinition(
            quantityType: "azimuth",
            dimension: .angle,
            canonicalUnit: .radian,
            shape: .scalar,
            expectedEndpoints: nil,
            inputUnits: [.radian, .degree],
            domain: .signedUnbounded
        ),
        MeasurementQuantityDefinition(
            quantityType: "signal_delay",
            dimension: .time,
            canonicalUnit: .second,
            shape: .scalar,
            expectedEndpoints: nil,
            inputUnits: [.second],
            domain: .nonNegative
        ),
        // Room-condition quantities for the acoustic environment
        // authority (issue bolph71656-ai/HTDT-Capture#253).
        MeasurementQuantityDefinition(
            quantityType: "air_temperature",
            dimension: .temperature,
            canonicalUnit: .degreeCelsius,
            shape: .scalar,
            expectedEndpoints: 0,
            inputUnits: [.celsius, .fahrenheit],
            // Celsius cannot pass below absolute zero.
            domain: .interval(lowerBound: -273.15, upperBound: nil)
        ),
        MeasurementQuantityDefinition(
            quantityType: "relative_humidity",
            dimension: .dimensionless,
            canonicalUnit: .percent,
            shape: .scalar,
            expectedEndpoints: 0,
            inputUnits: [.percent, .fraction],
            domain: .interval(lowerBound: 0, upperBound: 100)
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

    /// Contract check every production producer applies (issue bolph71656-ai/HTDT-Capture#287).
    /// Registered quantities must persist their canonical unit,
    /// declared value shape/endpoint semantics, and lie inside their
    /// physical value domain (legacy bolph71656-ai/HTDT-Capture#334). Unregistered tokens are the
    /// explicit custom path: they must carry the reserved `x_`
    /// namespace prefix (legacy bolph71656-ai/HTDT-Capture#344) and declare their own domain via their
    /// unit — the registry cannot know their bounds.
    public static func validate(
        quantityType: String,
        value: MeasurementValue,
        unit: MeasurementUnit,
        endpointCount: Int
    ) throws {
        guard let definition = definition(for: quantityType) else {
            // Custom quantities remain possible — scoped so a custom
            // token can never silently acquire future standard meaning.
            guard OpenTokenPolicy.isWireLegal(
                quantityType,
                vocabulary: .measurementQuantity
            )
            else {
                throw MeasurementModelError.unscopedCustomQuantity
            }
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
        guard definition.domain.allows(value) else {
            throw MeasurementModelError.valueOutsideQuantityDomain
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

/// Operator-facing input/display units (issue bolph71656-ai/HTDT-Capture#235). These are never
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

/// Deterministic numeric parsing for measurement input (issue bolph71656-ai/HTDT-Capture#235).
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
