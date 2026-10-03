import Foundation
import HTDTCaptureCore

/// UTC wall-clock rendering for non-manifest timestamps that must keep
/// sub-second precision.
///
/// Manifest canonicalization intentionally remains at whole-second
/// resolution via `BundleTimestamp.utcString`; do not change that
/// contract. Timing correlations and similar non-manifest UTC values use
/// this fractional RFC 3339 / ISO-8601 form instead, so the emitted text
/// can support the declared `estimated_uncertainty_s`.
public enum PlatformTimestamp {
    /// Upper bound of the serialization error introduced by rounding the
    /// wall-clock midpoint to the millisecond precision emitted by
    /// `fractionalUtcString(from:)`. Callers declaring a timing
    /// uncertainty must never report less than this quantization error.
    public static let fractionalUtcQuantizationSeconds = 0.000_5

    /// Emit `date` as an RFC 3339 / ISO-8601 UTC string carrying
    /// fractional (millisecond) precision, e.g. `2026-09-20T01:00:00.123Z`.
    public static func fractionalUtcString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

#if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
import ARKit
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import RoomPlan
import simd

public enum PlatformCaptureError: Error {
    case roomPlanUnsupported
    case currentFrameUnavailable
    case raycastMiss
    case orientationUnavailable
    case configurationUnavailable
    /// The running AR configuration resolved to a different capture
    /// mode than the session requires — persisted documents must never
    /// claim the requested mode the hardware is not actually running.
    case requestedCaptureModeUnsatisfied(
        resolved: CaptureMode
    )
}

public struct CapturedSpeakerOrientation: Sendable {
    public let frontAxisWorld: SpatialVector3F
    public let frameArtifacts: CapturedFrameSnapshot

    public init(
        frontAxisWorld: SpatialVector3F,
        frameArtifacts: CapturedFrameSnapshot
    ) {
        self.frontAxisWorld = frontAxisWorld
        self.frameArtifacts = frameArtifacts
    }
}

/// Whole-orientation camera authority in world space (issue #271).
/// Unlike `CapturedSpeakerOrientation`, which flattens the heading to
/// the X/Z plane for the speaker-yaw convention, this preserves the
/// full 3D forward+up axes for measurement-point (microphone capsule)
/// direction authority.
public struct CapturedPointOrientation: Sendable {
    public let frontAxisWorld: SpatialVector3F
    public let upAxisWorld: SpatialVector3F
    public let frameArtifacts: CapturedFrameSnapshot

    public init(
        frontAxisWorld: SpatialVector3F,
        upAxisWorld: SpatialVector3F,
        frameArtifacts: CapturedFrameSnapshot
    ) {
        self.frontAxisWorld = frontAxisWorld
        self.upAxisWorld = upAxisWorld
        self.frameArtifacts = frameArtifacts
    }
}

/// Bounded provenance of a live raycast hit used for annotation
/// placement. Two placements with materially different authority (hit on
/// observed existing plane geometry vs. an estimated plane fallback)
/// remain distinguishable after serialization.
public struct RaycastPlacementProvenance: Sendable, Equatable {
    /// The raycast target kind that produced the accepted hit.
    public enum Target: String, Sendable, Equatable {
        case existingPlaneGeometry = "existing_plane_geometry"
        case existingPlaneInfinite = "existing_plane_infinite"
        case estimatedPlane = "estimated_plane"
        case featurePoint = "feature_point"
        case unknown
    }

    /// The alignment requested by the accepted raycast query.
    public enum Alignment: String, Sendable, Equatable {
        case any
        case horizontal
        case vertical
        case unknown
    }

    /// Which raycast target produced the hit.
    public let target: Target
    /// Alignment policy of the accepted query.
    public let targetAlignment: Alignment
    /// Distance from the ray origin (camera position) to the hit, meters.
    public let hitDistanceMeters: Double
    /// Full hit transform in the capture world coordinate space.
    public let hitWorldTransform: Matrix4x4F
    /// Identifier of the anchor backing the hit, when ARKit provided one;
    /// explicitly nil otherwise, never fabricated.
    public let hitAnchorIdentifier: UUID?
    /// Type name of the backing anchor (e.g. "ARPlaneAnchor"), if any.
    public let hitAnchorType: String?

    public init(
        target: Target,
        targetAlignment: Alignment,
        hitDistanceMeters: Double,
        hitWorldTransform: Matrix4x4F,
        hitAnchorIdentifier: UUID? = nil,
        hitAnchorType: String? = nil
    ) {
        self.target = target
        self.targetAlignment = targetAlignment
        self.hitDistanceMeters = hitDistanceMeters
        self.hitWorldTransform = hitWorldTransform
        self.hitAnchorIdentifier = hitAnchorIdentifier
        self.hitAnchorType = hitAnchorType
    }
}

public struct CapturedRaycastPlacement: Sendable {
    public let positionWorld: Float3
    public let frameArtifacts: CapturedFrameSnapshot
    /// Provenance of the raycast hit that produced `positionWorld`.
    /// Always populated when produced by
    /// `snapshotCenterRaycastPlacement`; optional only so existing
    /// manual constructions remain source-compatible.
    public let raycastProvenance: RaycastPlacementProvenance?

    public init(
        positionWorld: Float3,
        frameArtifacts: CapturedFrameSnapshot,
        raycastProvenance: RaycastPlacementProvenance? = nil
    ) {
        self.positionWorld = positionWorld
        self.frameArtifacts = frameArtifacts
        self.raycastProvenance = raycastProvenance
    }
}

public struct CaptureReviewEvidenceSnapshot: Sendable {
    public let meshAnchors: [MeshAnchorSnapshot]
    public let meshSnapshotSucceeded: Bool
    public let frameArtifacts: CapturedFrameSnapshot
    public let trackingQualityEvent: TrackingQualityEvent

    public init(
        meshAnchors: [MeshAnchorSnapshot],
        meshSnapshotSucceeded: Bool = true,
        frameArtifacts: CapturedFrameSnapshot,
        trackingQualityEvent: TrackingQualityEvent
    ) {
        self.meshAnchors = meshAnchors
        self.meshSnapshotSucceeded = meshSnapshotSucceeded
        self.frameArtifacts = frameArtifacts
        self.trackingQualityEvent = trackingQualityEvent
    }
}

public struct DerivedShapeLiveObservationSet: Sendable {
    public let objectObservation: DerivedShapeObservation?
    public let objectVolumeObservation: DerivedShapeObservation?
    public let wallObservation: DerivedShapeObservation?
    public let floorReferenceY: Double?

    public init(
        objectObservation: DerivedShapeObservation?,
        objectVolumeObservation: DerivedShapeObservation? = nil,
        wallObservation: DerivedShapeObservation?,
        floorReferenceY: Double? = nil
    ) {
        self.objectObservation = objectObservation
        self.objectVolumeObservation = objectVolumeObservation
        self.wallObservation = wallObservation
        self.floorReferenceY = floorReferenceY
    }

    public static let empty = DerivedShapeLiveObservationSet(
        objectObservation: nil,
        objectVolumeObservation: nil,
        wallObservation: nil,
        floorReferenceY: nil
    )
}

/// Lifecycle events forwarded from the authoritative `ARSession`.
///
/// The host installs `sessionLifecycleHandler` and binds each event to
/// the capture generation/session authority it belongs to; stale
/// callbacks from prior generations are filtered by the host.
public enum ARSessionLifecycleEvent: Sendable, Equatable {
    /// ARKit began interrupting the session (phone call, app switch,
    /// system pressure). The session may lose its current frame and
    /// world tracking authority until `interruptionEnded`.
    case wasInterrupted
    /// A previously interrupted session resumed.
    case interruptionEnded
    /// The session failed terminally. `reason` is a stable
    /// `domain#code` diagnostic token, not localized UI text.
    case failed(reason: String)
    /// Camera tracking state transitioned. Carries the same state/reason
    /// mapping as `snapshotTrackingQualityEvent()` so relocalization and
    /// other authority-affecting transitions follow the coordinate-space
    /// discontinuity policy.
    case cameraTrackingStateChanged(TrackingQualityEvent)
    /// The session produced collaboration data for a peer session. This
    /// app does not run collaborative sessions; the event is forwarded so
    /// the host can register unexpected output.
    case didOutputCollaborationData(priorityIsCritical: Bool)
}

/// What `configureReferenceObjects` actually achieved on the live
/// session (#268) — the recorded outcome distinguishes applied sets,
/// an unsupported tracking request, a refused configuration, and a
/// post-run read-back mismatch, so provenance never overstates what
/// ARKit adopted.
public struct ReferenceObjectReconfigurationResult:
    Sendable, Equatable
{
    public enum Status: String, Sendable, Equatable {
        /// Requested sets verified on the running configuration.
        case configured
        /// The live configuration is not a world-tracking
        /// configuration — reference objects were not applied.
        case incompatibleConfiguration
        /// Tracking objects were requested but this OS/SDK cannot
        /// adopt them (`trackingObjects` is iOS 27+). Nothing was
        /// applied or silently demoted to detection.
        case trackingUnsupported
        /// `run` was issued but the live configuration's object sets
        /// differ from what was requested.
        case verificationMismatch
    }

    public let status: Status
    /// Machine-readable detail (`key=value`, space separated) —
    /// requested vs adopted object names for provenance.
    public let detail: String
    /// Whether `ARSession.run` was re-issued. When true the session
    /// restarted its configuration — the caller treats anchor and
    /// coordinate continuity accordingly.
    public let sessionRestarted: Bool

    public init(
        status: Status,
        detail: String,
        sessionRestarted: Bool
    ) {
        self.status = status
        self.detail = detail
        self.sessionRestarted = sessionRestarted
    }
}

@MainActor
private final class ARSessionLifecycleBridge:
    NSObject,
    @preconcurrency ARSessionDelegate
{
    /// Previously installed session delegate. ARKit exposes exactly one
    /// `ARSession.delegate`; every callback is forwarded so installing
    /// this bridge never starves a prior consumer such as
    /// RoomCaptureView.
    weak var passthrough: (any ARSessionDelegate)?

    var eventHandler: (
        @MainActor (ARSessionLifecycleEvent) -> Void
    )?

    func session(
        _ session: ARSession,
        didFailWithError error: any Error
    ) {
        let nsError = error as NSError
        eventHandler?(
            .failed(reason: "\(nsError.domain)#\(nsError.code)")
        )
        passthrough?.session?(session, didFailWithError: error)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        eventHandler?(.wasInterrupted)
        passthrough?.sessionWasInterrupted?(session)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        eventHandler?(.interruptionEnded)
        passthrough?.sessionInterruptionEnded?(session)
    }

    /// The most recent session-clock timestamp observed by this
    /// bridge. Delegate callbacks fire between frames; without it a
    /// callback during a frame gap would stamp `0` — which reads as
    /// "session start" in the recorded history.
    nonisolated(unsafe) private var lastObservedTimestamp: Double?

    func session(
        _ session: ARSession,
        cameraDidChangeTrackingState camera: ARCamera
    ) {
        if let timestamp = session.currentFrame?.timestamp {
            lastObservedTimestamp = timestamp
        }
        eventHandler?(
            .cameraTrackingStateChanged(
                SharedARSessionController.trackingQualityEvent(
                    camera: camera,
                    sessionTimestampSeconds:
                        lastObservedTimestamp ?? 0
                )
            )
        )
        passthrough?.session?(
            session,
            cameraDidChangeTrackingState: camera
        )
    }

    func session(
        _ session: ARSession,
        didOutputCollaborationData data: ARSession.CollaborationData
    ) {
        eventHandler?(
            .didOutputCollaborationData(
                priorityIsCritical: data.priority == .critical
            )
        )
        passthrough?.session?(
            session,
            didOutputCollaborationData: data
        )
    }

    // Passthrough-only callbacks: forwarded unchanged so the bridge is
    // transparent to any delegate that was installed before it. Mesh
    // anchors are additionally reported to the lifecycle observer so the
    // store can keep bounded add/update/remove diagnostics (#268).

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastObservedTimestamp = frame.timestamp
        passthrough?.session?(session, didUpdate: frame)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        reportMeshAnchors(anchors, kind: .added, session: session)
        reportObjectAnchors(anchors, kind: .added, session: session)
        passthrough?.session?(session, didAdd: anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        reportMeshAnchors(anchors, kind: .updated, session: session)
        reportObjectAnchors(anchors, kind: .updated, session: session)
        passthrough?.session?(session, didUpdate: anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        reportMeshAnchors(anchors, kind: .removed, session: session)
        reportObjectAnchors(anchors, kind: .removed, session: session)
        passthrough?.session?(session, didRemove: anchors)
    }

    private func reportMeshAnchors(
        _ anchors: [ARAnchor],
        kind: MeshAnchorLifecycleKind,
        session: ARSession
    ) {
        let identifiers = anchors.compactMap {
            ($0 as? ARMeshAnchor)?.identifier
        }
        guard !identifiers.isEmpty else { return }
        if let timestamp = session.currentFrame?.timestamp {
            lastObservedTimestamp = timestamp
        }
        meshAnchorHandler?(
            kind,
            identifiers,
            lastObservedTimestamp ?? 0
        )
    }

    /// Reference-object anchors are forwarded whole: the host needs the
    /// matched `referenceObject` name, `transform`, and (iOS 27)
    /// `ARTrackable.isTracked` — none of which a bare UUID carries.
    private func reportObjectAnchors(
        _ anchors: [ARAnchor],
        kind: MeshAnchorLifecycleKind,
        session: ARSession
    ) {
        let objectAnchors = anchors.compactMap {
            $0 as? ARObjectAnchor
        }
        guard !objectAnchors.isEmpty else { return }
        if let timestamp = session.currentFrame?.timestamp {
            lastObservedTimestamp = timestamp
        }
        objectAnchorHandler?(
            kind,
            objectAnchors,
            lastObservedTimestamp ?? 0
        )
    }

    var meshAnchorHandler: (
        @MainActor (
            MeshAnchorLifecycleKind,
            [UUID],
            Double
        ) -> Void
    )?

    var objectAnchorHandler: (
        @MainActor (
            MeshAnchorLifecycleKind,
            [ARObjectAnchor],
            Double
        ) -> Void
    )?

    func session(
        _ session: ARSession,
        didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer
    ) {
        passthrough?.session?(
            session,
            didOutputAudioSampleBuffer: audioSampleBuffer
        )
    }

    func sessionShouldAttemptRelocalization(
        _ session: ARSession
    ) -> Bool {
        // Matches the ARKit default when no delegate implements it.
        passthrough?.sessionShouldAttemptRelocalization?(session)
            ?? true
    }
}

@MainActor
@objc(HTDTRoomPlanViewDelegateBridge)
private final class RoomPlanViewDelegateBridge:
    NSObject,
    @preconcurrency RoomCaptureViewDelegate
{
    var completionHandler: (
        @MainActor (CapturedRoomData, (any Error)?) -> Void
    )?

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init()
    }

    func encode(with coder: NSCoder) {
        // RoomCaptureViewDelegate inherits NSCoding. This bridge has no
        // persistent state; capture authority remains in the host/store.
    }

    func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData,
        error: (any Error)?
    ) -> Bool {
        completionHandler?(roomDataForProcessing, error)
        return false
    }
}

/// Forwards RoomPlan coaching/instruction transitions to the host so a
/// bounded advisory history survives finalization (#260). The full
/// delegate protocol is implemented; only `didProvide` is consumed.
// RoomCaptureSessionDelegate is a pure-Swift protocol with nonisolated
// requirements (unlike the ObjC ARSessionDelegate/RoomCaptureViewDelegate
// bridges above), so the bridge cannot be MainActor-isolated. The
// handler is assigned once before `run` and only read afterwards.
private final class RoomPlanSessionInstructionBridge:
    RoomCaptureSessionDelegate,
    @unchecked Sendable
{
    nonisolated(unsafe) var instructionHandler: (
        @Sendable (RoomPlanGuidanceObservation) -> Void
    )?
    /// Fires on every RoomCaptureSession end — inside the bounded End
    /// transaction or on its own. The host distinguishes the two by
    /// capture state; an end outside End is otherwise invisible.
    nonisolated(unsafe) var endHandler: (
        @Sendable (String?) -> Void
    )?
    /// Last session-clock timestamp seen through `arSession`; keeps a
    /// mid-frame-gap callback from stamping `0` (reads as session
    /// start) in recorded guidance.
    nonisolated(unsafe) private var lastObservedTimestamp: Double?

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didProvide instruction: RoomCaptureSession.Instruction
    ) {
        if let timestamp = session.arSession.currentFrame?.timestamp {
            lastObservedTimestamp = timestamp
        }
        instructionHandler?(
            RoomPlanGuidanceObservation(
                instruction: String(describing: instruction),
                sessionTimestampSeconds:
                    lastObservedTimestamp ?? 0
            )
        )
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didUpdate room: CapturedRoom
    ) {}

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didAdd room: CapturedRoom
    ) {}

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didChange room: CapturedRoom
    ) {}

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didRemove room: CapturedRoom
    ) {}

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didStartWith configuration: RoomCaptureSession.Configuration
    ) {}

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: (any Error)?
    ) {
        endHandler?(error?.localizedDescription)
    }
}

@MainActor
public final class SharedARSessionController {
    public let arSession: ARSession
    public let roomCaptureView: RoomCaptureView
    public private(set) var context: CaptureSessionContext

    public var roomCaptureSession: RoomCaptureSession? {
        roomCaptureView.captureSession
    }

    private let roomPlanDelegateBridge =
        RoomPlanViewDelegateBridge()
    private let roomPlanInstructionBridge =
        RoomPlanSessionInstructionBridge()
    private let sessionDelegateBridge = ARSessionLifecycleBridge()
    private var liveRoomCaptureViewMountObserved = false

    /// Handler invoked on the main actor for ARSession lifecycle events:
    /// interruption began/ended, terminal failure, camera tracking
    /// transitions and collaboration-data output. The host binds each
    /// event to the active capture generation and applies the
    /// coordinate-discontinuity/recoverability policy.
    public var sessionLifecycleHandler: (
        @MainActor (ARSessionLifecycleEvent) -> Void
    )? {
        get { sessionDelegateBridge.eventHandler }
        set { sessionDelegateBridge.eventHandler = newValue }
    }

    /// Mesh anchor add/update/remove notifications for bounded lifecycle
    /// diagnostics (#268). Non-mesh anchors are filtered out.
    public var meshAnchorLifecycleHandler: (
        @MainActor (
            MeshAnchorLifecycleKind,
            [UUID],
            Double
        ) -> Void
    )? {
        get { sessionDelegateBridge.meshAnchorHandler }
        set { sessionDelegateBridge.meshAnchorHandler = newValue }
    }

    /// Reference-object anchor add/update/remove callbacks (#268) from
    /// the single shared session delegate — never a second delegate.
    /// Anchors arrive unfiltered so the host can read the matched
    /// `referenceObject` name, pose transform, and `isTracked`.
    public var objectAnchorLifecycleHandler: (
        @MainActor (
            MeshAnchorLifecycleKind,
            [ARObjectAnchor],
            Double
        ) -> Void
    )? {
        get { sessionDelegateBridge.objectAnchorHandler }
        set { sessionDelegateBridge.objectAnchorHandler = newValue }
    }

    /// Installs reference-object detection/tracking sets on the live
    /// `ARWorldTrackingConfiguration` and re-runs the session (#268).
    ///
    /// The result is always honest about what the running
    /// configuration adopted: `trackingObjects` is only reachable on
    /// iOS 27+, so a tracking request on an older system or an older
    /// SDK returns `.trackingUnsupported` rather than silently
    /// degrading the objects to detection. Read-back verification
    /// compares the live configuration's object names against what was
    /// requested — a mismatch is surfaced, never claimed as success.
    ///
    /// A `.arobject` archive is never accepted: iOS 27 cannot mix
    /// legacy and `.referenceobject` payloads in one session, and the
    /// detection-only legacy path is out of scope for this lane.
    @discardableResult
    public func configureReferenceObjects(
        detection: Set<ARReferenceObject>,
        tracking: Set<ARReferenceObject>
    ) -> ReferenceObjectReconfigurationResult {
        guard !detection.isEmpty || !tracking.isEmpty else {
            return ReferenceObjectReconfigurationResult(
                status: .configured,
                detail: "empty_sets no_change",
                sessionRestarted: false
            )
        }
        guard
            let configuration = arSession.configuration
                as? ARWorldTrackingConfiguration
        else {
            return ReferenceObjectReconfigurationResult(
                status: .incompatibleConfiguration,
                detail:
                    "live_configuration=\(String(describing: arSession.configuration.flatMap { Swift.type(of: $0) }))",
                sessionRestarted: false
            )
        }
        // Legacy `.arobject` payloads land in detectionObjects too;
        // there is no SDK affordance that separates them post-load, so
        // the host must hold the format gate at load time. This API
        // only carries `.referenceobject` archives and says so in the
        // outcome detail for provenance.
        let trackingSupported: Bool = {
            guard #available(iOS 27.0, *) else { return false }
            // `trackingObjects` is an iOS 27 SDK symbol — absent from
            // earlier SDK surfaces entirely — so it is probed through
            // KVC rather than referenced directly.
            return configuration.responds(
                to: NSSelectorFromString("setTrackingObjects:")
            )
        }()
        if !tracking.isEmpty, !trackingSupported {
            return ReferenceObjectReconfigurationResult(
                status: .trackingUnsupported,
                detail:
                    "tracking_requested=\(tracking.count) detection_requested=\(detection.count)",
                sessionRestarted: false
            )
        }
        let requestedDetectionNames = Set(detection.compactMap(\.name))
        let requestedTrackingNames = Set(tracking.compactMap(\.name))
        configuration.detectionObjects = detection
        if trackingSupported {
            configuration.setValue(
                NSSet(set: tracking),
                forKey: "trackingObjects"
            )
        }
        arSession.run(configuration, options: [])

        // Read-back: the live configuration post-run decides what was
        // actually adopted.
        guard
            let adopted = arSession.configuration
                as? ARWorldTrackingConfiguration
        else {
            return ReferenceObjectReconfigurationResult(
                status: .verificationMismatch,
                detail:
                    "post_run_configuration_missing detection_requested=\(requestedDetectionNames.sorted())",
                sessionRestarted: true
            )
        }
        let adoptedDetection = Set(
            adopted.detectionObjects.compactMap(\.name)
        )
        var adoptedTracking: Set<String> = []
        if trackingSupported {
            adoptedTracking = Set(
                ((adopted.value(forKey: "trackingObjects")
                    as? Set<ARReferenceObject>) ?? [])
                    .compactMap(\.name)
            )
        }
        let detectionOK = adoptedDetection == requestedDetectionNames
        let trackingOK =
            !trackingSupported || adoptedTracking == requestedTrackingNames
        return ReferenceObjectReconfigurationResult(
            status: detectionOK && trackingOK
                ? .configured : .verificationMismatch,
            detail:
                "detection_requested=\(requestedDetectionNames.sorted()) "
                + "tracking_requested=\(requestedTrackingNames.sorted()) "
                + "adopted_detection=\(adoptedDetection.sorted()) "
                + "adopted_tracking=\(adoptedTracking.sorted())",
            sessionRestarted: true
        )
    }

    /// RoomPlan coaching/instruction observations (#260). Installed as
    /// `roomCaptureSession.delegate` when RoomPlan runs; invoked from the
    /// framework's delegate queue (nonisolated), so hop to MainActor
    /// inside the handler if needed.
    public var roomPlanInstructionHandler: (
        @Sendable (RoomPlanGuidanceObservation) -> Void
    )? {
        get { roomPlanInstructionBridge.instructionHandler }
        set {
            roomPlanInstructionBridge.instructionHandler = newValue
        }
    }

    /// Fires with the error description (nil on a clean end) every time
    /// the RoomCaptureSession ends — inside the bounded End transaction
    /// or on its own. An end outside End stops the room model
    /// accumulating while the host still shows a scanning surface, so
    /// the host records it as provenance.
    public var roomPlanDidEndHandler: (
        @Sendable (String?) -> Void
    )? {
        get { roomPlanInstructionBridge.endHandler }
        set {
            roomPlanInstructionBridge.endHandler = newValue
        }
    }

    public init(
        arSession: ARSession = ARSession(),
        context: CaptureSessionContext = CaptureSessionContext()
    ) {
        self.arSession = arSession
        self.context = context
        self.roomCaptureView = RoomCaptureView(
            frame: .zero,
            arSession: arSession
        )
        self.roomCaptureView.isModelEnabled = true
        self.roomCaptureView.delegate = roomPlanDelegateBridge
        installSessionLifecycleBridge()
    }

    /// Installs the lifecycle bridge as `arSession.delegate` while
    /// preserving any previously installed delegate via passthrough
    /// forwarding. Re-invoked after RoomPlan start because
    /// RoomCaptureView may reclaim the session delegate when its capture
    /// session runs.
    public func installSessionLifecycleBridge() {
        if let existing = arSession.delegate,
           existing !== sessionDelegateBridge
        {
            sessionDelegateBridge.passthrough = existing
        }
        // The bridge is MainActor-isolated; pin delegate callbacks to
        // the main queue so isolation is guaranteed at the ARKit edge.
        arSession.delegateQueue = .main
        arSession.delegate = sessionDelegateBridge
    }

    public func setRoomPlanModelRenderingEnabled(
        _ enabled: Bool
    ) {
        guard roomCaptureView.isModelEnabled != enabled else {
            return
        }
        roomCaptureView.isModelEnabled = enabled
        roomCaptureView.setNeedsLayout()
    }

    func markLiveRoomCaptureViewMounted(
        _ view: RoomCaptureView
    ) {
        guard view === roomCaptureView else {
            return
        }
        liveRoomCaptureViewMountObserved = true
        // #269: bind the layer that displays the ARFrame so iOS 27's
        // `viewRotationAngle` becomes a live rotation authority for the
        // segmentation display-transform path.
        if #available(iOS 27, *) {
            arSession.viewLayer = roomCaptureView.layer
        }
        roomCaptureView.setNeedsLayout()
        roomCaptureView.layoutIfNeeded()
    }

    func markLiveRoomCaptureViewUnmounted(
        _ view: RoomCaptureView
    ) {
        guard view === roomCaptureView else {
            return
        }
        liveRoomCaptureViewMountObserved = false
    }

    public func waitForLiveRoomCaptureViewPresentation()
        async -> Bool
    {
        for _ in 0..<60 {
            if liveRoomCaptureViewMountObserved,
               roomCaptureView.window != nil,
               roomCaptureView.bounds.width > 1,
               roomCaptureView.bounds.height > 1
            {
                return true
            }

            if Task.isCancelled {
                return false
            }

            try? await Task.sleep(
                for: .milliseconds(50)
            )
        }

        return false
    }

    public func setRoomPlanCompletionHandler(
        _ handler: @escaping @MainActor (
            CapturedRoomData,
            (any Error)?
        ) -> Void
    ) {
        roomPlanDelegateBridge.completionHandler = handler
        roomCaptureView.delegate = roomPlanDelegateBridge
    }

    public func startRoomPlan(
        configuration: RoomCaptureSession.Configuration = .init()
    ) throws {
        guard RoomCaptureSession.isSupported else {
            throw PlatformCaptureError.roomPlanUnsupported
        }

        guard let roomCaptureSession else {
            throw PlatformCaptureError.roomPlanUnsupported
        }
        roomCaptureSession.delegate = roomPlanInstructionBridge
        roomCaptureSession.run(configuration: configuration)
        // RoomCaptureView may install itself as the ARSession delegate
        // when its capture session runs; reclaim the delegate while
        // forwarding every callback back to it.
        installSessionLifecycleBridge()
    }

    public func stopRoomPlanPreservingARSession() {
        roomCaptureSession?.stop(pauseARSession: false)
    }

    public func stopAndPauseARSession() {
        roomCaptureSession?.stop(pauseARSession: true)
    }

    /// Resolve the capture mode honestly satisfied by the configuration
    /// actually running on `arSession`. When `requestedMode` is provided
    /// and not satisfied by the running configuration, the resolution
    /// reports `unsatisfiedRequestedMode` so the host can fail closed or
    /// explicitly downgrade instead of persisting a mismatched mode.
    public func snapshotActiveConfigurationResolution(
        requestedMode: CaptureMode? = nil
    ) throws -> ActiveARConfigurationResolution {
        guard let resolution =
            PlatformCapabilityProbe.resolveActiveConfiguration(
                session: arSession,
                requestedMode: requestedMode,
                capabilities: PlatformCapabilityProbe.current()
            )
        else {
            throw PlatformCaptureError.configurationUnavailable
        }
        return resolution
    }

    /// Build the persisted configuration profile with the capture mode
    /// resolved from the actual running configuration, never asserted
    /// from device support alone. A no-mesh active configuration cannot
    /// claim `.roomPlanMesh` through this path.
    public func snapshotConfigurationProfile(
        requestedMode: CaptureMode? = nil,
        roomPlanOptions: [String: String] = [:]
    ) throws -> CaptureConfigurationProfile {
        let resolution = try snapshotActiveConfigurationResolution(
            requestedMode: requestedMode
        )
        return try ARConfigurationSnapshotAdapter.snapshot(
            session: arSession,
            captureMode: resolution.resolvedCaptureMode,
            roomPlanOptions: roomPlanOptions
        )
    }

    /// Snapshot the combined-feature signals observable on the live
    /// session. The host passes the RoomPlan phase it is in and applies
    /// `PlatformCapabilityProbe.applyingCombinedFeatureVerification`
    /// to persist verification results instead of leaving the capability
    /// matrix fields permanently unknown.
    public func currentCombinedFeatureObservation(
        roomPlanPhase: CombinedFeatureObservation.RoomPlanPhase
    ) -> CombinedFeatureObservation {
        let configuration = arSession.configuration
        let world =
            configuration as? ARWorldTrackingConfiguration
        let depthSemanticsEnabled =
            configuration?.frameSemantics
                .contains(.sceneDepth) ?? false
        let depthProduced =
            arSession.currentFrame.map {
                $0.sceneDepth != nil || $0.smoothedSceneDepth != nil
            } ?? false

        return CombinedFeatureObservation(
            roomPlanPhase: roomPlanPhase,
            sceneReconstructionActive:
                world.map { !$0.sceneReconstruction.isEmpty } ?? false,
            sceneDepthActive: depthSemanticsEnabled && depthProduced
        )
    }

    public func currentScanCoverageSample()
        throws -> ScanCoverageSample
    {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let camera = frame.camera.transform
        let forward = SIMD3<Double>(
            Double(-camera.columns.2.x),
            Double(-camera.columns.2.y),
            Double(-camera.columns.2.z)
        )
        let horizontalMagnitude = hypot(forward.x, forward.z)
        let yaw = atan2(forward.x, -forward.z)
        let pitch = atan2(
            forward.y,
            max(horizontalMagnitude, 0.000_001)
        )
        let tracking = trackingQualityEvent(from: frame)
        let cameraPosition = ScanCameraPosition(
            x: Double(camera.columns.3.x),
            y: Double(camera.columns.3.y),
            z: Double(camera.columns.3.z)
        )
        let meshAnchorCount = frame.anchors.reduce(into: 0) {
            count,
            anchor in
            if anchor is ARMeshAnchor {
                count += 1
            }
        }

        return ScanCoverageSample(
            sessionTimestampSeconds: frame.timestamp,
            yawRadians: yaw,
            pitchRadians: pitch,
            cameraPosition: cameraPosition,
            trackingState: tracking.state,
            trackingReason: tracking.reason,
            activeMeshAnchorCount: meshAnchorCount,
            hasSceneDepth:
                frame.sceneDepth != nil
                || frame.smoothedSceneDepth != nil,
            ambientLightIntensityLumens:
                frame.lightEstimate.map { Double($0.ambientIntensity) }
        )
    }

    public func currentSpatialCoverageSample(
        maxSurfacePoints: Int = 96
    ) throws -> SpatialCoverageSample {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let camera = frame.camera.transform
        let cameraFromWorld = simd_inverse(camera)
        let cameraPosition = SpatialCoveragePoint3D(
            x: Double(camera.columns.3.x),
            y: Double(camera.columns.3.y),
            z: Double(camera.columns.3.z)
        )
        let forward = SIMD3<Double>(
            Double(-camera.columns.2.x),
            Double(-camera.columns.2.y),
            Double(-camera.columns.2.z)
        )
        let yaw = atan2(forward.x, -forward.z)
        let tracking = trackingQualityEvent(from: frame)

        let anchors = frame.anchors
            .compactMap { $0 as? ARMeshAnchor }
            .sorted {
                $0.identifier.uuidString.lowercased()
                    < $1.identifier.uuidString.lowercased()
            }

        let sceneReconstructionSupported =
            ARWorldTrackingConfiguration
                .supportsSceneReconstruction(.mesh)
        let activeConfigurationName =
            arSession.configuration.map {
                String(describing: type(of: $0))
            }

        let sceneReconstructionEnabled: Bool
        if let worldConfiguration =
            arSession.configuration as? ARWorldTrackingConfiguration
        {
            sceneReconstructionEnabled =
                !worldConfiguration.sceneReconstruction.isEmpty
        } else {
            sceneReconstructionEnabled = false
        }

        let meshAvailability = MeshAvailabilityDiagnostic(
            sceneReconstructionSupported:
                sceneReconstructionSupported,
            sceneReconstructionEnabled:
                sceneReconstructionEnabled,
            activeMeshAnchorCount: anchors.count,
            activeConfigurationName:
                activeConfigurationName,
            configurationMismatchSuspected:
                sceneReconstructionSupported
                && !sceneReconstructionEnabled
        )

        let budget = min(max(maxSurfacePoints, 0), 128)
        var points: [SpatialCoveragePoint3D] = []
        points.reserveCapacity(budget)

        if budget > 0, !anchors.isEmpty {
            let perAnchorBudget =
                max(1, budget / anchors.count)

            for anchor in anchors.prefix(budget) {
                guard points.count < budget else {
                    break
                }

                let vertices = anchor.geometry.vertices
                guard vertices.count > 0,
                      liveFloat3SourceIsReadable(vertices)
                else {
                    continue
                }

                let anchorBudget = min(
                    perAnchorBudget,
                    budget - points.count
                )
                let vertexStride = max(
                    1,
                    vertices.count / max(anchorBudget, 1)
                )

                var index = 0
                var sampled = 0
                while index < vertices.count,
                      points.count < budget,
                      sampled < anchorBudget
                {
                    let address =
                        vertices.buffer.contents()
                            .advanced(
                                by:
                                    vertices.offset
                                    + index * vertices.stride
                            )
                    let local = address
                        .assumingMemoryBound(
                            to: SIMD3<Float>.self
                        )
                        .pointee
                    let world =
                        anchor.transform
                        * SIMD4<Float>(
                            local.x,
                            local.y,
                            local.z,
                            1
                        )
                    let cameraLocal =
                        cameraFromWorld * world
                    let forwardDepth =
                        -cameraLocal.z
                    let isCurrentViewCandidate =
                        forwardDepth >= 0.15
                        && forwardDepth <= 6.0
                        && abs(cameraLocal.x)
                            <= forwardDepth * 0.95
                        && abs(cameraLocal.y)
                            <= forwardDepth * 0.85

                    if isCurrentViewCandidate {
                        points.append(
                            SpatialCoveragePoint3D(
                                x: Double(world.x),
                                y: Double(world.y),
                                z: Double(world.z)
                            )
                        )
                    }

                    index += vertexStride
                    sampled += 1
                }
            }
        }

        var evidenceSource: SpatialCoverageEvidenceSource =
            points.isEmpty ? .none : .mesh

        if points.isEmpty, budget > 0 {
            let depthPoints = liveSceneDepthWorldPoints(
                frame: frame,
                maxPoints: budget,
                cropFraction: 0.95,
                minimumDepthMeters: 0.15,
                maximumDepthMeters: 5.5
            )
            points = depthPoints.map {
                SpatialCoveragePoint3D(
                    x: Double($0.x),
                    y: Double($0.y),
                    z: Double($0.z)
                )
            }
            if !points.isEmpty {
                evidenceSource = .sceneDepth
            }
        }

        return SpatialCoverageSample(
            sessionTimestampSeconds: frame.timestamp,
            cameraPositionWorld: cameraPosition,
            cameraYawRadians: yaw,
            trackingState: tracking.state,
            hasSceneDepth:
                frame.sceneDepth != nil
                || frame.smoothedSceneDepth != nil,
            meshAvailability: meshAvailability,
            surfaceEvidenceSource: evidenceSource,
            surfacePointsWorld: points
        )
    }

    public func currentDerivedShapeObservations(
        maxObjectPoints: Int = 384,
        maxWallPoints: Int = 512
    ) throws -> DerivedShapeLiveObservationSet {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let cameraPosition = frame.camera.transform.columns.3
        let anchors = frame.anchors
            .compactMap { $0 as? ARMeshAnchor }
            .sorted { lhs, rhs in
                let lhsPosition = lhs.transform.columns.3
                let rhsPosition = rhs.transform.columns.3
                let lhsDistance =
                    pow(lhsPosition.x - cameraPosition.x, 2)
                    + pow(lhsPosition.y - cameraPosition.y, 2)
                    + pow(lhsPosition.z - cameraPosition.z, 2)
                let rhsDistance =
                    pow(rhsPosition.x - cameraPosition.x, 2)
                    + pow(rhsPosition.y - cameraPosition.y, 2)
                    + pow(rhsPosition.z - cameraPosition.z, 2)
                if abs(lhsDistance - rhsDistance) > 0.000_001 {
                    return lhsDistance < rhsDistance
                }
                return lhs.identifier.uuidString.lowercased()
                    < rhs.identifier.uuidString.lowercased()
            }

        let meshObjectObservation =
            liveDerivedShapeObservation(
                anchors: anchors,
                // Unclassified mesh is not furniture authority. The
                // automatic fallback is limited to semantic object classes;
                // otherwise advisory shape remains unresolved instead of
                // mixing unrelated .none surfaces into one footprint.
                classifications: [.table, .seat],
                sessionTimestampSeconds: frame.timestamp,
                voxelSizeMeters: 0.035,
                maxPoints: maxObjectPoints,
                maxInspectedFaces: 2_500
            )
        let wallObservation =
            liveDerivedShapeObservation(
                anchors: anchors,
                classifications: [.wall],
                sessionTimestampSeconds: frame.timestamp,
                voxelSizeMeters: 0.06,
                maxPoints: maxWallPoints,
                maxInspectedFaces: 3_500
            )
        let meshFloorReferenceY = liveFloorReferenceY(
            anchors: anchors,
            maxInspectedFaces: 1_000,
            maxSamples: 192
        )

        let depthWorldPoints = liveSceneDepthWorldPoints(
            frame: frame,
            maxPoints: min(
                max(maxObjectPoints * 2, 256),
                512
            ),
            // Derived object fitting is intentionally more focused than
            // whole-room spatial coverage. A broad crop mixes nearby floor,
            // chairs and cabinets into one projected footprint and biases
            // curved furniture toward coarse polygons/rectangles.
            cropFraction: 0.82,
            minimumDepthMeters: 0.18,
            maximumDepthMeters: 4.5,
            focusOnForegroundConnectedSurface: true
        )
        let depthFloorReferenceY =
            meshFloorReferenceY
            ?? estimatedFloorY(from: depthWorldPoints)

        let depthVolumeObservation =
            liveDepthDerivedShapeObservation(
                points: depthWorldPoints,
                sessionTimestampSeconds: frame.timestamp,
                floorReferenceY: depthFloorReferenceY,
                voxelSizeMeters: 0.05,
                maxPoints: max(maxObjectPoints, 256)
            )

        let objectObservation: DerivedShapeObservation?
        if let depthVolumeObservation,
           depthVolumeObservation.points.count >= 8
        {
            // Scene depth preserves the observed contour of round/curved and
            // multi-level furniture substantially better than RoomPlan/ARMesh
            // semantic reconstruction. Keep ARMesh as a bounded fallback only.
            objectObservation = depthVolumeObservation
        } else {
            objectObservation = meshObjectObservation
        }

        return DerivedShapeLiveObservationSet(
            objectObservation: objectObservation,
            objectVolumeObservation:
                depthVolumeObservation
                ?? objectObservation,
            wallObservation: wallObservation,
            floorReferenceY: depthFloorReferenceY
        )
    }

    /// The hard cap on the targeted-pass observation window. The anchor
    /// radius bounds the orbit region, not the item — the window itself
    /// is always capped so context surfaces stay out. Exposed so the
    /// pass's provenance note reports the effective window, not the
    /// anchor bound.
    public static let maximumTargetedObservationWindowMeters = 0.55

    /// Bounded observation for the targeted-object pass (#250). The
    /// operator aims at one small item and orbits it; instead of the
    /// room-scan crop + foreground-component heuristics this sampler
    /// keeps only the depth points inside a tight 3D window around the
    /// aim anchor, then removes the dominant horizontal support surface
    /// so an item on a desk/shelf resolves to its own footprint rather
    /// than the surface it rests on. A fine voxel preserves small-object
    /// detail the room pipeline would decimate.
    ///
    /// Mesh faces are the bounded fallback when scene depth yields too
    /// little evidence; inside the window the semantic classification
    /// gate is lifted because small items are almost always
    /// `.none`-classified rather than furniture.
    public func liveTargetedShapeObservation(
        target: ScanTargetAnchor,
        windowRadiusMeters: Double? = nil,
        voxelSizeMeters: Double = 0.012,
        maxPoints: Int = 256,
        minimumPointCount: Int = 5
    ) -> DerivedShapeObservation? {
        guard voxelSizeMeters.isFinite,
              voxelSizeMeters > 0,
              maxPoints > 0,
              minimumPointCount > 0,
              let frame = arSession.currentFrame
        else {
            return nil
        }

        let targetPosition = SIMD3<Float>(
            Float(target.x),
            Float(target.y),
            Float(target.z)
        )
        let radius = Float(
            min(
                windowRadiusMeters ?? target.radiusMeters,
                Self.maximumTargetedObservationWindowMeters
            )
        )
        guard radius.isFinite, radius > 0 else {
            return nil
        }

        let inWindow: (SIMD3<Float>) -> Bool = { point in
            simd_distance(point, targetPosition) <= radius
        }

        let depthWorldPoints = liveSceneDepthWorldPoints(
            frame: frame,
            maxPoints: 512,
            // Tighter than the room crop: concentrates the grid on the
            // aimed region so a small target keeps enough samples.
            cropFraction: 0.55,
            minimumDepthMeters: 0.15,
            maximumDepthMeters: 4.5,
            focusOnForegroundConnectedSurface: false
        ).filter(inWindow)

        if !depthWorldPoints.isEmpty {
            let planeY = DerivedHorizontalPlaneSegmentation
                .dominantPlaneY(
                    verticalPositions: depthWorldPoints.map {
                        Double($0.y)
                    }
                )
            let objectPoints = DerivedHorizontalPlaneSegmentation
                .pointsAbove(
                    planeY: planeY,
                    marginMeters: 0.015,
                    minimumPointCount: minimumPointCount,
                    in: depthWorldPoints
                ) {
                    Double($0.y)
                }

            // When the plane filter falls back to the whole window and
            // the surviving points outline the clip sphere itself, the
            // "item" is the support surface — report unresolved rather
            // than persisting a phantom window-sized circle.
            if planeY != nil,
               objectPoints.count == depthWorldPoints.count,
               rimFraction(
                   of: objectPoints,
                   center: targetPosition,
                   radius: radius
               ) > 0.5
            {
                return nil
            }

            if let observation = liveDepthDerivedShapeObservation(
                points: objectPoints.map {
                    SIMD3<Float>($0.x, $0.y, $0.z)
                },
                sessionTimestampSeconds: frame.timestamp,
                floorReferenceY: nil,
                voxelSizeMeters: voxelSizeMeters,
                maxPoints: maxPoints,
                minimumPointCount: minimumPointCount
            ) {
                return observation
            }
        }

        // Bounded mesh fallback: every classification counts inside the
        // window — small items rarely land in the furniture classes.
        // The support plane must still be rejected: a clipped flat
        // surface's boundary rim is a perfect window-radius circle
        // that would otherwise resolve as a phantom item.
        guard
            let meshObservation = liveDerivedShapeObservation(
                anchors: frame.anchors
                    .compactMap { $0 as? ARMeshAnchor },
                classifications: nil,
                sessionTimestampSeconds: frame.timestamp,
                voxelSizeMeters: 0.015,
                maxPoints: maxPoints,
                maxInspectedFaces: 1_500,
                boundingCenter: targetPosition,
                boundingRadiusMeters: radius,
                supportPlaneRejection: (
                    marginMeters: 0.015,
                    minimumPointCount: minimumPointCount
                )
            )
        else {
            return nil
        }

        // Same rim guard as the depth path: the plane filter's
        // whole-window fallback can still leave the clip sphere's
        // outline as the dominant feature — a mesh "item" whose
        // boundary hugs the window edge is the window, not an item.
        if rimFraction(
            of: meshObservation.points.map {
                SIMD3<Float>(
                    Float($0.position.x),
                    Float(
                        $0.verticalPositionMeters
                            ?? Double(targetPosition.y)
                    ),
                    Float($0.position.y)
                )
            },
            center: targetPosition,
            radius: radius
        ) > 0.5 {
            return nil
        }
        return meshObservation
    }

    /// Fraction of points lying on the clip sphere's skin (within the
    /// outer 8% of the radius) — a value above ~0.5 means the set is
    /// the window's synthetic rim, not a bounded object.
    private func rimFraction(
        of points: [SIMD3<Float>],
        center: SIMD3<Float>,
        radius: Float
    ) -> Double {
        guard !points.isEmpty else {
            return 0
        }
        let rim = points.filter {
            simd_distance($0, center) > radius * 0.92
        }
        return Double(rim.count) / Double(points.count)
    }

    /// Result of a mask-gated targeted observation (#269).
    public struct MaskedTargetedObservationResult: Sendable {
        /// The observation to feed `DerivedShapeTemporalFusionTracker`.
        public let observation: DerivedShapeObservation
        /// Depth/mesh samples inside the mask∩window BEFORE voxel
        /// reduction — the true spatial-support count for the record's
        /// downstream depth-confidence policy context.
        public let supportedSampleCount: Int
        /// "arkit_confidence_map_nonzero" when a real confidence map
        /// was enforced, "confidence_map_absent" when the device
        /// provided none, "mesh_ray_gated" when only mesh support
        /// survived.
        public let depthConfidencePolicy: String
        public let usedMeshFallback: Bool

        public init(
            observation: DerivedShapeObservation,
            supportedSampleCount: Int,
            depthConfidencePolicy: String,
            usedMeshFallback: Bool
        ) {
            self.observation = observation
            self.supportedSampleCount = supportedSampleCount
            self.depthConfidencePolicy = depthConfidencePolicy
            self.usedMeshFallback = usedMeshFallback
        }
    }

    /// Mask-gated targeted observation for the #269 segmentation path:
    /// identical window/plane/rim guards to
    /// `liveTargetedShapeObservation`, but the depth evidence is
    /// limited to samples whose source-image position falls inside the
    /// operator's accepted mask on the RETAINED source frame — the same
    /// frame's own pose + intrinsics unproject it, so depth authority
    /// is same-frame by construction. The mesh fallback keeps only
    /// candidates whose projection through the source frame lands
    /// inside the mask silhouette (rays constrain mesh support; a 2D
    /// mask is never extruded into geometry).
    ///
    /// The depth decode runs `nonisolated` on the retained snapshot
    /// inside a utility-priority detached task — Vision/mask work stays
    /// off the AR delegate and MainActor paths; only the mesh-anchor
    /// read and observation assembly touch the actor.
    public func maskedTargetedShapeObservation(
        snapshot: CapturedFrameSnapshot,
        mask: SegmentationMaskGrid,
        target: ScanTargetAnchor,
        observationID: SegmentationObservationID,
        windowRadiusMeters: Double? = nil,
        voxelSizeMeters: Double = 0.012,
        maxPoints: Int = 256,
        minimumPointCount: Int = 8
    ) async -> MaskedTargetedObservationResult? {
        guard !mask.isEmpty,
              voxelSizeMeters.isFinite,
              voxelSizeMeters > 0,
              maxPoints > 0,
              minimumPointCount > 0
        else {
            return nil
        }

        let targetPosition = SIMD3<Float>(
            Float(target.x),
            Float(target.y),
            Float(target.z)
        )
        let radius = Float(
            min(
                windowRadiusMeters ?? target.radiusMeters,
                Self.maximumTargetedObservationWindowMeters
            )
        )
        guard radius.isFinite, radius > 0 else {
            return nil
        }

        let evidenceStem =
            "live-segmentation:"
            + observationID.rawValue.uuidString.lowercased()

        let depthResult = await Task.detached(priority: .utility) {
            Self.maskedSceneDepthWorldPoints(
                snapshot: snapshot,
                mask: mask,
                targetCenter: targetPosition,
                windowRadiusMeters: radius,
                maxPoints: 512
            )
        }.value

        if !depthResult.points.isEmpty {
            let planeY = DerivedHorizontalPlaneSegmentation
                .dominantPlaneY(
                    verticalPositions: depthResult.points.map {
                        Double($0.y)
                    }
                )
            let objectPoints = DerivedHorizontalPlaneSegmentation
                .pointsAbove(
                    planeY: planeY,
                    marginMeters: 0.015,
                    minimumPointCount: minimumPointCount,
                    in: depthResult.points
                ) {
                    Double($0.y)
                }

            // Same rim guard as the live path: a whole-window survivor
            // outlining the clip sphere is the support surface, not
            // the segmented item.
            if planeY != nil,
               objectPoints.count == depthResult.points.count,
               rimFraction(
                   of: objectPoints,
                   center: targetPosition,
                   radius: radius
               ) > 0.5
            {
                // fall through to the mesh path — unresolved there is
                // still honest (nil), never a fabricated solid.
            } else if let observation =
                liveDepthDerivedShapeObservation(
                    points: objectPoints,
                    sessionTimestampSeconds:
                        snapshot.sessionTimestampSeconds,
                    floorReferenceY: nil,
                    voxelSizeMeters: voxelSizeMeters,
                    maxPoints: maxPoints,
                    minimumPointCount: minimumPointCount,
                    evidenceRefStem: evidenceStem
                )
            {
                return MaskedTargetedObservationResult(
                    observation: observation,
                    supportedSampleCount: depthResult.points.count,
                    depthConfidencePolicy: depthResult.confidencePolicy,
                    usedMeshFallback: false
                )
            }
        }

        // Mesh fallback, constrained by the mask's silhouette: only
        // mesh points whose projection through the SOURCE frame's own
        // pose/intrinsics lands inside the accepted mask count as
        // evidence. The frame is explicitly related (same coordinate
        // space, recorded pose), so this is the "segmented rays
        // constrain mesh support" path — never an extrusion.
        guard let frame = arSession.currentFrame else {
            return nil
        }
        let imageWidth = CVPixelBufferGetWidth(snapshot.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(snapshot.capturedImage)
        guard imageWidth > 0, imageHeight > 0 else {
            return nil
        }

        guard let meshObservation = liveDerivedShapeObservation(
            anchors: frame.anchors.compactMap { $0 as? ARMeshAnchor },
            classifications: nil,
            sessionTimestampSeconds: snapshot.sessionTimestampSeconds,
            voxelSizeMeters: 0.015,
            maxPoints: maxPoints,
            maxInspectedFaces: 1_500,
            boundingCenter: targetPosition,
            boundingRadiusMeters: radius,
            supportPlaneRejection: (
                marginMeters: 0.015,
                minimumPointCount: minimumPointCount
            )
        ) else {
            return nil
        }

        let maskGatedPoints = meshObservation.points.filter { point in
            SegmentationDepthGate.maskContains(
                mask: mask,
                worldX: point.position.x,
                worldY: point.verticalPositionMeters
                    ?? Double(targetPosition.y),
                worldZ: point.position.y,
                worldFromCamera: snapshot.worldFromCamera,
                intrinsics: snapshot.intrinsics,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
        }
        guard maskGatedPoints.count >= minimumPointCount else {
            return nil
        }

        if rimFraction(
            of: maskGatedPoints.map {
                SIMD3<Float>(
                    Float($0.position.x),
                    Float(
                        $0.verticalPositionMeters
                            ?? Double(targetPosition.y)
                    ),
                    Float($0.position.y)
                )
            },
            center: targetPosition,
            radius: radius
        ) > 0.5 {
            return nil
        }

        let gated = DerivedShapeObservation(
            coordinateSpaceID: meshObservation.coordinateSpaceID,
            points: maskGatedPoints,
            observationStartSeconds:
                meshObservation.observationStartSeconds,
            observationEndSeconds:
                meshObservation.observationEndSeconds
        )
        return MaskedTargetedObservationResult(
            observation: gated,
            supportedSampleCount: maskGatedPoints.count,
            depthConfidencePolicy: "mesh_ray_gated",
            usedMeshFallback: true
        )
    }

    /// Depth-map decode for a mask-gated observation: mirrors
    /// `liveSceneDepthWorldPoints` exactly (confidence-map filtering,
    /// depth-range guards, scaled intrinsics, the
    /// `T_world_from_camera` unproject convention) but reads the
    /// RETAINED snapshot's own `ARDepthData` — the same-frame guarantee
    /// is structural — and admits only samples inside the mask and the
    /// observation window. Never upsamples depth: only real depth-map
    /// samples produce world points.
    ///
    /// `nonisolated`: pixel locks and row walks run wherever the
    /// caller's task runs (a detached bounded task in practice), never
    /// on MainActor or the AR delegate.
    nonisolated static func maskedSceneDepthWorldPoints(
        snapshot: CapturedFrameSnapshot,
        mask: SegmentationMaskGrid,
        targetCenter: SIMD3<Float>,
        windowRadiusMeters: Float,
        maxPoints: Int,
        minimumDepthMeters: Float = 0.15,
        maximumDepthMeters: Float = 4.5
    ) -> (points: [SIMD3<Float>], confidencePolicy: String) {
        let empty: ([SIMD3<Float>], String) = ([], "unavailable")
        guard maxPoints > 0,
              minimumDepthMeters > 0,
              maximumDepthMeters > minimumDepthMeters,
              windowRadiusMeters.isFinite,
              windowRadiusMeters > 0,
              !mask.isEmpty,
              let depthData =
                snapshot.smoothedDepthData ?? snapshot.discreteDepthData
        else {
            return empty
        }

        let depthMap = depthData.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 1,
              height > 1,
              CVPixelBufferGetPixelFormatType(depthMap)
                == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferLockBaseAddress(depthMap, .readOnly)
                == kCVReturnSuccess
        else {
            return empty
        }
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }
        guard let depthBaseAddress =
                CVPixelBufferGetBaseAddress(depthMap)
        else {
            return empty
        }

        var confidenceMap: CVPixelBuffer?
        var confidencePolicy = "confidence_map_absent"
        if let candidateConfidenceMap = depthData.confidenceMap,
           CVPixelBufferGetWidth(candidateConfidenceMap) == width,
           CVPixelBufferGetHeight(candidateConfidenceMap) == height,
           CVPixelBufferGetPixelFormatType(candidateConfidenceMap)
                == kCVPixelFormatType_OneComponent8,
           CVPixelBufferLockBaseAddress(
                candidateConfidenceMap,
                .readOnly
           ) == kCVReturnSuccess
        {
            if CVPixelBufferGetBaseAddress(candidateConfidenceMap)
                != nil
            {
                confidenceMap = candidateConfidenceMap
                confidencePolicy = "arkit_confidence_map_nonzero"
            } else {
                CVPixelBufferUnlockBaseAddress(
                    candidateConfidenceMap,
                    .readOnly
                )
            }
        }
        defer {
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(
                    confidenceMap,
                    .readOnly
                )
            }
        }

        let imageWidth = CVPixelBufferGetWidth(snapshot.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(snapshot.capturedImage)
        guard imageWidth > 0, imageHeight > 0 else {
            return empty
        }

        // Intrinsics scale to depth-map resolution exactly like the
        // live path — depth pixels index the same normalized image
        // space the mask tests in.
        let scaleX = Float(width) / Float(imageWidth)
        let scaleY = Float(height) / Float(imageHeight)
        let intrinsics = snapshot.intrinsics
        let fx = intrinsics.fx * scaleX
        let fy = intrinsics.fy * scaleY
        let cx = intrinsics.cx * scaleX
        let cy = intrinsics.cy * scaleY
        guard fx.isFinite, fy.isFinite, fx > 0, fy > 0 else {
            return empty
        }

        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let confidenceBytesPerRow =
            confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        let confidenceBaseAddress =
            confidenceMap.flatMap { CVPixelBufferGetBaseAddress($0) }
        guard depthBytesPerRow >= width * MemoryLayout<Float>.size
        else {
            return empty
        }
        if confidenceMap != nil, confidenceBytesPerRow < width {
            return empty
        }

        let step = max(
            1,
            Int(
                ceil(
                    sqrt(
                        Double(width) * Double(height)
                            / Double(maxPoints)
                    )
                )
            )
        )
        let radiusSquared =
            windowRadiusMeters * windowRadiusMeters

        // Column-major worldFromCamera: basis columns 0–2, translation
        // column 3 — the snapshot's own `T_world_from_camera`.
        let m = snapshot.worldFromCamera.values

        var points: [SIMD3<Float>] = []
        points.reserveCapacity(maxPoints)

        var y = step / 2
        while y < height, points.count < maxPoints {
            let depthRow = depthBaseAddress
                .advanced(by: y * depthBytesPerRow)
                .assumingMemoryBound(to: Float.self)
            let confidenceRow =
                confidenceBaseAddress?
                    .advanced(by: y * confidenceBytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)

            var x = step / 2
            while x < width, points.count < maxPoints {
                defer { x += step }
                // The mask is the spatial gate: depth pixels outside
                // the accepted silhouette never become evidence.
                guard mask.contains(
                    depthX: x,
                    depthY: y,
                    depthWidth: width,
                    depthHeight: height
                ) else {
                    continue
                }
                let depth = depthRow[x]
                guard depth.isFinite,
                      depth >= minimumDepthMeters,
                      depth <= maximumDepthMeters
                else {
                    continue
                }
                if let confidenceRow,
                   confidenceRow[x] == 0
                {
                    continue
                }
                let localX = (Float(x) - cx) * depth / fx
                let localY = -(Float(y) - cy) * depth / fy
                // camera→world via column-major transform:
                // world = R * local + t.
                let worldX =
                    m[0] * localX + m[4] * localY
                    - m[8] * depth + m[12]
                let worldY =
                    m[1] * localX + m[5] * localY
                    - m[9] * depth + m[13]
                let worldZ =
                    m[2] * localX + m[6] * localY
                    - m[10] * depth + m[14]
                guard worldX.isFinite,
                      worldY.isFinite,
                      worldZ.isFinite
                else {
                    continue
                }
                let dx = worldX - targetCenter.x
                let dy = worldY - targetCenter.y
                let dz = worldZ - targetCenter.z
                guard dx * dx + dy * dy + dz * dz
                        <= radiusSquared
                else {
                    continue
                }
                points.append(SIMD3<Float>(worldX, worldY, worldZ))
            }
            y += step
        }

        return (points, confidencePolicy)
    }

    public func snapshotActiveMeshAnchors() throws -> [MeshAnchorSnapshot] {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        return try snapshotMeshAnchors(from: frame)
    }

    public func snapshotHorizontalCameraHeading(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedSpeakerOrientation {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let camera = frame.camera.transform
        let x = -camera.columns.2.x
        let z = -camera.columns.2.z
        let magnitude = sqrt(x * x + z * z)
        guard magnitude.isFinite, magnitude > 0.001 else {
            throw PlatformCaptureError.orientationUnavailable
        }

        let front = try SpatialVector3F.unit(
            x / magnitude,
            0,
            z / magnitude
        )
        return CapturedSpeakerOrientation(
            frontAxisWorld: front,
            frameArtifacts: try ARFrameArtifactAdapter.snapshot(
                frame: frame,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                depthSelection: depthSelection
            )
        )
    }

    /// Full 3D camera orientation for measurement-point direction
    /// authority (issue #271): forward is the -Z camera column, up is
    /// the +Y column, both expressed in world space without flattening.
    public func snapshotCameraOrientation(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedPointOrientation {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let camera = frame.camera.transform
        let front = SIMD3<Float>(
            -camera.columns.2.x,
            -camera.columns.2.y,
            -camera.columns.2.z
        )
        let up = SIMD3<Float>(
            camera.columns.1.x,
            camera.columns.1.y,
            camera.columns.1.z
        )
        let frontMagnitude =
            (front.x * front.x + front.y * front.y + front.z * front.z)
                .squareRoot()
        let upMagnitude =
            (up.x * up.x + up.y * up.y + up.z * up.z).squareRoot()
        guard frontMagnitude.isFinite, frontMagnitude > 0.001,
              upMagnitude.isFinite, upMagnitude > 0.001
        else {
            throw PlatformCaptureError.orientationUnavailable
        }

        return CapturedPointOrientation(
            frontAxisWorld: try SpatialVector3F.unit(
                front.x / frontMagnitude,
                front.y / frontMagnitude,
                front.z / frontMagnitude
            ),
            upAxisWorld: try SpatialVector3F.unit(
                up.x / upMagnitude,
                up.y / upMagnitude,
                up.z / upMagnitude
            ),
            frameArtifacts: try ARFrameArtifactAdapter.snapshot(
                frame: frame,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                depthSelection: depthSelection
            )
        )
    }

    public func snapshotCenterRaycastPlacement(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedRaycastPlacement {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let camera = frame.camera.transform
        let origin = SIMD3<Float>(
            camera.columns.3.x,
            camera.columns.3.y,
            camera.columns.3.z
        )
        let direction = SIMD3<Float>(
            -camera.columns.2.x,
            -camera.columns.2.y,
            -camera.columns.2.z
        )

        let targets: [ARRaycastQuery.Target] = [
            .existingPlaneGeometry,
            .estimatedPlane,
        ]
        var hit: ARRaycastResult?
        var hitTarget: ARRaycastQuery.Target?
        for target in targets {
            let query = ARRaycastQuery(
                origin: origin,
                direction: direction,
                allowing: target,
                alignment: .any
            )
            if let result = arSession.raycast(query).first {
                hit = result
                hitTarget = target
                break
            }
        }

        guard let hit, let hitTarget else {
            throw PlatformCaptureError.raycastMiss
        }

        let position = hit.worldTransform.columns.3
        let hitPosition = SIMD3<Float>(
            position.x,
            position.y,
            position.z
        )
        let provenance = try RaycastPlacementProvenance(
            target: Self.raycastTargetToken(hitTarget),
            targetAlignment: Self.raycastAlignmentToken(
                hit.targetAlignment
            ),
            hitDistanceMeters: Double(
                simd_distance(origin, hitPosition)
            ),
            hitWorldTransform: Self.matrix4x4F(hit.worldTransform),
            hitAnchorIdentifier: hit.anchor?.identifier,
            hitAnchorType: hit.anchor.map {
                String(describing: type(of: $0))
            }
        )
        return CapturedRaycastPlacement(
            positionWorld: Float3(
                position.x,
                position.y,
                position.z
            ),
            frameArtifacts: try ARFrameArtifactAdapter.snapshot(
                frame: frame,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                depthSelection: depthSelection
            ),
            raycastProvenance: provenance
        )
    }

    private static func raycastTargetToken(
        _ target: ARRaycastQuery.Target
    ) -> RaycastPlacementProvenance.Target {
        switch target {
        case .existingPlaneGeometry:
            return .existingPlaneGeometry
        case .existingPlaneInfinite:
            return .existingPlaneInfinite
        case .estimatedPlane:
            return .estimatedPlane
        default:
            return .unknown
        }
    }

    private static func raycastAlignmentToken(
        _ alignment: ARRaycastQuery.TargetAlignment
    ) -> RaycastPlacementProvenance.Alignment {
        switch alignment {
        case .any:
            return .any
        case .horizontal:
            return .horizontal
        case .vertical:
            return .vertical
        default:
            return .unknown
        }
    }

    private nonisolated static func matrix4x4F(
        _ value: simd_float4x4
    ) throws -> Matrix4x4F {
        try Matrix4x4F(values: [
            value.columns.0.x, value.columns.0.y, value.columns.0.z, value.columns.0.w,
            value.columns.1.x, value.columns.1.y, value.columns.1.z, value.columns.1.w,
            value.columns.2.x, value.columns.2.y, value.columns.2.z, value.columns.2.w,
            value.columns.3.x, value.columns.3.y, value.columns.3.z, value.columns.3.w,
        ])
    }

    /// Bracketed monotonic↔UTC correlation sample for the given capture
    /// boundary (#200), corrected for ARFrame age (#206).
    ///
    /// The `boundary` chooses the persisted `method` label:
    /// `.sessionStart` is taken from the first AR frame the shared
    /// session delivers after the start request — before any unrelated
    /// configuration wait or persistence work — while `.sessionEnd` is
    /// the current-frame sample at the accepted End boundary.
    ///
    /// `ARFrame.timestamp` is the frame's capture instant in the host
    /// monotonic domain (the `mach_absolute_time`-derived seconds
    /// shared with `CACurrentMediaTime()`), while `currentFrame` is the
    /// latest already-produced frame — at least part of a frame
    /// interval old, and arbitrarily older during scheduling stalls or
    /// tracking interruptions. Sampling that same monotonic clock
    /// alongside the wall-clock bracket lets the estimator project the
    /// frame's capture instant and fold the observed frame age into the
    /// declared uncertainty instead of reporting only the
    /// property-access bracket.
    public func snapshotTimingCorrelation(
        boundary: CaptureTimingBoundary = .sessionEnd
    ) throws -> CaptureTimingCorrelation {
        let monotonicBefore = CACurrentMediaTime()
        let before = Date()
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        let after = Date()
        let monotonicAfter = CACurrentMediaTime()

        let estimate = FrameTimingCorrelationEstimator.estimate(
            frameTimestampSeconds: frame.timestamp,
            monotonicReadBeforeSeconds: monotonicBefore,
            monotonicReadAfterSeconds: monotonicAfter,
            wallClockReadBefore: before,
            wallClockReadAfter: after,
            utcSerializationQuantizationSeconds:
                PlatformTimestamp.fractionalUtcQuantizationSeconds
        )

        return try CaptureTimingCorrelation(
            monotonicSeconds: frame.timestamp,
            utc: PlatformTimestamp.fractionalUtcString(
                from: estimate.captureInstantUTC
            ),
            method: boundary.ageProjectedTimingMethod,
            estimatedUncertaintySeconds:
                estimate.uncertaintySeconds
        )
    }

    public func snapshotTrackingQualityEvent()
        throws -> TrackingQualityEvent
    {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        return trackingQualityEvent(from: frame)
    }

    public func snapshotFrameEvidence(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedFrameArtifacts {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        return try ARFrameArtifactAdapter.capture(
            frame: frame,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            depthSelection: depthSelection
        )
    }

    /// SNAPSHOT step for deferred frame evidence: retains the current
    /// frame's pixel/depth buffers and pose metadata only. The MainActor
    /// critical section is limited to this capture/retain; pair with
    /// `materializeFrameEvidence(_:)` on a bounded task to keep packing,
    /// hashing and HEIC generation off the main actor.
    public func snapshotFrameEvidenceCapture(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CapturedFrameSnapshot {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        return try ARFrameArtifactAdapter.snapshot(
            frame: frame,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            depthSelection: depthSelection
        )
    }

    /// Bounded usability assessment of the current camera frame
    /// (#274): samples the captured image's luma statistics on the
    /// fixed probe grid and pairs them with the frame's EXIF exposure
    /// duration and live tracking state. Returns nil while no frame is
    /// available; a nil result means "usability unknown", never a pass.
    public func currentFrameUsabilityAssessment()
        -> FrameUsabilityAssessment?
    {
        guard let frame = arSession.currentFrame else {
            return nil
        }
        var metrics = FrameUsabilityProbe.metrics(
            from: frame.capturedImage
        )
        metrics?.exposureSeconds =
            (frame.exifData["ExposureTime"] as? NSNumber)?.doubleValue
        return FrameUsabilityEvaluator().assess(
            metrics: metrics,
            trackingState: trackingQualityEvent(from: frame).state
        )
    }

    /// MATERIALIZE step: canonical binary packing, SHA-256 hashing and
    /// HEIC preview generation for a previously captured frame snapshot.
    /// Deliberately `nonisolated` so the host can call it from a detached
    /// or bounded persistence task without occupying the main actor.
    nonisolated
    public func materializeFrameEvidence(
        _ snapshot: CapturedFrameSnapshot
    ) async throws -> CapturedFrameArtifacts {
        try await ARFrameArtifactAdapter.materialize(snapshot)
    }

    public func snapshotReviewEvidence(
        depthSelection: FrameDepthSelection = .discrete
    ) throws -> CaptureReviewEvidenceSnapshot {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        let meshAnchors: [MeshAnchorSnapshot]
        let meshSnapshotSucceeded: Bool
        do {
            meshAnchors = try snapshotMeshAnchors(from: frame)
            meshSnapshotSucceeded = true
        } catch {
            meshAnchors = []
            meshSnapshotSucceeded = false
        }

        return CaptureReviewEvidenceSnapshot(
            meshAnchors: meshAnchors,
            meshSnapshotSucceeded: meshSnapshotSucceeded,
            frameArtifacts: try ARFrameArtifactAdapter.snapshot(
                frame: frame,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                depthSelection: depthSelection
            ),
            trackingQualityEvent: trackingQualityEvent(from: frame)
        )
    }

    private func liveSceneDepthWorldPoints(
        frame: ARFrame,
        maxPoints: Int,
        cropFraction: Float,
        minimumDepthMeters: Float,
        maximumDepthMeters: Float,
        focusOnForegroundConnectedSurface: Bool = false
    ) -> [SIMD3<Float>] {
        guard maxPoints > 0,
              cropFraction.isFinite,
              cropFraction > 0,
              minimumDepthMeters.isFinite,
              maximumDepthMeters.isFinite,
              minimumDepthMeters > 0,
              maximumDepthMeters > minimumDepthMeters,
              let depthData =
                frame.smoothedSceneDepth ?? frame.sceneDepth
        else {
            return []
        }

        let depthMap = depthData.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard
            width > 1,
            height > 1,
            CVPixelBufferGetPixelFormatType(depthMap)
                == kCVPixelFormatType_DepthFloat32,
            CVPixelBufferLockBaseAddress(
                depthMap,
                .readOnly
            ) == kCVReturnSuccess
        else {
            return []
        }
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        guard let depthBaseAddress =
                CVPixelBufferGetBaseAddress(depthMap)
        else {
            return []
        }

        let candidateConfidenceMap = depthData.confidenceMap
        var confidenceMap: CVPixelBuffer?
        if let candidateConfidenceMap,
           CVPixelBufferGetWidth(candidateConfidenceMap) == width,
           CVPixelBufferGetHeight(candidateConfidenceMap) == height,
           CVPixelBufferGetPixelFormatType(candidateConfidenceMap)
                == kCVPixelFormatType_OneComponent8,
           CVPixelBufferLockBaseAddress(
                candidateConfidenceMap,
                .readOnly
           ) == kCVReturnSuccess
        {
            if CVPixelBufferGetBaseAddress(candidateConfidenceMap) != nil {
                confidenceMap = candidateConfidenceMap
            } else {
                CVPixelBufferUnlockBaseAddress(
                    candidateConfidenceMap,
                    .readOnly
                )
            }
        }
        defer {
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(
                    confidenceMap,
                    .readOnly
                )
            }
        }

        let boundedCrop = min(max(cropFraction, 0.25), 1.0)
        let horizontalInset =
            Int(Float(width) * (1 - boundedCrop) / 2)
        let verticalInset =
            Int(Float(height) * (1 - boundedCrop) / 2)
        let minX = min(max(horizontalInset, 0), width - 1)
        let maxX = max(minX + 1, width - horizontalInset)
        let minY = min(max(verticalInset, 0), height - 1)
        let maxY = max(minY + 1, height - verticalInset)

        let sampleArea =
            max(1, (maxX - minX) * (maxY - minY))
        let step = max(
            1,
            Int(
                ceil(
                    sqrt(
                        Double(sampleArea)
                        / Double(maxPoints)
                    )
                )
            )
        )

        let imageResolution = frame.camera.imageResolution
        guard imageResolution.width > 0,
              imageResolution.height > 0
        else {
            return []
        }

        let scaleX =
            Float(width) / Float(imageResolution.width)
        let scaleY =
            Float(height) / Float(imageResolution.height)
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics.columns.0.x * scaleX
        let fy = intrinsics.columns.1.y * scaleY
        let cx = intrinsics.columns.2.x * scaleX
        let cy = intrinsics.columns.2.y * scaleY
        guard fx.isFinite, fy.isFinite,
              fx > 0, fy > 0
        else {
            return []
        }

        let depthBytesPerRow =
            CVPixelBufferGetBytesPerRow(depthMap)
        let confidenceBytesPerRow =
            confidenceMap.map {
                CVPixelBufferGetBytesPerRow($0)
            } ?? 0
        let confidenceBaseAddress =
            confidenceMap.flatMap {
                CVPixelBufferGetBaseAddress($0)
            }

        let minimumDepthRowBytes =
            width * MemoryLayout<Float>.size
        guard depthBytesPerRow >= minimumDepthRowBytes else {
            return []
        }
        if confidenceMap != nil,
           confidenceBytesPerRow < width
        {
            return []
        }

        var depthSamples: [DepthGridSample] = []
        depthSamples.reserveCapacity(maxPoints)

        var y = minY + step / 2
        while y < maxY, depthSamples.count < maxPoints {
            let depthRow = depthBaseAddress
                .advanced(by: y * depthBytesPerRow)
                .assumingMemoryBound(to: Float.self)
            let confidenceRow =
                confidenceBaseAddress?
                    .advanced(by: y * confidenceBytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)

            var x = minX + step / 2
            while x < maxX, depthSamples.count < maxPoints {
                let depth = depthRow[x]
                guard depth.isFinite,
                      depth >= minimumDepthMeters,
                      depth <= maximumDepthMeters
                else {
                    x += step
                    continue
                }

                if let confidenceRow,
                   confidenceRow[x] == 0
                {
                    x += step
                    continue
                }

                depthSamples.append(
                    DepthGridSample(
                        x: x,
                        y: y,
                        depthMeters: Double(depth)
                    )
                )
                x += step
            }
            y += step
        }

        let selectedSamples: [DepthGridSample]
        if focusOnForegroundConnectedSurface {
            selectedSamples =
                DepthConnectedSurfaceSelector
                    .selectForegroundConnectedComponent(
                        samples: depthSamples,
                        imageWidth: width,
                        imageHeight: height,
                        gridStepPixels: step,
                        minimumComponentCount: 8
                    )
        } else {
            selectedSamples = depthSamples
        }

        var points: [SIMD3<Float>] = []
        points.reserveCapacity(selectedSamples.count)

        for sample in selectedSamples {
            let depth = Float(sample.depthMeters)
            let localX =
                (Float(sample.x) - cx) * depth / fx
            let localY =
                -(Float(sample.y) - cy) * depth / fy
            let cameraPoint = SIMD4<Float>(
                localX,
                localY,
                -depth,
                1
            )
            let world = frame.camera.transform * cameraPoint
            if world.x.isFinite,
               world.y.isFinite,
               world.z.isFinite
            {
                points.append(
                    SIMD3<Float>(
                        world.x,
                        world.y,
                        world.z
                    )
                )
            }
        }

        return points
    }

    private func estimatedFloorY(
        from points: [SIMD3<Float>]
    ) -> Double? {
        let values = points
            .map { Double($0.y) }
            .filter(\.isFinite)
            .sorted()
        guard values.count >= 24,
              let first = values.first,
              let last = values.last,
              last - first >= 0.35
        else {
            return nil
        }

        let index = min(
            values.count - 1,
            Int(Double(values.count - 1) * 0.10)
        )
        return values[index]
    }

    private func liveDepthDerivedShapeObservation(
        points: [SIMD3<Float>],
        sessionTimestampSeconds: Double,
        floorReferenceY: Double?,
        voxelSizeMeters: Double,
        maxPoints: Int,
        minimumPointCount: Int = 8,
        // #269: when set, replaces the default
        // `live-scene-depth:<ts>:` stem so mask-gated evidence carries
        // its producing observation's id.
        evidenceRefStem: String? = nil
    ) -> DerivedShapeObservation? {
        guard maxPoints > 0,
              minimumPointCount > 0,
              voxelSizeMeters.isFinite,
              voxelSizeMeters > 0
        else {
            return nil
        }

        let filtered = points.filter { point in
            guard point.x.isFinite,
                  point.y.isFinite,
                  point.z.isFinite
            else {
                return false
            }
            guard let floorReferenceY else {
                return true
            }
            return Double(point.y) >= floorReferenceY + 0.05
        }

        let observations = filtered.enumerated().map {
            index,
            point in
            DerivedObservationPoint(
                position: DerivedPoint2D(
                    x: Double(point.x),
                    y: Double(point.z)
                ),
                evidenceRef:
                    (evidenceRefStem
                        ?? "live-scene-depth:"
                            + String(
                                format: "%.3f",
                                sessionTimestampSeconds
                            ))
                    + ":"
                    + String(index),
                evidenceKind: .sceneDepth,
                verticalPositionMeters: Double(point.y)
            )
        }

        let reduced = reduceLiveDerivedPoints(
            observations,
            voxelSizeMeters: voxelSizeMeters,
            maxPoints: maxPoints
        )
        guard reduced.count >= minimumPointCount else {
            return nil
        }

        return DerivedShapeObservation(
            coordinateSpaceID: context.coordinateSpaceID,
            points: reduced,
            observationStartSeconds: sessionTimestampSeconds,
            observationEndSeconds: sessionTimestampSeconds
        )
    }

    private func liveDerivedShapeObservation(
        anchors: [ARMeshAnchor],
        classifications requestedClassifications: [ARMeshClassification]?,
        sessionTimestampSeconds: Double,
        voxelSizeMeters: Double,
        maxPoints: Int,
        maxInspectedFaces: Int,
        boundingCenter: SIMD3<Float>? = nil,
        boundingRadiusMeters: Float = 0,
        supportPlaneRejection: (marginMeters: Double, minimumPointCount: Int)? = nil
    ) -> DerivedShapeObservation? {
        guard maxPoints > 0,
              maxInspectedFaces > 0,
              voxelSizeMeters.isFinite,
              voxelSizeMeters > 0
        else {
            return nil
        }

        var edges: [LiveDerivedMeshEdgeKey: LiveDerivedMeshEdgeRecord] = [:]
        var fallbackPoints: [DerivedObservationPoint] = []
        var inspectedFaces = 0

        outer: for anchor in anchors {
            let geometry = anchor.geometry
            let geometryClassifications = geometry.classification
            guard geometry.faces.indexCountPerPrimitive == 3,
                  geometry.faces.bytesPerIndex == 2
                    || geometry.faces.bytesPerIndex == 4,
                  liveMeshElementIsReadable(geometry.faces),
                  liveFloat3SourceIsReadable(geometry.vertices),
                  // A nil classification request (bounded targeted
                  // sampling) skips the semantic gate entirely — small
                  // items are typically unclassified — but a filtered
                  // call still requires readable classifications.
                  (requestedClassifications == nil
                      || (geometryClassifications != nil
                          && liveClassificationSourceIsReadable(
                              geometryClassifications!,
                              minimumCount: geometry.faces.count
                          )))
            else {
                continue
            }

            for faceIndex in 0..<geometry.faces.count {
                if inspectedFaces >= maxInspectedFaces {
                    break outer
                }
                inspectedFaces += 1

                if let requestedClassifications,
                   let geometryClassifications
                {
                    let classificationPointer =
                        geometryClassifications.buffer.contents().advanced(
                            by:
                                geometryClassifications.offset
                                + faceIndex * geometryClassifications.stride
                        )
                    let rawClassification =
                        classificationPointer
                            .assumingMemoryBound(to: UInt8.self)
                            .pointee
                    guard requestedClassifications.contains(where: {
                        rawClassification
                            == UInt8(truncatingIfNeeded: $0.rawValue)
                    }) else {
                        continue
                    }
                }

                guard let indices = liveMeshFaceIndices(
                    geometry: geometry,
                    faceIndex: faceIndex
                ) else {
                    continue
                }

                let vertices = indices.compactMap {
                    liveMeshWorldVertex(
                        geometry: geometry,
                        vertexIndex: Int($0),
                        transform: anchor.transform
                    )
                }
                guard vertices.count == 3 else {
                    continue
                }

                // A caller-supplied bound (targeted pass) drops faces
                // whose centroid falls outside the observation window.
                if let boundingCenter,
                   boundingRadiusMeters > 0
                {
                    let centroid = SIMD3<Float>(
                        (vertices[0].x + vertices[1].x + vertices[2].x) / 3,
                        (vertices[0].y + vertices[1].y + vertices[2].y) / 3,
                        (vertices[0].z + vertices[1].z + vertices[2].z) / 3
                    )
                    if simd_distance(centroid, boundingCenter)
                        > boundingRadiusMeters
                    {
                        continue
                    }
                }

                let evidenceRef =
                    "live-mesh:"
                    + anchor.identifier.uuidString.lowercased()
                    + ":face:"
                    + String(faceIndex)

                for point in vertices {
                    fallbackPoints.append(
                        DerivedObservationPoint(
                            position: DerivedPoint2D(
                                x: Double(point.x),
                                y: Double(point.z)
                            ),
                            evidenceRef: evidenceRef,
                            evidenceKind: .mesh,
                            verticalPositionMeters: Double(point.y)
                        )
                    )
                }

                recordLiveDerivedEdge(
                    anchorID: anchor.identifier,
                    firstIndex: indices[0],
                    firstPoint: vertices[0],
                    secondIndex: indices[1],
                    secondPoint: vertices[1],
                    evidenceRef: evidenceRef,
                    into: &edges
                )
                recordLiveDerivedEdge(
                    anchorID: anchor.identifier,
                    firstIndex: indices[1],
                    firstPoint: vertices[1],
                    secondIndex: indices[2],
                    secondPoint: vertices[2],
                    evidenceRef: evidenceRef,
                    into: &edges
                )
                recordLiveDerivedEdge(
                    anchorID: anchor.identifier,
                    firstIndex: indices[2],
                    firstPoint: vertices[2],
                    secondIndex: indices[0],
                    secondPoint: vertices[0],
                    evidenceRef: evidenceRef,
                    into: &edges
                )
            }
        }

        let boundaryPoints = edges.values
            .filter { $0.count == 1 }
            .flatMap { edge in
                [
                    DerivedObservationPoint(
                        position: DerivedPoint2D(
                            x: Double(edge.firstPoint.x),
                            y: Double(edge.firstPoint.z)
                        ),
                        evidenceRef: edge.evidenceRef,
                        evidenceKind: .mesh,
                        verticalPositionMeters: Double(edge.firstPoint.y)
                    ),
                    DerivedObservationPoint(
                        position: DerivedPoint2D(
                            x: Double(edge.secondPoint.x),
                            y: Double(edge.secondPoint.z)
                        ),
                        evidenceRef: edge.evidenceRef,
                        evidenceKind: .mesh,
                        verticalPositionMeters: Double(edge.secondPoint.y)
                    ),
                ]
            }

        var candidateBoundaryPoints = boundaryPoints
        var candidateFallbackPoints = fallbackPoints
        if let supportPlaneRejection {
            // Same dominant-surface removal as the depth path —
            // without it the window-clipped rim of a desk/shelf/floor
            // reads as a perfect circle anchored at the aim point.
            let planeY = DerivedHorizontalPlaneSegmentation
                .dominantPlaneY(
                    verticalPositions: fallbackPoints.compactMap {
                        $0.verticalPositionMeters
                    }
                )
            candidateBoundaryPoints =
                DerivedHorizontalPlaneSegmentation.pointsAbove(
                    planeY: planeY,
                    marginMeters: supportPlaneRejection.marginMeters,
                    minimumPointCount: 8,
                    in: candidateBoundaryPoints
                ) {
                    $0.verticalPositionMeters
                }
            candidateFallbackPoints =
                DerivedHorizontalPlaneSegmentation.pointsAbove(
                    planeY: planeY,
                    marginMeters: supportPlaneRejection.marginMeters,
                    minimumPointCount:
                        supportPlaneRejection.minimumPointCount,
                    in: candidateFallbackPoints
                ) {
                    $0.verticalPositionMeters
                }
        }

        let sourcePoints =
            candidateBoundaryPoints.count >= 8
            ? candidateBoundaryPoints
            : candidateFallbackPoints
        guard sourcePoints.count
                >= (supportPlaneRejection?.minimumPointCount ?? 1)
        else {
            return nil
        }

        let reduced = reduceLiveDerivedPoints(
            sourcePoints,
            voxelSizeMeters: voxelSizeMeters,
            maxPoints: maxPoints
        )
        guard !reduced.isEmpty else {
            return nil
        }

        return DerivedShapeObservation(
            coordinateSpaceID: context.coordinateSpaceID,
            points: reduced,
            observationStartSeconds: sessionTimestampSeconds,
            observationEndSeconds: sessionTimestampSeconds
        )
    }

    private func liveFloorReferenceY(
        anchors: [ARMeshAnchor],
        maxInspectedFaces: Int,
        maxSamples: Int
    ) -> Double? {
        guard maxInspectedFaces > 0, maxSamples > 0 else {
            return nil
        }

        var inspectedFaces = 0
        var samples: [Double] = []
        samples.reserveCapacity(maxSamples)

        outer: for anchor in anchors {
            let geometry = anchor.geometry
            guard let classifications = geometry.classification,
                  geometry.faces.indexCountPerPrimitive == 3,
                  geometry.faces.bytesPerIndex == 2
                    || geometry.faces.bytesPerIndex == 4,
                  liveMeshElementIsReadable(geometry.faces),
                  liveFloat3SourceIsReadable(geometry.vertices),
                  liveClassificationSourceIsReadable(
                    classifications,
                    minimumCount: geometry.faces.count
                  )
            else {
                continue
            }

            for faceIndex in 0..<geometry.faces.count {
                if inspectedFaces >= maxInspectedFaces
                    || samples.count >= maxSamples
                {
                    break outer
                }
                inspectedFaces += 1

                let pointer = classifications.buffer.contents().advanced(
                    by:
                        classifications.offset
                        + faceIndex * classifications.stride
                )
                let rawClassification = pointer
                    .assumingMemoryBound(to: UInt8.self)
                    .pointee
                guard rawClassification
                        == UInt8(
                            truncatingIfNeeded:
                                ARMeshClassification.floor.rawValue
                        ),
                      let indices = liveMeshFaceIndices(
                        geometry: geometry,
                        faceIndex: faceIndex
                      )
                else {
                    continue
                }

                let vertices = indices.compactMap {
                    liveMeshWorldVertex(
                        geometry: geometry,
                        vertexIndex: Int($0),
                        transform: anchor.transform
                    )
                }
                guard vertices.count == 3 else {
                    continue
                }

                samples.append(
                    Double(
                        (vertices[0].y + vertices[1].y + vertices[2].y)
                        / 3
                    )
                )
            }
        }

        let finite = samples.filter(\.isFinite).sorted()
        guard !finite.isEmpty else {
            return nil
        }
        let middle = finite.count / 2
        if finite.count.isMultiple(of: 2) {
            return (finite[middle - 1] + finite[middle]) / 2
        }
        return finite[middle]
    }

    private func liveGeometrySourceHasReadableRange(
        _ source: ARGeometrySource,
        bytesPerVector: Int
    ) -> Bool {
        guard source.count >= 0,
              source.offset >= 0,
              source.stride >= bytesPerVector,
              bytesPerVector > 0
        else {
            return false
        }

        guard source.count > 0 else {
            return source.offset <= source.buffer.length
        }

        let (strideBytes, strideOverflow) =
            (source.count - 1)
                .multipliedReportingOverflow(by: source.stride)
        guard !strideOverflow else {
            return false
        }
        let (lastStart, offsetOverflow) =
            source.offset.addingReportingOverflow(strideBytes)
        guard !offsetOverflow else {
            return false
        }
        let (requiredBytes, sizeOverflow) =
            lastStart.addingReportingOverflow(bytesPerVector)
        return !sizeOverflow
            && requiredBytes <= source.buffer.length
    }

    private func liveFloat3SourceIsReadable(
        _ source: ARGeometrySource
    ) -> Bool {
        source.format == .float3
            && source.componentsPerVector >= 3
            && liveGeometrySourceHasReadableRange(
                source,
                bytesPerVector: MemoryLayout<Float>.size * 3
            )
    }

    private func liveClassificationSourceIsReadable(
        _ source: ARGeometrySource,
        minimumCount: Int
    ) -> Bool {
        source.format == .uchar
            && source.componentsPerVector >= 1
            && source.count >= minimumCount
            && liveGeometrySourceHasReadableRange(
                source,
                bytesPerVector: MemoryLayout<UInt8>.size
            )
    }

    private func liveMeshElementIsReadable(
        _ element: ARGeometryElement
    ) -> Bool {
        guard element.count >= 0,
              element.indexCountPerPrimitive > 0,
              element.bytesPerIndex > 0
        else {
            return false
        }
        let (indexCount, countOverflow) =
            element.count.multipliedReportingOverflow(
                by: element.indexCountPerPrimitive
            )
        guard !countOverflow else {
            return false
        }
        let (requiredBytes, byteOverflow) =
            indexCount.multipliedReportingOverflow(
                by: element.bytesPerIndex
            )
        return !byteOverflow
            && requiredBytes <= element.buffer.length
    }

    private func liveMeshFaceIndices(
        geometry: ARMeshGeometry,
        faceIndex: Int
    ) -> [UInt32]? {
        let faces = geometry.faces
        guard faceIndex >= 0,
              faceIndex < faces.count,
              faces.indexCountPerPrimitive == 3,
              faces.bytesPerIndex == 2
                || faces.bytesPerIndex == 4,
              liveMeshElementIsReadable(faces)
        else {
            return nil
        }

        var result: [UInt32] = []
        result.reserveCapacity(3)
        for localIndex in 0..<3 {
            let flatIndex = faceIndex * 3 + localIndex
            let pointer = faces.buffer.contents().advanced(
                by: flatIndex * faces.bytesPerIndex
            )
            let bytes = pointer.assumingMemoryBound(to: UInt8.self)
            if faces.bytesPerIndex == 2 {
                result.append(
                    UInt32(bytes[0])
                    | (UInt32(bytes[1]) << 8)
                )
            } else {
                result.append(
                    UInt32(bytes[0])
                    | (UInt32(bytes[1]) << 8)
                    | (UInt32(bytes[2]) << 16)
                    | (UInt32(bytes[3]) << 24)
                )
            }
        }
        return result
    }

    /// Callers validate `geometry.vertices` once per anchor via
    /// `liveFloat3SourceIsReadable` before entering their face
    /// loops; this hot path only bounds-checks the index since
    /// reticle polling walks every face of every anchor per frame.
    private func liveMeshWorldVertex(
        geometry: ARMeshGeometry,
        vertexIndex: Int,
        transform: simd_float4x4
    ) -> SIMD3<Float>? {
        let source = geometry.vertices
        guard vertexIndex >= 0,
              vertexIndex < source.count
        else {
            return nil
        }

        let pointer = source.buffer.contents().advanced(
            by: source.offset + vertexIndex * source.stride
        )
        let values = pointer.assumingMemoryBound(to: Float.self)
        let local = SIMD4<Float>(
            values[0],
            values[1],
            values[2],
            1
        )
        let world = transform * local
        guard world.x.isFinite,
              world.y.isFinite,
              world.z.isFinite
        else {
            return nil
        }
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    private func recordLiveDerivedEdge(
        anchorID: UUID,
        firstIndex: UInt32,
        firstPoint: SIMD3<Float>,
        secondIndex: UInt32,
        secondPoint: SIMD3<Float>,
        evidenceRef: String,
        into edges: inout [
            LiveDerivedMeshEdgeKey:
                LiveDerivedMeshEdgeRecord
        ]
    ) {
        let lowIndex = min(firstIndex, secondIndex)
        let highIndex = max(firstIndex, secondIndex)
        let key = LiveDerivedMeshEdgeKey(
            anchorID: anchorID,
            lowVertexIndex: lowIndex,
            highVertexIndex: highIndex
        )

        if var existing = edges[key] {
            existing.count += 1
            edges[key] = existing
            return
        }

        let firstIsLow = firstIndex == lowIndex
        edges[key] = LiveDerivedMeshEdgeRecord(
            count: 1,
            firstPoint: firstIsLow ? firstPoint : secondPoint,
            secondPoint: firstIsLow ? secondPoint : firstPoint,
            evidenceRef: evidenceRef
        )
    }

    private func reduceLiveDerivedPoints(
        _ points: [DerivedObservationPoint],
        voxelSizeMeters: Double,
        maxPoints: Int
    ) -> [DerivedObservationPoint] {
        var cells: [
            LiveDerivedVoxelKey:
                DerivedObservationPoint
        ] = [:]

        for point in points.sorted(by: {
            if $0.position.x != $1.position.x {
                return $0.position.x < $1.position.x
            }
            if $0.position.y != $1.position.y {
                return $0.position.y < $1.position.y
            }
            if $0.verticalPositionMeters != $1.verticalPositionMeters {
                return ($0.verticalPositionMeters ?? -.infinity)
                    < ($1.verticalPositionMeters ?? -.infinity)
            }
            return $0.evidenceRef < $1.evidenceRef
        }) {
            let key = LiveDerivedVoxelKey(
                x: floorToIntClamped(
                    point.position.x / voxelSizeMeters
                ),
                z: floorToIntClamped(
                    point.position.y / voxelSizeMeters
                ),
                y: point.verticalPositionMeters.map {
                    floorToIntClamped($0 / voxelSizeMeters)
                } ?? Int.min
            )
            if cells[key] == nil {
                cells[key] = point
            }
        }

        let reduced = cells.values.sorted {
            if $0.position.x != $1.position.x {
                return $0.position.x < $1.position.x
            }
            if $0.position.y != $1.position.y {
                return $0.position.y < $1.position.y
            }
            if $0.verticalPositionMeters != $1.verticalPositionMeters {
                return ($0.verticalPositionMeters ?? -.infinity)
                    < ($1.verticalPositionMeters ?? -.infinity)
            }
            return $0.evidenceRef < $1.evidenceRef
        }

        guard reduced.count > maxPoints else {
            return reduced
        }

        let stride = Double(reduced.count) / Double(maxPoints)
        return (0..<maxPoints).map {
            reduced[Int(Double($0) * stride)]
        }
    }

    private func trackingQualityEvent(
        from frame: ARFrame
    ) -> TrackingQualityEvent {
        Self.trackingQualityEvent(
            camera: frame.camera,
            sessionTimestampSeconds: frame.timestamp
        )
    }

    fileprivate static func trackingQualityEvent(
        camera: ARCamera,
        sessionTimestampSeconds: Double
    ) -> TrackingQualityEvent {
        switch camera.trackingState {
        case .normal:
            return TrackingQualityEvent(
                sessionTimestampSeconds: sessionTimestampSeconds,
                state: .normal
            )
        case .notAvailable:
            return TrackingQualityEvent(
                sessionTimestampSeconds: sessionTimestampSeconds,
                state: .unavailable,
                reason: "arkit_not_available"
            )
        case let .limited(reason):
            return TrackingQualityEvent(
                sessionTimestampSeconds: sessionTimestampSeconds,
                state: .limited,
                reason: trackingReasonToken(reason)
            )
        }
    }

    fileprivate static func trackingReasonToken(
        _ reason: ARCamera.TrackingState.Reason
    ) -> String {
        switch reason {
        case .initializing:
            return "initializing"
        case .excessiveMotion:
            return "excessive_motion"
        case .insufficientFeatures:
            return "insufficient_features"
        case .relocalizing:
            return "relocalizing"
        @unknown default:
            return "unknown"
        }
    }

    private func snapshotMeshAnchors(
        from frame: ARFrame
    ) throws -> [MeshAnchorSnapshot] {
        let anchors = frame.anchors
            .compactMap { $0 as? ARMeshAnchor }
            .sorted {
                $0.identifier.uuidString.lowercased()
                    < $1.identifier.uuidString.lowercased()
            }

        return try anchors.map { anchor in
            try ARMeshSnapshotAdapter.snapshot(
                anchor: anchor,
                captureSessionID: context.captureSessionID,
                coordinateSpaceID: context.coordinateSpaceID,
                sessionTimestampSeconds: frame.timestamp
            )
        }
    }

    @discardableResult
    public func registerSpatialDiscontinuity(
        reason: CoordinateDiscontinuityReason,
        sessionTimestampSeconds: Double? = nil
    ) -> CoordinateSpaceID {
        context.registerDiscontinuity(
            reason: reason,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
    }
private struct LiveDerivedMeshEdgeKey: Hashable {
    let anchorID: UUID
    let lowVertexIndex: UInt32
    let highVertexIndex: UInt32
}

private struct LiveDerivedMeshEdgeRecord {
    var count: Int
    let firstPoint: SIMD3<Float>
    let secondPoint: SIMD3<Float>
    let evidenceRef: String
}

private struct LiveDerivedVoxelKey: Hashable {
    let x: Int
    let z: Int
    let y: Int
}

}

/// Target-aware annotation placement (#214/#246). The probe classifies
/// what the camera's center ray is hitting — existing/estimated plane,
/// live ARMesh triangle, or a persisted RoomPlan object — so the
/// reticle can name the target class before capture; the capture
/// then resolves the same candidates and returns bounded provenance.
extension SharedARSessionController {
    /// Bounded capture result for a targeted placement. `target` names
    /// the resolved target class; the method-specific fields are
    /// populated only when that class won.
    public struct TargetedPlacementCapture: Sendable {
        public let target: PlacementProbeTarget
        public let positionWorld: Float3
        public let hitDistanceMeters: Double?
        /// Mesh hit authority (#246): exact anchor ID + hit position.
        public let meshAnchorID: UUID?
        /// RoomPlan binding authority (#246): exact persisted object ID.
        public let roomPlanObjectID: String?
        public let roomPlanObjectCategory: String?
        /// Plane-raycast hit provenance (method `.raycast`).
        public let raycastProvenance: RaycastPlacementProvenance?
        /// Same-frame pixel/depth/pose artifacts to persist as the
        /// placement evidence frame.
        public let frameArtifacts: CapturedFrameSnapshot

        public init(
            target: PlacementProbeTarget,
            positionWorld: Float3,
            hitDistanceMeters: Double? = nil,
            meshAnchorID: UUID? = nil,
            roomPlanObjectID: String? = nil,
            roomPlanObjectCategory: String? = nil,
            raycastProvenance: RaycastPlacementProvenance? = nil,
            frameArtifacts: CapturedFrameSnapshot
        ) {
            self.target = target
            self.positionWorld = positionWorld
            self.hitDistanceMeters = hitDistanceMeters
            self.meshAnchorID = meshAnchorID
            self.roomPlanObjectID = roomPlanObjectID
            self.roomPlanObjectCategory = roomPlanObjectCategory
            self.raycastProvenance = raycastProvenance
            self.frameArtifacts = frameArtifacts
        }
    }

    /// The live camera center ray in capture world coordinates; nil
    /// while no AR frame is available.
    public func centerCameraRay()
        -> (origin: SIMD3<Float>, direction: SIMD3<Float>)?
    {
        guard let frame = arSession.currentFrame else {
            return nil
        }
        let camera = frame.camera.transform
        return (
            SIMD3<Float>(
                camera.columns.3.x,
                camera.columns.3.y,
                camera.columns.3.z
            ),
            SIMD3<Float>(
                -camera.columns.2.x,
                -camera.columns.2.y,
                -camera.columns.2.z
            )
        )
    }

    /// Camera yaw in degrees for the live heading arrow (#214): 0 = -Z
    /// world forward, +90 = +X — the same convention as
    /// `snapshotHorizontalCameraHeading`. nil while no frame exists.
    public func currentCameraHeadingDegrees() -> Float? {
        guard let frame = arSession.currentFrame else {
            return nil
        }
        let x = -frame.camera.transform.columns.2.x
        let z = -frame.camera.transform.columns.2.z
        guard (x * x + z * z) > 1e-6 else {
            return nil
        }
        return atan2(x, -z) * 180 / .pi
    }

    /// Live center-target probe (#214): classifies the strongest hit
    /// for the current frame's center ray across planes, live mesh and
    /// supplied RoomPlan objects. Cheap and side-effect-free; intended
    /// for repeated polling while the reticle is visible.
    public func probeCenterPlacementTarget(
        roomPlanObjects: [RoomPlanBindableObject],
        maxDistanceMeters: Float = 15
    ) -> AnnotationPlacementProbe {
        guard let ray = centerCameraRay() else {
            return .unavailable
        }

        guard let spatialRay = try? SpatialRay(
            origin: Float3(
                ray.origin.x, ray.origin.y, ray.origin.z
            ),
            direction: Float3(
                ray.direction.x, ray.direction.y, ray.direction.z
            )
        ) else {
            return .unavailable
        }

        var candidates = PlacementProbeCandidates()
        candidates.meshHit = liveMeshRaycastHit(
            origin: ray.origin,
            direction: ray.direction,
            maxDistanceMeters: maxDistanceMeters
        )
        candidates.roomPlanHit = RoomPlanObjectRaycast.nearestHit(
            ray: spatialRay,
            objects: roomPlanObjects,
            maxDistanceMeters: maxDistanceMeters
        )
        candidates.planeHit = planeRaycastHit(
            origin: ray.origin,
            direction: ray.direction,
            maxDistanceMeters: maxDistanceMeters
        )?.probe
        return PlacementProbeResolver.resolve(
            candidates: candidates,
            preference: .automatic
        )
    }

    /// A plane hit bundled with its full provenance; `probe` is what
    /// the reticle consumes, `provenance` what the capture persists.
    private struct PlaneRaycastHit: Sendable {
        let probe: PlaneProbeHit
        let provenance: RaycastPlacementProvenance?

        var target: PlacementProbeTarget { probe.target }
        var distanceMeters: Float { probe.distanceMeters }
        var positionWorld: Float3 { probe.positionWorld }
    }

    /// Captures a targeted placement for the given preference. An
    /// explicit mesh/object/plane request never falls through to a
    /// different target class (#246): it returns a `TargetedPlacement
    /// Capture` for exactly that class or throws `raycastMiss`.
    /// `.automatic` resolves the nearest of all candidates with the
    /// deterministic specificity order for ties.
    public func snapshotTargetedPlacement(
        preferring preference: PlacementTargetPreference,
        roomPlanObjects: [RoomPlanBindableObject],
        depthSelection: FrameDepthSelection = .discrete,
        maxDistanceMeters: Float = 15
    ) throws -> TargetedPlacementCapture {
        guard let frame = arSession.currentFrame else {
            throw PlatformCaptureError.currentFrameUnavailable
        }
        guard let ray = centerCameraRay() else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        guard let spatialRay = try? SpatialRay(
            origin: Float3(
                ray.origin.x, ray.origin.y, ray.origin.z
            ),
            direction: Float3(
                ray.direction.x, ray.direction.y, ray.direction.z
            )
        ) else {
            throw PlatformCaptureError.currentFrameUnavailable
        }

        var candidates = PlacementProbeCandidates()
        candidates.meshHit = liveMeshRaycastHit(
            origin: ray.origin,
            direction: ray.direction,
            maxDistanceMeters: maxDistanceMeters
        )
        candidates.roomPlanHit = RoomPlanObjectRaycast.nearestHit(
            ray: spatialRay,
            objects: roomPlanObjects,
            maxDistanceMeters: maxDistanceMeters
        )
        let planeHit = planeRaycastHit(
            origin: ray.origin,
            direction: ray.direction,
            maxDistanceMeters: maxDistanceMeters
        )
        candidates.planeHit = planeHit?.probe

        // The resolver decides which class wins; the full plane
        // provenance survives separately for the capture record.
        let planeProvenance = planeHit?.provenance

        let probe = PlacementProbeResolver.resolve(
            candidates: candidates,
            preference: preference
        )
        guard probe.status == .hit,
              let position = probe.positionWorld,
              let target = probe.target
        else {
            throw PlatformCaptureError.raycastMiss
        }

        let artifacts = try ARFrameArtifactAdapter.snapshot(
            frame: frame,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            depthSelection: depthSelection
        )

        switch target {
        case .mesh:
            guard let hit = candidates.meshHit else {
                throw PlatformCaptureError.raycastMiss
            }
            return TargetedPlacementCapture(
                target: .mesh,
                positionWorld: position,
                hitDistanceMeters: Double(hit.distanceMeters),
                meshAnchorID: hit.meshAnchorID,
                frameArtifacts: artifacts
            )
        case .roomPlanObject:
            guard let hit = candidates.roomPlanHit else {
                throw PlatformCaptureError.raycastMiss
            }
            return TargetedPlacementCapture(
                target: .roomPlanObject,
                positionWorld: position,
                hitDistanceMeters: Double(hit.distanceMeters),
                roomPlanObjectID: hit.object.identifier,
                roomPlanObjectCategory: hit.object.category,
                frameArtifacts: artifacts
            )
        case .existingPlaneGeometry, .estimatedPlane:
            guard let planeHit = candidates.planeHit else {
                throw PlatformCaptureError.raycastMiss
            }
            return TargetedPlacementCapture(
                target: planeHit.target,
                positionWorld: position,
                hitDistanceMeters: Double(planeHit.distanceMeters),
                raycastProvenance: planeProvenance,
                frameArtifacts: artifacts
            )
        }
    }

    /// Decodes the persisted processed `CapturedRoom` payload into
    /// bindable objects/surfaces for `roomplan_binding` placement
    /// (#246). iOS-only because `CapturedRoom` decoding is a RoomPlan
    /// API. `nonisolated`: pure data decoding — callers run it off
    /// the main actor while loading Review context.
    public nonisolated static func roomPlanBindableObjects(
        fromProcessedData data: Data
    ) -> [RoomPlanBindableObject] {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy =
            .convertFromString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
        guard let room = try? decoder.decode(
            CapturedRoom.self,
            from: data
        ) else {
            return []
        }
        var results: [RoomPlanBindableObject] = []
        for object in room.objects {
            guard let transform = try? matrix4x4F(
                object.transform
            ) else {
                continue
            }
            results.append(
                RoomPlanBindableObject(
                    identifier: object.identifier
                        .uuidString.lowercased(),
                    category: String(describing: object.category),
                    isSurface: false,
                    worldFromObject: transform,
                    dimensionsMeters: Float3(
                        object.dimensions.x,
                        object.dimensions.y,
                        object.dimensions.z
                    )
                )
            )
        }
        for surface in room.walls + room.windows
            + room.doors + room.openings + room.floors
        {
            guard let transform = try? matrix4x4F(
                surface.transform
            ) else {
                continue
            }
            results.append(
                RoomPlanBindableObject(
                    identifier: surface.identifier
                        .uuidString.lowercased(),
                    category: String(describing: surface.category),
                    isSurface: true,
                    worldFromObject: transform,
                    dimensionsMeters: Float3(
                        surface.dimensions.x,
                        surface.dimensions.y,
                        surface.dimensions.z
                    )
                )
            )
        }
        return results
    }

    /// Ray-vs-live-ARMesh hit over the session's current mesh anchors
    /// (#246). Uses the same vertex/index readers as the derived-shape
    /// pipeline; the hit returns the exact anchor ID for
    /// `mesh_hit_test` provenance.
    private func liveMeshRaycastHit(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        maxDistanceMeters: Float
    ) -> MeshRaycastHit? {
        guard let frame = arSession.currentFrame else {
            return nil
        }

        var best: MeshRaycastHit?
        for anchor in frame.anchors.compactMap({
            $0 as? ARMeshAnchor
        }) {
            let geometry = anchor.geometry
            guard geometry.faces.indexCountPerPrimitive == 3,
                  geometry.faces.bytesPerIndex == 2
                      || geometry.faces.bytesPerIndex == 4,
                  liveMeshElementIsReadable(geometry.faces),
                  liveFloat3SourceIsReadable(geometry.vertices)
            else {
                continue
            }

            for faceIndex in 0..<geometry.faces.count {
                guard let indices = liveMeshFaceIndices(
                    geometry: geometry,
                    faceIndex: faceIndex
                ) else {
                    continue
                }
                var triangle: [SIMD3<Float>] = []
                triangle.reserveCapacity(3)
                for vertexIndex in indices {
                    guard let vertex = liveMeshWorldVertex(
                        geometry: geometry,
                        vertexIndex: Int(vertexIndex),
                        transform: anchor.transform
                    ) else {
                        break
                    }
                    triangle.append(vertex)
                }
                guard triangle.count == 3 else {
                    continue
                }

                guard let hitDistance = simdRayTriangleIntersection(
                    origin: origin,
                    direction: direction,
                    a: triangle[0],
                    b: triangle[1],
                    c: triangle[2],
                    maxDistance: maxDistanceMeters
                ) else {
                    continue
                }

                if let best,
                   hitDistance >= best.distanceMeters
                {
                    continue
                }
                best = MeshRaycastHit(
                    meshAnchorID: anchor.identifier,
                    distanceMeters: hitDistance,
                    positionWorld: Float3(
                        origin.x + direction.x * hitDistance,
                        origin.y + direction.y * hitDistance,
                        origin.z + direction.z * hitDistance
                    ),
                    triangleIndex: faceIndex
                )
            }
        }
        return best
    }

    /// One plane-raycast probe: existing-plane geometry first, then the
    /// estimated-plane fallback — each carries its own target token so
    /// the lower-specificity fallback is explicit, never silent.
    private func planeRaycastHit(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        maxDistanceMeters: Float
    ) -> PlaneRaycastHit? {
        for (target, probeTarget) in [
            (ARRaycastQuery.Target.existingPlaneGeometry,
             PlacementProbeTarget.existingPlaneGeometry),
            (.estimatedPlane, .estimatedPlane),
        ] {
            let query = ARRaycastQuery(
                origin: origin,
                direction: direction,
                allowing: target,
                alignment: .any
            )
            guard let hit = arSession.raycast(query).first
            else {
                continue
            }
            let position = hit.worldTransform.columns.3
            let distance = simd_distance(
                origin,
                SIMD3<Float>(position.x, position.y, position.z)
            )
            guard distance <= maxDistanceMeters else {
                continue
            }
            let provenance = try? RaycastPlacementProvenance(
                target: Self.raycastTargetToken(target),
                targetAlignment: Self.raycastAlignmentToken(
                    hit.targetAlignment
                ),
                hitDistanceMeters: Double(distance),
                hitWorldTransform: Self.matrix4x4F(
                    hit.worldTransform
                ),
                hitAnchorIdentifier: hit.anchor?.identifier,
                hitAnchorType: hit.anchor.map {
                    String(describing: type(of: $0))
                }
            )
            return PlaneRaycastHit(
                probe: PlaneProbeHit(
                    target: probeTarget,
                    distanceMeters: distance,
                    positionWorld: Float3(
                        position.x, position.y, position.z
                    )
                ),
                provenance: provenance
            )
        }
        return nil
    }
}

/// Non-culling Möller–Trumbore on simd vectors; returns the distance
/// along `direction` or nil. Kept local to this file so the platform
/// raycast never allocates Core structs per triangle.
private func simdRayTriangleIntersection(
    origin: SIMD3<Float>,
    direction: SIMD3<Float>,
    a: SIMD3<Float>,
    b: SIMD3<Float>,
    c: SIMD3<Float>,
    maxDistance: Float
) -> Float? {
    let edgeAB = b - a
    let edgeAC = c - a
    let p = simd_cross(direction, edgeAC)
    let determinant = simd_dot(edgeAB, p)
    guard abs(determinant) > 1e-8 else {
        return nil
    }
    let inverse = 1 / determinant
    let s = origin - a
    let u = simd_dot(s, p) * inverse
    guard u >= 0, u <= 1 else {
        return nil
    }
    let q = simd_cross(s, edgeAB)
    let v = simd_dot(direction, q) * inverse
    guard v >= 0, u + v <= 1 else {
        return nil
    }
    let t = simd_dot(edgeAC, q) * inverse
    guard t.isFinite, t >= 0, t <= maxDistance else {
        return nil
    }
    return t
}

#endif
