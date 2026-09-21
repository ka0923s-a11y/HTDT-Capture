import Foundation

public enum StrictJSONError: Error, Sendable, Equatable {
    case invalidUTF8
    case byteOrderMarkForbidden
    case unexpectedEndOfInput
    case unexpectedByte(Int)
    case invalidNumberLiteral(Int)
    case invalidStringEscape(Int)
    case unpairedSurrogateEscape(Int)
    case unterminatedString
    case duplicateObjectKey(String)
    case depthLimitExceeded
    case nonFiniteNumber
    case trailingContent(Int)
}

public indirect enum StrictJSONValue: Sendable, Equatable {
    case object([(key: String, value: StrictJSONValue)])
    case array([StrictJSONValue])
    case string(String)
    case integer(String)
    case number(Double)
    case boolean(Bool)
    case null

    // Tuples cannot conform to Equatable, so the object case needs a
    // manual implementation: key order is significant because
    // StrictJSON preserves source order for diagnostics.
    public static func == (
        lhs: StrictJSONValue,
        rhs: StrictJSONValue
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            return a.count == b.count
                && zip(a, b).allSatisfy {
                    $0.key == $1.key && $0.value == $1.value
                }
        case let (.array(a), .array(b)):
            return a == b
        case let (.string(a), .string(b)):
            return a == b
        case let (.integer(a), .integer(b)):
            return a == b
        case let (.number(a), .number(b)):
            return a == b
        case let (.boolean(a), .boolean(b)):
            return a == b
        case (.null, .null):
            return true
        default:
            return false
        }
    }

    public var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    public var members: [(key: String, value: StrictJSONValue)]? {
        guard case let .object(pairs) = self else {
            return nil
        }
        return pairs
    }

    public var elements: [StrictJSONValue]? {
        guard case let .array(elements) = self else {
            return nil
        }
        return elements
    }

    public var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    public var integerLexeme: String? {
        guard case let .integer(lexeme) = self else {
            return nil
        }
        return lexeme
    }

    /// Exact integer accessor used by descriptor cross-checks. Accepts
    /// integral floating-point lexemes (e.g. `4.0`) because the schema's
    /// "integer" type and the reference validator both treat them as
    /// integers; returns nil for fractional or out-of-range values.
    public var intValue: Int? {
        switch self {
        case let .integer(lexeme):
            return Int(lexeme)
        case let .number(value):
            guard value == value.rounded() else {
                return nil
            }
            return Int(exactly: value)
        default:
            return nil
        }
    }

    public var numberValue: Double? {
        switch self {
        case let .integer(lexeme):
            return Double(lexeme)
        case let .number(value):
            return value
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        guard case let .boolean(value) = self else {
            return nil
        }
        return value
    }

    public func member(_ key: String) -> StrictJSONValue? {
        members?.first(where: { $0.key == key })?.value
    }
}

public enum StrictJSON {
    public static let maximumDepth = 256

    public static func parse(_ data: Data) throws -> StrictJSONValue {
        var parser = ByteParser(data: data)
        return try parser.parseDocument()
    }
}

private struct ByteParser {
    let data: Data
    var offset = 0

    init(data: Data) {
        self.data = data
    }

    var remaining: Int {
        data.count - offset
    }

    func peek() -> UInt8? {
        guard offset < data.count else {
            return nil
        }
        return data[data.startIndex + offset]
    }

    mutating func parseDocument() throws -> StrictJSONValue {
        if data.count >= 3,
           data[data.startIndex] == 0xEF,
           data[data.startIndex + 1] == 0xBB,
           data[data.startIndex + 2] == 0xBF
        {
            throw StrictJSONError.byteOrderMarkForbidden
        }
        skipWhitespace()
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard offset == data.count else {
            throw StrictJSONError.trailingContent(offset)
        }
        return value
    }

    mutating func skipWhitespace() {
        while let byte = peek(),
              byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            offset += 1
        }
    }

    mutating func parseValue(depth: Int) throws -> StrictJSONValue {
        guard let byte = peek() else {
            throw StrictJSONError.unexpectedEndOfInput
        }
        switch byte {
        case 0x7B:
            return try parseObject(depth: depth)
        case 0x5B:
            return try parseArray(depth: depth)
        case 0x22:
            return .string(try parseString())
        case 0x74:
            try expectLiteral("true")
            return .boolean(true)
        case 0x66:
            try expectLiteral("false")
            return .boolean(false)
        case 0x6E:
            try expectLiteral("null")
            return .null
        default:
            return try parseNumber()
        }
    }

    mutating func expectLiteral(_ literal: String) throws {
        for expected in literal.utf8 {
            guard let byte = peek(), byte == expected else {
                throw StrictJSONError.unexpectedByte(offset)
            }
            offset += 1
        }
    }

    mutating func parseObject(depth: Int) throws -> StrictJSONValue {
        guard depth < StrictJSON.maximumDepth else {
            throw StrictJSONError.depthLimitExceeded
        }
        offset += 1
        var pairs: [(key: String, value: StrictJSONValue)] = []
        var seen = Set<String>()
        skipWhitespace()
        if peek() == 0x7D {
            offset += 1
            return .object(pairs)
        }
        while true {
            skipWhitespace()
            guard peek() == 0x22 else {
                if offset >= data.count {
                    throw StrictJSONError.unexpectedEndOfInput
                }
                throw StrictJSONError.unexpectedByte(offset)
            }
            let key = try parseString()
            guard seen.insert(key).inserted else {
                throw StrictJSONError.duplicateObjectKey(key)
            }
            skipWhitespace()
            guard peek() == 0x3A else {
                if offset >= data.count {
                    throw StrictJSONError.unexpectedEndOfInput
                }
                throw StrictJSONError.unexpectedByte(offset)
            }
            offset += 1
            skipWhitespace()
            let value = try parseValue(depth: depth + 1)
            pairs.append((key: key, value: value))
            skipWhitespace()
            guard let next = peek() else {
                throw StrictJSONError.unexpectedEndOfInput
            }
            if next == 0x2C {
                offset += 1
                continue
            }
            if next == 0x7D {
                offset += 1
                return .object(pairs)
            }
            throw StrictJSONError.unexpectedByte(offset)
        }
    }

    mutating func parseArray(depth: Int) throws -> StrictJSONValue {
        guard depth < StrictJSON.maximumDepth else {
            throw StrictJSONError.depthLimitExceeded
        }
        offset += 1
        var elements: [StrictJSONValue] = []
        skipWhitespace()
        if peek() == 0x5D {
            offset += 1
            return .array(elements)
        }
        while true {
            skipWhitespace()
            elements.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            guard let next = peek() else {
                throw StrictJSONError.unexpectedEndOfInput
            }
            if next == 0x2C {
                offset += 1
                continue
            }
            if next == 0x5D {
                offset += 1
                return .array(elements)
            }
            throw StrictJSONError.unexpectedByte(offset)
        }
    }

    mutating func parseString() throws -> String {
        offset += 1
        var bytes: [UInt8] = []
        while true {
            guard offset < data.count else {
                throw StrictJSONError.unterminatedString
            }
            let byte = data[data.startIndex + offset]
            offset += 1
            switch byte {
            case 0x22:
                guard let decoded = String(bytes: bytes, encoding: .utf8)
                else {
                    throw StrictJSONError.invalidUTF8
                }
                return decoded
            case 0x5C:
                try parseEscape(into: &bytes)
            case 0x00 ... 0x1F:
                throw StrictJSONError.unexpectedByte(offset - 1)
            default:
                bytes.append(byte)
            }
        }
    }

    mutating func parseEscape(into bytes: inout [UInt8]) throws {
        guard offset < data.count else {
            throw StrictJSONError.unterminatedString
        }
        let escaped = data[data.startIndex + offset]
        offset += 1
        switch escaped {
        case 0x22:
            bytes.append(0x22)
        case 0x5C:
            bytes.append(0x5C)
        case 0x2F:
            bytes.append(0x2F)
        case 0x62:
            bytes.append(0x08)
        case 0x66:
            bytes.append(0x0C)
        case 0x6E:
            bytes.append(0x0A)
        case 0x72:
            bytes.append(0x0D)
        case 0x74:
            bytes.append(0x09)
        case 0x75:
            let scalar = try parseUnicodeScalar()
            bytes.append(contentsOf: scalar)
        default:
            throw StrictJSONError.invalidStringEscape(offset - 1)
        }
    }

    mutating func parseUnicodeScalar() throws -> [UInt8] {
        let first = try parseHexQuad()
        let value: UInt32
        if (0xD800 ... 0xDBFF).contains(first) {
            guard remaining >= 2,
                  peek() == 0x5C,
                  data[data.startIndex + offset + 1] == 0x75
            else {
                throw StrictJSONError.unpairedSurrogateEscape(offset)
            }
            offset += 2
            let second = try parseHexQuad()
            guard (0xDC00 ... 0xDFFF).contains(second) else {
                throw StrictJSONError.unpairedSurrogateEscape(offset)
            }
            value = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
        } else if (0xDC00 ... 0xDFFF).contains(first) {
            throw StrictJSONError.unpairedSurrogateEscape(offset)
        } else {
            value = first
        }
        guard let scalar = Unicode.Scalar(value) else {
            throw StrictJSONError.unpairedSurrogateEscape(offset)
        }
        return Array(String(scalar).utf8)
    }

    mutating func parseHexQuad() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0 ..< 4 {
            guard offset < data.count else {
                throw StrictJSONError.unterminatedString
            }
            let byte = data[data.startIndex + offset]
            offset += 1
            let digit: UInt32
            switch byte {
            case 0x30 ... 0x39:
                digit = UInt32(byte - 0x30)
            case 0x41 ... 0x46:
                digit = UInt32(byte - 0x41 + 10)
            case 0x61 ... 0x66:
                digit = UInt32(byte - 0x61 + 10)
            default:
                throw StrictJSONError.invalidStringEscape(offset - 1)
            }
            value = value * 16 + digit
        }
        return value
    }

    mutating func parseNumber() throws -> StrictJSONValue {
        let start = offset
        var isFractional = false
        if peek() == 0x2D {
            offset += 1
        }
        guard let first = peek() else {
            throw StrictJSONError.invalidNumberLiteral(start)
        }
        if first == 0x30 {
            offset += 1
        } else if (0x31 ... 0x39).contains(first) {
            while let byte = peek(), (0x30 ... 0x39).contains(byte) {
                offset += 1
            }
        } else {
            throw StrictJSONError.invalidNumberLiteral(start)
        }
        if peek() == 0x2E {
            isFractional = true
            offset += 1
            var digits = 0
            while let byte = peek(), (0x30 ... 0x39).contains(byte) {
                offset += 1
                digits += 1
            }
            guard digits > 0 else {
                throw StrictJSONError.invalidNumberLiteral(start)
            }
        }
        if let byte = peek(), byte == 0x65 || byte == 0x45 {
            isFractional = true
            offset += 1
            if let sign = peek(), sign == 0x2B || sign == 0x2D {
                offset += 1
            }
            var digits = 0
            while let digit = peek(), (0x30 ... 0x39).contains(digit) {
                offset += 1
                digits += 1
            }
            guard digits > 0 else {
                throw StrictJSONError.invalidNumberLiteral(start)
            }
        }
        let lexeme = String(
            decoding: data[(data.startIndex + start) ..< (data.startIndex + offset)],
            as: UTF8.self
        )
        guard isFractional else {
            return .integer(lexeme == "-0" ? "0" : lexeme)
        }
        guard let value = Double(lexeme) else {
            throw StrictJSONError.invalidNumberLiteral(start)
        }
        guard value.isFinite else {
            throw StrictJSONError.nonFiniteNumber
        }
        return .number(value)
    }
}

public enum CanonicalJSONProfile {
    public static func canonicalBytes(
        of value: StrictJSONValue
    ) throws -> Data {
        var output = ""
        try append(value, to: &output)
        return Data(output.utf8)
    }

    private static func append(
        _ value: StrictJSONValue,
        to output: inout String
    ) throws {
        switch value {
        case let .object(pairs):
            for pair in pairs {
                try CanonicalJSON.validateNFC(pair.key)
            }
            let sorted = pairs.sorted {
                BundleLogicalPath.utf8Less($0.key, $1.key)
            }
            output.append("{")
            for (index, pair) in sorted.enumerated() {
                if index > 0 {
                    output.append(",")
                }
                try CanonicalJSON.appendEscapedString(pair.key, to: &output)
                output.append(":")
                try append(pair.value, to: &output)
            }
            output.append("}")
        case let .array(elements):
            output.append("[")
            for (index, element) in elements.enumerated() {
                if index > 0 {
                    output.append(",")
                }
                try append(element, to: &output)
            }
            output.append("]")
        case let .string(string):
            try CanonicalJSON.validateNFC(string)
            try CanonicalJSON.appendEscapedString(string, to: &output)
        case let .integer(lexeme):
            output.append(lexeme)
        case let .number(value):
            output.append(canonicalFloat(value))
        case let .boolean(flag):
            output.append(flag ? "true" : "false")
        case .null:
            output.append("null")
        }
    }

    static func canonicalFloat(_ value: Double) -> String {
        if value == 0 {
            return value.sign == .minus ? "-0.0" : "0.0"
        }
        let description = String(describing: value.magnitude)
        var intDigitCount = 0
        var exponent = 0
        var digits = ""
        var index = description.startIndex
        while index < description.endIndex,
              let scalar = description[index].asciiValue,
              scalar >= 0x30, scalar <= 0x39
        {
            digits.append(description[index])
            intDigitCount += 1
            index = description.index(after: index)
        }
        if index < description.endIndex, description[index] == "." {
            index = description.index(after: index)
            while index < description.endIndex,
                  let scalar = description[index].asciiValue,
                  scalar >= 0x30, scalar <= 0x39
            {
                digits.append(description[index])
                index = description.index(after: index)
            }
        }
        if index < description.endIndex,
           description[index] == "e" || description[index] == "E"
        {
            index = description.index(after: index)
            var exponentSign = 1
            if index < description.endIndex {
                if description[index] == "-" {
                    exponentSign = -1
                    index = description.index(after: index)
                } else if description[index] == "+" {
                    index = description.index(after: index)
                }
            }
            var magnitude = 0
            while index < description.endIndex,
                  let scalar = description[index].asciiValue,
                  scalar >= 0x30, scalar <= 0x39
            {
                magnitude = magnitude * 10 + Int(scalar - 0x30)
                index = description.index(after: index)
            }
            exponent = exponentSign * magnitude
        }
        let leading = digits.prefix(while: { $0 == "0" }).count
        var significant = String(digits.dropFirst(leading))
        while significant.hasSuffix("0") {
            significant.removeLast()
        }
        if significant.isEmpty {
            significant = "0"
        }
        let point = intDigitCount + exponent - leading
        let sign = value.sign == .minus ? "-" : ""
        if point <= -4 || point > 16 {
            var mantissa = String(significant.prefix(1))
            if significant.count > 1 {
                mantissa += "." + String(significant.dropFirst())
            }
            let exponentValue = point - 1
            let magnitude = abs(exponentValue)
            let padded = magnitude < 10 ? "0\(magnitude)" : "\(magnitude)"
            let marker = exponentValue < 0 ? "-" : "+"
            return "\(sign)\(mantissa)e\(marker)\(padded)"
        }
        if point <= 0 {
            return "\(sign)0.\(String(repeating: "0", count: -point))\(significant)"
        }
        if point >= significant.count {
            return "\(sign)\(significant)\(String(repeating: "0", count: point - significant.count)).0"
        }
        let whole = significant.prefix(point)
        let fraction = significant.dropFirst(point)
        return "\(sign)\(whole).\(fraction)"
    }
}

struct CanonicalDecimal: Sendable, Equatable {
    var negative: Bool
    var digits: String
    var point: Int
}

extension CanonicalDecimal {
    static func normalized(
        negative: Bool,
        rawDigits: String,
        point: Int
    ) -> CanonicalDecimal {
        var digits = rawDigits
        var adjustedPoint = point
        while digits.hasPrefix("0") {
            digits.removeFirst()
            adjustedPoint -= 1
        }
        while digits.hasSuffix("0") {
            digits.removeLast()
        }
        if digits.isEmpty {
            return CanonicalDecimal(negative: false, digits: "0", point: 1)
        }
        return CanonicalDecimal(
            negative: negative,
            digits: digits,
            point: adjustedPoint
        )
    }

    static func fromIntegerLexeme(_ lexeme: String) -> CanonicalDecimal {
        let negative = lexeme.hasPrefix("-")
        let raw = negative ? String(lexeme.dropFirst()) : lexeme
        return normalized(
            negative: negative,
            rawDigits: raw,
            point: raw.count
        )
    }

    static func fromDouble(_ value: Double) -> CanonicalDecimal {
        if value == value.rounded() {
            let exact = String(format: "%.0f", value)
            return fromIntegerLexeme(exact)
        }
        let description = String(describing: value)
        var digits = ""
        var intDigitCount = 0
        var exponent = 0
        var index = description.startIndex
        let negative = description.hasPrefix("-")
        if negative {
            index = description.index(after: index)
        }
        while index < description.endIndex,
              let scalar = description[index].asciiValue,
              scalar >= 0x30, scalar <= 0x39
        {
            digits.append(description[index])
            intDigitCount += 1
            index = description.index(after: index)
        }
        if index < description.endIndex, description[index] == "." {
            index = description.index(after: index)
            while index < description.endIndex,
                  let scalar = description[index].asciiValue,
                  scalar >= 0x30, scalar <= 0x39
            {
                digits.append(description[index])
                index = description.index(after: index)
            }
        }
        if index < description.endIndex,
           description[index] == "e" || description[index] == "E"
        {
            index = description.index(after: index)
            var exponentSign = 1
            if index < description.endIndex {
                if description[index] == "-" {
                    exponentSign = -1
                    index = description.index(after: index)
                } else if description[index] == "+" {
                    index = description.index(after: index)
                }
            }
            var magnitude = 0
            while index < description.endIndex,
                  let scalar = description[index].asciiValue,
                  scalar >= 0x30, scalar <= 0x39
            {
                magnitude = magnitude * 10 + Int(scalar - 0x30)
                index = description.index(after: index)
            }
            exponent = exponentSign * magnitude
        }
        return normalized(
            negative: negative,
            rawDigits: digits,
            point: intDigitCount + exponent
        )
    }

    static func compare(
        _ lhs: CanonicalDecimal,
        _ rhs: CanonicalDecimal
    ) -> ComparisonResult {
        let lhsZero = lhs.digits == "0"
        let rhsZero = rhs.digits == "0"
        if lhsZero, rhsZero {
            return .orderedSame
        }
        if lhsZero {
            return rhs.negative ? .orderedDescending : .orderedAscending
        }
        if rhsZero {
            return lhs.negative ? .orderedAscending : .orderedDescending
        }
        if lhs.negative != rhs.negative {
            return lhs.negative ? .orderedAscending : .orderedDescending
        }
        var magnitude: ComparisonResult
        if lhs.point != rhs.point {
            magnitude = lhs.point < rhs.point
                ? .orderedAscending
                : .orderedDescending
        } else {
            let count = max(lhs.digits.count, rhs.digits.count)
            let left = lhs.digits.padding(
                toLength: count,
                withPad: "0",
                startingAt: 0
            )
            let right = rhs.digits.padding(
                toLength: count,
                withPad: "0",
                startingAt: 0
            )
            magnitude = left == right
                ? .orderedSame
                : (left < right ? .orderedAscending : .orderedDescending)
        }
        if lhs.negative {
            switch magnitude {
            case .orderedAscending:
                return .orderedDescending
            case .orderedDescending:
                return .orderedAscending
            case .orderedSame:
                return .orderedSame
            }
        }
        return magnitude
    }

    static func compare(
        _ lhs: StrictJSONValue,
        _ rhs: StrictJSONValue
    ) -> ComparisonResult? {
        let left = decimal(for: lhs)
        let right = decimal(for: rhs)
        guard let left, let right else {
            return nil
        }
        return compare(left, right)
    }

    static func decimal(for value: StrictJSONValue) -> CanonicalDecimal? {
        switch value {
        case let .integer(lexeme):
            return fromIntegerLexeme(lexeme)
        case let .number(number):
            return fromDouble(number)
        default:
            return nil
        }
    }
}
