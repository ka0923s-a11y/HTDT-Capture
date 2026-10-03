import Foundation

/// Pre-capture storage assessment for the setup workflow (legacy bolph71656-ai/HTDT-Capture#212).
/// Uses the same thresholds as the runtime `CaptureResourceMonitor`
/// policy so the preflight warning agrees with the in-scan failure
/// boundary: warning below `storageWarningBytes`, blocking below
/// `storageCriticalBytes`.
public enum CaptureStorageReadiness: String, Sendable, Equatable {
    /// The storage probe could not determine free space; scanning may
    /// proceed and the runtime monitor remains the authority.
    case unknown
    case sufficient
    case low
    case critical
}

public struct CaptureStoragePreflight: Sendable, Equatable {
    public let availableBytes: UInt64?
    public let warningBytes: UInt64
    public let criticalBytes: UInt64

    public init(
        availableBytes: UInt64?,
        warningBytes: UInt64 = 2 * 1024 * 1024 * 1024,
        criticalBytes: UInt64 = 512 * 1024 * 1024
    ) {
        self.availableBytes = availableBytes
        self.warningBytes = warningBytes
        self.criticalBytes = criticalBytes
    }

    public var readiness: CaptureStorageReadiness {
        guard let availableBytes else {
            return .unknown
        }
        if availableBytes <= criticalBytes {
            return .critical
        }
        if availableBytes <= warningBytes {
            return .low
        }
        return .sufficient
    }

    /// Whether the storage state is bad enough to block starting a
    /// canonical capture. Low storage is advisory; at/below the
    /// critical threshold starting would just hit the runtime
    /// monitor's termination path.
    public var blocksCaptureStart: Bool {
        readiness == .critical
    }
}

/// Battery / power-mode readiness surfaced in the pre-capture setup
/// (legacy bolph71656-ai/HTDT-Capture#272). These inputs are advisory only: no charge percentage becomes
/// a canonical quality rule, but a nearly depleted or power-throttled
/// device produces an actionable warning before a long acquisition.
public struct CaptureDeviceReadiness: Sendable, Equatable {
    public enum BatteryState: String, Sendable, Equatable {
        /// Battery level/state unavailable (monitoring off or not a
        /// battery device).
        case unknown
        case unplugged
        case charging
        case full
    }

    /// Fraction 0...1, or nil when the device cannot report a level.
    public let batteryLevel: Double?
    public let batteryState: BatteryState
    public let lowPowerModeEnabled: Bool
    /// Fraction below which starting a long scan is warned against
    /// (still non-blocking).
    public let lowBatteryThreshold: Double

    public init(
        batteryLevel: Double?,
        batteryState: BatteryState,
        lowPowerModeEnabled: Bool,
        lowBatteryThreshold: Double = 0.2
    ) {
        self.batteryLevel = batteryLevel
        self.batteryState = batteryState
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.lowBatteryThreshold = lowBatteryThreshold
    }

    public var hasLowBattery: Bool {
        guard let batteryLevel,
              batteryState == .unplugged
        else {
            return false
        }
        return batteryLevel <= lowBatteryThreshold
    }

    /// Advisory warnings, most important first. Empty when nothing is
    /// worth telling the operator.
    public var advisories: [CaptureDeviceReadinessAdvisory] {
        var result: [CaptureDeviceReadinessAdvisory] = []
        if hasLowBattery {
            result.append(.lowBattery)
        }
        if lowPowerModeEnabled {
            result.append(.lowPowerMode)
        }
        return result
    }
}

public enum CaptureDeviceReadinessAdvisory: String, Sendable, Equatable {
    case lowBattery = "low_battery"
    case lowPowerMode = "low_power_mode"
}
