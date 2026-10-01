import Foundation

public struct CaptureRegionID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct CapturePortalID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum CaptureRegionKind: String, Codable, Sendable, Equatable {
    case room
    case openPlanArea = "open_plan_area"
    case hallway
    case stairwell
    case alcove
    case other
}

public enum CapturePortalKind: String, Codable, Sendable, Equatable {
    case doorway
    case openPassage = "open_passage"
    case stairOpening = "stair_opening"
    case other
}

/// Lifecycle of one room/region segment inside a connected capture
/// (issue #222). `active` is the segment currently being scanned;
/// `completed` segments may be revisited before finalization.
public enum CaptureRegionState: String, Codable, Sendable, Equatable {
    case active
    case completed
}

public enum ConnectedSpaceError: Error, Sendable, Equatable {
    case emptyField
    case duplicateRegionID
    case duplicatePortalID
    case unknownRegionID
    case activeSegmentExists
    case noActiveSegment
    case portalEndpointsNotDistinct
    /// Regions in different coordinate spaces can never be linked in
    /// one connected-space document — v1 has no cross-space merge.
    case crossSpacePortal
    case encodedDocumentMismatch
}

/// One scanned room/region segment. All segments in one connected-space
/// document share the revision's single bound coordinate space —
/// independent spaces are never silently merged (issue #222).
public struct CaptureRegionSegment: Codable, Sendable, Equatable {
    public let regionID: CaptureRegionID
    public let label: String
    public let kind: CaptureRegionKind
    public let state: CaptureRegionState
    public let coordinateSpaceID: CoordinateSpaceID
    public let captureSessionID: CaptureSessionID
    public let evidenceRefs: [String]
    /// Number of times the operator re-entered this segment after
    /// completing it.
    public let revisitCount: Int

    public init(
        regionID: CaptureRegionID,
        label: String,
        kind: CaptureRegionKind,
        state: CaptureRegionState,
        coordinateSpaceID: CoordinateSpaceID,
        captureSessionID: CaptureSessionID,
        evidenceRefs: [String] = [],
        revisitCount: Int = 0
    ) throws {
        let normalizedLabel = SchemaOwnedText.nfc(label)
        guard !normalizedLabel.isEmpty else {
            throw ConnectedSpaceError.emptyField
        }
        guard revisitCount >= 0 else {
            throw ConnectedSpaceError.emptyField
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw ConnectedSpaceError.emptyField
        }
        self.regionID = regionID
        self.label = normalizedLabel
        self.kind = kind
        self.state = state
        self.coordinateSpaceID = coordinateSpaceID
        self.captureSessionID = captureSessionID
        self.evidenceRefs = normalizedEvidence
        self.revisitCount = revisitCount
    }

    private enum CodingKeys: String, CodingKey {
        case regionID = "region_id"
        case label
        case kind
        case state
        case coordinateSpaceID = "coordinate_space_id"
        case captureSessionID = "capture_session_id"
        case evidenceRefs = "evidence_refs"
        case revisitCount = "revisit_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            regionID: container.decode(
                CaptureRegionID.self,
                forKey: .regionID
            ),
            label: container.decode(String.self, forKey: .label),
            kind: container.decode(
                CaptureRegionKind.self,
                forKey: .kind
            ),
            state: container.decode(
                CaptureRegionState.self,
                forKey: .state
            ),
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            captureSessionID: container.decode(
                CaptureSessionID.self,
                forKey: .captureSessionID
            ),
            evidenceRefs: container.decode(
                [String].self,
                forKey: .evidenceRefs
            ),
            revisitCount: container.decode(
                Int.self,
                forKey: .revisitCount
            )
        )
    }
}

/// An explicit doorway/passage relationship between two segments
/// (issue #222). Portals are the only way segments relate — an
/// implicit or geometric "looks adjacent" merge is never produced.
public struct CaptureRegionPortal: Codable, Sendable, Equatable {
    public let portalID: CapturePortalID
    public let regionAID: CaptureRegionID
    public let regionBID: CaptureRegionID
    public let kind: CapturePortalKind
    /// Shared coordinate space both regions live in.
    public let coordinateSpaceID: CoordinateSpaceID
    public let label: String?
    public let evidenceRefs: [String]

    public init(
        portalID: CapturePortalID = CapturePortalID(),
        regionAID: CaptureRegionID,
        regionBID: CaptureRegionID,
        kind: CapturePortalKind,
        coordinateSpaceID: CoordinateSpaceID,
        label: String? = nil,
        evidenceRefs: [String] = []
    ) throws {
        guard regionAID != regionBID else {
            throw ConnectedSpaceError.portalEndpointsNotDistinct
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw ConnectedSpaceError.emptyField
        }
        self.portalID = portalID
        self.regionAID = regionAID
        self.regionBID = regionBID
        self.kind = kind
        self.coordinateSpaceID = coordinateSpaceID
        self.label = SchemaOwnedText.nfc(label)
        self.evidenceRefs = normalizedEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case portalID = "portal_id"
        case regionAID = "region_a_id"
        case regionBID = "region_b_id"
        case kind
        case coordinateSpaceID = "coordinate_space_id"
        case label
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            portalID: container.decode(
                CapturePortalID.self,
                forKey: .portalID
            ),
            regionAID: container.decode(
                CaptureRegionID.self,
                forKey: .regionAID
            ),
            regionBID: container.decode(
                CaptureRegionID.self,
                forKey: .regionBID
            ),
            kind: container.decode(
                CapturePortalKind.self,
                forKey: .kind
            ),
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            label: container.decodeIfPresent(
                String.self,
                forKey: .label
            ),
            evidenceRefs: container.decode(
                [String].self,
                forKey: .evidenceRefs
            )
        )
    }
}

/// The persisted connected-space document at
/// `session/connected-spaces.json` (issue #222). All segments and
/// portals reference the revision's single coordinate authority.
public struct ConnectedSpaceDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.connected-spaces"
    public static let schemaVersion = "1.0.0"
    public static let path = "session/connected-spaces.json"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    /// The shared coordinate authority every segment/portal lives in.
    public let coordinateSpaceID: CoordinateSpaceID
    public let segments: [CaptureRegionSegment]
    public let portals: [CaptureRegionPortal]

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        segments: [CaptureRegionSegment],
        portals: [CaptureRegionPortal]
    ) throws {
        guard !segments.isEmpty else {
            throw ConnectedSpaceError.emptyField
        }
        guard Set(segments.map(\.regionID)).count == segments.count
        else {
            throw ConnectedSpaceError.duplicateRegionID
        }
        guard Set(portals.map(\.portalID)).count == portals.count
        else {
            throw ConnectedSpaceError.duplicatePortalID
        }
        // Every segment and portal must live in the bound space — a
        // segment recorded in another space cannot be smuggled into a
        // shared document.
        guard segments.allSatisfy({
            $0.coordinateSpaceID == coordinateSpaceID
        }), portals.allSatisfy({
            $0.coordinateSpaceID == coordinateSpaceID
        }) else {
            throw ConnectedSpaceError.crossSpacePortal
        }
        let regionIDs = Set(segments.map(\.regionID))
        for portal in portals {
            guard regionIDs.contains(portal.regionAID),
                  regionIDs.contains(portal.regionBID)
            else {
                throw ConnectedSpaceError.unknownRegionID
            }
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.segments = segments
        self.portals = portals
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case segments
        case portals
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.schema,
              schemaVersion == Self.schemaVersion
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription:
                        "Unsupported connected-space schema"
                )
            )
        }
        try self.init(
            captureRevisionID: container.decode(
                CaptureRevisionID.self,
                forKey: .captureRevisionID
            ),
            captureSessionID: container.decode(
                CaptureSessionID.self,
                forKey: .captureSessionID
            ),
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            segments: container.decode(
                [CaptureRegionSegment].self,
                forKey: .segments
            ),
            portals: container.decode(
                [CaptureRegionPortal].self,
                forKey: .portals
            )
        )
    }
}

/// Operator-facing connected-room workflow tracker (issue #222). The
/// app drives segment lifecycle explicitly: begin, record a portal
/// crossing, complete, revisit before finalization.
public struct ConnectedSpaceTracker: Sendable, Equatable {
    public let coordinateSpaceID: CoordinateSpaceID
    public let captureSessionID: CaptureSessionID
    public private(set) var segments: [CaptureRegionSegment]
    public private(set) var portals: [CaptureRegionPortal]

    public init(
        coordinateSpaceID: CoordinateSpaceID,
        captureSessionID: CaptureSessionID
    ) {
        self.coordinateSpaceID = coordinateSpaceID
        self.captureSessionID = captureSessionID
        self.segments = []
        self.portals = []
    }

    /// Rebuilds the tracker from its persisted document — segments
    /// and portals restore verbatim, so a reopened draft keeps the
    /// recorded connected-space map instead of silently restarting
    /// empty.
    public init(restoring document: ConnectedSpaceDocument) {
        self.coordinateSpaceID = document.coordinateSpaceID
        self.captureSessionID = document.captureSessionID
        self.segments = document.segments
        self.portals = document.portals
    }

    public var activeSegment: CaptureRegionSegment? {
        segments.first { $0.state == .active }
    }

    /// Starts scanning a new room/region. Exactly one segment is
    /// active at a time — finish or revisit before beginning another.
    @discardableResult
    public mutating func beginSegment(
        label: String,
        kind: CaptureRegionKind,
        evidenceRefs: [String] = []
    ) throws -> CaptureRegionSegment {
        guard activeSegment == nil else {
            throw ConnectedSpaceError.activeSegmentExists
        }
        let segment = try CaptureRegionSegment(
            regionID: CaptureRegionID(),
            label: label,
            kind: kind,
            state: .active,
            coordinateSpaceID: coordinateSpaceID,
            captureSessionID: captureSessionID,
            evidenceRefs: evidenceRefs
        )
        segments.append(segment)
        return segment
    }

    /// Records that the operator physically crossed from the active
    /// segment into another segment — the explicit doorway/portal
    /// relationship the connected workflow requires.
    @discardableResult
    public mutating func recordPortal(
        toRegionID other: CaptureRegionID,
        kind: CapturePortalKind,
        label: String? = nil,
        evidenceRefs: [String] = []
    ) throws -> CaptureRegionPortal {
        guard let active = activeSegment else {
            throw ConnectedSpaceError.noActiveSegment
        }
        guard segments.contains(where: { $0.regionID == other }) else {
            throw ConnectedSpaceError.unknownRegionID
        }
        let portal = try CaptureRegionPortal(
            regionAID: active.regionID,
            regionBID: other,
            kind: kind,
            coordinateSpaceID: coordinateSpaceID,
            label: label,
            evidenceRefs: evidenceRefs
        )
        portals.append(portal)
        return portal
    }

    /// Finishes the active segment so another can begin.
    public mutating func completeActiveSegment() throws {
        guard let active = activeSegment,
              let index = segments.firstIndex(where: {
                  $0.regionID == active.regionID
              })
        else {
            throw ConnectedSpaceError.noActiveSegment
        }
        segments[index] = try CaptureRegionSegment(
            regionID: active.regionID,
            label: active.label,
            kind: active.kind,
            state: .completed,
            coordinateSpaceID: active.coordinateSpaceID,
            captureSessionID: active.captureSessionID,
            evidenceRefs: active.evidenceRefs,
            revisitCount: active.revisitCount
        )
    }

    /// Re-enters a completed segment for additional scanning before
    /// finalization. The revisit is recorded, never silent.
    public mutating func revisitRegion(
        _ regionID: CaptureRegionID
    ) throws {
        guard activeSegment == nil else {
            throw ConnectedSpaceError.activeSegmentExists
        }
        guard let index = segments.firstIndex(where: {
            $0.regionID == regionID && $0.state == .completed
        }) else {
            throw ConnectedSpaceError.unknownRegionID
        }
        let prior = segments[index]
        segments[index] = try CaptureRegionSegment(
            regionID: prior.regionID,
            label: prior.label,
            kind: prior.kind,
            state: .active,
            coordinateSpaceID: prior.coordinateSpaceID,
            captureSessionID: prior.captureSessionID,
            evidenceRefs: prior.evidenceRefs,
            revisitCount: prior.revisitCount + 1
        )
    }

    /// Appends evidence links to a segment (frames, mesh anchors seen
    /// while that region was active).
    public mutating func appendEvidence(
        to regionID: CaptureRegionID,
        refs: [String]
    ) throws {
        guard let index = segments.firstIndex(where: {
            $0.regionID == regionID
        }) else {
            throw ConnectedSpaceError.unknownRegionID
        }
        let prior = segments[index]
        let merged = Array(
            Set(prior.evidenceRefs + refs)
        ).sorted()
        segments[index] = try CaptureRegionSegment(
            regionID: prior.regionID,
            label: prior.label,
            kind: prior.kind,
            state: prior.state,
            coordinateSpaceID: prior.coordinateSpaceID,
            captureSessionID: prior.captureSessionID,
            evidenceRefs: merged,
            revisitCount: prior.revisitCount
        )
    }

    /// Builds the persisted document for the working set.
    public func document(
        captureRevisionID: CaptureRevisionID
    ) throws -> ConnectedSpaceDocument {
        try ConnectedSpaceDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            segments: segments,
            portals: portals
        )
    }

    /// Encoded payload for the supplemental-document store path.
    public func package(
        captureRevisionID: CaptureRevisionID
    ) throws -> Data {
        let document = try document(
            captureRevisionID: captureRevisionID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard
            let decoded = try? JSONDecoder().decode(
                ConnectedSpaceDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw ConnectedSpaceError.encodedDocumentMismatch
        }
        return data
    }
}
