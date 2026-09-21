import Foundation

public enum JSONSchemaError: Error, Sendable, Equatable {
    case schemaDocumentNotObject
    case unsupportedKeyword(String)
    case invalidKeywordValue(String)
    case invalidPattern(String)
    case unsupportedFormat(String)
    case unsupportedRef(String)
    case unresolvedRef(String)
    case unknownSchema(String)
}

public struct JSONSchemaViolation: Sendable, Equatable {
    public let path: String
    public let detail: String

    public init(path: String, detail: String) {
        self.path = path
        self.detail = detail
    }
}

enum JSONSchemaType: String, Sendable, CaseIterable {
    case object
    case array
    case string
    case integer
    case number
    case boolean
    case null
}

struct JSONSchemaPattern: @unchecked Sendable {
    let source: String
    let expression: NSRegularExpression

    func matches(_ value: String) -> Bool {
        expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex ..< value.endIndex, in: value)
        ) != nil
    }
}

enum JSONSchemaDateFormat: Sendable {
    case dateTime
    case date
}

enum AdditionalPropertiesMode: Sendable {
    case allowed
    case forbidden
    case schema(JSONSchemaNode)
}

/// Reference type so the recursive schema tree has finite size. Instances
/// are fully populated during compilation and never mutated afterwards.
final class JSONSchemaNode: @unchecked Sendable {
    var types: Set<JSONSchemaType>?
    var constValue: StrictJSONValue?
    var enumValues: [StrictJSONValue]?
    var required: Set<String> = []
    var properties: [String: JSONSchemaNode] = [:]
    var additionalProperties: AdditionalPropertiesMode = .allowed
    var pattern: JSONSchemaPattern?
    var format: JSONSchemaDateFormat?
    var minLength: Int?
    var maxLength: Int?
    var minimum: StrictJSONValue?
    var maximum: StrictJSONValue?
    var minItems: Int?
    var maxItems: Int?
    var uniqueItems = false
    var items: JSONSchemaNode?
    var oneOf: [JSONSchemaNode]?
    var allOf: [JSONSchemaNode]?
    var ifNode: JSONSchemaNode?
    var thenNode: JSONSchemaNode?
    var elseNode: JSONSchemaNode?
    var refName: String?

    init() {}
}

public struct CompiledJSONSchema: Sendable {
    let root: JSONSchemaNode
    let definitions: [String: JSONSchemaNode]
}

public enum JSONSchemaValidator {
    public static func compile(
        _ document: StrictJSONValue
    ) throws -> CompiledJSONSchema {
        guard case .object = document else {
            throw JSONSchemaError.schemaDocumentNotObject
        }
        var definitions: [String: JSONSchemaNode] = [:]
        if let defs = document.member("$defs") {
            guard let members = defs.members else {
                throw JSONSchemaError.invalidKeywordValue("$defs")
            }
            for member in members {
                definitions[member.key] = try compileNode(
                    member.value,
                    allowsDefinitions: false
                )
            }
        }
        let root = try compileNode(document, allowsDefinitions: true)
        for name in referencedDefinitions(in: root) {
            guard definitions[name] != nil else {
                throw JSONSchemaError.unresolvedRef(name)
            }
        }
        return CompiledJSONSchema(root: root, definitions: definitions)
    }

    public static func validate(
        _ value: StrictJSONValue,
        schema: CompiledJSONSchema
    ) -> JSONSchemaViolation? {
        check(value, node: schema.root, schema: schema, path: "$")
    }

    private static func compileNode(
        _ value: StrictJSONValue,
        allowsDefinitions: Bool
    ) throws -> JSONSchemaNode {
        guard let members = value.members else {
            throw JSONSchemaError.schemaDocumentNotObject
        }
        var node = JSONSchemaNode()
        for member in members {
            switch member.key {
            case "$schema", "$id", "title":
                continue
            case "$defs":
                guard allowsDefinitions else {
                    throw JSONSchemaError.unsupportedKeyword("$defs")
                }
                continue
            case "$ref":
                guard let ref = member.value.stringValue,
                      ref.hasPrefix("#/$defs/"),
                      ref.count > "#/$defs/".count
                else {
                    throw JSONSchemaError.unsupportedRef(
                        member.value.stringValue ?? "non-string $ref"
                    )
                }
                node.refName = String(ref.dropFirst("#/$defs/".count))
            case "type":
                node.types = try compileTypes(member.value)
            case "const":
                node.constValue = member.value
            case "enum":
                guard let values = member.value.elements else {
                    throw JSONSchemaError.invalidKeywordValue("enum")
                }
                node.enumValues = values
            case "required":
                guard let names = member.value.elements else {
                    throw JSONSchemaError.invalidKeywordValue("required")
                }
                var required = Set<String>()
                for name in names {
                    guard let string = name.stringValue else {
                        throw JSONSchemaError.invalidKeywordValue("required")
                    }
                    required.insert(string)
                }
                node.required = required
            case "properties":
                guard let properties = member.value.members else {
                    throw JSONSchemaError.invalidKeywordValue("properties")
                }
                for property in properties {
                    node.properties[property.key] = try compileNode(
                        property.value,
                        allowsDefinitions: false
                    )
                }
            case "additionalProperties":
                switch member.value {
                case let .boolean(flag):
                    node.additionalProperties = flag ? .allowed : .forbidden
                case .object:
                    node.additionalProperties = .schema(
                        try compileNode(
                            member.value,
                            allowsDefinitions: false
                        )
                    )
                default:
                    throw JSONSchemaError.invalidKeywordValue(
                        "additionalProperties"
                    )
                }
            case "pattern":
                guard let source = member.value.stringValue,
                      let expression = try? NSRegularExpression(
                          pattern: source
                      )
                else {
                    throw JSONSchemaError.invalidPattern(
                        member.value.stringValue ?? "non-string pattern"
                    )
                }
                node.pattern = JSONSchemaPattern(
                    source: source,
                    expression: expression
                )
            case "format":
                guard let format = member.value.stringValue else {
                    throw JSONSchemaError.invalidKeywordValue("format")
                }
                switch format {
                case "date-time":
                    node.format = .dateTime
                case "date":
                    node.format = .date
                default:
                    throw JSONSchemaError.unsupportedFormat(format)
                }
            case "minLength":
                node.minLength = try compileNonNegative(
                    member.value,
                    keyword: member.key
                )
            case "maxLength":
                node.maxLength = try compileNonNegative(
                    member.value,
                    keyword: member.key
                )
            case "minItems":
                node.minItems = try compileNonNegative(
                    member.value,
                    keyword: member.key
                )
            case "maxItems":
                node.maxItems = try compileNonNegative(
                    member.value,
                    keyword: member.key
                )
            case "minimum":
                node.minimum = try compileNumber(member.value, keyword: member.key)
            case "maximum":
                node.maximum = try compileNumber(member.value, keyword: member.key)
            case "uniqueItems":
                guard case let .boolean(flag) = member.value else {
                    throw JSONSchemaError.invalidKeywordValue("uniqueItems")
                }
                node.uniqueItems = flag
            case "items":
                node.items = try compileNode(
                    member.value,
                    allowsDefinitions: false
                )
            case "oneOf":
                node.oneOf = try compileBranchList(
                    member.value,
                    keyword: member.key
                )
            case "allOf":
                node.allOf = try compileBranchList(
                    member.value,
                    keyword: member.key
                )
            case "if":
                node.ifNode = try compileNode(
                    member.value,
                    allowsDefinitions: false
                )
            case "then":
                node.thenNode = try compileNode(
                    member.value,
                    allowsDefinitions: false
                )
            case "else":
                node.elseNode = try compileNode(
                    member.value,
                    allowsDefinitions: false
                )
            default:
                throw JSONSchemaError.unsupportedKeyword(member.key)
            }
        }
        return node
    }

    private static func compileTypes(
        _ value: StrictJSONValue
    ) throws -> Set<JSONSchemaType> {
        var types = Set<JSONSchemaType>()
        if let single = value.stringValue {
            guard let type = JSONSchemaType(rawValue: single) else {
                throw JSONSchemaError.invalidKeywordValue("type")
            }
            types.insert(type)
            return types
        }
        guard let elements = value.elements else {
            throw JSONSchemaError.invalidKeywordValue("type")
        }
        for element in elements {
            guard let name = element.stringValue,
                  let type = JSONSchemaType(rawValue: name)
            else {
                throw JSONSchemaError.invalidKeywordValue("type")
            }
            types.insert(type)
        }
        return types
    }

    private static func compileNonNegative(
        _ value: StrictJSONValue,
        keyword: String
    ) throws -> Int {
        guard case let .integer(lexeme) = value,
              let number = Int(lexeme),
              number >= 0
        else {
            throw JSONSchemaError.invalidKeywordValue(keyword)
        }
        return number
    }

    private static func compileNumber(
        _ value: StrictJSONValue,
        keyword: String
    ) throws -> StrictJSONValue {
        switch value {
        case .integer, .number:
            return value
        default:
            throw JSONSchemaError.invalidKeywordValue(keyword)
        }
    }

    private static func compileBranchList(
        _ value: StrictJSONValue,
        keyword: String
    ) throws -> [JSONSchemaNode] {
        guard let elements = value.elements else {
            throw JSONSchemaError.invalidKeywordValue(keyword)
        }
        var branches: [JSONSchemaNode] = []
        for element in elements {
            branches.append(
                try compileNode(element, allowsDefinitions: false)
            )
        }
        return branches
    }

    private static func referencedDefinitions(
        in node: JSONSchemaNode
    ) -> Set<String> {
        var names = Set<String>()
        if let ref = node.refName {
            names.insert(ref)
        }
        for property in node.properties.values {
            names.formUnion(referencedDefinitions(in: property))
        }
        if case let .schema(child) = node.additionalProperties {
            names.formUnion(referencedDefinitions(in: child))
        }
        if let items = node.items {
            names.formUnion(referencedDefinitions(in: items))
        }
        for branch in node.oneOf ?? [] {
            names.formUnion(referencedDefinitions(in: branch))
        }
        for branch in node.allOf ?? [] {
            names.formUnion(referencedDefinitions(in: branch))
        }
        for node in [node.ifNode, node.thenNode, node.elseNode] {
            if let node {
                names.formUnion(referencedDefinitions(in: node))
            }
        }
        return names
    }

    private static func valueType(
        _ value: StrictJSONValue
    ) -> JSONSchemaType {
        switch value {
        case .object:
            return .object
        case .array:
            return .array
        case .string:
            return .string
        case .integer:
            return .integer
        case .number:
            return .number
        case .boolean:
            return .boolean
        case .null:
            return .null
        }
    }

    private static func typeAllowed(
        _ value: StrictJSONValue,
        types: Set<JSONSchemaType>
    ) -> Bool {
        switch value {
        case .object:
            return types.contains(.object)
        case .array:
            return types.contains(.array)
        case .string:
            return types.contains(.string)
        case .boolean:
            return types.contains(.boolean)
        case .null:
            return types.contains(.null)
        case .integer:
            return types.contains(.integer) || types.contains(.number)
        case let .number(number):
            // Draft 2020-12: "integer" matches any number with a zero
            // fractional part, so an integral float lexeme (e.g. 4.0)
            // satisfies "type": "integer" exactly like the reference
            // validator's numeric handling.
            if types.contains(.number) {
                return true
            }
            return types.contains(.integer) && number == number.rounded()
        }
    }

    private static func check(
        _ value: StrictJSONValue,
        node: JSONSchemaNode,
        schema: CompiledJSONSchema,
        path: String
    ) -> JSONSchemaViolation? {
        if let refName = node.refName {
            guard let target = schema.definitions[refName] else {
                return JSONSchemaViolation(
                    path: path,
                    detail: "unresolved $ref \(refName)"
                )
            }
            if let violation = check(
                value,
                node: target,
                schema: schema,
                path: path
            ) {
                return violation
            }
        }
        if let types = node.types, !typeAllowed(value, types: types) {
            return JSONSchemaViolation(
                path: path,
                detail: "expected type \(types.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: "|"))"
            )
        }
        if let constValue = node.constValue,
           !jsonValuesEqual(value, constValue)
        {
            return JSONSchemaViolation(
                path: path,
                detail: "const mismatch"
            )
        }
        if let enumValues = node.enumValues,
           !enumValues.contains(where: { jsonValuesEqual(value, $0) })
        {
            return JSONSchemaViolation(
                path: path,
                detail: "enum mismatch"
            )
        }
        switch value {
        case let .object(pairs):
            let present = Set(pairs.map(\.key))
            for name in node.required.sorted()
            where !present.contains(name)
            {
                return JSONSchemaViolation(
                    path: path,
                    detail: "missing required property \(name)"
                )
            }
            for pair in pairs {
                if let property = node.properties[pair.key] {
                    if let violation = check(
                        pair.value,
                        node: property,
                        schema: schema,
                        path: "\(path).\(pair.key)"
                    ) {
                        return violation
                    }
                } else {
                    switch node.additionalProperties {
                    case .allowed:
                        continue
                    case .forbidden:
                        return JSONSchemaViolation(
                            path: "\(path).\(pair.key)",
                            detail: "additional property \(pair.key) forbidden"
                        )
                    case let .schema(child):
                        if let violation = check(
                            pair.value,
                            node: child,
                            schema: schema,
                            path: "\(path).\(pair.key)"
                        ) {
                            return violation
                        }
                    }
                }
            }
        case let .array(elements):
            if let minItems = node.minItems, elements.count < minItems {
                return JSONSchemaViolation(
                    path: path,
                    detail: "fewer than \(minItems) items"
                )
            }
            if let maxItems = node.maxItems, elements.count > maxItems {
                return JSONSchemaViolation(
                    path: path,
                    detail: "more than \(maxItems) items"
                )
            }
            if node.uniqueItems {
                var seen = Set<String>()
                for element in elements {
                    let key = uniquenessKey(element)
                    if !seen.insert(key).inserted {
                        return JSONSchemaViolation(
                            path: path,
                            detail: "duplicate array element"
                        )
                    }
                }
            }
            if let items = node.items {
                for (index, element) in elements.enumerated() {
                    if let violation = check(
                        element,
                        node: items,
                        schema: schema,
                        path: "\(path)[\(index)]"
                    ) {
                        return violation
                    }
                }
            }
        case let .string(string):
            let length = string.unicodeScalars.count
            if let minLength = node.minLength, length < minLength {
                return JSONSchemaViolation(
                    path: path,
                    detail: "shorter than \(minLength) scalars"
                )
            }
            if let maxLength = node.maxLength, length > maxLength {
                return JSONSchemaViolation(
                    path: path,
                    detail: "longer than \(maxLength) scalars"
                )
            }
            if let pattern = node.pattern, !pattern.matches(string) {
                return JSONSchemaViolation(
                    path: path,
                    detail: "pattern \(pattern.source) mismatch"
                )
            }
            if let format = node.format {
                switch format {
                case .dateTime:
                    if !isValidDateTime(string) {
                        return JSONSchemaViolation(
                            path: path,
                            detail: "invalid date-time \(string)"
                        )
                    }
                case .date:
                    if !isValidDate(string) {
                        return JSONSchemaViolation(
                            path: path,
                            detail: "invalid date \(string)"
                        )
                    }
                }
            }
        case .integer, .number:
            if let minimum = node.minimum,
               let order = CanonicalDecimal.compare(value, minimum),
               order == .orderedAscending
            {
                return JSONSchemaViolation(
                    path: path,
                    detail: "below minimum"
                )
            }
            if let maximum = node.maximum,
               let order = CanonicalDecimal.compare(value, maximum),
               order == .orderedDescending
            {
                return JSONSchemaViolation(
                    path: path,
                    detail: "above maximum"
                )
            }
        default:
            break
        }
        if let allOf = node.allOf {
            for branch in allOf {
                if let violation = check(
                    value,
                    node: branch,
                    schema: schema,
                    path: path
                ) {
                    return violation
                }
            }
        }
        if let oneOf = node.oneOf {
            var matches = 0
            for branch in oneOf where check(
                value,
                node: branch,
                schema: schema,
                path: path
            ) == nil {
                matches += 1
            }
            if matches != 1 {
                return JSONSchemaViolation(
                    path: path,
                    detail: "oneOf matched \(matches) branches"
                )
            }
        }
        if let ifNode = node.ifNode {
            let condition = check(
                value,
                node: ifNode,
                schema: schema,
                path: path
            ) == nil
            if condition, let thenNode = node.thenNode {
                if let violation = check(
                    value,
                    node: thenNode,
                    schema: schema,
                    path: path
                ) {
                    return violation
                }
            } else if !condition, let elseNode = node.elseNode {
                if let violation = check(
                    value,
                    node: elseNode,
                    schema: schema,
                    path: path
                ) {
                    return violation
                }
            }
        }
        return nil
    }

    private static func uniquenessKey(
        _ value: StrictJSONValue
    ) -> String {
        switch value {
        case let .object(pairs):
            let sorted = pairs.sorted {
                BundleLogicalPath.utf8Less($0.key, $1.key)
            }
            var result = "O{"
            for pair in sorted {
                result += "\(pair.key.count):\(pair.key)=\(uniquenessKey(pair.value));"
            }
            return result + "}"
        case let .array(elements):
            var result = "A["
            for element in elements {
                result += "\(uniquenessKey(element)),"
            }
            return result + "]"
        case let .string(string):
            return "S\(string.count):\(string)"
        case let .integer(lexeme):
            return "N\(lexeme)"
        case let .number(number):
            if number == 0 {
                return "N0"
            }
            if number == number.rounded(), number.isFinite {
                return "N\(String(format: "%.0f", number))"
            }
            return "R\(String(describing: number))"
        case let .boolean(flag):
            return "B\(flag ? "true" : "false")"
        case .null:
            return "Z"
        }
    }

    static func jsonValuesEqual(
        _ lhs: StrictJSONValue,
        _ rhs: StrictJSONValue
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.object(left), .object(right)):
            guard left.count == right.count else {
                return false
            }
            for pair in left {
                guard let candidate = right.first(where: {
                    $0.key == pair.key
                }) else {
                    return false
                }
                guard jsonValuesEqual(pair.value, candidate.value) else {
                    return false
                }
            }
            return true
        case let (.array(left), .array(right)):
            guard left.count == right.count else {
                return false
            }
            for index in left.indices
            where !jsonValuesEqual(left[index], right[index])
            {
                return false
            }
            return true
        case let (.string(left), .string(right)):
            return left == right
        case let (.boolean(left), .boolean(right)):
            return left == right
        case (.null, .null):
            return true
        case (.integer, .integer), (.integer, .number), (.number, .integer),
             (.number, .number):
            return CanonicalDecimal.compare(lhs, rhs) == .orderedSame
        default:
            return false
        }
    }

    private static func isValidDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10 else {
            return false
        }
        guard isDigit(bytes, 0), isDigit(bytes, 1), isDigit(bytes, 2),
              isDigit(bytes, 3), bytes[4] == 0x2D, isDigit(bytes, 5),
              isDigit(bytes, 6), bytes[7] == 0x2D, isDigit(bytes, 8),
              isDigit(bytes, 9)
        else {
            return false
        }
        return validDateFields(
            year: numericValue(bytes, 0, 4),
            month: numericValue(bytes, 5, 2),
            day: numericValue(bytes, 8, 2)
        )
    }

    private static func isValidDateTime(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count >= 20 else {
            return false
        }
        guard isDigit(bytes, 0), isDigit(bytes, 1), isDigit(bytes, 2),
              isDigit(bytes, 3), bytes[4] == 0x2D, isDigit(bytes, 5),
              isDigit(bytes, 6), bytes[7] == 0x2D, isDigit(bytes, 8),
              isDigit(bytes, 9),
              bytes[10] == 0x54 || bytes[10] == 0x74,
              isDigit(bytes, 11), isDigit(bytes, 12), bytes[13] == 0x3A,
              isDigit(bytes, 14), isDigit(bytes, 15), bytes[16] == 0x3A,
              isDigit(bytes, 17), isDigit(bytes, 18)
        else {
            return false
        }
        guard validDateFields(
            year: numericValue(bytes, 0, 4),
            month: numericValue(bytes, 5, 2),
            day: numericValue(bytes, 8, 2)
        ) else {
            return false
        }
        let hour = numericValue(bytes, 11, 2)
        let minute = numericValue(bytes, 14, 2)
        let second = numericValue(bytes, 17, 2)
        guard hour <= 23, minute <= 59, second <= 60 else {
            return false
        }
        var index = 19
        if bytes[index] == 0x2E {
            index += 1
            let start = index
            while index < bytes.count, bytes[index] >= 0x30,
                  bytes[index] <= 0x39
            {
                index += 1
            }
            guard index > start else {
                return false
            }
        }
        guard index < bytes.count else {
            return false
        }
        if bytes[index] == 0x5A || bytes[index] == 0x7A {
            return index == bytes.count - 1
        }
        guard bytes[index] == 0x2B || bytes[index] == 0x2D else {
            return false
        }
        index += 1
        guard bytes.count - index == 5,
              isDigit(bytes, index), isDigit(bytes, index + 1),
              bytes[index + 2] == 0x3A,
              isDigit(bytes, index + 3), isDigit(bytes, index + 4)
        else {
            return false
        }
        let offsetHour = numericValue(bytes, index, 2)
        let offsetMinute = numericValue(bytes, index + 3, 2)
        return offsetHour <= 23 && offsetMinute <= 59
    }

    private static func isDigit(_ bytes: [UInt8], _ index: Int) -> Bool {
        bytes[index] >= 0x30 && bytes[index] <= 0x39
    }

    private static func numericValue(
        _ bytes: [UInt8],
        _ offset: Int,
        _ length: Int
    ) -> Int {
        var value = 0
        for index in offset ..< offset + length {
            value = value * 10 + Int(bytes[index] - 0x30)
        }
        return value
    }

    private static func validDateFields(
        year: Int,
        month: Int,
        day: Int
    ) -> Bool {
        guard month >= 1, month <= 12 else {
            return false
        }
        let lengths = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30,
                       31, 31, 30, 31, 30, 31]
        return day >= 1 && day <= lengths[month - 1]
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}
