import Foundation
import HTDTCaptureCore
import Testing
@testable import HTDTCapturePlatform

private let warningThresholdBytes: Int64 = 2 * 1024 * 1024 * 1024
private let criticalThresholdBytes: Int64 = 512 * 1024 * 1024
private let healthyBytes: Int64 = 4 * 1024 * 1024 * 1024
private let hysteresisBytes: Int64 = 64 * 1024 * 1024

/// Deterministic `CaptureStorageSampleDriver`: ticks only when the test
/// calls `fireTick()`, so no test waits on real time (#140).
@MainActor
private final class ManualStorageSampleDriver: CaptureStorageSampleDriver {
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private(set) var intervals: [Duration] = []
    private var tickHandler: (@MainActor () -> Void)?

    func start(
        interval: Duration,
        tick: @escaping @MainActor () -> Void
    ) {
        startCount += 1
        intervals.append(interval)
        tickHandler = tick
    }

    func cancel() {
        cancelCount += 1
        tickHandler = nil
    }

    func fireTick() {
        tickHandler?()
    }
}

@MainActor
private final class ResourceEventRecorder {
    private(set) var events: [CaptureResourceEvent] = []
    private(set) var failures: [CaptureFailureCode?] = []

    var handler: CaptureResourceMonitor.EventHandler {
        { event, failure in
            self.events.append(event)
            self.failures.append(failure)
        }
    }
}

// MARK: - Typed storage assessment (#181)

@Test
@MainActor
func healthyCapacityProducesNoAssessment() {
    let recorder = ResourceEventRecorder()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { healthyBytes },
        thermalStateProvider: { .nominal },
        sampleDriver: ManualStorageSampleDriver(),
        eventHandler: recorder.handler
    )

    #expect(monitor.currentStorageAssessment() == nil)

    monitor.start()
    #expect(recorder.events.isEmpty)
}

@Test
@MainActor
func unavailableCapacityProducesTypedWarningAssessment() throws {
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { nil },
        thermalStateProvider: { .nominal },
        sampleDriver: ManualStorageSampleDriver(),
        eventHandler: { _, _ in }
    )

    // "Could not determine" is an explicit typed result, not silently
    // treated as sufficient capacity (#181).
    let assessment = try #require(monitor.currentStorageAssessment())
    #expect(assessment.condition == .capacityUnavailable)
    #expect(assessment.failure == nil)
    #expect(assessment.event.kind == .storagePressure)
    #expect(assessment.event.severity == .warning)
    #expect(
        assessment.event.detail
            == CaptureResourceMonitorDetailToken.storageCapacityUnavailable
    )
    #expect(assessment.event.detail == "storage_capacity_unavailable")
}

@Test
@MainActor
func warningAndCriticalThresholdsAreUnchanged() {
    var capacity: Int64 = warningThresholdBytes - 1
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { capacity },
        thermalStateProvider: { .nominal },
        sampleDriver: ManualStorageSampleDriver(),
        eventHandler: { _, _ in }
    )

    #expect(
        monitor.currentStorageAssessment()?.condition
            == .storageWarning(
                availableBytes: warningThresholdBytes - 1
            )
    )
    #expect(
        monitor.currentStorageAssessment()?.event.severity == .warning
    )
    #expect(monitor.currentStorageAssessment()?.failure == nil)

    capacity = criticalThresholdBytes - 1
    #expect(
        monitor.currentStorageAssessment()?.condition
            == .storageCritical(
                availableBytes: criticalThresholdBytes - 1
            )
    )
    #expect(
        monitor.currentStorageAssessment()?.event.severity == .error
    )
    #expect(
        monitor.currentStorageAssessment()?.failure == .storagePressure
    )
}

// MARK: - Stable machine diagnostics (#183)

@Test
@MainActor
func queryFailureUsesStableMachineTokenNotLocalizedText() throws {
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: {
            throw NSError(domain: "HTDTTestDomain", code: 42)
        },
        thermalStateProvider: { .nominal },
        sampleDriver: ManualStorageSampleDriver(),
        eventHandler: { _, _ in }
    )

    let assessment = try #require(monitor.currentStorageAssessment())
    #expect(
        assessment.condition
            == .sampleFailed(domain: "HTDTTestDomain", code: 42)
    )
    #expect(assessment.event.severity == .warning)
    #expect(assessment.failure == nil)
    // Canonical detail carries only stable tokens + NSError domain/code,
    // never `localizedDescription` (#183).
    #expect(
        assessment.event.detail
            == "storage_sample_failed domain=HTDTTestDomain code=42"
    )
}

// MARK: - Transition tracker hysteresis (#140)

@Test
func storageTrackerEmitsOnlyOnTransitionsWithHysteresis() {
    var tracker = CaptureStoragePressureTracker()
    let policy = CaptureResourceMonitorPolicy(
        storageWarningBytes: 1_000,
        storageCriticalBytes: 100,
        storageHysteresisBytes: 50,
        maximumPeriodicStorageSamples: 0
    )

    #expect(
        tracker.record(
            sample: .measured(availableBytes: 2_000),
            policy: policy
        ) == nil
    )
    // Crossing the warning boundary emits immediately.
    #expect(
        tracker.record(
            sample: .measured(availableBytes: 900),
            policy: policy
        ) == .storageWarning(availableBytes: 900)
    )
    // Same band: suppressed.
    #expect(
        tracker.record(
            sample: .measured(availableBytes: 950),
            policy: policy
        ) == nil
    )
    // Above the raw threshold but inside the hysteresis margin: suppressed.
    #expect(
        tracker.record(
            sample: .measured(availableBytes: 1_049),
            policy: policy
        ) == nil
    )
    // Past the margin: recovers to healthy, non-eventful.
    #expect(
        tracker.record(
            sample: .measured(availableBytes: 1_050),
            policy: policy
        ) == nil
    )
    #expect(tracker.state == .healthy)
    // A new deterioration after recovery re-alerts.
    #expect(
        tracker.record(
            sample: .measured(availableBytes: 900),
            policy: policy
        ) == .storageWarning(availableBytes: 900)
    )
}

@Test
func storageTrackerCriticalRecoveryUsesHysteresisMargin() {
    var tracker = CaptureStoragePressureTracker()
    let policy = CaptureResourceMonitorPolicy(
        storageWarningBytes: 1_000,
        storageCriticalBytes: 100,
        storageHysteresisBytes: 50,
        maximumPeriodicStorageSamples: 0
    )

    #expect(
        tracker.record(
            sample: .measured(availableBytes: 50),
            policy: policy
        ) == .storageCritical(availableBytes: 50)
    )
    // Within the critical recovery margin: stays critical, no re-emit.
    #expect(
        tracker.record(
            sample: .measured(availableBytes: 149),
            policy: policy
        ) == nil
    )
    // Exiting the critical band lands on warning and emits that transition.
    #expect(
        tracker.record(
            sample: .measured(availableBytes: 150),
            policy: policy
        ) == .storageWarning(availableBytes: 150)
    )
}

@Test
func storageTrackerSuppressesUndeterminedChurn() {
    var tracker = CaptureStoragePressureTracker()
    let policy = CaptureResourceMonitorPolicy(
        storageWarningBytes: 1_000,
        storageCriticalBytes: 100,
        maximumPeriodicStorageSamples: 0
    )

    #expect(
        tracker.record(sample: .capacityUnavailable, policy: policy)
            == .capacityUnavailable
    )
    #expect(
        tracker.record(sample: .capacityUnavailable, policy: policy)
            == nil
    )
    // A failed query while already undetermined does not re-emit.
    #expect(
        tracker.record(
            sample: .queryFailed(domain: "D", code: 1),
            policy: policy
        ) == nil
    )
    // Measured deterioration out of undetermined emits again.
    #expect(
        tracker.record(
            sample: .measured(availableBytes: 90),
            policy: policy
        ) == .storageCritical(availableBytes: 90)
    )
}

// MARK: - Periodic sampling while started (#140)

@Test
@MainActor
func periodicSamplingEmitsOnTransitionsAndAppliesCriticalPolicy() {
    var capacity: Int64 = healthyBytes
    let driver = ManualStorageSampleDriver()
    let recorder = ResourceEventRecorder()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { capacity },
        thermalStateProvider: { .nominal },
        sampleDriver: driver,
        eventHandler: recorder.handler
    )

    monitor.start()
    // Healthy baseline stays silent; periodic sampling armed once.
    #expect(recorder.events.isEmpty)
    #expect(driver.startCount == 1)
    #expect(driver.intervals == [.seconds(5)])

    capacity = warningThresholdBytes - 1
    driver.fireTick()
    #expect(recorder.events.map(\.severity) == [.warning])
    #expect(recorder.failures == [nil])

    // Same band on the next tick: no duplicate event.
    capacity = warningThresholdBytes - 2
    driver.fireTick()
    #expect(recorder.events.count == 1)

    // Critical transition applies the existing storage failure policy
    // promptly, while still scanning.
    capacity = criticalThresholdBytes - 1
    driver.fireTick()
    #expect(
        recorder.events.map(\.kind)
            == [.storagePressure, .storagePressure]
    )
    #expect(recorder.events.map(\.severity) == [.warning, .error])
    #expect(recorder.failures == [nil, .storagePressure])

    // Recovery past the thresholds emits nothing.
    capacity = healthyBytes
    driver.fireTick()
    #expect(recorder.events.count == 2)

    monitor.stop()
}

@Test
@MainActor
func periodicSamplingHysteresisSuppressesOscillation() {
    var capacity: Int64 = warningThresholdBytes - 1
    let driver = ManualStorageSampleDriver()
    let recorder = ResourceEventRecorder()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { capacity },
        thermalStateProvider: { .nominal },
        sampleDriver: driver,
        eventHandler: recorder.handler
    )

    monitor.start()
    #expect(recorder.events.count == 1)

    // Oscillate around the warning boundary inside the hysteresis margin:
    // no warning/clear spam.
    capacity = warningThresholdBytes + 1
    driver.fireTick()
    capacity = warningThresholdBytes - 1
    driver.fireTick()
    capacity = warningThresholdBytes + 1
    driver.fireTick()
    #expect(recorder.events.count == 1)

    // Clear recovery past the margin, then a real re-drop re-alerts.
    capacity = warningThresholdBytes + hysteresisBytes
    driver.fireTick()
    #expect(recorder.events.count == 1)
    capacity = warningThresholdBytes - 1
    driver.fireTick()
    #expect(recorder.events.count == 2)

    monitor.stop()
}

@Test
@MainActor
func stopCancelsPeriodicSamplingAndSuppressesEmission() {
    var capacity: Int64 = healthyBytes
    let driver = ManualStorageSampleDriver()
    let recorder = ResourceEventRecorder()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { capacity },
        thermalStateProvider: { .nominal },
        sampleDriver: driver,
        eventHandler: recorder.handler
    )

    monitor.start()
    monitor.stop()
    #expect(driver.cancelCount == 1)

    capacity = criticalThresholdBytes - 1
    driver.fireTick()  // cancelled: driver cleared the tick handler
    monitor.sampleStorage()  // guard !isStarted: no emission
    #expect(recorder.events.isEmpty)
    #expect(monitor.eventLog.isEmpty)
}

@Test
@MainActor
func periodicSamplingIsBoundedByPolicy() {
    var capacity: Int64 = healthyBytes
    var capacityCalls = 0
    let driver = ManualStorageSampleDriver()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        policy: CaptureResourceMonitorPolicy(
            maximumPeriodicStorageSamples: 2
        ),
        capacitySource: {
            capacityCalls += 1
            return capacity
        },
        thermalStateProvider: { .nominal },
        sampleDriver: driver,
        eventHandler: { _, _ in }
    )

    monitor.start()
    // Baseline sample at start() is not a periodic tick.
    #expect(capacityCalls == 1)

    driver.fireTick()
    driver.fireTick()
    // Two periodic samples consumed the budget; the driver is cancelled so
    // the loop cannot run unbounded.
    #expect(capacityCalls == 3)
    #expect(driver.cancelCount == 1)

    driver.fireTick()
    #expect(capacityCalls == 3)
    monitor.stop()
}

@Test
@MainActor
func zeroPeriodicSampleBudgetDoesNotStartDriver() {
    let driver = ManualStorageSampleDriver()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        policy: CaptureResourceMonitorPolicy(
            maximumPeriodicStorageSamples: 0
        ),
        capacitySource: { healthyBytes },
        thermalStateProvider: { .nominal },
        sampleDriver: driver,
        eventHandler: { _, _ in }
    )

    monitor.start()
    #expect(driver.startCount == 0)
    monitor.stop()
}

@Test
@MainActor
func unavailableMetadataDuringScanEmitsTypedWarningOnce() {
    var capacity: Int64? = healthyBytes
    let driver = ManualStorageSampleDriver()
    let recorder = ResourceEventRecorder()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { capacity },
        thermalStateProvider: { .nominal },
        sampleDriver: driver,
        eventHandler: recorder.handler
    )

    monitor.start()
    #expect(recorder.events.isEmpty)

    // Capacity metadata becomes unavailable mid-scan: one typed warning.
    capacity = nil
    driver.fireTick()
    #expect(recorder.events.count == 1)
    #expect(
        recorder.events[0].detail == "storage_capacity_unavailable"
    )
    #expect(recorder.events[0].severity == .warning)
    #expect(recorder.failures[0] == nil)

    // Still unavailable: suppressed by the transition tracker.
    driver.fireTick()
    #expect(recorder.events.count == 1)

    // Measured again below the warning threshold: new transition emits.
    capacity = warningThresholdBytes - 1
    driver.fireTick()
    #expect(recorder.events.count == 2)
    #expect(recorder.events[1].severity == .warning)

    monitor.stop()
}

// MARK: - Final preflight + emission chronology (#140, #190)

@Test
@MainActor
func preflightAssessmentStillWorksAfterStop() throws {
    var capacity: Int64 = healthyBytes
    let recorder = ResourceEventRecorder()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { capacity },
        thermalStateProvider: { .nominal },
        sampleDriver: ManualStorageSampleDriver(),
        eventHandler: recorder.handler
    )

    monitor.start()
    monitor.stop()

    // The explicit final preflight sample is preserved: it works while the
    // monitor is stopped and does not emit through the event handler.
    capacity = criticalThresholdBytes - 1
    let assessment = try #require(monitor.currentStorageAssessment())
    #expect(
        assessment.condition
            == .storageCritical(
                availableBytes: criticalThresholdBytes - 1
            )
    )
    #expect(assessment.failure == .storagePressure)
    #expect(recorder.events.isEmpty)
}

@Test
@MainActor
func stoppedAssessmentReflectsRecoveryForRetry() throws {
    var capacity: Int64 = healthyBytes
    let recorder = ResourceEventRecorder()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { capacity },
        thermalStateProvider: { .nominal },
        sampleDriver: ManualStorageSampleDriver(),
        eventHandler: recorder.handler
    )

    monitor.start()
    monitor.stop()

    // The deferred finalization retry re-assesses the stopped monitor
    // synchronously; a recovered capacity must clear the earlier critical
    // result instead of leaving the retry permanently deferred.
    capacity = criticalThresholdBytes - 1
    #expect(
        try #require(monitor.currentStorageAssessment()).failure
            == .storagePressure
    )

    capacity = healthyBytes
    #expect(monitor.currentStorageAssessment() == nil)
    #expect(recorder.events.isEmpty)
}

@Test
@MainActor
func sampleStorageIsIgnoredUntilStarted() {
    let recorder = ResourceEventRecorder()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { criticalThresholdBytes - 1 },
        thermalStateProvider: { .nominal },
        sampleDriver: ManualStorageSampleDriver(),
        eventHandler: recorder.handler
    )

    monitor.sampleStorage()
    #expect(recorder.events.isEmpty)
    #expect(monitor.eventLog.isEmpty)
}

@Test
@MainActor
func eventLogRecordsMonotonicSequenceAndUTCTimestamps() {
    var capacity: Int64 = warningThresholdBytes - 1
    var tickIndex = 0
    let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    let driver = ManualStorageSampleDriver()
    let recorder = ResourceEventRecorder()
    let monitor = CaptureResourceMonitor(
        rootDirectory: URL(fileURLWithPath: "/tmp"),
        capacitySource: { capacity },
        utcTimestampProvider: {
            defer { tickIndex += 1 }
            return epoch.addingTimeInterval(TimeInterval(tickIndex))
        },
        thermalStateProvider: { .nominal },
        sampleDriver: driver,
        eventHandler: recorder.handler
    )

    monitor.start()  // baseline warning: sequence 0 at epoch
    capacity = criticalThresholdBytes - 1
    driver.fireTick()  // critical: sequence 1 at epoch + 1

    #expect(recorder.events.count == 2)
    #expect(monitor.eventLog.map(\.sequence) == [0, 1])
    #expect(monitor.eventLog[0].occurredAtUTC == epoch)
    #expect(
        monitor.eventLog[1].occurredAtUTC
            == epoch.addingTimeInterval(1)
    )
    #expect(monitor.eventLog[0].event == recorder.events[0])
    #expect(monitor.eventLog[1].event == recorder.events[1])
    #expect(monitor.eventLog[1].failure == .storagePressure)
    #expect(monitor.eventLog[1].event.severity == .error)

    monitor.stop()
}
