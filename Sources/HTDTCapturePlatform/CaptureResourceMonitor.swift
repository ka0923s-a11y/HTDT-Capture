import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(UIKit)
import UIKit
#endif

/// Stable, machine-safe tokens used in `CaptureResourceEvent.detail` values
/// produced by `CaptureResourceMonitor`. Event details are persisted in
/// canonical `quality/capture-quality.json`, so they must never embed
/// localized or platform-versioned text (legacy bolph71656-ai/HTDT-Capture#183).
public enum CaptureResourceMonitorDetailToken {
    /// `volumeAvailableCapacityForImportantUsage` could not be determined:
    /// the query succeeded but the platform reported no value. Distinct from
    /// "enough storage" — see legacy bolph71656-ai/HTDT-Capture#181.
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
    /// Low-frequency interval between periodic storage samples while the
    /// monitor is started (legacy bolph71656-ai/HTDT-Capture#140).
    public let storageSampleInterval: Duration
    /// Capacity margin above a threshold required before the monitor reports
    /// recovery to a lower-pressure band, so capacity oscillation near a
    /// boundary does not spam storage-pressure events (legacy bolph71656-ai/HTDT-Capture#140).
    public let storageHysteresisBytes: Int64
    /// Hard bound on periodic samples per `start()` session. `0` disables
    /// periodic sampling; the explicit preflight assessment is unaffected
    /// (legacy bolph71656-ai/HTDT-Capture#140).
    public let maximumPeriodicStorageSamples: Int

    public init(
        storageWarningBytes: Int64 = 2 * 1024 * 1024 * 1024,
        storageCriticalBytes: Int64 = 512 * 1024 * 1024,
        storageSampleInterval: Duration = .seconds(5),
        storageHysteresisBytes: Int64 = 64 * 1024 * 1024,
        maximumPeriodicStorageSamples: Int = 5760
    ) {
        precondition(storageWarningBytes > storageCriticalBytes)
        precondition(storageCriticalBytes >= 0)
        precondition(storageSampleInterval > .zero)
        precondition(storageHysteresisBytes >= 0)
        precondition(maximumPeriodicStorageSamples >= 0)
        self.storageWarningBytes = storageWarningBytes
        self.storageCriticalBytes = storageCriticalBytes
        self.storageSampleInterval = storageSampleInterval
        self.storageHysteresisBytes = storageHysteresisBytes
        self.maximumPeriodicStorageSamples =
            maximumPeriodicStorageSamples
    }
}

/// One raw storage-capacity observation for the monitored volume (legacy bolph71656-ai/HTDT-Capture#181).
public enum CaptureStorageSample: Sendable, Equatable {
    /// `volumeAvailableCapacityForImportantUsage` reported a byte count.
    case measured(availableBytes: Int64)
    /// The query succeeded but the platform reported no capacity value. This
    /// is not evidence that storage is above the safety thresholds.
    case capacityUnavailable
    /// The query threw; `domain`/`code` are the stable `NSError` machine
    /// identifiers, not localized text (legacy bolph71656-ai/HTDT-Capture#183).
    case queryFailed(domain: String, code: Int)
}

/// Typed storage condition behind a `CaptureResourceAssessment`, so callers
/// can distinguish "enough storage" (no assessment) from "could not
/// determine" (`.capacityUnavailable`/`.sampleFailed`) without parsing
/// detail strings (legacy bolph71656-ai/HTDT-Capture#181).
public enum CaptureStorageCondition: Sendable, Equatable {
    case storageWarning(availableBytes: Int64)
    case storageCritical(availableBytes: Int64)
    case capacityUnavailable
    case sampleFailed(domain: String, code: Int)
}

public struct CaptureResourceAssessment: Sendable, Equatable {
    public let event: CaptureResourceEvent
    public let failure: CaptureFailureCode?
    /// Machine-stable storage condition that produced `event` (legacy bolph71656-ai/HTDT-Capture#181).
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

/// Tracks the last emitted storage condition so periodic sampling emits an
/// event only when the condition transitions, with a hysteresis margin on
/// recovery so capacity oscillation near a threshold does not spam events
/// (legacy bolph71656-ai/HTDT-Capture#140).
public struct CaptureStoragePressureTracker: Sendable, Equatable {
    /// The condition currently treated as emitted/known.
    public enum State: String, Sendable, Equatable {
        case healthy
        case warning
        case critical
        /// Capacity could not be determined. Missing metadata and query
        /// failures share this state so alternating between those causes
        /// does not re-emit.
        case undetermined
    }

    public private(set) var state: State

    public init(state: State = .healthy) {
        self.state = state
    }

    /// Records a raw sample and returns the condition that must be emitted,
    /// or `nil` when the sample does not change the emitted condition.
    /// Deterioration emits immediately at the raw threshold; recovery
    /// requires the `policy` hysteresis margin.
    @discardableResult
    public mutating func record(
        sample: CaptureStorageSample,
        policy: CaptureResourceMonitorPolicy
    ) -> CaptureStorageCondition? {
        switch sample {
        case .measured(let available):
            return recordMeasured(available, policy: policy)
        case .capacityUnavailable:
            guard state != .undetermined else {
                return nil
            }
            state = .undetermined
            return .capacityUnavailable
        case .queryFailed(let domain, let code):
            guard state != .undetermined else {
                return nil
            }
            state = .undetermined
            return .sampleFailed(domain: domain, code: code)
        }
    }

    private mutating func recordMeasured(
        _ available: Int64,
        policy: CaptureResourceMonitorPolicy
    ) -> CaptureStorageCondition? {
        let next: State
        switch state {
        case .critical:
            if available
                < policy.storageCriticalBytes
                    + policy.storageHysteresisBytes
            {
                next = .critical
            } else if available
                < policy.storageWarningBytes
                    + policy.storageHysteresisBytes
            {
                next = .warning
            } else {
                next = .healthy
            }
        case .warning:
            if available < policy.storageCriticalBytes {
                next = .critical
            } else if available
                < policy.storageWarningBytes
                    + policy.storageHysteresisBytes
            {
                next = .warning
            } else {
                next = .healthy
            }
        case .healthy, .undetermined:
            if available < policy.storageCriticalBytes {
                next = .critical
            } else if available < policy.storageWarningBytes {
                next = .warning
            } else {
                next = .healthy
            }
        }

        guard next != state else {
            return nil
        }
        state = next
        switch next {
        case .critical:
            return .storageCritical(availableBytes: available)
        case .warning:
            return .storageWarning(availableBytes: available)
        case .healthy, .undetermined:
            // Recovery to a healthy reading is non-eventful; `undetermined`
            // is unreachable for measured samples.
            return nil
        }
    }
}

/// Drives periodic storage sampling while a monitor is started (legacy bolph71656-ai/HTDT-Capture#140). The
/// production driver is a low-frequency task-loop timer; tests inject a
/// manual driver so no test waits on real time.
@MainActor
public protocol CaptureStorageSampleDriver: AnyObject, Sendable {
    /// Starts producing ticks at `interval`; `tick` runs on the MainActor
    /// once per sampling period until `cancel()`.
    func start(
        interval: Duration,
        tick: @escaping @MainActor () -> Void
    )
    /// Stops producing ticks; idempotent.
    func cancel()
}

/// Default `CaptureStorageSampleDriver`: a task loop sleeping `interval`
/// between ticks until cancelled (legacy bolph71656-ai/HTDT-Capture#140).
@available(iOS 17.0, *)
@MainActor
public final class CaptureStorageSampleTimerDriver
    : CaptureStorageSampleDriver
{
    private let sleeper: @Sendable (Duration) async throws -> Void
    private var task: Task<Void, Never>?

    public init(
        sleeper: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.sleeper = sleeper
    }

    deinit {
        task?.cancel()
    }

    public func start(
        interval: Duration,
        tick: @escaping @MainActor () -> Void
    ) {
        cancel()
        let sleeper = self.sleeper
        task = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await sleeper(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                tick()
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Ordered emission record for `CaptureResourceMonitor.eventLog`: the
/// monitor-side chronology authority until `CaptureResourceEvent` carries
/// `occurred_at_utc`/`sequence` itself (legacy bolph71656-ai/HTDT-Capture#190).
public struct CaptureResourceMonitorLogEntry: Sendable, Equatable {
    /// Monotonic emission counter within the monitor instance; gives a
    /// deterministic total order even when wall-clock times tie.
    public let sequence: Int
    /// UTC wall-clock emission time from the monitor's injected clock.
    public let occurredAtUTC: Date
    public let event: CaptureResourceEvent
    /// Failure policy applied alongside the emission, if any.
    public let failure: CaptureFailureCode?

    public init(
        sequence: Int,
        occurredAtUTC: Date,
        event: CaptureResourceEvent,
        failure: CaptureFailureCode?
    ) {
        self.sequence = sequence
        self.occurredAtUTC = occurredAtUTC
        self.event = event
        self.failure = failure
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
    /// (legacy bolph71656-ai/HTDT-Capture#181).
    public typealias StorageCapacitySource = () throws -> Int64?
    /// UTC wall-clock source stamped on every emitted event (legacy bolph71656-ai/HTDT-Capture#190).
    public typealias UTCTimestampProvider = () -> Date
    /// Thermal-state source; injectable so tests do not depend on the host
    /// machine's real thermal pressure.
    public typealias ThermalStateProvider = () -> ProcessInfo.ThermalState

    private let rootDirectory: URL
    private let policy: CaptureResourceMonitorPolicy
    private let eventHandler: EventHandler
    private let capacitySource: StorageCapacitySource
    private let utcTimestampProvider: UTCTimestampProvider
    private let thermalStateProvider: ThermalStateProvider
    private let sampleDriver: any CaptureStorageSampleDriver
    private var isStarted = false
    private var storageTracker = CaptureStoragePressureTracker()
    private var periodicSamplesRemaining = 0
    private var emissionSequence = 0

    /// Ordered log of every event this monitor emitted, oldest first. Each
    /// entry carries the monotonic `sequence` and UTC `occurredAtUTC` that
    /// will populate `CaptureResourceEvent` once the canonical model gains
    /// `occurred_at_utc`/`sequence` fields (legacy bolph71656-ai/HTDT-Capture#190).
    public private(set) var eventLog: [CaptureResourceMonitorLogEntry] = []

    public init(
        rootDirectory: URL,
        policy: CaptureResourceMonitorPolicy = .init(),
        capacitySource: StorageCapacitySource? = nil,
        utcTimestampProvider: @escaping UTCTimestampProvider = { Date() },
        thermalStateProvider: @escaping ThermalStateProvider = {
            ProcessInfo.processInfo.thermalState
        },
        sampleDriver: (any CaptureStorageSampleDriver)? = nil,
        eventHandler: @escaping EventHandler
    ) {
        self.rootDirectory = rootDirectory
        self.policy = policy
        self.capacitySource = capacitySource
            ?? Self.makeVolumeCapacitySource(
                rootDirectory: rootDirectory
            )
        self.utcTimestampProvider = utcTimestampProvider
        self.thermalStateProvider = thermalStateProvider
        self.sampleDriver =
            sampleDriver ?? CaptureStorageSampleTimerDriver()
        self.eventHandler = eventHandler
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let driver = sampleDriver
        Task { @MainActor in driver.cancel() }
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
        startPeriodicStorageSampling()
    }

    public func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        NotificationCenter.default.removeObserver(self)
        // Cancel bounded periodic sampling; a later start() re-baselines the
        // transition tracker (legacy bolph71656-ai/HTDT-Capture#140).
        sampleDriver.cancel()
        periodicSamplesRemaining = 0
        storageTracker = CaptureStoragePressureTracker()
    }

    /// Unconditional storage assessment for explicit preflight checks such
    /// as finalization. `nil` means capacity was measured above the warning
    /// threshold; an unavailable or failed query returns an explicit typed
    /// assessment instead of silently passing (legacy bolph71656-ai/HTDT-Capture#181).
    public func currentStorageAssessment()
        -> CaptureResourceAssessment?
    {
        let sample = readStorageSample()
        guard let condition = storageCondition(for: sample) else {
            return nil
        }
        return assessment(for: condition)
    }

    /// Performs a bounded one-shot storage sample while started and emits an
    /// event only when the storage condition transitions (legacy bolph71656-ai/HTDT-Capture#140). For an
    /// unconditional preflight assessment use `currentStorageAssessment()`.
    public func sampleStorage() {
        guard isStarted else {
            return
        }
        emitStorageTransition(readStorageSample())
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
        emit(
            makeEvent(
                kind: .memoryPressure,
                severity: .warning,
                detail: "UIApplication memory warning received"
            ),
            failure: nil
        )
    }

    @objc
    private func applicationDidEnterBackground(
        _ notification: Notification
    ) {
        guard isStarted else {
            return
        }
        emit(
            makeEvent(
                kind: .interruption,
                severity: .error,
                detail:
                    "application entered background during active capture"
            ),
            failure: .interrupted
        )
    }

    private func emitCurrentThermalState() {
        guard isStarted else {
            return
        }

        switch thermalStateProvider() {
        case .nominal:
            break
        case .fair:
            emit(
                makeEvent(
                    kind: .thermalPressure,
                    severity: .warning,
                    detail: "thermal state fair"
                ),
                failure: nil
            )
        case .serious:
            emit(
                makeEvent(
                    kind: .thermalPressure,
                    severity: .warning,
                    detail: "thermal state serious"
                ),
                failure: nil
            )
        case .critical:
            emit(
                makeEvent(
                    kind: .thermalPressure,
                    severity: .error,
                    detail: "thermal state critical"
                ),
                failure: .thermalPressure
            )
        @unknown default:
            emit(
                makeEvent(
                    kind: .thermalPressure,
                    severity: .warning,
                    detail: "unknown thermal state"
                ),
                failure: nil
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
            // unlike `localizedDescription` (legacy bolph71656-ai/HTDT-Capture#183). The domain is bounded so
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
                event: makeEvent(
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
                event: makeEvent(
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
                event: makeEvent(
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
                event: makeEvent(
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

    private func emitStorageTransition(
        _ sample: CaptureStorageSample
    ) {
        guard let condition = storageTracker.record(
            sample: sample,
            policy: policy
        ) else {
            return
        }
        let assessment = assessment(for: condition)
        emit(assessment.event, failure: assessment.failure)
    }

    /// Low-frequency periodic sampling while started (legacy bolph71656-ai/HTDT-Capture#140). Bounded by
    /// `policy.maximumPeriodicStorageSamples` and cancelled by `stop()`;
    /// does not replace the explicit final preflight assessment.
    private func startPeriodicStorageSampling() {
        periodicSamplesRemaining = policy.maximumPeriodicStorageSamples
        guard periodicSamplesRemaining > 0 else {
            return
        }
        sampleDriver.start(
            interval: policy.storageSampleInterval
        ) { [weak self] in
            self?.performPeriodicStorageSample()
        }
    }

    private func performPeriodicStorageSample() {
        guard isStarted,
              periodicSamplesRemaining > 0
        else {
            return
        }
        periodicSamplesRemaining -= 1
        emitStorageTransition(readStorageSample())
        if periodicSamplesRemaining == 0 {
            // The sampling budget is exhausted; stop polling rather than
            // running an unbounded loop (legacy bolph71656-ai/HTDT-Capture#140).
            sampleDriver.cancel()
        }
    }

    // MARK: - Emission

    /// Single construction point for `CaptureResourceEvent`. Events are
    /// stamped with `occurred_at_utc`/`sequence` at emission time in
    /// `emit` so persisted events share `eventLog` chronology (legacy bolph71656-ai/HTDT-Capture#190).
    private func makeEvent(
        kind: CaptureResourceEventKind,
        severity: QualityDiagnosticSeverity,
        detail: String
    ) -> CaptureResourceEvent {
        CaptureResourceEvent(
            kind: kind,
            severity: severity,
            detail: detail
        )
    }

    /// Central emission path: stamps the event with the monotonic
    /// sequence number and injected UTC timestamp, appends the ordered
    /// `eventLog` entry, then invokes the host handler (legacy bolph71656-ai/HTDT-Capture#190). Stamping
    /// here — rather than in `makeEvent` — also covers events that were
    /// constructed before emission, such as storage assessments.
    private func emit(
        _ event: CaptureResourceEvent,
        failure: CaptureFailureCode?
    ) {
        let occurredAtUTC = utcTimestampProvider()
        let stamped = CaptureResourceEvent(
            kind: event.kind,
            severity: event.severity,
            detail: event.detail,
            occurredAtUtc: Self.utcFormatter.string(
                from: occurredAtUTC
            ),
            sequence: UInt64(emissionSequence)
        )
        eventLog.append(
            CaptureResourceMonitorLogEntry(
                sequence: emissionSequence,
                occurredAtUTC: occurredAtUTC,
                event: stamped,
                failure: failure
            )
        )
        emissionSequence += 1
        eventHandler(stamped, failure)
    }

    private static let utcFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter
    }()
}

