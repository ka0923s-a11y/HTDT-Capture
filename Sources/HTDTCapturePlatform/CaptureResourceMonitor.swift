import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(UIKit)
import UIKit
#endif

/// Stable, machine-safe tokens used in `CaptureResourceEvent.detail` values
/// produced by `CaptureResourceMonitor`. Event details are persisted in
/// canonical `quality/capture-quality.json`, so they must never embed
/// localized or platform-versioned text (#183).
public enum CaptureResourceMonitorDetailToken {
    /// `volumeAvailableCapacityForImportantUsage` could not be determined:
    /// the query succeeded but the platform reported no value. Distinct from
    /// "enough storage" — see #181.
    public static let storageCapacityUnavailable =
        "storage_capacity_unavailable"
    /// The capacity query threw. The detail appends the stable `NSError`
    /// domain and integer code as ` domain=<domain> code=<code>` so the same
    /// failure produces identical canonical bytes regardless of locale.
    public static let storageSampleFailed = "storage_sample_failed"
}

public struct CaptureResourceMonitorPolicy: Sendable, Equatable {
    public let storageWarningBytes: Int64
    public let storageCriticalBytes: Int64

    public init(
        storageWarningBytes: Int64 = 2 * 1024 * 1024 * 1024,
        storageCriticalBytes: Int64 = 512 * 1024 * 1024
    ) {
        precondition(storageWarningBytes > storageCriticalBytes)
        precondition(storageCriticalBytes >= 0)
        self.storageWarningBytes = storageWarningBytes
        self.storageCriticalBytes = storageCriticalBytes
    }
}

/// One raw storage-capacity observation for the monitored volume (#181).
public enum CaptureStorageSample: Sendable, Equatable {
    /// `volumeAvailableCapacityForImportantUsage` reported a byte count.
    case measured(availableBytes: Int64)
    /// The query succeeded but the platform reported no capacity value. This
    /// is not evidence that storage is above the safety thresholds.
    case capacityUnavailable
    /// The query threw; `domain`/`code` are the stable `NSError` machine
    /// identifiers, not localized text (#183).
    case queryFailed(domain: String, code: Int)
}

/// Typed storage condition behind a `CaptureResourceAssessment`, so callers
/// can distinguish "enough storage" (no assessment) from "could not
/// determine" (`.capacityUnavailable`/`.sampleFailed`) without parsing
/// detail strings (#181).
public enum CaptureStorageCondition: Sendable, Equatable {
    case storageWarning(availableBytes: Int64)
    case storageCritical(availableBytes: Int64)
    case capacityUnavailable
    case sampleFailed(domain: String, code: Int)
}

public struct CaptureResourceAssessment: Sendable, Equatable {
    public let event: CaptureResourceEvent
    public let failure: CaptureFailureCode?
    /// Machine-stable storage condition that produced `event` (#181).
    /// Finalization preflight should treat `.capacityUnavailable` and
    /// `.sampleFailed` as fail-closed candidates rather than as evidence
    /// that remaining capacity is safe.
    public let condition: CaptureStorageCondition

    public init(
        event: CaptureResourceEvent,
        failure: CaptureFailureCode?,
        condition: CaptureStorageCondition
    ) {
        self.event = event
        self.failure = failure
        self.condition = condition
    }
}

@available(iOS 17.0, *)
@MainActor
public final class CaptureResourceMonitor: NSObject {
    public typealias EventHandler = @MainActor (
        CaptureResourceEvent,
        CaptureFailureCode?
    ) -> Void
    /// Reads `volumeAvailableCapacityForImportantUsage` bytes for the
    /// monitored volume: a byte count when measured, `nil` when the platform
    /// reports the metadata as unavailable, or throws when the query fails
    /// (#181).
    public typealias StorageCapacitySource = () throws -> Int64?

    private let rootDirectory: URL
    private let policy: CaptureResourceMonitorPolicy
    private let eventHandler: EventHandler
    private let capacitySource: StorageCapacitySource
    private var isStarted = false

    public init(
        rootDirectory: URL,
        policy: CaptureResourceMonitorPolicy = .init(),
        capacitySource: StorageCapacitySource? = nil,
        eventHandler: @escaping EventHandler
    ) {
        self.rootDirectory = rootDirectory
        self.policy = policy
        self.capacitySource = capacitySource
            ?? Self.makeVolumeCapacitySource(
                rootDirectory: rootDirectory
            )
        self.eventHandler = eventHandler
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func start() {
        guard !isStarted else {
            return
        }
        isStarted = true

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(thermalStateChanged(_:)),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        #if os(iOS) && canImport(UIKit)
        center.addObserver(
            self,
            selector: #selector(memoryWarning(_:)),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground(_:)),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        #endif

        emitCurrentThermalState()
        sampleStorage()
    }

    public func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        NotificationCenter.default.removeObserver(self)
    }

    /// Unconditional storage assessment for explicit preflight checks such
    /// as finalization. `nil` means capacity was measured above the warning
    /// threshold; an unavailable or failed query returns an explicit typed
    /// assessment instead of silently passing (#181).
    public func currentStorageAssessment()
        -> CaptureResourceAssessment?
    {
        let sample = readStorageSample()
        guard let condition = storageCondition(for: sample) else {
            return nil
        }
        return assessment(for: condition)
    }

    public func sampleStorage() {
        guard isStarted,
              let assessment = currentStorageAssessment()
        else {
            return
        }

        eventHandler(
            assessment.event,
            assessment.failure
        )
    }

    @objc
    private func thermalStateChanged(_ notification: Notification) {
        emitCurrentThermalState()
    }

    @objc
    private func memoryWarning(_ notification: Notification) {
        guard isStarted else {
            return
        }
        eventHandler(
            CaptureResourceEvent(
                kind: .memoryPressure,
                severity: .warning,
                detail: "UIApplication memory warning received"
            ),
            nil
        )
    }

    @objc
    private func applicationDidEnterBackground(
        _ notification: Notification
    ) {
        guard isStarted else {
            return
        }
        eventHandler(
            CaptureResourceEvent(
                kind: .interruption,
                severity: .error,
                detail:
                    "application entered background during active capture"
            ),
            .interrupted
        )
    }

    private func emitCurrentThermalState() {
        guard isStarted else {
            return
        }

        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            break
        case .fair:
            eventHandler(
                CaptureResourceEvent(
                    kind: .thermalPressure,
                    severity: .warning,
                    detail: "thermal state fair"
                ),
                nil
            )
        case .serious:
            eventHandler(
                CaptureResourceEvent(
                    kind: .thermalPressure,
                    severity: .warning,
                    detail: "thermal state serious"
                ),
                nil
            )
        case .critical:
            eventHandler(
                CaptureResourceEvent(
                    kind: .thermalPressure,
                    severity: .error,
                    detail: "thermal state critical"
                ),
                .thermalPressure
            )
        @unknown default:
            eventHandler(
                CaptureResourceEvent(
                    kind: .thermalPressure,
                    severity: .warning,
                    detail: "unknown thermal state"
                ),
                nil
            )
        }
    }

    // MARK: - Storage assessment

    private static func makeVolumeCapacitySource(
        rootDirectory: URL
    ) -> StorageCapacitySource {
        {
            try rootDirectory
                .resourceValues(
                    forKeys: [.volumeAvailableCapacityForImportantUsageKey]
                )
                .volumeAvailableCapacityForImportantUsage
                .map { Int64($0) }
        }
    }

    private func readStorageSample() -> CaptureStorageSample {
        do {
            guard let available = try capacitySource() else {
                return .capacityUnavailable
            }
            return .measured(availableBytes: available)
        } catch {
            // NSError domain + integer code are stable machine identifiers,
            // unlike `localizedDescription` (#183). The domain is bounded so
            // canonical detail bytes stay bounded.
            let nsError = error as NSError
            return .queryFailed(
                domain: String(nsError.domain.prefix(128)),
                code: nsError.code
            )
        }
    }

    /// Raw (unhysteresised) condition for a single storage sample. `nil`
    /// means the capacity was measured above the warning threshold.
    private func storageCondition(
        for sample: CaptureStorageSample
    ) -> CaptureStorageCondition? {
        switch sample {
        case .measured(let available):
            if available < policy.storageCriticalBytes {
                return .storageCritical(availableBytes: available)
            }
            if available < policy.storageWarningBytes {
                return .storageWarning(availableBytes: available)
            }
            return nil
        case .capacityUnavailable:
            return .capacityUnavailable
        case .queryFailed(let domain, let code):
            return .sampleFailed(domain: domain, code: code)
        }
    }

    private func assessment(
        for condition: CaptureStorageCondition
    ) -> CaptureResourceAssessment {
        switch condition {
        case .storageCritical(let available):
            return CaptureResourceAssessment(
                event: CaptureResourceEvent(
                    kind: .storagePressure,
                    severity: .error,
                    detail:
                        "available storage below critical capture threshold: "
                        + String(available)
                        + " bytes"
                ),
                failure: .storagePressure,
                condition: condition
            )
        case .storageWarning(let available):
            return CaptureResourceAssessment(
                event: CaptureResourceEvent(
                    kind: .storagePressure,
                    severity: .warning,
                    detail:
                        "available storage below warning capture threshold: "
                        + String(available)
                        + " bytes"
                ),
                failure: nil,
                condition: condition
            )
        case .capacityUnavailable:
            return CaptureResourceAssessment(
                event: CaptureResourceEvent(
                    kind: .storagePressure,
                    severity: .warning,
                    detail:
                        CaptureResourceMonitorDetailToken
                            .storageCapacityUnavailable
                ),
                failure: nil,
                condition: condition
            )
        case .sampleFailed(let domain, let code):
            return CaptureResourceAssessment(
                event: CaptureResourceEvent(
                    kind: .storagePressure,
                    severity: .warning,
                    detail:
                        CaptureResourceMonitorDetailToken
                            .storageSampleFailed
                        + " domain="
                        + domain
                        + " code="
                        + String(code)
                ),
                failure: nil,
                condition: condition
            )
        }
    }
}
