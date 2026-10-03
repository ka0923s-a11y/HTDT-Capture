import Foundation

/// Byte accounting for the live working revision, broken into the
/// categories the product actually spends storage on (issue bolph71656-ai/HTDT-Capture#308).
/// Computed by scanning the working-set root — the same authority the
/// manifest's `bytes` fields are built from — so the totals the
/// operator sees during capture equal the retained bytes of the
/// bundle that would be finalized.
public struct CaptureWorkingSetStorageProfile:
    Sendable,
    Equatable
{
    /// `evidence/frames/*` excluding `.preview.heic` — descriptor JSON
    /// plus `.pixelbin` pixel payloads.
    public let framePixelBytes: Int64
    /// `evidence/depth/*` — `.depthbin` and `.confidencebin` payloads.
    public let depthConfidenceBytes: Int64
    /// `mesh/**` — anchor index plus `.meshbin` geometry payloads.
    public let meshBytes: Int64
    /// `roomplan/**` — raw, processed, and metadata RoomPlan payloads.
    public let roomPlanBytes: Int64
    /// `.preview.heic` previews plus `derived/**` and `advisory/**`
    /// derived payloads.
    public let previewAndDerivedBytes: Int64
    /// Everything else in the working set — `session/`, `annotations/`,
    /// `quality/`, `verification/`, `reference/`, `revision/`,
    /// `evidence/` root JSON documents, and any unbound payload.
    public let documentBytes: Int64
    /// Sum of every category — the working revision's retained bytes.
    public let totalBytes: Int64

    public init(
        framePixelBytes: Int64 = 0,
        depthConfidenceBytes: Int64 = 0,
        meshBytes: Int64 = 0,
        roomPlanBytes: Int64 = 0,
        previewAndDerivedBytes: Int64 = 0,
        documentBytes: Int64 = 0
    ) {
        self.framePixelBytes = framePixelBytes
        self.depthConfidenceBytes = depthConfidenceBytes
        self.meshBytes = meshBytes
        self.roomPlanBytes = roomPlanBytes
        self.previewAndDerivedBytes = previewAndDerivedBytes
        self.documentBytes = documentBytes
        self.totalBytes = framePixelBytes + depthConfidenceBytes
            + meshBytes + roomPlanBytes + previewAndDerivedBytes
            + documentBytes
    }

    /// Categorizes a scanned bundle path into its byte bucket.
    static func accumulate(
        path: String,
        bytes: Int64,
        into profile: inout Accumulator
    ) {
        if path.hasPrefix("evidence/depth/") {
            profile.depthConfidenceBytes += bytes
        } else if path.hasPrefix("evidence/frames/") {
            if path.hasSuffix(".preview.heic") {
                profile.previewAndDerivedBytes += bytes
            } else {
                profile.framePixelBytes += bytes
            }
        } else if path.hasPrefix("mesh/") {
            profile.meshBytes += bytes
        } else if path.hasPrefix("roomplan/") {
            profile.roomPlanBytes += bytes
        } else if path.hasPrefix("derived/")
            || path.hasPrefix("advisory/")
        {
            profile.previewAndDerivedBytes += bytes
        } else {
            profile.documentBytes += bytes
        }
    }

    /// Scratch accumulator kept internal so the public initializer's
    /// field set stays the documented category list.
    struct Accumulator {
        var framePixelBytes: Int64 = 0
        var depthConfidenceBytes: Int64 = 0
        var meshBytes: Int64 = 0
        var roomPlanBytes: Int64 = 0
        var previewAndDerivedBytes: Int64 = 0
        var documentBytes: Int64 = 0
    }
}

/// Device free-storage band as presented to the operator (issue bolph71656-ai/HTDT-Capture#308).
/// Mirrors the platform monitor's warning/critical thresholds; an
/// `unknown` band means the capacity query could not produce a
/// measured value and the UI says so instead of guessing.
public enum CaptureStoragePressureBand: String, Sendable, Equatable {
    case nominal
    case warning
    case critical
    case unknown
}

/// Usage of the bounded automatic evidence-frame selector (legacy bolph71656-ai/HTDT-Capture#216) as
/// the operator needs it for legacy bolph71656-ai/HTDT-Capture#308: frames and estimated bytes retained
/// against the published budget, plus what remains.
public struct AutomaticKeyframeBudgetStatus:
    Sendable,
    Equatable
{
    public let retainedFrameCount: Int
    public let maximumRetainedFrames: Int
    public let retainedEstimatedBytes: Int
    public let maximumRetainedBytes: Int
    public let policyVersion: String

    public init(
        tracker: AutomaticKeyframeTracker
    ) {
        let configuration = tracker.configuration
        self.retainedFrameCount = tracker.retainedCount
        self.maximumRetainedFrames =
            configuration.maximumRetainedFrames
        self.retainedEstimatedBytes = tracker.retainedByteEstimate
        self.maximumRetainedBytes = configuration.maximumRetainedBytes
        self.policyVersion = configuration.policyVersion
    }

    public init(
        retainedFrameCount: Int,
        maximumRetainedFrames: Int,
        retainedEstimatedBytes: Int,
        maximumRetainedBytes: Int,
        policyVersion: String
    ) {
        self.retainedFrameCount = retainedFrameCount
        self.maximumRetainedFrames = maximumRetainedFrames
        self.retainedEstimatedBytes = retainedEstimatedBytes
        self.maximumRetainedBytes = maximumRetainedBytes
        self.policyVersion = policyVersion
    }

    public var remainingFrames: Int {
        max(0, maximumRetainedFrames - retainedFrameCount)
    }

    public var remainingBytes: Int {
        max(0, maximumRetainedBytes - retainedEstimatedBytes)
    }
}

/// The complete storage advisory the capture HUD surfaces (issue
/// legacy bolph71656-ai/HTDT-Capture#308): retained evidence bytes by category, evidence counts,
/// measured device free space with the warning/critical margin, and
/// the automatic-keyframe budget usage. Advisory only — none of these
/// values feed `ready_for_htdt_ingestion`; the platform monitor's
/// threshold events remain the gate-adjacent resource diagnostics.
public struct CaptureEvidenceStorageAdvisory:
    Sendable,
    Equatable
{
    public let profile: CaptureWorkingSetStorageProfile
    public let evidenceFrameCount: Int
    public let depthEvidenceCount: Int
    /// Measured device capacity for important usage, when the platform
    /// could report it; nil for unavailable/failed queries.
    public let deviceAvailableBytes: Int64?
    public let pressureBand: CaptureStoragePressureBand
    public let storageWarningBytes: Int64
    public let storageCriticalBytes: Int64
    public let keyframeBudget: AutomaticKeyframeBudgetStatus?

    public init(
        profile: CaptureWorkingSetStorageProfile,
        evidenceFrameCount: Int,
        depthEvidenceCount: Int,
        deviceAvailableBytes: Int64?,
        pressureBand: CaptureStoragePressureBand,
        storageWarningBytes: Int64,
        storageCriticalBytes: Int64,
        keyframeBudget: AutomaticKeyframeBudgetStatus? = nil
    ) {
        self.profile = profile
        self.evidenceFrameCount = evidenceFrameCount
        self.depthEvidenceCount = depthEvidenceCount
        self.deviceAvailableBytes = deviceAvailableBytes
        self.pressureBand = pressureBand
        self.storageWarningBytes = storageWarningBytes
        self.storageCriticalBytes = storageCriticalBytes
        self.keyframeBudget = keyframeBudget
    }

    /// Bytes of headroom before the warning threshold; nil when the
    /// device capacity is unmeasured. Negative values mean the working
    /// revision already overshot the threshold.
    public var marginToWarningBytes: Int64? {
        deviceAvailableBytes.map { $0 - storageWarningBytes }
    }

    public var marginToCriticalBytes: Int64? {
        deviceAvailableBytes.map { $0 - storageCriticalBytes }
    }
}
