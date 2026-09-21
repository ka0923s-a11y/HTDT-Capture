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
    public static let expectedSchema = "htdt.capture.device"
    public static let expectedSchemaVersion = "1.0.0"

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

        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.expectedSchema,
              schemaVersion == Self.expectedSchemaVersion
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "Unsupported capture device schema"
            )
        }
        let platform = try container.decode(String.self, forKey: .platform)
        guard platform == "iOS" else {
            throw DecodingError.dataCorruptedError(
                forKey: .platform,
                in: container,
                debugDescription: "Unsupported capture device platform"
            )
        }
        try self.init(
            osVersion: container.decode(String.self, forKey: .osVersion),
            osBuild: container.decodeIfPresent(
                String.self,
                forKey: .osBuild
            ),
            hardwareModel: container.decode(
                String.self,
                forKey: .hardwareModel
            ),
            appVersion: container.decodeIfPresent(
                String.self,
                forKey: .appVersion
            ),
            appBuild: container.decodeIfPresent(
                String.self,
                forKey: .appBuild
            )
        )
    }
}

/// Which capture-session boundary a timing correlation sample closes.
/// The v1 `session/timing.json` document orders its two correlations
/// `[start, end]` and has no explicit role field, so the boundary
/// semantics are carried in the correlation `method` label (#200).
public enum CaptureTimingBoundary: Sendable {
    /// The first AR frame the shared session delivers after the start
    /// request. The host samples it before any unrelated configuration
    /// wait or foundation persistence so the stored two-clock authority
    /// begins at the true session-start boundary. RoomPlan's `run()`
    /// necessarily starts the underlying ARSession, so
    /// framework-internal observations between the run request and this
    /// first delivered frame precede the stored correlation interval;
    /// the method label marks that explicitly.
    case sessionStart
    /// The current-frame sample captured at the accepted End boundary
    /// before the session is asked to stop.
    case sessionEnd

    /// The `method` label persisted on the correlation sample.
    public var timingMethod: String {
        switch self {
        case .sessionStart:
            return "bracketed_first_arframe_at_session_start"
        case .sessionEnd:
            return "bracketed_arframe_current_frame"
        }
    }

    /// The `method` label when the sample is produced by the
    /// frame-age-projected estimator (#206): the projected capture
    /// instant and the frame-age-inflated uncertainty are identified
    /// by the suffix so downstream consumers can distinguish the
    /// semantics from a plain read-time bracket.
    public var ageProjectedTimingMethod: String {
        timingMethod + "_age_projected"
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            monotonicSeconds: container.decode(
                Double.self,
                forKey: .monotonicSeconds
            ),
            utc: container.decode(String.self, forKey: .utc),
            method: container.decode(String.self, forKey: .method),
            estimatedUncertaintySeconds: container.decodeIfPresent(
                Double.self,
                forKey: .estimatedUncertaintySeconds
            )
        )
    }
}

/// Result of `FrameTimingCorrelationEstimator.estimate`: the frame's
/// projected capture instant and the full uncertainty budget that
/// instant carries (#206).
public struct FrameTimingCorrelationEstimate:
    Sendable,
    Equatable
{
    /// UTC estimate of the instant the frame was captured — the
    /// wall-clock read midpoint shifted back by the measured frame age.
    public let captureInstantUTC: Date
    /// Signed skew between the monotonic read midpoint and the frame's
    /// own timestamp, in seconds. Positive values are observed frame
    /// age; a negative value means the timestamp was future-dated
    /// relative to the read bracket (clock-domain inconsistency) and is
    /// never projected forward.
    public let observedFrameDeltaSeconds: Double
    /// Declared correlation error bound: half the wall-clock read
    /// bracket, half the monotonic read bracket, the magnitude of the
    /// observed frame delta, and the caller's UTC serialization
    /// quantization.
    public let uncertaintySeconds: Double

    public init(
        captureInstantUTC: Date,
        observedFrameDeltaSeconds: Double,
        uncertaintySeconds: Double
    ) {
        self.captureInstantUTC = captureInstantUTC
        self.observedFrameDeltaSeconds = observedFrameDeltaSeconds
        self.uncertaintySeconds = uncertaintySeconds
    }
}

/// Deterministic frame-age correction for monotonic↔UTC correlation
/// samples (#206).
///
/// `ARSession.currentFrame` vends the latest already-produced frame:
/// its `timestamp` is the capture instant in the host monotonic clock
/// domain (the `mach_absolute_time`-derived seconds shared with
/// `CACurrentMediaTime()`), which always lags the wall-clock read by at
/// least part of a frame interval and can lag arbitrarily during
/// scheduling stalls or tracking interruptions. Bracketing the
/// property read alone therefore bounds only the read latency, not the
/// frame's age.
///
/// Given paired monotonic and wall-clock samples bracketing the frame
/// read, the estimator projects the frame's capture instant onto the
/// wall clock by the measured monotonic delta and folds the observed
/// skew into the declared uncertainty, so a stale `currentFrame` can
/// never carry a near-zero error budget. Non-finite inputs surface as
/// non-finite results and are rejected by `CaptureTimingCorrelation`'s
/// own validation.
public enum FrameTimingCorrelationEstimator {
    public static func estimate(
        frameTimestampSeconds: Double,
        monotonicReadBeforeSeconds: Double,
        monotonicReadAfterSeconds: Double,
        wallClockReadBefore: Date,
        wallClockReadAfter: Date,
        utcSerializationQuantizationSeconds: Double
    ) -> FrameTimingCorrelationEstimate {
        let wallMidpointSeconds =
            (
                wallClockReadBefore.timeIntervalSince1970
                + wallClockReadAfter.timeIntervalSince1970
            ) / 2
        let monotonicMidpointSeconds =
            (
                monotonicReadBeforeSeconds
                + monotonicReadAfterSeconds
            ) / 2

        // Observed skew between the frame's capture timestamp and the
        // instant the frame property was actually read, measured in
        // the shared host monotonic domain.
        let observedDeltaSeconds =
            monotonicMidpointSeconds - frameTimestampSeconds

        // Project the wall-clock midpoint back to the capture instant.
        // A future-dated timestamp (negative delta) is never projected
        // forward; its magnitude still feeds the uncertainty below.
        let frameAgeSeconds = max(0, observedDeltaSeconds)
        let captureInstantUTC = Date(
            timeIntervalSince1970:
                wallMidpointSeconds - frameAgeSeconds
        )

        // The declared error must cover the wall-clock sampling
        // bracket, the monotonic sampling bracket feeding the
        // projection, the observed frame staleness/skew itself, and
        // the quantization error of the emitted UTC text.
        let uncertaintySeconds =
            max(
                0,
                wallClockReadAfter.timeIntervalSince(
                    wallClockReadBefore
                )
            ) / 2
            + max(
                0,
                monotonicReadAfterSeconds
                    - monotonicReadBeforeSeconds
            ) / 2
            + abs(observedDeltaSeconds)
            + max(0, utcSerializationQuantizationSeconds)

        return FrameTimingCorrelationEstimate(
            captureInstantUTC: captureInstantUTC,
            observedFrameDeltaSeconds: observedDeltaSeconds,
            uncertaintySeconds: uncertaintySeconds
        )
    }
}

public struct CaptureTimingDocument:
    Codable,
    Sendable,
    Equatable
{
    public static let expectedSchema = "htdt.capture.timing"
    public static let expectedSchemaVersion = "1.0.0"

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

        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.clockDomain = normalizedDomain
        self.correlations = correlations
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case clockDomain = "clock_domain"
        case correlations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.expectedSchema,
              schemaVersion == Self.expectedSchemaVersion
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "Unsupported capture timing schema"
            )
        }
        try self.init(
            clockDomain: container.decode(
                String.self,
                forKey: .clockDomain
            ),
            correlations: container.decode(
                [CaptureTimingCorrelation].self,
                forKey: .correlations
            )
        )
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
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
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
