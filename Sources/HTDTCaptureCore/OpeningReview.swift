import Foundation

public struct OpeningID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Kind of room opening candidate (issue #231).
///
/// Door/window/opening are the RoomPlan-inferable portal kinds; the
/// remaining kinds are the operator-only boundary openings the
/// refinement calls out (HVAC supply/return or open duct, transfer
/// grille, intentionally characterized door undercut, cable/service
/// penetration). Candidates of any kind are review records only — a
/// confirmed penetration is never auto-promoted into solver Portal
/// physics.
public enum RoomOpeningKind: String, Codable, Sendable, CaseIterable {
    case door
    case window
    /// A portal/opening that is neither a door nor a window (e.g. an
    /// open passage between rooms).
    case opening
    /// HVAC supply/return grille or open duct.
    case hvacGrille = "hvac_grille"
    /// Transfer grille between rooms.
    case transferGrille = "transfer_grille"
    /// Door undercut/gap when intentionally characterized as an
    /// opening.
    case doorUndercut = "door_undercut"
    /// Cable/service penetration through a room boundary.
    case servicePenetration = "service_penetration"
    case other
}

/// Whether the boundary opening was open or closed when observed
/// (issue #231). `unknown` is the default and covers candidates where
/// the state was not observable or not meaningful to record.
public enum RoomOpeningState: String, Codable, Sendable, CaseIterable {
    /// Air/people can pass through — e.g. an open duct, transfer
    /// grille, or a door observed open.
    case open
    /// The opening is present but closed off — e.g. a closed door or
    /// a covered grille.
    case closed
    /// Not observed or not meaningful for this candidate.
    case unknown
}

/// How the candidate entered the review set (issue #231). Source
/// lineage is explicit so HTDT can distinguish RoomPlan-inferred
/// openings from operator-declared ones.
public enum RoomOpeningSource: String, Codable, Sendable {
    /// Enumerated from the committed RoomPlan `captured-room.json`
    /// inference payload.
    case roomplanInference = "roomplan_inference"
    /// Added by the operator during review (e.g. an opening RoomPlan
    /// did not infer).
    case userDeclared = "user_declared"
}

/// Operator disposition for one candidate (issue #231). Nothing is
/// silently dropped: a rejected candidate is marked
/// `intentionallyIgnored` so the review document records that the
/// operator saw it and dismissed it.
public enum RoomOpeningDisposition: String, Codable, Sendable {
    /// Enumerated but not yet reviewed.
    case unreviewed
    /// Operator confirms this is a real opening; the candidate is an
    /// authoring candidate for HTDT.
    case confirmed
    /// Possibly real but not verifiable in this capture; flags the
    /// region for follow-up scanning in a later revision.
    case needsMoreScanning = "needs_more_scanning"
    /// Reviewed and deliberately excluded from HTDT authoring
    /// candidates.
    case intentionallyIgnored = "intentionally_ignored"
}

/// One opening/portal candidate in the review set (issue #231).
/// Geometry is expressed in the capture's bound coordinate space when
/// the source observed it; operator-declared candidates may omit
/// observed geometry entirely.
public struct RoomOpeningCandidate: Codable, Sendable, Equatable {
    public let openingID: OpeningID
    public let kind: RoomOpeningKind
    public let source: RoomOpeningSource
    /// Deterministic lineage token for the source record, e.g.
    /// `roomplan:door:3` or `user:<uuid>`. HTDT reads this to join the
    /// candidate back to the originating evidence.
    public let sourceRef: String
    /// Center of the opening in `coordinate_space_id` meters, when the
    /// source observed geometry.
    public let centerMeters: WorldPoint3D?
    public let widthMeters: Double?
    public let heightMeters: Double?
    public var disposition: RoomOpeningDisposition
    /// Open/closed/unknown as observed; defaults to `.unknown` so
    /// review documents written before the field existed decode
    /// unchanged.
    public var openState: RoomOpeningState
    /// UTC the operator last set `disposition`; nil while unreviewed.
    public var reviewedAtUTC: String?
    /// Spatial evidence links (`path:`/`frame:`/`mesh_anchor:`) the
    /// operator attached while reviewing.
    public var evidenceRefs: [String]

    public init(
        openingID: OpeningID = OpeningID(),
        kind: RoomOpeningKind,
        source: RoomOpeningSource,
        sourceRef: String,
        centerMeters: WorldPoint3D? = nil,
        widthMeters: Double? = nil,
        heightMeters: Double? = nil,
        disposition: RoomOpeningDisposition = .unreviewed,
        openState: RoomOpeningState = .unknown,
        reviewedAtUTC: String? = nil,
        evidenceRefs: [String] = []
    ) throws {
        guard !sourceRef.isEmpty else {
            throw OpeningReviewError.emptySourceRef
        }
        if let centerMeters {
            guard centerMeters.isFinite else {
                throw OpeningReviewError.nonFiniteValue
            }
        }
        for extent in [widthMeters, heightMeters] {
            if let extent {
                guard extent.isFinite, extent > 0 else {
                    throw OpeningReviewError.nonFiniteValue
                }
            }
        }
        self.openingID = openingID
        self.kind = kind
        self.source = source
        self.sourceRef = sourceRef
        self.centerMeters = centerMeters
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.disposition = disposition
        self.openState = openState
        self.reviewedAtUTC = reviewedAtUTC
        self.evidenceRefs = evidenceRefs
    }

    private enum CodingKeys: String, CodingKey {
        case openingID = "opening_id"
        case kind
        case source
        case sourceRef = "source_ref"
        case centerMeters = "center_m"
        case widthMeters = "width_m"
        case heightMeters = "height_m"
        case disposition
        case openState = "open_state"
        case reviewedAtUTC = "reviewed_at"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            openingID: container.decode(
                OpeningID.self,
                forKey: .openingID
            ),
            kind: container.decode(
                RoomOpeningKind.self,
                forKey: .kind
            ),
            source: container.decode(
                RoomOpeningSource.self,
                forKey: .source
            ),
            sourceRef: container.decode(
                String.self,
                forKey: .sourceRef
            ),
            centerMeters: container.decodeIfPresent(
                WorldPoint3D.self,
                forKey: .centerMeters
            ),
            widthMeters: container.decodeIfPresent(
                Double.self,
                forKey: .widthMeters
            ),
            heightMeters: container.decodeIfPresent(
                Double.self,
                forKey: .heightMeters
            ),
            disposition: container.decode(
                RoomOpeningDisposition.self,
                forKey: .disposition
            ),
            openState: container.decodeIfPresent(
                RoomOpeningState.self,
                forKey: .openState
            ) ?? .unknown,
            reviewedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .reviewedAtUTC
            ),
            evidenceRefs: container.decode(
                [String].self,
                forKey: .evidenceRefs
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(openingID, forKey: .openingID)
        try container.encode(kind, forKey: .kind)
        try container.encode(source, forKey: .source)
        try container.encode(sourceRef, forKey: .sourceRef)
        try container.encodeIfPresent(centerMeters, forKey: .centerMeters)
        try container.encodeIfPresent(widthMeters, forKey: .widthMeters)
        try container.encodeIfPresent(heightMeters, forKey: .heightMeters)
        try container.encode(disposition, forKey: .disposition)
        // `open_state` always encodes: a candidate re-saved after review
        // states what was recorded, including an explicit `unknown`.
        try container.encode(openState, forKey: .openState)
        try container.encodeIfPresent(
            reviewedAtUTC,
            forKey: .reviewedAtUTC
        )
        try container.encode(evidenceRefs, forKey: .evidenceRefs)
    }
}

public enum OpeningReviewError: Error, Sendable, Equatable {
    case emptySourceRef
    case nonFiniteValue
    case duplicateOpeningID
    case unknownOpening
    case encodedDocumentMismatch
}

/// Canonical opening-review document (issue #231), persisted at
/// `annotations/opening-review.json`. This is the operator's review of
/// door/window/portal candidates — confirmation state only; HTDT reads
/// it as authoring candidates and never treats a candidate as observed
/// geometry unless `disposition == .confirmed`.
public struct OpeningReviewDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.opening-review"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    public let coordinateSpaceID: CoordinateSpaceID
    public let openings: [RoomOpeningCandidate]

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        openings: [RoomOpeningCandidate]
    ) throws {
        var seen = Set<OpeningID>()
        for opening in openings {
            guard seen.insert(opening.openingID).inserted else {
                throw OpeningReviewError.duplicateOpeningID
            }
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.coordinateSpaceID = coordinateSpaceID
        self.openings = openings
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case openings
    }
}

public struct OpeningReviewPackage: Sendable, Equatable {
    public static let path = "annotations/opening-review.json"

    public let document: OpeningReviewDocument
    public let data: Data

    public init(document: OpeningReviewDocument, data: Data) {
        self.document = document
        self.data = data
    }

    /// Operator-reviewed candidates over RoomPlan inference: user
    /// authority derived from the committed processed payload, so the
    /// manifest carries the lineage edge explicitly.
    public var payloadDeclaration: BundlePayloadDeclaration {
        BundlePayloadDeclaration(
            path: Self.path,
            mediaType: "application/json",
            producer: "annotation",
            provenanceClass: .userAnnotation,
            role: .canonical,
            sourceRefs: [
                "capture_session:"
                    + document.captureSessionID.description
            ]
        )
    }
}

public enum OpeningReviewPackageBuilder {
    public static func build(
        document: OpeningReviewDocument
    ) throws -> OpeningReviewPackage {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard let decoded = try? JSONDecoder().decode(
            OpeningReviewDocument.self,
            from: data
        ), decoded == document else {
            throw OpeningReviewError.encodedDocumentMismatch
        }
        return OpeningReviewPackage(
            document: document,
            data: data
        )
    }
}

/// Pure merge/update operations over an opening-review candidate set
/// (issue #231), kept separate from persistence so enumeration, UI and
/// tests share exactly one behavior.
public enum OpeningReviewEditor {
    /// Merges freshly enumerated RoomPlan candidates into `existing`:
    /// candidates already tracked (matched by `source_ref`) keep the
    /// operator's disposition; brand-new source records append as
    /// `.unreviewed`. The result is deterministic — input order is
    /// preserved and never silently reorders prior review state.
    public static func merge(
        existing: [RoomOpeningCandidate],
        enumerated: [RoomOpeningCandidate]
    ) -> [RoomOpeningCandidate] {
        let bySourceRef = Dictionary(
            existing.map { ($0.sourceRef, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var merged = existing
        var seenRefs = Set(existing.map(\.sourceRef))
        for candidate in enumerated {
            if bySourceRef[candidate.sourceRef] != nil {
                continue
            }
            if seenRefs.insert(candidate.sourceRef).inserted {
                merged.append(candidate)
            }
        }
        return merged
    }

    /// Sets the operator disposition of one candidate. Returns nil when
    /// the opening id is not part of the review set.
    public static func setDisposition(
        _ disposition: RoomOpeningDisposition,
        openingID: OpeningID,
        in openings: [RoomOpeningCandidate],
        reviewedAtUTC: String
    ) -> [RoomOpeningCandidate]? {
        var updated = openings
        guard let index = updated.firstIndex(where: {
            $0.openingID == openingID
        }) else {
            return nil
        }
        updated[index].disposition = disposition
        updated[index].reviewedAtUTC =
            disposition == .unreviewed ? nil : reviewedAtUTC
        return updated
    }

    /// Sets the observed open/closed/unknown state of one candidate
    /// (issue #231). Returns nil when the opening id is not part of the
    /// review set.
    public static func setOpenState(
        _ openState: RoomOpeningState,
        openingID: OpeningID,
        in openings: [RoomOpeningCandidate]
    ) -> [RoomOpeningCandidate]? {
        var updated = openings
        guard let index = updated.firstIndex(where: {
            $0.openingID == openingID
        }) else {
            return nil
        }
        updated[index].openState = openState
        return updated
    }

    /// Appends an operator-declared candidate of any review kind,
    /// including the non-RoomPlan boundary kinds (vent/grille,
    /// penetration). Returns nil when `sourceRef` collides with an
    /// already-tracked candidate.
    public static func addUserDeclaredCandidate(
        kind: RoomOpeningKind,
        sourceRef: String,
        centerMeters: WorldPoint3D? = nil,
        widthMeters: Double? = nil,
        heightMeters: Double? = nil,
        openState: RoomOpeningState = .unknown,
        evidenceRefs: [String] = [],
        to openings: [RoomOpeningCandidate]
    ) -> [RoomOpeningCandidate]? {
        guard !openings.contains(where: {
            $0.sourceRef == sourceRef
        }) else {
            return nil
        }
        guard let candidate = try? RoomOpeningCandidate(
            kind: kind,
            source: .userDeclared,
            sourceRef: sourceRef,
            centerMeters: centerMeters,
            widthMeters: widthMeters,
            heightMeters: heightMeters,
            openState: openState,
            evidenceRefs: evidenceRefs
        ) else {
            return nil
        }
        return openings + [candidate]
    }
}
