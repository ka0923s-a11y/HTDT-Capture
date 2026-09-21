import Foundation

public enum DepthEvidenceError: Error, Sendable, Equatable {
    case invalidDimensions
    case sampleCountOverflow
    case sampleCountMismatch(expected: Int, actual: Int)
    case nonFiniteDepth(Int)
    case validityCountMismatch(expected: Int, actual: Int)
    case invalidValidityValue(index: Int, value: UInt8)
    case confidenceCountMismatch(expected: Int, actual: Int)
}

public struct DepthMapPayload: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let valuesMeters: [Float]
    public let validityMask: [UInt8]?

    public init(
        width: Int,
        height: Int,
        valuesMeters: [Float],
        validityMask: [UInt8]? = nil
    ) throws {
        guard width > 0, height > 0 else {
            throw DepthEvidenceError.invalidDimensions
        }
        let count = width.multipliedReportingOverflow(by: height)
        guard !count.overflow else {
            throw DepthEvidenceError.sampleCountOverflow
        }
        guard valuesMeters.count == count.partialValue else {
            throw DepthEvidenceError.sampleCountMismatch(
                expected: count.partialValue,
                actual: valuesMeters.count
            )
        }
        for (index, value) in valuesMeters.enumerated() where !value.isFinite {
            throw DepthEvidenceError.nonFiniteDepth(index)
        }
        if let validityMask {
            guard validityMask.count == count.partialValue else {
                throw DepthEvidenceError.validityCountMismatch(
                    expected: count.partialValue,
                    actual: validityMask.count
                )
            }
            for (index, value) in validityMask.enumerated()
                where value != 0 && value != 1
            {
                throw DepthEvidenceError.invalidValidityValue(
                    index: index,
                    value: value
                )
            }
        }

        self.width = width
        self.height = height
        self.valuesMeters = valuesMeters
        self.validityMask = validityMask
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case valuesMeters
        case validityMask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            width: container.decode(Int.self, forKey: .width),
            height: container.decode(Int.self, forKey: .height),
            valuesMeters: container.decode(
                [Float].self,
                forKey: .valuesMeters
            ),
            validityMask: container.decodeIfPresent(
                [UInt8].self,
                forKey: .validityMask
            )
        )
    }
}

public struct ConfidenceMapPayload: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let values: [UInt8]

    public init(
        width: Int,
        height: Int,
        values: [UInt8]
    ) throws {
        guard width > 0, height > 0 else {
            throw DepthEvidenceError.invalidDimensions
        }
        let count = width.multipliedReportingOverflow(by: height)
        guard !count.overflow else {
            throw DepthEvidenceError.sampleCountOverflow
        }
        guard values.count == count.partialValue else {
            throw DepthEvidenceError.confidenceCountMismatch(
                expected: count.partialValue,
                actual: values.count
            )
        }

        self.width = width
        self.height = height
        self.values = values
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            width: container.decode(Int.self, forKey: .width),
            height: container.decode(Int.self, forKey: .height),
            values: container.decode([UInt8].self, forKey: .values)
        )
    }
}
