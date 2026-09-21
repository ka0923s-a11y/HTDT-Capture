import Foundation

public enum CaptureSessionMetadataError:
    Error,
    Sendable,
    Equatable
{
    case emptyDeviceField
    case invalidMonotonicTimestamp
    case emptyClockDomain
    case emptyTimingMethod
    case invalidTimingUncertainty
    case invalidUTCTimestamp
    case invalidCalendarDate
    case emptySessionReference
    case invalidCorrelationOrder
    case encodedTimingMismatch
}

/// Shared timestamp authority policy for schema-owned time fields.
/// `date-time` fields must be canonical UTC RFC3339 text ending in `Z`
/// (`YYYY-MM-DDTHH:MM:SS[.fraction]Z`), matching the manifest timestamp
/// profile; `date` fields must be valid `YYYY-MM-DD` Gregorian calendar
/// dates. Validation is bytewise so results are deterministic across
/// locales and platforms.
enum SchemaTimestampText {
    static func isUTCTimestamp(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        // Shortest form: "YYYY-MM-DDTHH:MM:SSZ" (20 bytes).
        guard bytes.count >= 20,
              bytes[bytes.count - 1] == 0x5A,          // 'Z'
              bytes[4] == 0x2D, bytes[7] == 0x2D,      // '-'
              bytes[10] == 0x54,                       // 'T'
              bytes[13] == 0x3A, bytes[16] == 0x3A     // ':'
        else {
            return false
        }
        guard let year = decimalValue(bytes, in: 0..<4),
              let month = decimalValue(bytes, in: 5..<7),
              let day = decimalValue(bytes, in: 8..<10),
              let hour = decimalValue(bytes, in: 11..<13),
              let minute = decimalValue(bytes, in: 14..<16),
              let second = decimalValue(bytes, in: 17..<19)
        else {
            return false
        }
        if bytes.count > 20 {
            // Optional fractional seconds: '.' then one or more digits
            // immediately before the trailing 'Z'.
            guard bytes[19] == 0x2E else {             // '.'
                return false
            }
            let fraction = bytes[20..<(bytes.count - 1)]
            guard !fraction.isEmpty,
                  fraction.allSatisfy(isDecimalDigit)
            else {
                return false
            }
        }
        guard isValidDate(year: year, month: month, day: day),
              hour <= 23,
              minute <= 59,
              second <= 59
        else {
            return false
        }
        return true
    }

    static func isCalendarDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == 0x2D, bytes[7] == 0x2D,
              let year = decimalValue(bytes, in: 0..<4),
              let month = decimalValue(bytes, in: 5..<7),
              let day = decimalValue(bytes, in: 8..<10)
        else {
            return false
        }
        return isValidDate(year: year, month: month, day: day)
    }

    private static func isDecimalDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private static func decimalValue(
        _ bytes: [UInt8],
        in range: Range<Int>
    ) -> Int? {
        var value = 0
        for index in range {
            guard isDecimalDigit(bytes[index]) else {
                return nil
            }
            value = value * 10 + Int(bytes[index] - 0x30)
        }
        return value
    }

    private static func isValidDate(
        year: Int,
        month: Int,
        day: Int
    ) -> Bool {
        guard year >= 1, day >= 1 else {
            return false
        }
        let daysInMonth: Int
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            daysInMonth = 31
        case 4, 6, 9, 11:
            daysInMonth = 30
        case 2:
            let leap =
                (year % 4 == 0 && year % 100 != 0)
                || year % 400 == 0
            daysInMonth = leap ? 29 : 28
        default:
            return false
        }
        return day <= daysInMonth
    }
}

public struct CaptureDeviceDocument:
    Codable,
    Sendable,
    Equatable
{
    public let schema: String
    public let schemaVersion: String
    public let platform: String
    public let osVersion: String
    public let osBuild: String?
    public let hardwareModel: String
    public let appVersion: String?
    public let appBuild: String?

    public init(
        osVersion: String,
        osBuild: String? = nil,
        hardwareModel: String,
        appVersion: String? = nil,
        appBuild: String? = nil
    ) throws {
        let normalizedOSVersion = SchemaOwnedText.nfc(osVersion)
        let normalizedHardwareModel = SchemaOwnedText.nfc(hardwareModel)
        guard !normalizedOSVersion.isEmpty,
              !normalizedHardwareModel.isEmpty
        else {
            throw CaptureSessionMetadataError.emptyDeviceField
        }

        self.schema = "htdt.capture.device"
        self.schemaVersion = "1.0.0"
        self.platform = "iOS"
        self.osVersion = normalizedOSVersion
        self.osBuild = SchemaOwnedText.nfc(osBuild)
        self.hardwareModel = normalizedHardwareModel
        self.appVersion = SchemaOwnedText.nfc(appVersion)
        self.appBuild = SchemaOwnedText.nfc(appBuild)
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case platform
        case osVersion = "os_version"
        case osBuild = "os_build"
        case hardwareModel = "hardware_model"
        case appVersion = "app_version"
        case appBuild = "app_build"
    }
}

public struct CaptureTimingCorrelation:
    Codable,
    Sendable,
    Equatable
{
    public let monotonicSeconds: Double
    public let utc: String
    public let method: String
    public let estimatedUncertaintySeconds: Double?

    public init(
        monotonicSeconds: Double,
        utc: String,
        method: String,
        estimatedUncertaintySeconds: Double? = nil
    ) throws {
        guard monotonicSeconds.isFinite,
              monotonicSeconds >= 0
        else {
            throw CaptureSessionMetadataError
                .invalidMonotonicTimestamp
        }
        let normalizedMethod = SchemaOwnedText.nfc(method)
        guard !normalizedMethod.isEmpty else {
            throw CaptureSessionMetadataError.emptyTimingMethod
        }
        guard SchemaTimestampText.isUTCTimestamp(utc) else {
            throw CaptureSessionMetadataError.invalidUTCTimestamp
        }
        if let estimatedUncertaintySeconds {
            guard estimatedUncertaintySeconds.isFinite,
                  estimatedUncertaintySeconds >= 0
            else {
                throw CaptureSessionMetadataError
                    .invalidTimingUncertainty
            }
        }

        self.monotonicSeconds = monotonicSeconds
        self.utc = utc
        self.method = normalizedMethod
        self.estimatedUncertaintySeconds =
            estimatedUncertaintySeconds
    }

    private enum CodingKeys: String, CodingKey {
        case monotonicSeconds = "monotonic_s"
        case utc
        case method
        case estimatedUncertaintySeconds =
            "estimated_uncertainty_s"
    }
}

public struct CaptureTimingDocument:
    Codable,
    Sendable,
    Equatable
{
    public let schema: String
    public let schemaVersion: String
    public let clockDomain: String
    public let correlations: [CaptureTimingCorrelation]

    public init(
        clockDomain: String,
        correlations: [CaptureTimingCorrelation]
    ) throws {
        let normalizedDomain = SchemaOwnedText.nfc(clockDomain)
        guard !normalizedDomain.isEmpty else {
            throw CaptureSessionMetadataError.emptyClockDomain
        }
        guard !correlations.isEmpty else {
            throw CaptureSessionMetadataError
                .invalidCorrelationOrder
        }

        var previous = -Double.infinity
        for correlation in correlations {
            guard correlation.monotonicSeconds >= previous else {
                throw CaptureSessionMetadataError
                    .invalidCorrelationOrder
            }
            previous = correlation.monotonicSeconds
        }

        self.schema = "htdt.capture.timing"
        self.schemaVersion = "1.0.0"
        self.clockDomain = normalizedDomain
        self.correlations = correlations
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case clockDomain = "clock_domain"
        case correlations
    }
}

public struct CaptureTimingPackage:
    Sendable,
    Equatable
{
    public static let path = "session/timing.json"
    public static let clockDomain =
        "arkit_arframe_timestamp_seconds"

    public let document: CaptureTimingDocument
    public let data: Data

    public init(
        document: CaptureTimingDocument,
        data: Data
    ) {
        self.document = document
        self.data = data
    }

    public var payloadDeclaration: BundlePayloadDeclaration {
        BundlePayloadDeclaration(
            path: Self.path,
            mediaType: "application/json",
            producer: "capture_session",
            provenanceClass: .captureAppDerived,
            role: .canonical
        )
    }
}

public enum CaptureTimingPackageBuilder {
    public static func build(
        start: CaptureTimingCorrelation,
        end: CaptureTimingCorrelation
    ) throws -> CaptureTimingPackage {
        guard end.monotonicSeconds >= start.monotonicSeconds else {
            throw CaptureSessionMetadataError
                .invalidCorrelationOrder
        }

        let document = try CaptureTimingDocument(
            clockDomain: CaptureTimingPackage.clockDomain,
            correlations: [start, end]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)

        guard
            let decoded = try? JSONDecoder().decode(
                CaptureTimingDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw CaptureSessionMetadataError
                .encodedTimingMismatch
        }

        return CaptureTimingPackage(
            document: document,
            data: data
        )
    }
}
