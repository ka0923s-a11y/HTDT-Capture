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
        guard canonicalString == canonicalString.lowercased(),
              let uuid = UUID(uuidString: canonicalString),
              uuid.uuidString.lowercased() == canonicalString
        else {
            return nil
        }
        self.init(rawValue: uuid)
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
                debugDescription: "Expected canonical lowercase UUID text"
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
