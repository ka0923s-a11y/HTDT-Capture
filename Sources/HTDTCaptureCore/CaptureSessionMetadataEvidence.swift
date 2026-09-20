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
    case invalidCorrelationOrder
    case encodedTimingMismatch
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
        guard !osVersion.isEmpty,
              !hardwareModel.isEmpty
        else {
            throw CaptureSessionMetadataError.emptyDeviceField
        }

        self.schema = "htdt.capture.device"
        self.schemaVersion = "1.0.0"
        self.platform = "iOS"
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.hardwareModel = hardwareModel
        self.appVersion = appVersion
        self.appBuild = appBuild
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
        guard !method.isEmpty else {
            throw CaptureSessionMetadataError.emptyTimingMethod
        }
        guard ISO8601DateFormatter().date(from: utc) != nil else {
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
        self.method = method
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
        guard !clockDomain.isEmpty else {
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
        self.clockDomain = clockDomain
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
