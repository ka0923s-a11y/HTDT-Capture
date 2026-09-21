import Foundation

public protocol CaptureIdentifier:
    RawRepresentable,
    Codable,
    Hashable,
    Sendable,
    CustomStringConvertible
where RawValue == UUID {
    init(rawValue: UUID)
}

public extension CaptureIdentifier {
    init() {
        self.init(rawValue: UUID())
    }

    init?(canonicalString: String) {
        guard let uuid = UUID(canonicalUUIDv4Text: canonicalString)
        else {
            return nil
        }
        self.init(rawValue: uuid)
    }

    init?(validatingRawValue rawValue: UUID) {
        guard rawValue.isCanonicalUUIDv4 else {
            return nil
        }
        self.init(rawValue: rawValue)
    }

    var description: String {
        rawValue.uuidString.lowercased()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = Self(canonicalString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription:
                    "Expected canonical lowercase UUIDv4 text"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public struct CaptureSeriesID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct CaptureRevisionID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct CaptureSessionID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct CoordinateSpaceID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

extension UUID {
    var isCanonicalUUIDv4: Bool {
        var value = uuid
        let bytes = withUnsafeBytes(of: &value) {
            Array($0)
        }
        return (bytes[6] & 0xf0) == 0x40
            && (bytes[8] & 0xc0) == 0x80
    }

    init?(canonicalUUIDv4Text text: String) {
        guard text == text.lowercased(),
              let uuid = UUID(uuidString: text),
              uuid.uuidString.lowercased() == text,
              uuid.isCanonicalUUIDv4
        else {
            return nil
        }
        self = uuid
    }
}
