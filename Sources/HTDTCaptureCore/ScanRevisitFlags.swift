import Foundation

/// Operator revisit flags ("scan bookmarks") — issue #325.
///
/// During capture the operator can drop a single-tap flag on the area
/// currently in view when something needs mandatory attention later —
/// a suspicious corner, an opening that may not have been captured, a
/// reflective surface, an object worth measuring. Flagging never
/// interrupts the scan and never creates an annotation: a flag is
/// advisory intent, persisted into the working set so Review must
/// surface every unresolved one. Resolving a flag links or creates
/// real authority (annotation, measurement, targeted rescan) rather
/// than mutating the flag into evidence.

/// Quick category picked after flagging, only once the operator is
/// safe/stationary. Optional — a flag with no category still routes to
/// Review.
public enum ScanRevisitFlagCategory:
    String,
    Codable,
    Sendable,
    CaseIterable
{
    /// Geometry looks wrong or missing (walls, surfaces).
    case geometry
    /// A door/window/opening may not have been captured (#231 route).
    case opening
    /// Reflective or transparent surface that may have fooled sensors.
    case reflectiveTransparent = "reflective_transparent"
    /// An object needing closer detail capture (#250 route).
    case objectDetail = "object_detail"
    /// A spot needing a measurement (#298 route).
    case measurement
    /// Equipment/furniture to identify in the catalog (#314 route).
    case equipment
    /// Anything else worth a human look.
    case other
}

/// Where Review routes a flag for remediation. Derived from the
/// category — it is a suggestion for which remediation workflow to
/// open, never a completed action.
public enum ScanRevisitRemediation: String, Codable, Sendable {
    /// Re-observe the region / targeted rescan (#231).
    case targetedRescan = "targeted_rescan"
    /// Annotate or re-orbit the object (#250).
    case annotation
    /// Verify or re-capture at another angle (#256).
    case reobserve
    /// Create a measurement (#298).
    case measurement
    /// Match equipment against the catalog (#314).
    case equipmentNote = "equipment_note"
    /// No specific workflow — general review.
    case generalReview = "general_review"
}

public extension ScanRevisitFlagCategory {
    var suggestedRemediation: ScanRevisitRemediation {
        switch self {
        case .geometry, .opening:
            return .targetedRescan
        case .reflectiveTransparent:
            return .reobserve
        case .objectDetail:
            return .annotation
        case .measurement:
            return .measurement
        case .equipment:
            return .equipmentNote
        case .other:
            return .generalReview
        }
    }
}

/// Lifecycle of a flag. `unavailable` means the flag's location
/// evidence can no longer be trusted for review (e.g. a coordinate
/// discontinuity invalidated the referenced space) — it is shown
/// distinctly rather than counted resolved.
public enum ScanRevisitFlagStatus: String, Codable, Sendable {
    case unresolved
    case resolved
    case skipped
    case unavailable
}

/// A world-space position/direction snapshot attached to a flag. All
/// values are finite meters in the capture coordinate space named by
/// `coordinateSpaceID`.
public struct ScanRevisitFlagVector: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

/// What resolving a flag produced. The flag itself never becomes an
/// annotation: `authorityRef` is the reference the operator's
/// resolution created or linked (annotation id, measurement id,
/// targeted-rescan pass id, or a free-form path/ref).
public struct ScanRevisitFlagResolution: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable {
        /// Linked to real authority (annotation/measurement/rescan).
        case linkedAuthority = "linked_authority"
        /// Reviewed and intentionally closed without new authority.
        case acknowledged
        /// Could not be reviewed (stale space, missing evidence).
        case markedUnavailable = "marked_unavailable"
    }

    public let outcome: Outcome
    /// Reference to the created/linked authority, when the outcome
    /// produced one (e.g. an annotation UUID or a bundle path).
    public let authorityRef: String?
    /// Session-clock seconds when the resolution was recorded, or nil
    /// when resolved during post-scan Review.
    public let sessionTimestampSeconds: Double?

    public init(
        outcome: Outcome,
        authorityRef: String? = nil,
        sessionTimestampSeconds: Double? = nil
    ) {
        self.outcome = outcome
        self.authorityRef = authorityRef
        self.sessionTimestampSeconds = sessionTimestampSeconds
    }
}

public struct ScanRevisitFlag:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    /// Stable identifier of the flag (UUID string).
    public let flagID: String
    /// Capture coordinate space the position fields are expressed in.
    public let coordinateSpaceID: CoordinateSpaceID
    /// Capture session that created the flag.
    public let captureSessionID: CaptureSessionID
    /// Approximate flagged point: the center-raycast target when one
    /// was valid at flag time, else the camera position.
    public let targetPointWorld: ScanRevisitFlagVector?
    /// True when `targetPointWorld` came from a real raycast hit rather
    /// than a camera-position fallback.
    public let targetFromRaycast: Bool
    /// Camera pose at flag time — where the operator stood.
    public let cameraPositionWorld: ScanRevisitFlagVector?
    /// Camera forward direction at flag time — what they looked at.
    public let cameraForwardWorld: ScanRevisitFlagVector?
    /// Start-relative coverage cell `"x,z"` containing the target, so
    /// Review can focus the coverage map cell even when world position
    /// precision is poor.
    public let coverageCell: String?
    public let category: ScanRevisitFlagCategory?
    /// Short free-form note, bounded (`ScanRevisitFlagStore` truncates).
    public let note: String?
    /// Session-clock seconds when the flag was dropped.
    public let createdSessionTimestampSeconds: Double
    public private(set) var status: ScanRevisitFlagStatus
    public private(set) var resolution: ScanRevisitFlagResolution?

    public var id: String { flagID }

    public init(
        flagID: String = UUID().uuidString.lowercased(),
        coordinateSpaceID: CoordinateSpaceID,
        captureSessionID: CaptureSessionID,
        targetPointWorld: ScanRevisitFlagVector?,
        targetFromRaycast: Bool,
        cameraPositionWorld: ScanRevisitFlagVector?,
        cameraForwardWorld: ScanRevisitFlagVector?,
        coverageCell: String?,
        category: ScanRevisitFlagCategory?,
        note: String?,
        createdSessionTimestampSeconds: Double,
        status: ScanRevisitFlagStatus = .unresolved,
        resolution: ScanRevisitFlagResolution? = nil
    ) {
        self.flagID = flagID
        self.coordinateSpaceID = coordinateSpaceID
        self.captureSessionID = captureSessionID
        self.targetPointWorld = targetPointWorld
        self.targetFromRaycast = targetFromRaycast
        self.cameraPositionWorld = cameraPositionWorld
        self.cameraForwardWorld = cameraForwardWorld
        self.coverageCell = coverageCell
        self.category = category
        self.note = note
        self.createdSessionTimestampSeconds =
            createdSessionTimestampSeconds.isFinite
            ? max(0, createdSessionTimestampSeconds)
            : 0
        self.status = status
        self.resolution = resolution
    }

    /// A one-line location summary for Review rows: the coverage cell
    /// when known, else whether a raycast/camera position exists.
    public var locationSummary: String {
        if let coverageCell {
            return "cell \(coverageCell)"
        }
        if targetPointWorld != nil {
            return targetFromRaycast ? "raycast target" : "camera position"
        }
        return "location unavailable"
    }

    public var suggestedRemediation: ScanRevisitRemediation {
        category?.suggestedRemediation ?? .generalReview
    }

    /// Records a resolution without mutating the flag's observed
    /// evidence — the flag keeps its creation-time geometry and gains
    /// an outcome plus an authority link.
    public mutating func resolve(
        outcome: ScanRevisitFlagResolution.Outcome,
        authorityRef: String? = nil,
        sessionTimestampSeconds: Double? = nil
    ) {
        resolution = ScanRevisitFlagResolution(
            outcome: outcome,
            authorityRef: authorityRef,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
        switch outcome {
        case .linkedAuthority:
            status = .resolved
        case .acknowledged:
            status = .skipped
        case .markedUnavailable:
            status = .unavailable
        }
    }

    /// Resets back to unresolved (e.g. an accidental skip).
    public mutating func reopen() {
        status = .unresolved
        resolution = nil
    }
}

/// Persisted working-set document listing every revisit flag of the
/// capture (#325). Written by the host through the supplemental
/// document path so the finalized bundle carries it as a derived
/// `capture_app_derived` payload at `session/revisit-flags.json`.
/// It asserts no geometry authority — flags are advisory pointers
/// Review must surface.
public struct CaptureRevisitFlagDocument: Codable, Sendable, Equatable {
    public static let path = "session/revisit-flags.json"
    /// Upper bound on flags per capture; beyond this the oldest
    /// unresolved flag stays and the store refuses new appends.
    public static let maxFlagCount = 64
    /// Upper bound on the free-form note length.
    public static let maxNoteLength = 140

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let flags: [ScanRevisitFlag]

    public init(
        captureRevisionID: CaptureRevisionID,
        flags: [ScanRevisitFlag]
    ) {
        self.schema = "htdt.capture.revisit_flags"
        self.schemaVersion = "1.0.0"
        self.captureRevisionID = captureRevisionID
        self.flags = flags
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case flags
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// In-memory flag list the host coordinator owns during scanning.
/// Append-only during capture; resolution happens in Review. Bounded
/// so a runaway tap loop cannot grow the working set document
/// without limit.
public struct CaptureRevisitFlagStore: Sendable, Equatable {
    public private(set) var flags: [ScanRevisitFlag] = []
    public let maxFlagCount: Int

    public init(
        maxFlagCount: Int = CaptureRevisitFlagDocument.maxFlagCount
    ) {
        precondition(maxFlagCount > 0)
        self.maxFlagCount = maxFlagCount
    }

    public var unresolvedFlags: [ScanRevisitFlag] {
        flags.filter { $0.status == .unresolved }
    }

    /// True when the flag cap has been reached — the host should keep
    /// the "flag" affordance but surface that no more can be added.
    public var isFull: Bool {
        flags.count >= maxFlagCount
    }

    /// Appends a flag. Returns false when the store is full; the flag
    /// is not recorded in that case so the caller can surface a
    /// distinct "flag limit reached" state.
    @discardableResult
    public mutating func add(_ flag: ScanRevisitFlag) -> Bool {
        guard !isFull else { return false }
        flags.append(flag.withTrimmedNote())
        return true
    }

    /// Attaches or replaces the optional details (category/note) — the
    /// sheet offered only once the operator is safe/stationary.
    @discardableResult
    public mutating func updateDetails(
        flagID: String,
        category: ScanRevisitFlagCategory?,
        note: String?
    ) -> Bool {
        guard let index = flags.firstIndex(where: {
            $0.flagID == flagID
        }) else {
            return false
        }
        var flag = flags[index]
        flag = ScanRevisitFlag(
            flagID: flag.flagID,
            coordinateSpaceID: flag.coordinateSpaceID,
            captureSessionID: flag.captureSessionID,
            targetPointWorld: flag.targetPointWorld,
            targetFromRaycast: flag.targetFromRaycast,
            cameraPositionWorld: flag.cameraPositionWorld,
            cameraForwardWorld: flag.cameraForwardWorld,
            coverageCell: flag.coverageCell,
            category: category,
            note: note,
            createdSessionTimestampSeconds:
                flag.createdSessionTimestampSeconds,
            status: flag.status,
            resolution: flag.resolution
        )
        flags[index] = flag.withTrimmedNote()
        return true
    }

    /// Resolves a flag during Review: links authority, acknowledges, or
    /// marks unavailable. Never mutates the flag's captured geometry.
    @discardableResult
    public mutating func resolve(
        flagID: String,
        outcome: ScanRevisitFlagResolution.Outcome,
        authorityRef: String? = nil,
        sessionTimestampSeconds: Double? = nil
    ) -> Bool {
        guard let index = flags.firstIndex(where: {
            $0.flagID == flagID
        }) else {
            return false
        }
        flags[index].resolve(
            outcome: outcome,
            authorityRef: authorityRef,
            sessionTimestampSeconds: sessionTimestampSeconds
        )
        return true
    }

    @discardableResult
    public mutating func reopen(flagID: String) -> Bool {
        guard let index = flags.firstIndex(where: {
            $0.flagID == flagID
        }) else {
            return false
        }
        flags[index].reopen()
        return true
    }

    /// Flags whose coordinate space no longer matches the current one
    /// after a coordinate discontinuity — they stay listed, marked
    /// unavailable rather than silently resolved.
    public mutating func markFlagsUnavailable(
        notIn coordinateSpaceID: CoordinateSpaceID
    ) {
        for index in flags.indices
        where flags[index].status == .unresolved
            && flags[index].coordinateSpaceID != coordinateSpaceID
        {
            flags[index].resolve(outcome: .markedUnavailable)
        }
    }

    public func document(
        captureRevisionID: CaptureRevisionID
    ) -> CaptureRevisitFlagDocument {
        CaptureRevisitFlagDocument(
            captureRevisionID: captureRevisionID,
            flags: flags
        )
    }
}

private extension ScanRevisitFlag {
    func withTrimmedNote() -> ScanRevisitFlag {
        guard let note,
              note.count
                > CaptureRevisitFlagDocument.maxNoteLength
        else {
            return self
        }
        return ScanRevisitFlag(
            flagID: flagID,
            coordinateSpaceID: coordinateSpaceID,
            captureSessionID: captureSessionID,
            targetPointWorld: targetPointWorld,
            targetFromRaycast: targetFromRaycast,
            cameraPositionWorld: cameraPositionWorld,
            cameraForwardWorld: cameraForwardWorld,
            coverageCell: coverageCell,
            category: category,
            note: String(
                note.prefix(CaptureRevisitFlagDocument.maxNoteLength)
            ),
            createdSessionTimestampSeconds:
                createdSessionTimestampSeconds,
            status: status,
            resolution: resolution
        )
    }
}
