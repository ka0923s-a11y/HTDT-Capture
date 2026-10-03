import Foundation

/// The depth evidence a contact-sheet tile carries (issue bolph71656-ai/HTDT-Capture#376) — a
/// summary of the committed descriptor's depth authority, never the
/// payload bytes themselves.
public enum ContactSheetDepthSummary: Sendable, Equatable {
    /// No depth was requested or recorded for this frame.
    case none
    /// `captured_scene_depth` — discrete-session depth observation.
    case discrete(hasConfidence: Bool)
    /// `captured_smoothed_scene_depth` — smoothed depth observation.
    case smoothed(hasConfidence: Bool)
    /// Depth was requested but unavailable at capture time.
    case unavailable

    public var hasDepth: Bool {
        switch self {
        case .discrete, .smoothed:
            return true
        case .none, .unavailable:
            return false
        }
    }

    public var hasConfidence: Bool {
        switch self {
        case .discrete(let confidence), .smoothed(let confidence):
            return confidence
        case .none, .unavailable:
            return false
        }
    }
}

/// One contact-sheet tile (issue bolph71656-ai/HTDT-Capture#376): the committed evidence-frame
/// item plus the pre-finalization review metadata — pose heading,
/// depth/confidence summary, usability warnings, reference counts and
/// privacy flag — computed from the same declared payload set the
/// Review workspace reads.
public struct EvidenceContactSheetItem: Sendable, Equatable, Identifiable {
    public let item: ReviewEvidenceItem
    /// Index in capture-time order (stable sort by
    /// `session_timestamp_seconds`, then frame id).
    public let captureOrder: Int
    /// Camera yaw in degrees (0 = the -Z axis, increasing clockwise
    /// viewed from +Y) extracted from `T_world_from_camera`; nil when
    /// the descriptor is unavailable. Display-only — the pose
    /// authority stays the committed descriptor.
    public let headingDegrees: Double?
    public let depthSummary: ContactSheetDepthSummary
    /// Usability warning the capture pipeline recorded for this frame
    /// (`frame_usability` advisory notes + the `usability=` token on
    /// automatic-keyframe notes); nil means no warning was recorded.
    public let usabilityStatus: FrameUsabilityStatus?
    public let usabilityIssues: [FrameUsabilityIssue]
    /// Operator privacy flag recorded via a `privacy_flag` advisory
    /// note naming this frame (legacy bolph71656-ai/HTDT-Capture#376).
    public let privacyFlagged: Bool

    public init(
        item: ReviewEvidenceItem,
        captureOrder: Int,
        headingDegrees: Double?,
        depthSummary: ContactSheetDepthSummary,
        usabilityStatus: FrameUsabilityStatus?,
        usabilityIssues: [FrameUsabilityIssue] = [],
        privacyFlagged: Bool = false
    ) {
        self.item = item
        self.captureOrder = captureOrder
        self.headingDegrees = headingDegrees
        self.depthSummary = depthSummary
        self.usabilityStatus = usabilityStatus
        self.usabilityIssues = usabilityIssues
        self.privacyFlagged = privacyFlagged
    }

    public var id: EvidenceFrameID { item.frameID }

    /// Tiles flagged with a usability warning the operator should eye.
    public var hasUsabilityWarning: Bool {
        guard let status = usabilityStatus else { return false }
        return status != .usable
    }
}

/// Contact-sheet filters (issue bolph71656-ai/HTDT-Capture#376). Filters AND together — a tile
/// must satisfy every active predicate to show.
public struct EvidenceContactSheetFilter: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Referenced by at least one committed authority.
    public static let referenced = Self(rawValue: 1 << 0)
    /// Not referenced by any authority (removal candidates).
    public static let unreferenced = Self(rawValue: 1 << 1)
    /// A usability warning was recorded.
    public static let warnings = Self(rawValue: 1 << 2)
    /// A depth payload was captured.
    public static let hasDepth = Self(rawValue: 1 << 3)
    /// Equipment-identity evidence (field-evidence canonical-frame
    /// bindings of kind `equipment_identity` — the "identity" filter).
    public static let identityPhotos = Self(rawValue: 1 << 4)
    /// Automatically retained keyframes (not operator picks).
    public static let automaticKeyframes = Self(rawValue: 1 << 5)
    /// Operator-flagged privacy-sensitive tiles.
    public static let privacyFlagged = Self(rawValue: 1 << 6)

    public static let all: Self = []
}

/// Contact-sheet ordering (issue bolph71656-ai/HTDT-Capture#376).
public enum EvidenceContactSheetSort: String, Sendable, Equatable {
    /// Scan order — session timestamp, frame id on ties.
    case captureTime = "capture_time"
    /// Heading order — yaw angle then timestamp (a "room direction"
    /// walk of the evidence).
    case roomDirection = "room_direction"
    /// Most-referenced first — the frames carrying the most authority
    /// bindings.
    case referenceCount = "reference_count"
    /// Largest retained payload first — the storage view.
    case byteSize = "byte_size"
}

/// Per-tile removal assessment (issue bolph71656-ai/HTDT-Capture#376). `removable` is the only
/// state that deletes bytes; every other state carries the dependents
/// or the reason so the UI can show *why* — never a silent refuse.
public enum ContactSheetRemovalAssessment: Sendable, Equatable {
    case removable
    /// End-boundary closing evidence — never removable in Review.
    case endBoundaryEvidence
    /// Referenced by committed authorities — the operator must
    /// resolve the listed dependents first (tokens as displayed in
    /// the gallery, e.g. `entity:<id>`, `measurement:<id>`).
    case blockedByDependents([String])
    /// Read-only persisted view — removal is unavailable.
    case readOnlyBundle
}

/// A multi-select removal plan (issue bolph71656-ai/HTDT-Capture#376): the tiles that may be
/// removed now, and the tiles blocked with the dependents shown.
public struct ContactSheetRemovalPlan: Sendable, Equatable {
    public struct Blocked: Sendable, Equatable {
        public let frameID: EvidenceFrameID
        public let dependents: [String]
        public let reason: String
    }

    public let removable: [EvidenceFrameID]
    public let blocked: [Blocked]
    /// Reclaimed bytes when `removable` executes.
    public let reclaimableBytes: Int64
}

/// The pre-finalization evidence contact sheet model (issue bolph71656-ai/HTDT-Capture#376).
/// Built from the same declared payload set the Review workspace
/// loads, so every tile refers to committed, integrity-covered bytes.
/// The model carries no image data — tiles resolve thumbnails lazily
/// through `previewFileURL` at render time.
public struct EvidenceContactSheetModel: Sendable, Equatable {
    public let items: [EvidenceContactSheetItem]
    /// True when the sheet presents a persisted (finalized or
    /// exported) bundle — removal is read-only (legacy bolph71656-ai/HTDT-Capture#376).
    public let readOnly: Bool

    public init(
        evidenceItems: [ReviewEvidenceItem],
        descriptors: [FrameEvidenceDescriptor],
        advisoryNotes: [CaptureAdvisoryNote],
        identityFrameIDs: Set<EvidenceFrameID> = [],
        readOnly: Bool = false
    ) {
        self.readOnly = readOnly
        let descriptorsByID = Dictionary(
            descriptors.map { ($0.frameID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Advisory-note parsing: `frame=<uuid>` tokens name the
        // frame; `usability=<status>` on a keyframe note carries the
        // usability verdict inline; a `frame_usability` note's
        // `status=`/`issues=` tokens carry the assessment.
        var usabilityByFrame: [EvidenceFrameID: (
            status: FrameUsabilityStatus,
            issues: [FrameUsabilityIssue]
        )] = [:]
        var privacyFlagged = Set<EvidenceFrameID>()

        func frameToken(_ detail: String) -> EvidenceFrameID? {
            for token in detail.split(separator: " ")
            where token.hasPrefix("frame=") {
                return EvidenceFrameID(
                    canonicalString: String(
                        token.dropFirst("frame=".count)
                    )
                )
            }
            return nil
        }

        for note in advisoryNotes {
            switch note.kind {
            case .frameUsability:
                guard let frameID = frameToken(note.detail) else {
                    continue
                }
                var status: FrameUsabilityStatus = .suspect
                var issues: [FrameUsabilityIssue] = []
                for token in note.detail.split(separator: " ") {
                    if token.hasPrefix("status="),
                       let parsed = FrameUsabilityStatus(
                        rawValue: String(token.dropFirst(7))
                       )
                    {
                        status = parsed
                    }
                    if token.hasPrefix("issues=") {
                        issues = String(token.dropFirst(7))
                            .split(separator: ",")
                            .compactMap {
                                FrameUsabilityIssue(
                                    rawValue: String($0)
                                )
                            }
                    }
                }
                usabilityByFrame[frameID] = (status, issues)
            case .automaticKeyframe:
                guard let frameID = frameToken(note.detail) else {
                    continue
                }
                for token in note.detail.split(separator: " ")
                where token.hasPrefix("usability=") {
                    if let parsed = FrameUsabilityStatus(
                        rawValue: String(token.dropFirst(10))
                    ), parsed != .usable {
                        usabilityByFrame[frameID] = (
                            status: parsed, issues: []
                        )
                    }
                }
            case .privacyFlag:
                if let frameID = frameToken(note.detail) {
                    privacyFlagged.insert(frameID)
                }
            case .privacyFlagCleared:
                // legacy bolph71656-ai/HTDT-Capture#460: notes replay in capture order — a clearing
                // note recorded after the flag lifts it again.
                if let frameID = frameToken(note.detail) {
                    privacyFlagged.remove(frameID)
                }
            default:
                continue
            }
        }

        // Capture-time order: session timestamp, then frame id for a
        // deterministic total order.
        let ordered = evidenceItems.enumerated().sorted {
            let a = $0.element
            let b = $1.element
            if a.sessionTimestampSeconds != b.sessionTimestampSeconds {
                return a.sessionTimestampSeconds
                    < b.sessionTimestampSeconds
            }
            return a.frameID.description < b.frameID.description
        }

        self.items = ordered.enumerated().map { order, pair in
            let item = pair.element
            let descriptor = descriptorsByID[item.frameID]
            let depthSummary: ContactSheetDepthSummary
            if let descriptor {
                switch descriptor.depthStatus {
                case .capturedDiscrete:
                    depthSummary = .discrete(
                        hasConfidence:
                            descriptor.depth?.confidenceRelativePath
                                != nil
                    )
                case .capturedSmoothed:
                    depthSummary = .smoothed(
                        hasConfidence:
                            descriptor.depth?.confidenceRelativePath
                                != nil
                    )
                case .unavailable:
                    depthSummary = .unavailable
                case .notRequested:
                    depthSummary = .none
                }
            } else {
                depthSummary = .none
            }
            return EvidenceContactSheetItem(
                item: item,
                captureOrder: order,
                headingDegrees: descriptor.flatMap {
                    Self.headingDegrees(worldFromCamera: $0.worldFromCamera)
                },
                depthSummary: depthSummary,
                usabilityStatus: usabilityByFrame[item.frameID]?.status,
                usabilityIssues:
                    usabilityByFrame[item.frameID]?.issues ?? [],
                privacyFlagged: privacyFlagged.contains(item.frameID)
                    || identityFrameIDs.contains(item.frameID)
            )
        }
    }

    /// Camera yaw from `T_world_from_camera` (column-major): the
    /// camera forward is -Z in camera space, so world forward is the
    /// negated third basis column. Degrees clockwise from -Z.
    static func headingDegrees(
        worldFromCamera: Matrix4x4F
    ) -> Double {
        let forwardX = -Double(worldFromCamera.values[8])
        let forwardZ = -Double(worldFromCamera.values[10])
        var degrees = atan2(forwardX, -forwardZ) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// Tiles matching every active filter, in the requested order.
    /// `[]` (`.all`) shows everything.
    public func items(
        matching filter: EvidenceContactSheetFilter,
        sortedBy sort: EvidenceContactSheetSort = .captureTime,
        identityFrameIDs: Set<EvidenceFrameID> = []
    ) -> [EvidenceContactSheetItem] {
        var result = items
        func isReferenced(_ item: EvidenceContactSheetItem) -> Bool {
            !item.item.referencedBy.isEmpty
        }
        if filter.contains(.referenced) {
            result = result.filter(isReferenced)
        }
        if filter.contains(.unreferenced) {
            result = result.filter { !isReferenced($0) }
        }
        if filter.contains(.warnings) {
            result = result.filter(\.hasUsabilityWarning)
        }
        if filter.contains(.hasDepth) {
            result = result.filter { $0.depthSummary.hasDepth }
        }
        if filter.contains(.identityPhotos) {
            result = result.filter {
                identityFrameIDs.contains($0.item.frameID)
            }
        }
        if filter.contains(.automaticKeyframes) {
            result = result.filter {
                $0.item.retentionReason == .automaticKeyframe
            }
        }
        if filter.contains(.privacyFlagged) {
            result = result.filter(\.privacyFlagged)
        }
        switch sort {
        case .captureTime:
            result.sort { $0.captureOrder < $1.captureOrder }
        case .roomDirection:
            result.sort {
                let ha = $0.headingDegrees
                let hb = $1.headingDegrees
                if ha == nil, hb == nil {
                    return $0.captureOrder < $1.captureOrder
                }
                guard let ha else { return false }
                guard let hb else { return true }
                if ha != hb { return ha < hb }
                return $0.captureOrder < $1.captureOrder
            }
        case .referenceCount:
            result.sort {
                ($0.item.referencedBy.count, -$0.captureOrder)
                    > ($1.item.referencedBy.count, -$1.captureOrder)
            }
        case .byteSize:
            result.sort { $0.item.byteCount > $1.item.byteCount }
        }
        return result
    }

    /// Total retained bytes across all tiles (issue bolph71656-ai/HTDT-Capture#376): the same
    /// sum the Review byte total reports.
    public var totalRetainedBytes: Int64 {
        items.reduce(0) { $0 + $1.item.byteCount }
    }

    /// Byte sum for a multi-select — the tile footer shows what the
    /// selection would reclaim or is worth.
    public func bytes(for selection: Set<EvidenceFrameID>) -> Int64 {
        items.filter { selection.contains($0.item.frameID) }
            .reduce(0) { $0 + $1.item.byteCount }
    }

    /// Per-tile removal classification (issue bolph71656-ai/HTDT-Capture#376): referenced or
    /// end-boundary tiles report the dependents that must be resolved
    /// first rather than deleting bytes silently.
    public func removalAssessment(
        for frameID: EvidenceFrameID
    ) -> ContactSheetRemovalAssessment {
        guard !readOnly else {
            return .readOnlyBundle
        }
        guard let entry = items.first(where: {
            $0.item.frameID == frameID
        }) else {
            return .readOnlyBundle
        }
        if entry.item.retentionReason == .endBoundary {
            return .endBoundaryEvidence
        }
        if !entry.item.referencedBy.isEmpty {
            return .blockedByDependents(entry.item.referencedBy)
        }
        if !entry.item.removable {
            return .readOnlyBundle
        }
        return .removable
    }

    /// The multi-select removal plan (issue bolph71656-ai/HTDT-Capture#376): everything
    /// removable in one pass plus the blocked tiles with the
    /// dependents shown, so a bulk removal never half-applies
    /// silently.
    public func removalPlan(
        for selection: Set<EvidenceFrameID>
    ) -> ContactSheetRemovalPlan {
        var removable: [EvidenceFrameID] = []
        var blocked: [ContactSheetRemovalPlan.Blocked] = []
        for frameID in selection.sorted(by: {
            $0.description < $1.description
        }) {
            switch removalAssessment(for: frameID) {
            case .removable:
                removable.append(frameID)
            case .endBoundaryEvidence:
                blocked.append(
                    .init(
                        frameID: frameID,
                        dependents: [],
                        reason: "end_boundary_evidence"
                    )
                )
            case .blockedByDependents(let dependents):
                blocked.append(
                    .init(
                        frameID: frameID,
                        dependents: dependents,
                        reason: "referenced"
                    )
                )
            case .readOnlyBundle:
                blocked.append(
                    .init(
                        frameID: frameID,
                        dependents: [],
                        reason: "read_only"
                    )
                )
            }
        }
        return ContactSheetRemovalPlan(
            removable: removable,
            blocked: blocked,
            reclaimableBytes: bytes(for: Set(removable))
        )
    }

    /// The frame-id → tile index map for frame↔annotation jumps
    /// (issue bolph71656-ai/HTDT-Capture#376): a caller asks for the tile of a known frame and
    /// scrolls it into view, or resolves which tiles an annotation's
    /// evidence refs name.
    public func tileIndex(of frameID: EvidenceFrameID) -> Int? {
        items.firstIndex { $0.item.frameID == frameID }
    }

    /// Tiles referenced by an annotation/record's evidence or
    /// binding refs (`frame:<id>` and `path:evidence/frames/<id>.json`
    /// tokens) — the annotation→frame jump direction.
    public func frames(referencedBy refs: [String])
        -> [EvidenceFrameID]
    {
        var found: [EvidenceFrameID] = []
        for ref in refs {
            let idText: String
            if ref.hasPrefix("frame:") {
                idText = String(ref.dropFirst("frame:".count))
            } else if ref.hasPrefix("path:evidence/frames/"),
                      ref.hasSuffix(".json")
            {
                idText = String(
                    ref.dropFirst("path:evidence/frames/".count)
                        .dropLast(".json".count)
                )
            } else {
                continue
            }
            if let id = EvidenceFrameID(canonicalString: idText),
               items.contains(where: { $0.item.frameID == id })
            {
                found.append(id)
            }
        }
        return found
    }
}
