import Foundation
import HTDTCaptureCore

/// A human-presentable binding choice for a field note (issue bolph71656-ai/HTDT-Capture#420):
/// the operator binds a note to a *subject* — "Front Left speaker",
/// "2.4 m — length" — while the exact authority ref stays available
/// under Details. Labels are derived only from committed record
/// fields; a ref that matches nothing keeps an honest fallback of a
/// localized type name plus a short diagnostic tag — never an
/// invented UUID label.
public struct FieldNoteBindingCandidate:
    Sendable, Equatable, Identifiable
{
    public enum Kind: String, Sendable, CaseIterable {
        case entity
        case measurement
        case evidence
        case setting
        case wiring
        case instrument
        case `operator`
        case roomState
        case other

        /// Localized section title for the grouped bind sheet.
        public var sectionTitle: String {
            switch self {
            case .entity:
                return String(localized: "Entities")
            case .measurement:
                return String(localized: "Measurements")
            case .evidence:
                return String(localized: "Evidence")
            case .setting:
                return String(localized: "Settings")
            case .wiring:
                return String(localized: "Wiring")
            case .instrument:
                return String(localized: "Instruments")
            case .operator:
                return String(localized: "Operators")
            case .roomState:
                return String(localized: "Room states")
            case .other:
                return String(localized: "Other")
            }
        }
    }

    /// The exact authority ref the note binds to.
    public let ref: String
    public let kind: Kind
    /// Primary human label — the operator's own words where the
    /// record carries them.
    public let title: String
    /// Context line: type/role/route detail, never a UUID.
    public let subtitle: String?
    /// SF Symbol name for the row icon.
    public let systemImage: String

    public var id: String { ref }

    public init(
        ref: String,
        kind: Kind,
        title: String,
        subtitle: String?,
        systemImage: String
    ) {
        self.ref = ref
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }
}

/// Maps committed authority records onto binding candidates, and
/// resolves arbitrary refs back to human labels on every surface that
/// renders them (issue bolph71656-ai/HTDT-Capture#420 — the shared human authority-ref
/// resolver).
public enum FieldNoteBindingResolver {
    /// Human label pieces for one candidate kind — used both by the
    /// grouped picker and by note rows presenting bound subjects.
    public static func kindName(_ kind: FieldNoteBindingCandidate.Kind)
        -> String
    {
        switch kind {
        case .entity:
            return String(localized: "Entity")
        case .measurement:
            return String(localized: "Measurement")
        case .evidence:
            return String(localized: "Evidence record")
        case .setting:
            return String(localized: "Settings observation")
        case .wiring:
            return String(localized: "Wiring route")
        case .instrument:
            return String(localized: "Instrument")
        case .operator:
            return String(localized: "Operator")
        case .roomState:
            return String(localized: "Room state")
        case .other:
            return String(localized: "Item")
        }
    }

    /// The namespace part of `ref` mapped to a candidate kind.
    public static func kind(of ref: String) -> FieldNoteBindingCandidate
        .Kind
    {
        guard let colon = ref.firstIndex(of: ":") else {
            return .other
        }
        switch String(ref[..<colon]) {
        case "entity", "equipment", "inventory_item":
            return .entity
        case "measurement":
            return .measurement
        case "field_evidence", "frame", "path", "sha256":
            return .evidence
        case "settings_observation", "calibration_plan_item":
            return .setting
        case "wiring_route":
            return .wiring
        case "instrument":
            return .instrument
        case "operator":
            return .operator
        case "room_state":
            return .roomState
        default:
            return .other
        }
    }

    /// Short human type name for a bare ref namespace — the fallback
    /// label when no committed record carries a human name.
    public static func namespaceName(of ref: String) -> String {
        switch kind(of: ref) {
        case .entity: return kindName(.entity)
        case .measurement: return kindName(.measurement)
        case .evidence: return kindName(.evidence)
        case .setting: return kindName(.setting)
        case .wiring: return kindName(.wiring)
        case .instrument: return kindName(.instrument)
        case .operator: return kindName(.operator)
        case .roomState: return kindName(.roomState)
        case .other:
            guard let colon = ref.firstIndex(of: ":") else {
                return kindName(.other)
            }
            let ns = String(ref[..<colon])
            switch ns {
            case "task_item":
                return String(localized: "Task")
            case "surface":
                return String(localized: "Surface")
            case "mesh_anchor":
                return String(localized: "Mesh anchor")
            case "path":
                return String(localized: "File")
            case "commissioning_check":
                return String(localized: "Commissioning check")
            default:
                return kindName(.other)
            }
        }
    }

    /// Builds candidates from committed records — the order follows
    /// the bind sheet's section order.
    public static func candidates(
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        fieldEvidence: [FieldEvidenceRecord],
        instruments: [MeasurementInstrumentProfile],
        operatorProfiles: [OperatorProfile],
        settingsObservations: [InstalledSettingsObservation],
        wiringRoutes: [AsBuiltWiringRoute]
    ) -> [FieldNoteBindingCandidate] {
        var out: [FieldNoteBindingCandidate] = []
        out += annotations.map { entity in
            FieldNoteBindingCandidate(
                ref: "entity:" + entity.entityID.description,
                kind: .entity,
                title: entity.label,
                subtitle: AnnotationPresentation
                    .entityTypeName(entity.type),
                systemImage: "square.3.layers.3d"
            )
        }
        out += measurements.map { m in
            FieldNoteBindingCandidate(
                ref: "measurement:" + m.measurementID.description,
                kind: .measurement,
                title: measurementTitle(m),
                subtitle: MissionPresentation
                    .quantityTypeName(m.quantityType),
                systemImage: "ruler"
            )
        }
        out += fieldEvidence.map { record in
            FieldNoteBindingCandidate(
                ref: "field_evidence:" + record.evidenceID.description,
                kind: .evidence,
                title: record.title,
                subtitle: FieldAuthorityPresentation
                    .evidenceKindName(record.kind),
                systemImage: "photo"
            )
        }
        out += settingsObservations.map { obs in
            FieldNoteBindingCandidate(
                ref: "settings_observation:"
                    + obs.observationID.description,
                kind: .setting,
                title: settingsTitle(obs),
                subtitle: obs.targetRef,
                systemImage: "slider.horizontal.3"
            )
        }
        out += wiringRoutes.map { route in
            FieldNoteBindingCandidate(
                ref: "wiring_route:" + route.routeID.description,
                kind: .wiring,
                title: routeTitle(route),
                subtitle: FieldAuthorityPresentation.routeStateName(
                    route.state
                ),
                systemImage: "cable.connector"
            )
        }
        out += instruments.map { inst in
            FieldNoteBindingCandidate(
                ref: "instrument:" + inst.instrumentID.description,
                kind: .instrument,
                title: inst.operatorLabel ?? inst.model,
                subtitle: FieldAuthorityPresentation
                    .instrumentClassName(inst.instrumentClass),
                systemImage: "waveform"
            )
        }
        out += operatorProfiles.map { op in
            FieldNoteBindingCandidate(
                ref: "operator:" + op.operatorID.description,
                kind: .operator,
                title: op.displayName,
                subtitle: op.role,
                systemImage: "person"
            )
        }
        return out
    }

    /// Candidates for the field-return workspace (issue bolph71656-ai/HTDT-Capture#418): the
    /// non-spatial collections a task row's fulfillment refs point
    /// at — inventory units and room-state observations included.
    public static func fieldReturnCandidates(
        inventoryItems: [SystemInventoryItem],
        fieldEvidence: [FieldEvidenceRecord],
        instruments: [MeasurementInstrumentProfile],
        operatorProfiles: [OperatorProfile],
        settingsObservations: [InstalledSettingsObservation],
        wiringRoutes: [AsBuiltWiringRoute],
        roomStateObservations: [RoomStateObservation]
    ) -> [FieldNoteBindingCandidate] {
        var out: [FieldNoteBindingCandidate] = []
        out += inventoryItems.map { item in
            FieldNoteBindingCandidate(
                ref: "inventory_item:" + item.itemID.description,
                kind: .entity,
                title: item.userLabel,
                subtitle: FieldReturnPresentation
                    .equipmentClassName(item.equipmentClass),
                systemImage: "shippingbox"
            )
        }
        out += fieldEvidence.map { record in
            FieldNoteBindingCandidate(
                ref: "field_evidence:" + record.evidenceID.description,
                kind: .evidence,
                title: record.title,
                subtitle: FieldAuthorityPresentation
                    .evidenceKindName(record.kind),
                systemImage: "photo"
            )
        }
        out += settingsObservations.map { obs in
            FieldNoteBindingCandidate(
                ref: "settings_observation:"
                    + obs.observationID.description,
                kind: .setting,
                title: settingsTitle(obs),
                subtitle: obs.targetRef,
                systemImage: "slider.horizontal.3"
            )
        }
        out += wiringRoutes.map { route in
            FieldNoteBindingCandidate(
                ref: "wiring_route:" + route.routeID.description,
                kind: .wiring,
                title: routeTitle(route),
                subtitle: FieldAuthorityPresentation.routeStateName(
                    route.state
                ),
                systemImage: "cable.connector"
            )
        }
        out += roomStateObservations.map { obs in
            FieldNoteBindingCandidate(
                ref: "room_state:" + obs.observationID.description,
                kind: .roomState,
                title: FieldReturnPresentation.roomStateKindName(
                    obs.kind
                ),
                subtitle: FieldReturnPresentation
                    .roomStateValueName(obs.state),
                systemImage: "house"
            )
        }
        out += instruments.map { inst in
            FieldNoteBindingCandidate(
                ref: "instrument:" + inst.instrumentID.description,
                kind: .instrument,
                title: inst.operatorLabel ?? inst.model,
                subtitle: FieldAuthorityPresentation
                    .instrumentClassName(inst.instrumentClass),
                systemImage: "waveform"
            )
        }
        out += operatorProfiles.map { op in
            FieldNoteBindingCandidate(
                ref: "operator:" + op.operatorID.description,
                kind: .operator,
                title: op.displayName,
                subtitle: op.role,
                systemImage: "person"
            )
        }
        return out
    }

    /// Resolves a ref to its human label using the committed
    /// records; falls back to a localized type name plus a short
    /// diagnostic tag (issue bolph71656-ai/HTDT-Capture#420 — never an invented label, never a
    /// raw UUID).
    public static func resolve(
        ref: String,
        in candidates: [FieldNoteBindingCandidate]
    ) -> FieldNoteBindingCandidate {
        if let match = candidates.first(where: { $0.ref == ref }) {
            return match
        }
        return FieldNoteBindingCandidate(
            ref: ref,
            kind: kind(of: ref),
            title: namespaceName(of: ref),
            subtitle: diagnosticTag(of: ref),
            systemImage: "tag"
        )
    }

    /// The bounded trailing fragment of a ref shown as a diagnostic
    /// tag under a fallback label — e.g. the first 8 chars of the id.
    public static func diagnosticTag(of ref: String) -> String? {
        guard let colon = ref.firstIndex(of: ":") else {
            return nil
        }
        let id = String(ref[ref.index(after: colon)...])
        return "#" + String(id.prefix(8))
    }

    /// Localized label for a note category token — well-known tokens
    /// have human names; `x_` extensions keep the operator's own
    /// suffix (with "Custom" context), never the raw `x_` token.
    public static func categoryName(
        _ category: CaptureFieldNoteCategory
    ) -> String {
        switch category.rawValue {
        case CaptureFieldNoteCategory.general.rawValue:
            return String(localized: "General")
        case CaptureFieldNoteCategory.roomCondition.rawValue:
            return String(localized: "Room condition")
        case CaptureFieldNoteCategory.obstruction.rawValue:
            return String(localized: "Obstruction")
        case CaptureFieldNoteCategory.equipmentState.rawValue:
            return String(localized: "Equipment state")
        case CaptureFieldNoteCategory.geometryCaveat.rawValue:
            return String(localized: "Geometry caveat")
        case CaptureFieldNoteCategory.measurementCaveat.rawValue:
            return String(localized: "Measurement caveat")
        case CaptureFieldNoteCategory.followUp.rawValue:
            return String(localized: "Follow-up")
        case CaptureFieldNoteCategory
            .installationObservation.rawValue:
            return String(localized: "Installation observation")
        default:
            let suffix = category.rawValue.hasPrefix("x_")
                ? String(category.rawValue.dropFirst(2))
                : category.rawValue
            let human = suffix
                .replacingOccurrences(of: "_", with: " ")
            return String(
                format: String(localized: "Custom: %@"),
                human
            )
        }
    }

    /// Caption-length explanation of what a note category means —
    /// shown under each option so the choice is understandable.
    public static func categoryDescription(
        _ category: CaptureFieldNoteCategory
    ) -> String {
        switch category.rawValue {
        case CaptureFieldNoteCategory.general.rawValue:
            return String(localized:
                "A general note that does not fit a narrower category.")
        case CaptureFieldNoteCategory.roomCondition.rawValue:
            return String(localized:
                "Something about the room's current condition — lighting, clutter, occupancy.")
        case CaptureFieldNoteCategory.obstruction.rawValue:
            return String(localized:
                "Something blocking the room or equipment — a sofa in front of a speaker, a door swing.")
        case CaptureFieldNoteCategory.equipmentState.rawValue:
            return String(localized:
                "The observed state of a device — powered off, on standby, in a mode.")
        case CaptureFieldNoteCategory.geometryCaveat.rawValue:
            return String(localized:
                "A warning that the captured geometry may be wrong here — thin walls, reflections.")
        case CaptureFieldNoteCategory.measurementCaveat.rawValue:
            return String(localized:
                "A warning that a measurement may be unreliable — noisy environment, weak signal.")
        case CaptureFieldNoteCategory.followUp.rawValue:
            return String(localized:
                "Something to come back to later — a task or an open question.")
        case CaptureFieldNoteCategory
            .installationObservation.rawValue:
            return String(localized:
                "A fact noticed during install — cable routing, mounting, connections.")
        default:
            return String(localized:
                "An operator-defined category written into the note.")
        }
    }

    /// Localized label for a note status.
    public static func statusName(
        _ status: CaptureFieldNoteStatus
    ) -> String {
        switch status {
        case .active:
            return String(localized: "Active")
        case .resolved:
            return String(localized: "Resolved")
        case .superseded:
            return String(localized: "Superseded")
        }
    }

    /// Localized label for the authoring method (Details only).
    public static func authoringMethodName(
        _ method: CaptureFieldNoteAuthoringMethod
    ) -> String {
        switch method {
        case .typed:
            return String(localized: "Typed")
        case .dictated:
            return String(localized: "Dictated")
        }
    }

    /// Localized anchor indicator (issue bolph71656-ai/HTDT-Capture#421): subject-point
    /// anchors render as "Location captured"; viewpoint anchors
    /// render as the recording stance — never as a subject location.
    public static func anchorName(
        _ kind: CaptureFieldNoteAnchorKind
    ) -> String {
        switch kind {
        case .subjectPoint:
            return String(localized: "Location captured")
        case .viewpoint:
            return String(localized: "Recorded from viewpoint")
        }
    }

    // MARK: - label fragments

    static func measurementTitle(_ m: CaptureMeasurement)
        -> String
    {
        let quantity = MissionPresentation
            .quantityTypeName(m.quantityType)
        switch m.value {
        case .scalar(let scalar):
            return quantity + " — "
                + scalar.formatted() + " " + m.unit.rawValue
        case .vector3(let x, let y, let z):
            return quantity + " — ("
                + [x, y, z].map { $0.formatted() }
                    .joined(separator: ", ") + ")"
        }
    }

    static func settingsTitle(
        _ obs: InstalledSettingsObservation
    ) -> String {
        guard let first = obs.settings.first else {
            return String(localized: "Settings observation")
        }
        if first.parameter == .other,
           let custom = first.customParameter
        {
            return custom.replacingOccurrences(
                of: "_", with: " "
            )
        }
        return FieldAuthorityPresentation
            .settingParameterName(first.parameter)
    }

    private static func routeTitle(_ route: AsBuiltWiringRoute)
        -> String
    {
        route.cableType
    }
}
