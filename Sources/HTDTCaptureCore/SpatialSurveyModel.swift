import Foundation

/// Spatial semantic survey pass (issue bolph71656-ai/HTDT-Capture#409): a room-scale read
/// model that walks the accepted capture — boundaries, openings,
/// room objects, and semantic entities — and tells the operator
/// what is reviewed, what is partially documented, what needs
/// follow-up, and what the mission required but never found.
///
/// Everything here is *derived* from committed authority + field
/// records and the imported task plan; nothing is persisted. The
/// model never invents material, room-state, or equipment schemas —
/// it attributes the records the capture already carries
/// (`TheaterAuthorityCollection`, field evidence, instruments,
/// settings observations, wiring routes, measurements) to targets.
///
/// The survey is a completeness view, not acoustic authority:
/// observed construction identity is recorded, never absorption
/// coefficients.
public enum SurveyTargetClass: String, Sendable, CaseIterable {
    /// Walls, floors — the room's boundary surfaces.
    case roomBoundary = "room_boundary"
    /// Doors, windows, openings — boundary apertures.
    case opening
    /// Detected furniture/equipment objects (RoomPlan objects).
    case roomObject = "room_object"
    /// Committed annotation entities (speakers, seats, screens…).
    case semanticEntity = "semantic_entity"
    /// Construction-feature candidates bound to geometry.
    case feature
    /// The room itself — room-wide records (state snapshots,
    /// field notes) bind here when they have no finer target.
    case room
}

/// Fine kind of a survey target — drives which record families a
/// target is expected to hold and how the UI names it.
public enum SurveyTargetKind: String, Sendable, CaseIterable {
    case room, wall, floor, door, window, opening, object,
        speaker, seat, screen, projector, display,
        genericEntity = "generic_entity",
        meshRegion = "mesh_region"

    /// True when the kind is an opening aperture.
    public var isOpeningKind: Bool {
        switch self {
        case .door, .window, .opening:
            return true
        default:
            return false
        }
    }
}

/// Documentation state of one target — computed, never stored
/// (issue bolph71656-ai/HTDT-Capture#409 §4). `unknown` and `notApplicable` are first-class
/// distinct from "not visited": the survey never pretends a gap is
/// reviewed.
public enum SurveyRecordState: String, Sendable, CaseIterable {
    /// Present in the capture but nothing recorded about it yet.
    case notReviewed = "not_reviewed"
    /// Some record kinds present; required coverage incomplete.
    case partiallyDocumented = "partially_documented"
    /// Recorded and nothing pending — operator-confirmable state.
    case reviewed
    /// Records exist but something asks for another look: an open
    /// revisit flag, a needs-attention field note, a problem-surface
    /// observation, or an unavailable-marked required plan item.
    case needsFollowUp = "needs_follow_up"
    /// The mission requires it but no matching geometry/entity
    /// exists in this capture — surfaced, never hidden.
    case unavailable
    /// Identity could not be resolved (marker without lineage,
    /// opaque mesh region) — nothing to attribute records to.
    case unknown
    /// No record family applies to this target in the current
    /// filter mode — shown dimmed, not counted as a gap.
    case notApplicable = "not_applicable"

    /// Whether this state is a survey gap the "next unresolved"
    /// ordering may hand to the operator.
    public var isUnresolved: Bool {
        switch self {
        case .notReviewed, .partiallyDocumented, .needsFollowUp,
             .unavailable:
            return true
        case .reviewed, .unknown, .notApplicable:
            return false
        }
    }
}

/// Which committed-record family a survey attribution belongs to —
/// aligned to the issue's filtered survey modes.
public enum SurveyRecordFamily: String, Sendable, CaseIterable {
    case surfaceIdentity = "surface_identity"
    case construction
    case constructionFeature = "construction_feature"
    case problemSurface = "problem_surface"
    case roomState = "room_state"
    case furnitureSemantics = "furniture_semantics"
    case equipmentInventory = "equipment_inventory"
    case installation
    case commissioning
    case wiring
    case measurement
    case fieldEvidence = "field_evidence"

    /// Families surfaced by each survey filter mode.
    public var surveyModes: Set<SurveyMode> {
        switch self {
        case .surfaceIdentity, .construction, .constructionFeature,
             .problemSurface:
            return [.all, .construction]
        case .roomState:
            return [.all, .roomState]
        case .furnitureSemantics, .equipmentInventory, .installation,
             .commissioning, .wiring, .measurement:
            return [.all, .equipmentInstallation]
        case .fieldEvidence:
            return [.all]
        }
    }
}

/// Survey filter modes (issue bolph71656-ai/HTDT-Capture#409 §7): scoped passes over the same
/// target list.
public enum SurveyMode: String, Sendable, CaseIterable {
    case all
    case construction
    case roomState = "room_state"
    case equipmentInstallation = "equipment_installation"
}

// MARK: - Targets

/// One survey target (issue bolph71656-ai/HTDT-Capture#409 §2): an accepted-geometry or
/// semantic thing the pass walks. `matchTokens` is the complete set
/// of identity tokens the target answers to — lowercased — so
/// attribution is exact matching, never fuzzy.
public struct SurveyTarget: Sendable, Equatable, Identifiable {
    /// Stable id: `roomplan:<kind>:<uuid>`, `entity:<id>`,
    /// `mesh:<uuid>`, or `room`.
    public let targetID: String
    public let targetClass: SurveyTargetClass
    public let kind: SurveyTargetKind
    public let label: String
    /// Normalized identity tokens — lowercased.
    public let matchTokens: Set<String>
    /// `PlanMarker.identifier` for focus linking into the plan/3D
    /// surfaces, when the target maps to one.
    public let planMarkerIdentifier: String?
    /// Task-plan item ids whose `target_ref` names this target —
    /// exact mapping, never fuzzy (issue bolph71656-ai/HTDT-Capture#409 §8).
    public let missionItemIDs: [String]
    /// Requirement of the strongest bound plan item (required wins
    /// over optional).
    public let missionRequirement: TaskPlanRequirement?

    public init(
        targetID: String,
        targetClass: SurveyTargetClass,
        kind: SurveyTargetKind,
        label: String,
        matchTokens: Set<String>,
        planMarkerIdentifier: String? = nil,
        missionItemIDs: [String] = [],
        missionRequirement: TaskPlanRequirement? = nil
    ) {
        self.targetID = targetID
        self.targetClass = targetClass
        self.kind = kind
        self.label = label
        self.matchTokens = matchTokens
        self.planMarkerIdentifier = planMarkerIdentifier
        self.missionItemIDs = missionItemIDs
        self.missionRequirement = missionRequirement
    }

    public var id: String { targetID }

    /// True when a required plan item names this target.
    public var isMissionRequired: Bool {
        missionRequirement == .required
    }
}

/// Token expansion shared by attribution (issue bolph71656-ai/HTDT-Capture#409 §6): a token
/// matches when either side agrees on the bare identity or on a
/// scheme-qualified form — exact in both directions.
public enum SurveyMatchTokens {
    /// All normalized forms one identity can appear under.
    public static func expand(_ token: String) -> Set<String> {
        let base = token.lowercased()
        var out: Set<String> = [base]
        if let range = base.range(of: ":") {
            // `scheme:value` also matches the bare value.
            out.insert(String(base[range.upperBound...]))
        }
        return out
    }

    /// The full match set for a roomplan surface/object id.
    public static func roomPlan(id: String, kind: String) -> Set<String>
    {
        let base = id.lowercased()
        return [
            base, "roomplan:" + kind + ":" + base,
            "roomplan:surface:" + base, "roomplan:object:" + base,
        ]
    }

    /// The full match set for an annotation entity id.
    public static func entity(_ id: String) -> Set<String> {
        let base = id.lowercased()
        return [base, "entity:" + base]
    }
}

// MARK: - Record attribution

/// One committed record attributed to a target (issue bolph71656-ai/HTDT-Capture#409 §5):
/// the object-first detail reads only the kinds present here.
public struct SurveyRecordRef: Sendable, Equatable, Identifiable {
    public let family: SurveyRecordFamily
    /// AuthorityRecordID / FieldEvidenceID / … string form.
    public let recordID: String
    /// Evidence refs the record carries — the target's evidence
    /// binding (issue bolph71656-ai/HTDT-Capture#409 §9).
    public let evidenceRefs: [String]

    public init(
        family: SurveyRecordFamily,
        recordID: String,
        evidenceRefs: [String] = []
    ) {
        self.family = family
        self.recordID = recordID
        self.evidenceRefs = evidenceRefs
    }

    public var id: String { family.rawValue + ":" + recordID }
}

/// A target's derived row: state + the attributed record refs +
/// attention reasons, in survey order.
public struct SurveyTargetEntry: Sendable, Equatable, Identifiable {
    public let target: SurveyTarget
    public let state: SurveyRecordState
    /// Families the target is expected to hold in this mode —
    /// defines `reviewed` vs `partiallyDocumented`.
    public let expectedFamilies: Set<SurveyRecordFamily>
    public let records: [SurveyRecordRef]
    /// Human-readable reasons the entry needs follow-up.
    public let attentionReasons: [String]
    /// Required-but-pending mission item refs on this target.
    public let pendingMissionItemIDs: [String]

    public init(
        target: SurveyTarget,
        state: SurveyRecordState,
        expectedFamilies: Set<SurveyRecordFamily>,
        records: [SurveyRecordRef],
        attentionReasons: [String],
        pendingMissionItemIDs: [String]
    ) {
        self.target = target
        self.state = state
        self.expectedFamilies = expectedFamilies
        self.records = records
        self.attentionReasons = attentionReasons
        self.pendingMissionItemIDs = pendingMissionItemIDs
    }

    public var id: String { target.targetID }

    /// Record families actually present — object-first detail shows
    /// only these kinds (issue bolph71656-ai/HTDT-Capture#409 §5).
    public var presentFamilies: Set<SurveyRecordFamily> {
        Set(records.map(\.family))
    }
}

/// The survey's aggregate counts — the header never counts targets
/// that are `notApplicable` in this mode as gaps.
public struct SurveySummary: Sendable, Equatable {
    public let totalCount: Int
    public let reviewedCount: Int
    public let partiallyDocumentedCount: Int
    public let notReviewedCount: Int
    public let needsFollowUpCount: Int
    public let unavailableCount: Int
    public let unknownCount: Int
    public let notApplicableCount: Int
    /// Mission-required targets not yet fully covered.
    public let missionRequiredGapCount: Int

    public var remainingCount: Int {
        notReviewedCount + partiallyDocumentedCount
            + needsFollowUpCount + unavailableCount
    }
}

// MARK: - The model

/// The derived survey over one capture revision (issue bolph71656-ai/HTDT-Capture#409).
/// `entries` are ordered per the issue's next-unresolved policy:
/// mission-required gaps → needs-attention → boundaries → objects →
/// optional rest — so `nextUnresolved` is simply the first entry
/// whose state is unresolved.
public struct SpatialSurveyModel: Sendable, Equatable {
    public let mode: SurveyMode
    public let entries: [SurveyTargetEntry]
    /// Targets in the issue's next-unresolved order.
    public let nextUnresolved: [SurveyTargetEntry]
    public let summary: SurveySummary

    /// Build the survey from the reviewable inputs. All inputs are
    /// committed records — nothing speculative becomes a target.
    /// - Parameters:
    ///   - roomPlanObjects: accepted RoomPlan surfaces+objects.
    ///   - meshAnchorIDs: accepted mesh anchor identities (targets of
    ///     kind `.meshRegion` — identity-only).
    ///   - annotations: committed annotation entities.
    ///   - authorities: the committed theater-authority collection.
    ///   - fieldEvidence / instruments / settingsObservations /
    ///     wiringRoutes / measurements / fieldNotes / revisitFlags:
    ///     committed record sets from the workspace.
    ///   - taskPlan: imported plan when present — drives mission
    ///     requirement mapping and `unavailable` targets.
    ///   - taskPlanStatus: committed per-item outcomes.
    public init(
        roomPlanObjects: [RoomPlanBindableObject],
        meshAnchorIDs: [UUID] = [],
        annotations: [CaptureAnnotationEntity],
        authorities: TheaterAuthorityCollection?,
        fieldEvidence: [FieldEvidenceRecord],
        instruments: [MeasurementInstrumentProfile],
        settingsObservations: [InstalledSettingsObservation],
        wiringRoutes: [AsBuiltWiringRoute],
        measurements: [CaptureMeasurement],
        fieldNotes: [CaptureFieldNote] = [],
        revisitFlags: [ScanRevisitFlag] = [],
        taskPlan: HTDTCaptureTaskPlan?,
        taskPlanStatus: CaptureTaskPlanStatusDocument?,
        mode: SurveyMode
    ) {
        self.mode = mode

        // ---- Targets ------------------------------------------------
        var targets: [SurveyTarget] = [
            SurveyTarget(
                targetID: "room",
                targetClass: .room,
                kind: .room,
                label: "Room",
                matchTokens: ["room", "room:*"]
            )
        ]
        for object in roomPlanObjects {
            let id = object.identifier
            let kind: SurveyTargetKind = object.isSurface
                ? Self.boundaryKind(for: object.category)
                : .object
            let cls: SurveyTargetClass = object.isSurface
                ? (kind.isOpeningKind ? .opening : .roomBoundary)
                : .roomObject
            targets.append(
                SurveyTarget(
                    targetID: "roomplan:" + kind.rawValue + ":" + id,
                    targetClass: cls,
                    kind: kind,
                    label: object.category,
                    matchTokens: SurveyMatchTokens.roomPlan(
                        id: id, kind: kind.rawValue
                    ),
                    planMarkerIdentifier:
                        "roomplan:" + kind.rawValue + ":" + id
                )
            )
        }
        for entity in annotations {
            let desc = entity.entityID.description
            let kind = Self.entityKind(for: entity.type)
            targets.append(
                SurveyTarget(
                    targetID: "entity:" + desc,
                    targetClass: .semanticEntity,
                    kind: kind,
                    label: entity.label,
                    matchTokens: SurveyMatchTokens.entity(desc),
                    planMarkerIdentifier: "entity:" + desc
                )
            )
        }
        for anchorID in meshAnchorIDs {
            let id = anchorID.uuidString.lowercased()
            targets.append(
                SurveyTarget(
                    targetID: "mesh:" + id,
                    targetClass: .feature,
                    kind: .meshRegion,
                    label: "Mesh region " + id.prefix(8),
                    matchTokens: [id, "mesh:" + id]
                )
            )
        }

        // ---- Mission requirement mapping (exact targetRef) ---------
        var pendingRequiredByTarget: [String: [String]] = [:]
        var unavailableItems: [(itemID: String, label: String)] = []
        if let taskPlan {
            for item in taskPlan.semanticTasks {
                guard let ref = item.targetRef?.lowercased()
                else { continue }
                let idx = targets.firstIndex {
                    Self.tokens($0.matchTokens).contains(ref)
                }
                if let idx {
                    targets[idx] = targets[idx].addingMissionItem(
                        item.itemID, requirement: item.requirement
                    )
                    let itemOutcome = taskPlanStatus?.items
                        .first(where: {
                            $0.itemID == item.itemID
                        })?.outcome
                    if item.requirement == .required,
                       itemOutcome != .completed
                    {
                        pendingRequiredByTarget[
                            targets[idx].targetID, default: []
                        ].append(item.itemID)
                    }
                    if itemOutcome == .unavailable {
                        pendingRequiredByTarget[
                            targets[idx].targetID, default: []
                        ].append(item.itemID)
                    }
                } else if item.requirement == .required {
                    unavailableItems.append(
                        (item.itemID, item.label ?? ref)
                    )
                }
            }
        }

        // ---- Record attribution ------------------------------------
        // token → record refs
        var recordsByToken: [String: [SurveyRecordRef]] = [:]
        // authorityRecordID string → tokens it binds, so
        // cross-referencing records (room-state observations) can
        // attribute through it.
        var tokensByAuthorityID: [String: Set<String>] = [:]
        // observationID → tokens
        var tokensByObservationID: [String: Set<String>] = [:]
        // authorityRecordID → record ref (for family inheritance)
        var recordByAuthorityID: [String: SurveyRecordRef] = [:]

        func attribute(
            _ tokens: Set<String>,
            _ ref: SurveyRecordRef
        ) {
            for token in tokens {
                recordsByToken[token, default: []].append(ref)
            }
        }

        if let authorities {
            for r in authorities.surfaceSemantics {
                let tokens = bindingTokens(r.binding)
                attribute(
                    tokens,
                    SurveyRecordRef(
                        family: .surfaceIdentity,
                        recordID: r.authorityID.description
                    )
                )
                tokensByAuthorityID[
                    r.authorityID.description
                ] = tokens
            }
            for r in authorities.surfaceConstructions {
                let tokens = bindingTokens(r.binding)
                attribute(
                    tokens,
                    SurveyRecordRef(
                        family: .construction,
                        recordID: r.authorityID.description
                    )
                )
                tokensByAuthorityID[
                    r.authorityID.description
                ] = tokens
            }
            for r in authorities.problemSurfaces {
                let tokens = bindingTokens(r.binding)
                let ref = SurveyRecordRef(
                    family: .problemSurface,
                    recordID: r.authorityID.description
                )
                attribute(tokens, ref)
                tokensByAuthorityID[
                    r.authorityID.description
                ] = tokens
                recordByAuthorityID[
                    r.authorityID.description
                ] = ref
            }
            for r in authorities.constructionFeatures {
                let tokens = bindingTokens(r.binding)
                attribute(
                    tokens,
                    SurveyRecordRef(
                        family: .constructionFeature,
                        recordID: r.authorityID.description
                    )
                )
                tokensByAuthorityID[
                    r.authorityID.description
                ] = tokens
            }
            for r in authorities.furnitureSemantics {
                var tokens = r.binding.map(bindingTokens) ?? []
                if let entity = r.targetEntityID {
                    tokens.formUnion(
                        SurveyMatchTokens.entity(entity.description)
                    )
                }
                attribute(
                    tokens,
                    SurveyRecordRef(
                        family: .furnitureSemantics,
                        recordID: r.authorityID.description
                    )
                )
            }
            for r in authorities.inventoryItems {
                var tokens: Set<String> = []
                if let entity = r.hostRackEntityID {
                    tokens.formUnion(
                        SurveyMatchTokens.entity(entity.description)
                    )
                }
                // Room-bound when no placement: inventory is a
                // room-scale record.
                if tokens.isEmpty {
                    tokens = ["room"]
                }
                attribute(
                    tokens,
                    SurveyRecordRef(
                        family: .equipmentInventory,
                        recordID: r.itemID.description,
                        evidenceRefs: r.evidenceRefs
                    )
                )
            }
            for r in authorities.speakerInstallations {
                var tokens = r.hostSurface.map(bindingTokens) ?? []
                tokens.formUnion(
                    SurveyMatchTokens.entity(
                        r.speakerEntityID.description
                    )
                )
                attribute(
                    tokens,
                    SurveyRecordRef(
                        family: .installation,
                        recordID: r.authorityID.description
                    )
                )
            }
            for r in authorities.screenSemantics {
                attribute(
                    SurveyMatchTokens.entity(
                        r.screenEntityID.description
                    ),
                    SurveyRecordRef(
                        family: .installation,
                        recordID: r.authorityID.description
                    )
                )
            }
            for r in authorities.seatLayouts {
                attribute(
                    SurveyMatchTokens.entity(
                        r.seatEntityID.description
                    ),
                    SurveyRecordRef(
                        family: .installation,
                        recordID: r.authorityID.description
                    )
                )
            }
            for r in authorities.routingVerifications {
                var tokens: Set<String> = []
                for entity in r.speakerEntityIDs {
                    tokens.formUnion(
                        SurveyMatchTokens.entity(entity.description)
                    )
                }
                if tokens.isEmpty { tokens = ["room"] }
                attribute(
                    tokens,
                    SurveyRecordRef(
                        family: .commissioning,
                        recordID: r.authorityID.description
                    )
                )
            }
            for r in authorities.projectorCommissionings {
                attribute(
                    SurveyMatchTokens.entity(
                        r.projectorEntityID.description
                    ),
                    SurveyRecordRef(
                        family: .commissioning,
                        recordID: r.authorityID.description
                    )
                )
            }
            for r in authorities.installationAlignments {
                attribute(
                    SurveyMatchTokens.entity(
                        r.finalEntityID.description
                    ),
                    SurveyRecordRef(
                        family: .commissioning,
                        recordID: r.authorityID.description,
                        evidenceRefs: r.evidenceRefs
                    )
                )
            }
            for r in authorities.roomStateObservations {
                var tokens: Set<String> = []
                if let entity = r.targetEntityID {
                    tokens.formUnion(
                        SurveyMatchTokens.entity(entity.description)
                    )
                }
                if let authority = r.targetAuthorityID,
                   let bound = tokensByAuthorityID[
                       authority.description
                   ]
                {
                    tokens.formUnion(bound)
                }
                if tokens.isEmpty { tokens = ["room"] }
                attribute(
                    tokens,
                    SurveyRecordRef(
                        family: .roomState,
                        recordID: r.observationID.description,
                        evidenceRefs: r.evidenceRefs
                    )
                )
                tokensByObservationID[
                    r.observationID.description
                ] = tokens
            }
            for snapshot in authorities.roomStateSnapshots {
                var tokens: Set<String> = []
                for observationID in snapshot.observationIDs {
                    tokens.formUnion(
                        tokensByObservationID[
                            observationID.description
                        ] ?? []
                    )
                }
                if tokens.isEmpty { tokens = ["room"] }
                attribute(
                    tokens,
                    SurveyRecordRef(
                        family: .roomState,
                        recordID: snapshot.snapshotID.description
                    )
                )
            }
        }

        for r in fieldEvidence {
            var tokens: Set<String> = []
            for target in r.targetRefs {
                tokens.formUnion(SurveyMatchTokens.expand(target))
            }
            if tokens.isEmpty { tokens = ["room"] }
            attribute(
                tokens,
                SurveyRecordRef(
                    family: .fieldEvidence,
                    recordID: r.evidenceID.description,
                    evidenceRefs: [r.evidenceID.description]
                )
            )
        }
        for r in instruments {
            attribute(
                ["room"],
                SurveyRecordRef(
                    family: .measurement,
                    recordID: r.instrumentID.description,
                    evidenceRefs: r.calibrationEvidenceRefs
                )
            )
        }
        for r in settingsObservations {
            let tokens = SurveyMatchTokens.expand(r.targetRef)
            attribute(
                tokens.isEmpty ? ["room"] : tokens,
                SurveyRecordRef(
                    family: .commissioning,
                    recordID: r.observationID.description,
                    evidenceRefs: r.evidenceRefs
                )
            )
        }
        for r in wiringRoutes {
            var tokens: Set<String> = []
            for endpoint in [r.endpointA, r.endpointB] {
                if let ref = endpoint.bindingRef {
                    tokens.formUnion(SurveyMatchTokens.expand(ref))
                }
            }
            if tokens.isEmpty { tokens = ["room"] }
            attribute(
                tokens,
                SurveyRecordRef(
                    family: .wiring,
                    recordID: r.routeID.description,
                    evidenceRefs: r.evidenceRefs
                )
            )
        }
        for r in measurements {
            var tokens: Set<String> = []
            for ref in r.endpointRefs {
                tokens.formUnion(SurveyMatchTokens.expand(ref))
            }
            if tokens.isEmpty { tokens = ["room"] }
            attribute(
                tokens,
                SurveyRecordRef(
                    family: .measurement,
                    recordID: r.measurementID.description
                )
            )
        }

        // ---- Attention reasons -------------------------------------
        var attentionByToken: [String: [String]] = [:]
        for note in fieldNotes where note.needsAttention {
            for target in note.bindingRefs {
                for token in SurveyMatchTokens.expand(target) {
                    attentionByToken[token, default: []]
                        .append("Field note needs attention")
                }
            }
        }
        for flag in revisitFlags where flag.resolution == nil {
            for token in SurveyMatchTokens.expand(
                flag.flagID
            ) {
                attentionByToken[token, default: []]
                    .append("Open revisit flag")
            }
        }

        // ---- Entries ------------------------------------------------
        var entries: [SurveyTargetEntry] = []
        for target in targets {
            var records: [SurveyRecordRef] = []
            var seen = Set<String>()
            for token in target.matchTokens {
                for ref in recordsByToken[token] ?? []
                where seen.insert(ref.id).inserted {
                    records.append(ref)
                }
            }
            var reasons: [String] = []
            for token in target.matchTokens {
                reasons.append(
                    contentsOf: attentionByToken[token] ?? []
                )
            }
            if records.contains(
                where: { $0.family == .problemSurface }
            ) {
                reasons.append("Problem-surface observation recorded")
            }
            let pending = pendingRequiredByTarget[target.targetID] ?? []
            if !pending.isEmpty {
                reasons.append("Required mission item pending")
            }

            let expected = Self.expectedFamilies(
                for: target, mode: mode
            )
            let relevant = records.filter {
                $0.family.surveyModes.contains(mode)
            }
            let state: SurveyRecordState
            if expected.isEmpty && relevant.isEmpty {
                state = .notApplicable
            } else if target.matchTokens.isEmpty {
                state = .unknown
            } else if !reasons.isEmpty {
                state = .needsFollowUp
            } else if relevant.isEmpty {
                state = .notReviewed
            } else if !pending.isEmpty
                || !expected.isSubset(of: relevant.map(\.family).asSet)
            {
                state = .partiallyDocumented
            } else {
                state = .reviewed
            }
            entries.append(
                SurveyTargetEntry(
                    target: target,
                    state: state,
                    expectedFamilies: expected,
                    records: records,
                    attentionReasons: reasons,
                    pendingMissionItemIDs: pending
                )
            )
        }
        // Mission-required targets with no geometry in the capture —
        // unavailable, never silently absent (issue bolph71656-ai/HTDT-Capture#409 §8).
        for item in unavailableItems {
            entries.append(
                SurveyTargetEntry(
                    target: SurveyTarget(
                        targetID: "mission:" + item.itemID,
                        targetClass: .semanticEntity,
                        kind: .genericEntity,
                        label: item.label,
                        matchTokens: [],
                        missionItemIDs: [item.itemID],
                        missionRequirement: .required
                    ),
                    state: .unavailable,
                    expectedFamilies: [],
                    records: [],
                    attentionReasons: [
                        "Required by mission but not found in capture"
                    ],
                    pendingMissionItemIDs: [item.itemID]
                )
            )
        }

        // Issue ordering: mission-required gaps → needs-attention →
        // boundaries → objects → optional.
        func rank(_ entry: SurveyTargetEntry) -> Int {
            if entry.target.isMissionRequired
                && entry.state.isUnresolved
            {
                return 0
            }
            if entry.state == .needsFollowUp { return 1 }
            switch entry.target.targetClass {
            case .roomBoundary, .opening:
                return entry.state.isUnresolved ? 2 : 4
            case .room:
                return entry.state.isUnresolved ? 2 : 4
            case .roomObject, .semanticEntity, .feature:
                return entry.state.isUnresolved ? 3 : 4
            }
        }
        let ordered = entries.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.target.targetID < b.target.targetID
        }
        self.entries = ordered
        self.nextUnresolved = ordered.filter {
            $0.state.isUnresolved
        }

        var reviewed = 0
        var partial = 0
        var notReviewed = 0
        var needsFollowUp = 0
        var unavailable = 0
        var unknown = 0
        var notApplicable = 0
        var missionGaps = 0
        for entry in ordered {
            switch entry.state {
            case .reviewed: reviewed += 1
            case .partiallyDocumented: partial += 1
            case .notReviewed: notReviewed += 1
            case .needsFollowUp: needsFollowUp += 1
            case .unavailable: unavailable += 1
            case .unknown: unknown += 1
            case .notApplicable: notApplicable += 1
            }
            // A mission gap is a requirement still pending — a
            // required target whose item completed keeps its survey
            // state but is not a gap.
            if !entry.pendingMissionItemIDs.isEmpty {
                missionGaps += 1
            }
        }
        self.summary = SurveySummary(
            totalCount: ordered.count,
            reviewedCount: reviewed,
            partiallyDocumentedCount: partial,
            notReviewedCount: notReviewed,
            needsFollowUpCount: needsFollowUp,
            unavailableCount: unavailable,
            unknownCount: unknown,
            notApplicableCount: notApplicable,
            missionRequiredGapCount: missionGaps
        )
    }

    /// Record families a target is expected to hold in `mode` —
    /// coverage defines reviewed vs partiallyDocumented. Empty means
    /// the target is `notApplicable` to the mode unless it already
    /// carries records there.
    public static func expectedFamilies(
        for target: SurveyTarget,
        mode: SurveyMode
    ) -> Set<SurveyRecordFamily> {
        var families: Set<SurveyRecordFamily> = []
        switch target.targetClass {
        case .roomBoundary:
            families = [.surfaceIdentity, .construction]
            if target.kind == .wall || target.kind == .floor {
                families.insert(.roomState)
            }
        case .opening:
            families = [.surfaceIdentity, .roomState]
        case .roomObject:
            families = [.furnitureSemantics]
        case .semanticEntity:
            switch target.kind {
            case .speaker:
                families = [.installation, .commissioning]
            case .screen, .projector, .display:
                families = [.installation, .commissioning]
            case .seat:
                families = [.installation]
            default:
                families = [.installation]
            }
        case .feature:
            families = [.constructionFeature]
        case .room:
            families = [.roomState]
        }
        if mode != .all {
            families = families.filter {
                $0.surveyModes.contains(mode)
            }
        }
        return families
    }

    private static func tokens(_ set: Set<String>) -> Set<String> {
        set
    }

    private static func boundaryKind(
        for category: String
    ) -> SurveyTargetKind {
        // CapturedRoom surface categories render with associated
        // values (e.g. `door(isOpen: true)`) — match the family.
        let base = category.lowercased()
        if base.hasPrefix("door") { return .door }
        if base.hasPrefix("window") { return .window }
        if base.hasPrefix("opening") || base.hasPrefix("dooropening") {
            return .opening
        }
        if base.hasPrefix("floor") { return .floor }
        return .wall
    }

    private static func entityKind(
        for type: AnnotationEntityType
    ) -> SurveyTargetKind {
        switch type {
        case .speaker, .subwoofer:
            return .speaker
        case .seat:
            return .seat
        case .projectionScreen:
            return .screen
        case .projector:
            return .projector
        case .display:
            return .display
        default:
            return .genericEntity
        }
    }
}

private extension SurveyTarget {
    func addingMissionItem(
        _ itemID: String,
        requirement: TaskPlanRequirement
    ) -> SurveyTarget {
        var items = missionItemIDs
        if !items.contains(itemID) {
            items.append(itemID)
        }
        let merged: TaskPlanRequirement =
            missionRequirement == .required
                || requirement == .required
                ? .required : .optional
        return SurveyTarget(
            targetID: targetID,
            targetClass: targetClass,
            kind: kind,
            label: label,
            matchTokens: matchTokens,
            planMarkerIdentifier: planMarkerIdentifier,
            missionItemIDs: items,
            missionRequirement: merged
        )
    }
}

private extension Array where Element == SurveyRecordFamily {
    var asSet: Set<SurveyRecordFamily> { Set(self) }
}

/// Lowercased identity tokens a `SurfaceRegionBinding` advertises —
/// the same expansion the match set uses on the target side.
private func bindingTokens(
    _ binding: SurfaceRegionBinding
) -> Set<String> {
    var tokens: Set<String> = []
    if let id = binding.roomPlanSurfaceID {
        tokens.formUnion(
            SurveyMatchTokens.roomPlan(id: id, kind: "surface")
        )
    }
    if let id = binding.roomPlanObjectID {
        tokens.formUnion(
            SurveyMatchTokens.roomPlan(id: id, kind: "object")
        )
    }
    if let id = binding.meshAnchorID {
        let base = id.uuidString.lowercased()
        tokens.formUnion([base, "mesh:" + base])
    }
    if let id = binding.semanticEntityID {
        tokens.formUnion(SurveyMatchTokens.entity(id))
    }
    return tokens.isEmpty ? ["room"] : tokens
}
