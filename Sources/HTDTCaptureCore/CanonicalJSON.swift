import Foundation

public enum CanonicalJSONError: Error, Sendable, Equatable {
    case nonNFCString(String)
}

public indirect enum CanonicalJSONValue: Sendable, Equatable {
    case object([String: CanonicalJSONValue])
    case array([CanonicalJSONValue])
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case null
}

public enum CanonicalJSON {
    public static func encode(
        _ value: CanonicalJSONValue
    ) throws -> Data {
        var output = ""
        try append(value, to: &output)
        return Data(output.utf8)
    }

    private static func append(
        _ value: CanonicalJSONValue,
        to output: inout String
    ) throws {
        switch value {
        case let .object(object):
            output.append("{")
            let keys = try object.keys.map { key -> String in
                try validateNFC(key)
                return key
            }.sorted(by: utf8Less)
            for (index, key) in keys.enumerated() {
                if index > 0 {
                    output.append(",")
                }
                try appendEscapedString(key, to: &output)
                output.append(":")
                if let child = object[key] {
                    try append(child, to: &output)
                }
            }
            output.append("}")

        case let .array(array):
            output.append("[")
            for (index, child) in array.enumerated() {
                if index > 0 {
                    output.append(",")
                }
                try append(child, to: &output)
            }
            output.append("]")

        case let .string(string):
            try validateNFC(string)
            try appendEscapedString(string, to: &output)

        case let .integer(integer):
            output.append(String(integer))

        case let .boolean(boolean):
            output.append(boolean ? "true" : "false")

        case .null:
            output.append("null")
        }
    }

    private static func validateNFC(_ value: String) throws {
        guard value.precomposedStringWithCanonicalMapping == value else {
            throw CanonicalJSONError.nonNFCString(value)
        }
    }

    private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        Array(lhs.utf8).lexicographicallyPrecedes(Array(rhs.utf8))
    }

    private static func appendEscapedString(
        _ value: String,
        to output: inout String
    ) throws {
        try validateNFC(value)
        output.append("\"")
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                output.append("\\\"")
            case 0x5c:
                output.append("\\\\")
            case 0x08:
                output.append("\\b")
            case 0x0c:
                output.append("\\f")
            case 0x0a:
                output.append("\\n")
            case 0x0d:
                output.append("\\r")
            case 0x09:
                output.append("\\t")
            case 0x00...0x1f:
                output.append(
                    String(
                        format: "\\u%04x",
                        scalar.value
                    )
                )
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output.append("\"")
    }
}
