import Foundation

/// Snapshot of AR frame-interval health for one capture (legacy bolph71656-ai/HTDT-Capture#273
/// instrumentation). The distribution lives in the tracker's bounded
/// window; the summary carries the numbers a physical-benchmark run
/// needs without holding per-frame data.
public struct ARFrameCadenceSummary: Equatable, Sendable {
    /// Frames observed since the last reset.
    public private(set) var frameCount = 0
    /// Intervals retained in the bounded recent window.
    public private(set) var windowCount = 0
    /// Longest interval ever observed (seconds).
    public private(set) var maximumIntervalSeconds = 0.0
    /// Mean interval over the recent window (seconds).
    public private(set) var windowMeanIntervalSeconds = 0.0
    /// Window intervals longer than `nominal * stretchFactor`.
    public private(set) var windowStretchedCount = 0
    /// All intervals ever observed longer than `nominal * stretchFactor`.
    public private(set) var totalStretchedCount = 0
    /// `windowStretchedCount / windowCount` — the stretched-frame
    /// incidence a benchmark run compares across workload profiles.
    public private(set) var windowStretchedFraction = 0.0

    init(
        frameCount: Int = 0,
        windowCount: Int = 0,
        maximumIntervalSeconds: Double = 0,
        windowMeanIntervalSeconds: Double = 0,
        windowStretchedCount: Int = 0,
        totalStretchedCount: Int = 0,
        windowStretchedFraction: Double = 0
    ) {
        self.frameCount = frameCount
        self.windowCount = windowCount
        self.maximumIntervalSeconds = maximumIntervalSeconds
        self.windowMeanIntervalSeconds = windowMeanIntervalSeconds
        self.windowStretchedCount = windowStretchedCount
        self.totalStretchedCount = totalStretchedCount
        self.windowStretchedFraction = windowStretchedFraction
    }
}

/// Bounded AR frame-cadence measurement (legacy bolph71656-ai/HTDT-Capture#273 "AR frame interval
/// distribution"). Fed frame timestamps from the session lifecycle
/// bridge's `didUpdate` passthrough; admits nothing — it exists so the
/// physical benchmark can see whether optional work degrades the
/// authoritative capture's cadence.
public struct ARFrameCadenceTracker {
    /// Nominal per-frame interval for the active video profile —
    /// ARKit video formats run at 60 Hz unless the profile says
    /// otherwise; a different profile re-instantiates with its value.
    public var nominalIntervalSeconds: Double = 1.0 / 60.0
    /// An interval counts as "stretched" past `nominal * factor`.
    public var stretchFactor: Double = 1.5
    /// Bounded recent-interval window (`OptionalWorkAdmissionTracker`
    /// follows the same bounded-log convention).
    public var windowLimit = 240

    private var lastTimestampSeconds: Double?
    private var window: [Double] = []
    private var windowTotalSeconds = 0.0
    private var windowStretched = 0
    private var observedFrames = 0
    private var stretched = 0
    private var maximumInterval = 0.0

    public init() {}

    /// Feeds one frame timestamp (seconds on the ARSession clock).
    /// The first frame after a reset establishes the baseline and
    /// produces no interval.
    public mutating func record(timestampSeconds: Double) {
        observedFrames += 1
        defer { lastTimestampSeconds = timestampSeconds }
        guard let previous = lastTimestampSeconds else { return }
        let interval = timestampSeconds - previous
        guard interval > 0 else { return }

        maximumInterval = max(maximumInterval, interval)
        let isStretched = interval > nominalIntervalSeconds * stretchFactor
        if isStretched { stretched += 1 }

        window.append(interval)
        windowTotalSeconds += interval
        if isStretched { windowStretched += 1 }
        if window.count > windowLimit {
            let dropped = window.removeFirst()
            windowTotalSeconds -= dropped
            if dropped > nominalIntervalSeconds * stretchFactor {
                windowStretched -= 1
            }
        }
    }

    /// Clears every observation — called when a new capture generation
    /// starts so the distribution describes one capture only.
    public mutating func reset() {
        lastTimestampSeconds = nil
        window.removeAll(keepingCapacity: false)
        windowTotalSeconds = 0
        windowStretched = 0
        observedFrames = 0
        stretched = 0
        maximumInterval = 0
    }

    public func summary() -> ARFrameCadenceSummary {
        ARFrameCadenceSummary(
            frameCount: observedFrames,
            windowCount: window.count,
            maximumIntervalSeconds: maximumInterval,
            windowMeanIntervalSeconds: window.isEmpty
                ? 0
                : windowTotalSeconds / Double(window.count),
            windowStretchedCount: windowStretched,
            totalStretchedCount: stretched,
            windowStretchedFraction: window.isEmpty
                ? 0
                : Double(windowStretched) / Double(window.count)
        )
    }
}
