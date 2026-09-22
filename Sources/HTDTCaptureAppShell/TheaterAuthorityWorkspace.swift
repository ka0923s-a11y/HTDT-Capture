import Foundation
import SwiftUI
import HTDTCaptureCore

/// A selectable captured element for the surface-binding pickers: a
/// RoomPlan surface/object or an ARMesh anchor, labelled for display.
public struct CapturedSurfaceOption: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case roomPlanSurface
        case roomPlanObject
        case meshAnchor
    }
    public let identifier: String
    public let kind: Kind
    public let label: String
    public var id: String { identifier }
    public init(identifier: String, kind: Kind, label: String) {
        self.identifier = identifier
        self.kind = kind
        self.label = label
    }
}

/// Theater-semantic authority sections (#218, #233, #256, #262, #264,
/// #280, #281, #288, #289, #290, #316, #335, #346). Every record is
/// user-authored authority — the app never infers the semantics it
/// records.
///
/// #357: mission/object-first workspace. Task-plan semantic/evidence
/// items deep-link straight into the matching authoring form, entity
/// context filters the offered record kinds, staged records list in
/// human terms with inspect/edit/delete (+undo), the snapshot flow
/// guides the observation prerequisite, and the full raw kind list
/// stays reachable under Advanced. Records stay staged until the
/// workspace's canonical Save.
struct TheaterAuthoritySection: View {
    let coordinateSpaceID: CoordinateSpaceID
    /// Working revision identity — room-state snapshots bind it.
    let captureRevisionID: CaptureRevisionID
    let availableEvidenceRefs: [String]
    /// Staged annotation entities authority records may reference.
    let entities: [CaptureAnnotationEntity]
    /// Staged measurements — used to evaluate task-plan outcomes.
    let measurements: [CaptureMeasurement]
    /// Captured RoomPlan surfaces/objects offered for binding (#218).
    let roomPlanSurfaces: [CapturedSurfaceOption]
    /// Captured mesh anchors offered for binding (#218).
    let meshAnchors: [CapturedSurfaceOption]
    /// Design targets the placement-verification flow can aim at
    /// (#346); empty until the mission supplies them.
    let plannedTargets: [PlannedAsBuiltSpec]
    /// Proven plan alignment the placement assist runs under, when
    /// the session established one (#293).
    let establishedAlignment: PlanAlignmentAuthority?
    /// Live task-plan tracker — when bound, mission items deep-link
    /// into authoring and fulfill through exact record/evidence refs
    /// (#357/#359).
    var taskPlanStatus: Binding<CaptureTaskPlanStatus>?
    @Binding var authorities: TheaterAuthorityCollection

    @State private var addingKind: AuthorityKind?
    @State private var addPrefillEntityID: AnnotationEntityID?
    @State private var missionContext: MissionContext?
    @State private var editingDraft: AuthorityRecordDraft?
    @State private var inspectingDescriptor: AuthorityRecordDescriptor?
    @State private var bindingRecordItem: HTDTTaskPlanSemanticItem?
    @State private var bindingEvidenceItem: HTDTTaskPlanEvidenceItem?
    @State private var objectEntitySelection: AnnotationEntityID?
    @State private var lastDeleted: AuthorityRecordDraft?
    @State private var errorText: String?

    /// The semantic item a newly authored record should fulfill.
    private struct MissionContext: Identifiable {
        let itemID: String
        let label: String
        var id: String { itemID }
    }

    /// One record kind the workspace can stage. `rawValue` matches the
    /// `SemanticTaskKind` wire token so a mission item maps straight to
    /// its authoring form.
    enum AuthorityKind: String, CaseIterable, Identifiable {
        case surfaceSemantics = "surface_semantics"
        case surfaceConstruction = "surface_construction"
        case problemSurface = "problem_surface"
        case constructionFeature = "construction_feature"
        case roomStateObservation = "room_state_observation"
        case roomStateSnapshot = "room_state_snapshot"
        case inventoryItem = "inventory_item"
        case furnitureSemantics = "furniture_semantics"
        case speakerInstallation = "speaker_installation"
        case screenSemantics = "screen_semantics"
        case seatLayout = "seat_layout"
        case routingVerification = "routing_verification"
        case projectorCommissioning = "projector_commissioning"
        case installationAlignment = "installation_alignment"

        var id: String { rawValue }

        var semanticKind: SemanticTaskKind {
            SemanticTaskKind(rawValue: rawValue)!
        }

        var title: String {
            switch self {
            case .surfaceSemantics:
                return String(localized: "Surface authority")
            case .surfaceConstruction:
                return String(localized: "Construction observation")
            case .problemSurface:
                return String(localized: "Problem surface")
            case .constructionFeature:
                return String(localized: "Construction feature")
            case .roomStateObservation:
                return String(localized: "Room state observation")
            case .roomStateSnapshot:
                return String(localized: "Room state snapshot")
            case .inventoryItem:
                return String(localized: "Inventory item")
            case .furnitureSemantics:
                return String(localized: "Furniture confirmation")
            case .speakerInstallation:
                return String(localized: "Speaker installation")
            case .screenSemantics:
                return String(localized: "Screen semantics")
            case .seatLayout:
                return String(localized: "Seat layout")
            case .routingVerification:
                return String(localized: "Routing verification")
            case .projectorCommissioning:
                return String(localized: "Projector commissioning")
            case .installationAlignment:
                return String(localized: "Placement verification")
            }
        }

        func count(in collection: TheaterAuthorityCollection) -> Int {
            switch self {
            case .surfaceSemantics:
                return collection.surfaceSemantics.count
            case .surfaceConstruction:
                return collection.surfaceConstructions.count
            case .problemSurface:
                return collection.problemSurfaces.count
            case .constructionFeature:
                return collection.constructionFeatures.count
            case .roomStateObservation:
                return collection.roomStateObservations.count
            case .roomStateSnapshot:
                return collection.roomStateSnapshots.count
            case .inventoryItem:
                return collection.inventoryItems.count
            case .furnitureSemantics:
                return collection.furnitureSemantics.count
            case .speakerInstallation:
                return collection.speakerInstallations.count
            case .screenSemantics:
                return collection.screenSemantics.count
            case .seatLayout:
                return collection.seatLayouts.count
            case .routingVerification:
                return collection.routingVerifications.count
            case .projectorCommissioning:
                return collection.projectorCommissionings.count
            case .installationAlignment:
                return collection.installationAlignments.count
            }
        }
    }

    /// Human-term grouping for the staged record list (#357).
    enum RecordGroup: String, CaseIterable, Identifiable {
        case roomAndSurfaces
        case roomState
        case equipment
        case objects
        case speakersAndAudio
        case projection
        case seating
        case placementVerification

        var id: String { rawValue }

        var title: String {
            switch self {
            case .roomAndSurfaces:
                return String(localized: "Room & surfaces")
            case .roomState:
                return String(localized: "Room state")
            case .equipment:
                return String(localized: "Equipment")
            case .objects:
                return String(localized: "Objects & furniture")
            case .speakersAndAudio:
                return String(localized: "Speakers & audio")
            case .projection:
                return String(localized: "Projection")
            case .seating:
                return String(localized: "Seating")
            case .placementVerification:
                return String(localized: "Placement verification")
            }
        }

        var kinds: [AuthorityKind] {
            switch self {
            case .roomAndSurfaces:
                return [
                    .surfaceSemantics, .surfaceConstruction,
                    .problemSurface, .constructionFeature,
                ]
            case .roomState:
                return [.roomStateObservation, .roomStateSnapshot]
            case .equipment:
                return [.inventoryItem]
            case .objects:
                return [.furnitureSemantics]
            case .speakersAndAudio:
                return [.speakerInstallation, .routingVerification]
            case .projection:
                return [.screenSemantics, .projectorCommissioning]
            case .seating:
                return [.seatLayout]
            case .placementVerification:
                return [.installationAlignment]
            }
        }
    }

    var body: some View {
        missionRows
        objectRows
        roomFlowRows
        recordRows
        advancedRows
        if let lastDeleted {
            HStack {
                Text(
                    String(localized: "Deleted ")
                        + lastDeleted.title
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Undo")) {
                    commit(lastDeleted, missionItemID: nil)
                    self.lastDeleted = nil
                }
            }
        }
        if let errorText {
            Text(errorText)
                .font(.caption)
                .foregroundStyle(.red)
        }
        Text(
            "Authorities are user-attested claims; the app never infers them. Records stay staged until Save."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .sheet(item: $addingKind) { kind in
            recordSheet(kind: kind)
        }
        .sheet(item: $editingDraft) { draft in
            editSheet(draft: draft)
        }
        .sheet(item: $inspectingDescriptor) { descriptor in
            inspectSheet(descriptor)
        }
        .sheet(item: $bindingRecordItem) { item in
            recordBindSheet(item)
        }
        .sheet(item: $bindingEvidenceItem) { item in
            evidenceBindSheet(item)
        }
    }

    // MARK: Mission tasks (#357/#359)

    @ViewBuilder private var missionRows: some View {
        if let status = taskPlanStatus {
            let plan = status.wrappedValue.planImport.plan
            if !plan.semanticTasks.isEmpty || !plan.evidenceTasks.isEmpty {
                Text(String(localized: "Mission tasks"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                let outcomes = status.wrappedValue.itemOutcomes(
                    annotations: entities,
                    measurements: measurements,
                    authorities: authorities,
                    committedEvidenceRefs: availableEvidenceRefs
                )
                ForEach(plan.semanticTasks, id: \.itemID) { item in
                    semanticMissionRow(item, outcomes: outcomes)
                }
                ForEach(plan.evidenceTasks, id: \.itemID) { item in
                    evidenceMissionRow(item, outcomes: outcomes)
                }
            }
        }
    }

    private func outcomeSymbol(
        _ outcome: TaskPlanItemOutcome?
    ) -> String {
        switch outcome {
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "arrow.right.circle"
        case .unavailable: return "exclamationmark.circle"
        default: return "circle"
        }
    }

    private func kindTitle(_ kind: SemanticTaskKind) -> String {
        AuthorityKind(rawValue: kind.rawValue)?.title ?? kind.rawValue
    }

    private func missionDetail(
        _ item: HTDTTaskPlanSemanticItem
    ) -> String {
        var parts = [kindTitle(item.semanticKind)]
        if let subtype = item.expectedSubtype {
            parts.append(subtype)
        }
        if let target = item.targetRef {
            parts.append(
                String(localized: "target ") + target
            )
        }
        if let planned = item.plannedRef {
            parts.append(
                String(localized: "plan ") + planned
            )
        }
        parts.append(
            item.requirement == .required
                ? String(localized: "required")
                : String(localized: "optional")
        )
        return parts.joined(separator: " · ")
    }

    private func semanticMissionRow(
        _ item: HTDTTaskPlanSemanticItem,
        outcomes: [CaptureTaskPlanStatusDocument.ItemOutcome]
    ) -> some View {
        let outcome = outcomes.first { $0.itemID == item.itemID }
        let completed = outcome?.outcome == .completed
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: outcomeSymbol(outcome?.outcome))
                    .foregroundStyle(
                        completed ? .green : .secondary
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        item.label
                            ?? kindTitle(item.semanticKind)
                    )
                    Text(missionDetail(item))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                if !completed {
                    Button(String(localized: "Author record")) {
                        missionContext = MissionContext(
                            itemID: item.itemID,
                            label: item.label
                                ?? kindTitle(item.semanticKind)
                        )
                        addPrefillEntityID = item.targetRef
                            .flatMap {
                                AnnotationEntityID(
                                    canonicalString: $0
                                )
                            }
                        addingKind = AuthorityKind(
                            rawValue: item.semanticKind.rawValue
                        )
                    }
                    Button(String(localized: "Bind existing")) {
                        bindingRecordItem = item
                    }
                    markMenu(item.itemID)
                } else {
                    Button(String(localized: "Unbind")) {
                        markResult(
                            of: {
                                try taskPlanStatus?.wrappedValue
                                    .clearFulfillment(
                                        itemID: item.itemID
                                    )
                            }
                        )
                    }
                    .font(.caption)
                }
            }
            .font(.callout)
        }
    }

    private func evidenceMissionRow(
        _ item: HTDTTaskPlanEvidenceItem,
        outcomes: [CaptureTaskPlanStatusDocument.ItemOutcome]
    ) -> some View {
        let outcome = outcomes.first { $0.itemID == item.itemID }
        let completed = outcome?.outcome == .completed
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: outcomeSymbol(outcome?.outcome))
                    .foregroundStyle(
                        completed ? .green : .secondary
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.purpose)
                    Text(
                        [
                            item.subjectRef,
                            item.guidance,
                            item.requirement == .required
                                ? String(localized: "required")
                                : String(localized: "optional"),
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                if !completed {
                    Button(String(localized: "Bind evidence")) {
                        bindingEvidenceItem = item
                    }
                    markMenu(item.itemID)
                } else {
                    Button(String(localized: "Unbind")) {
                        markResult(
                            of: {
                                try taskPlanStatus?.wrappedValue
                                    .clearFulfillment(
                                        itemID: item.itemID
                                    )
                            }
                        )
                    }
                    .font(.caption)
                }
            }
            .font(.callout)
        }
    }

    private func markMenu(_ itemID: String) -> some View {
        Menu(String(localized: "Mark")) {
            Button(String(localized: "Skipped")) {
                mark(itemID, .skipped)
            }
            Button(String(localized: "Unavailable")) {
                mark(itemID, .unavailable)
            }
            Button(String(localized: "Pending")) {
                mark(itemID, .pending)
            }
        }
    }

    private func mark(
        _ itemID: String,
        _ outcome: TaskPlanItemOutcome
    ) {
        markResult {
            try taskPlanStatus?.wrappedValue.mark(
                itemID: itemID,
                as: outcome
            )
        }
    }

    private func markResult(of action: () throws -> Void) {
        do {
            try action()
            errorText = nil
        } catch {
            errorText = String(describing: error)
        }
    }

    // MARK: Object-context flows (#357)

    @ViewBuilder private var objectRows: some View {
        if !entities.isEmpty {
            Text(String(localized: "Document an object"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            EntityPicker(
                title: String(localized: "Object"),
                entities: entities,
                types: [],
                selection: $objectEntitySelection
            )
            if let objectEntitySelection,
               let entity = entities.first(where: {
                   $0.entityID == objectEntitySelection
               })
            {
                ForEach(objectKinds(for: entity.type)) { kind in
                    Button(kind.title) {
                        addPrefillEntityID = objectEntitySelection
                        missionContext = nil
                        addingKind = kind
                    }
                }
            }
        }
    }

    /// Record kinds an entity of this type can plausibly host — the
    /// contextual entry the flat list used to flatten away (#357).
    private func objectKinds(
        for type: AnnotationEntityType
    ) -> [AuthorityKind] {
        switch type {
        case .speaker, .subwoofer:
            return [
                .speakerInstallation, .routingVerification,
                .installationAlignment,
            ]
        case .projector:
            return [
                .projectorCommissioning, .installationAlignment,
            ]
        case .projectionScreen:
            return [.screenSemantics, .roomStateObservation]
        case .seat:
            return [.seatLayout, .roomStateObservation]
        case .equipmentRack:
            return [.inventoryItem]
        case .acousticTreatment:
            return [.surfaceSemantics, .roomStateObservation]
        default:
            return [.roomStateObservation, .furnitureSemantics]
        }
    }

    // MARK: Room-level flows

    @ViewBuilder private var roomFlowRows: some View {
        Text(String(localized: "Document the room"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        ForEach(
            [
                AuthorityKind.surfaceSemantics, .surfaceConstruction,
                .problemSurface, .constructionFeature,
                .roomStateObservation, .inventoryItem,
                .furnitureSemantics,
            ]
        ) { kind in
            Button(kind.title) {
                addPrefillEntityID = nil
                missionContext = nil
                addingKind = kind
            }
        }
        Button(AuthorityKind.roomStateSnapshot.title) {
            addPrefillEntityID = nil
            missionContext = nil
            addingKind = .roomStateSnapshot
        }
        .disabled(authorities.roomStateObservations.isEmpty)
        if authorities.roomStateObservations.isEmpty {
            Text(
                "Snapshots bind room-state observations — record an observation first."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Staged records

    @ViewBuilder private var recordRows: some View {
        let descriptors = authorities.recordDescriptors
        if !descriptors.isEmpty {
            Text(String(localized: "Authority records"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(RecordGroup.allCases) { group in
                let rows = descriptors.filter { descriptor in
                    group.kinds.contains {
                        $0.semanticKind == descriptor.kind
                    }
                }
                if !rows.isEmpty {
                    Text(group.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(rows) { descriptor in
                        Button {
                            inspectingDescriptor = descriptor
                        } label: {
                            HStack {
                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(displayTitle(descriptor))
                                    Text(descriptorLine(descriptor))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(
                                    systemName: "chevron.right"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func displayTitle(
        _ descriptor: AuthorityRecordDescriptor
    ) -> String {
        if let entityID = descriptor.targetEntityID,
           let entity = entities.first(where: {
               $0.entityID == entityID
           })
        {
            return entity.label
        }
        return descriptor.title
    }

    private func descriptorLine(
        _ descriptor: AuthorityRecordDescriptor
    ) -> String {
        [
            kindTitle(descriptor.kind),
            descriptor.detail,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    // MARK: Advanced raw list (#357)

    private var advancedRows: some View {
        DisclosureGroup(
            String(localized: "Advanced — every record kind")
        ) {
            ForEach(AuthorityKind.allCases) { kind in
                LabeledContent(
                    kind.title,
                    value: String(kind.count(in: authorities))
                )
            }
        }
        .font(.caption)
    }

    // MARK: Sheets

    private func recordSheet(kind: AuthorityKind) -> some View {
        NavigationStack {
            AuthorityRecordForm(
                kind: kind,
                coordinateSpaceID: coordinateSpaceID,
                captureRevisionID: captureRevisionID,
                availableEvidenceRefs: availableEvidenceRefs,
                entities: entities,
                roomPlanSurfaces: roomPlanSurfaces,
                meshAnchors: meshAnchors,
                authorities: authorities,
                plannedTargets: plannedTargets,
                establishedAlignment: establishedAlignment,
                editing: nil,
                prefilledEntityID: addPrefillEntityID,
                missionLabel: missionContext?.label
            ) { draft in
                commit(draft, missionItemID: missionContext?.itemID)
            }
        }
    }

    private func editSheet(draft: AuthorityRecordDraft) -> some View {
        NavigationStack {
            AuthorityRecordForm(
                kind: draft.authorityKind,
                coordinateSpaceID: coordinateSpaceID,
                captureRevisionID: captureRevisionID,
                availableEvidenceRefs: availableEvidenceRefs,
                entities: entities,
                roomPlanSurfaces: roomPlanSurfaces,
                meshAnchors: meshAnchors,
                authorities: authorities,
                plannedTargets: plannedTargets,
                establishedAlignment: establishedAlignment,
                editing: draft,
                prefilledEntityID: nil,
                missionLabel: nil
            ) { updated in
                commit(updated, missionItemID: nil)
            }
        }
    }

    private func inspectSheet(
        _ descriptor: AuthorityRecordDescriptor
    ) -> some View {
        NavigationStack {
            AuthorityRecordDetailView(
                descriptor: descriptor,
                kindTitle: kindTitle(descriptor.kind),
                lines: detailLines(for: descriptor),
                onEdit: {
                    if let draft = AuthorityRecordDraft(
                        descriptor: descriptor,
                        in: authorities
                    ) {
                        editingDraft = draft
                        inspectingDescriptor = nil
                    }
                },
                onDelete: {
                    removeRecord(descriptor)
                }
            )
        }
    }

    private func recordBindSheet(
        _ item: HTDTTaskPlanSemanticItem
    ) -> some View {
        NavigationStack {
            Form {
                let candidates = authorities.recordDescriptors
                    .filter {
                        $0.kind == item.semanticKind
                            && (item.expectedSubtype == nil
                                || $0.subtype == item.expectedSubtype)
                    }
                if candidates.isEmpty {
                    Text(
                        "No matching records yet — author one first."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                ForEach(candidates) { descriptor in
                    Button(displayTitle(descriptor)) {
                        do {
                            try taskPlanStatus?.wrappedValue.fulfill(
                                itemID: item.itemID,
                                with: descriptor.recordID,
                                in: authorities
                            )
                            errorText = nil
                        } catch {
                            errorText = String(describing: error)
                        }
                        bindingRecordItem = nil
                    }
                }
            }
            .navigationTitle(
                String(localized: "Bind record")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        bindingRecordItem = nil
                    }
                }
            }
        }
    }

    private func evidenceBindSheet(
        _ item: HTDTTaskPlanEvidenceItem
    ) -> some View {
        NavigationStack {
            Form {
                if availableEvidenceRefs.isEmpty {
                    Text(
                        "No committed evidence frames yet — capture evidence first."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                ForEach(
                    availableEvidenceRefs,
                    id: \.self
                ) { reference in
                    Button(reference) {
                        do {
                            try taskPlanStatus?.wrappedValue
                                .fulfillEvidence(
                                    itemID: item.itemID,
                                    evidenceRef: reference,
                                    in: availableEvidenceRefs
                                )
                            errorText = nil
                        } catch {
                            errorText = String(describing: error)
                        }
                        bindingEvidenceItem = nil
                    }
                }
            }
            .navigationTitle(
                String(localized: "Bind evidence")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        bindingEvidenceItem = nil
                    }
                }
            }
        }
    }

    // MARK: Apply / remove

    private func commit(
        _ draft: AuthorityRecordDraft,
        missionItemID: String?
    ) {
        do {
            let updated = try draft.apply(to: authorities)
            authorities = updated
            if let missionItemID {
                try taskPlanStatus?.wrappedValue.fulfill(
                    itemID: missionItemID,
                    with: draft.recordID,
                    in: updated
                )
            }
            errorText = nil
        } catch {
            errorText = String(describing: error)
        }
        addingKind = nil
        editingDraft = nil
        missionContext = nil
        addPrefillEntityID = nil
    }

    /// Removes a staged record; the collection's validating init makes
    /// a record still referenced elsewhere refuse deletion rather than
    /// strand the referencing record (#357).
    private func removeRecord(
        _ descriptor: AuthorityRecordDescriptor
    ) {
        guard
            let draft = AuthorityRecordDraft(
                descriptor: descriptor,
                in: authorities
            )
        else { return }
        do {
            authorities = try AuthorityRecordDraft.removed(
                descriptor,
                from: authorities
            )
            lastDeleted = draft
            errorText = nil
        } catch {
            errorText = String(localized: "Record is still referenced")
                + " · " + String(describing: error)
        }
        inspectingDescriptor = nil
    }

    private func detailLines(
        for descriptor: AuthorityRecordDescriptor
    ) -> [(String, String)] {
        var lines: [(String, String)] = [
            (String(localized: "ID"), descriptor.recordID.description),
        ]
        guard
            let draft = AuthorityRecordDraft(
                descriptor: descriptor,
                in: authorities
            )
        else { return lines }
        switch draft {
        case .surfaceSemantics(let record):
            lines.append(("Host", record.hostClassification.rawValue))
            if let label = record.label {
                lines.append(("Label", label))
            }
            lines += bindingLines(record.binding)
        case .surfaceConstruction(let record):
            lines.append(
                ("Construction", record.constructionKind.rawValue)
            )
            lines.append(("Source", record.source.rawValue))
            if let detail = record.materialDetail {
                lines.append(("Material", detail))
            }
            lines += bindingLines(record.binding)
        case .problemSurface(let record):
            lines.append(("Kind", record.kind.rawValue))
            if let notes = record.notes {
                lines.append(("Notes", notes))
            }
            lines += bindingLines(record.binding)
        case .constructionFeature(let record):
            lines.append(("Kind", record.kind.rawValue))
            lines.append(
                ("Confirmation", record.confirmationSource.rawValue)
            )
            if let label = record.label {
                lines.append(("Label", label))
            }
            lines += bindingLines(record.binding)
        case .roomStateObservation(let record):
            lines.append(("Kind", record.kind.rawValue))
            lines.append(("State", record.state.rawValue))
            if let detail = record.stateDetail {
                lines.append(("Detail", detail))
            }
            if let target = record.targetEntityID {
                lines.append(
                    ("Entity", entityLabel(target))
                )
            }
            lines.append(("Observed", record.observedAtUTC))
        case .roomStateSnapshot(let record):
            lines.append(("Label", record.label))
            lines.append(
                (
                    "Observations",
                    String(record.observationIDs.count)
                )
            )
            if let campaign = record.campaignID {
                lines.append(("Campaign", campaign))
            }
            lines.append(("Observed", record.observedAtUTC))
        case .inventoryItem(let record):
            lines.append(
                ("Class", record.equipmentClass.rawValue)
            )
            lines.append(("Label", record.userLabel))
            if let manufacturer = record.manufacturer {
                lines.append(("Manufacturer", manufacturer))
            }
            if let model = record.model {
                lines.append(("Model", model))
            }
            if let rack = record.hostRackEntityID {
                lines.append(("Rack", entityLabel(rack)))
            }
        case .furnitureSemantics(let record):
            lines.append(("Category", record.category.rawValue))
            lines.append(
                ("Relevance", record.relevance.rawValue)
            )
            lines.append(("Source", record.source.rawValue))
            if let target = record.targetEntityID {
                lines.append(("Entity", entityLabel(target)))
            }
        case .speakerInstallation(let record):
            lines.append(
                ("Speaker", entityLabel(record.speakerEntityID))
            )
            lines.append(
                ("Mounting", record.mountingMode.rawValue)
            )
            if let note = record.hardwareNote {
                lines.append(("Hardware", note))
            }
        case .screenSemantics(let record):
            lines.append(
                ("Screen", entityLabel(record.screenEntityID))
            )
            lines.append(
                (
                    "Transparent",
                    record.acousticallyTransparent.rawValue
                )
            )
            if !record.behindScreenSpeakerEntityIDs.isEmpty {
                lines.append(
                    (
                        "Behind-screen speakers",
                        String(
                            record.behindScreenSpeakerEntityIDs
                                .count
                        )
                    )
                )
            }
        case .seatLayout(let record):
            lines.append(("Seat", entityLabel(record.seatEntityID)))
            if let row = record.rowIdentifier {
                lines.append(("Row", row))
            }
            if let ordinal = record.seatOrdinal {
                lines.append(("Ordinal", String(ordinal)))
            }
        case .routingVerification(let record):
            lines.append(
                (
                    "Output",
                    record.channelRole?.rawValue
                        ?? record.outputLabel ?? ""
                )
            )
            lines.append(("Band", record.bandScope.rawValue))
            lines.append(
                ("State", record.verificationState.rawValue)
            )
            lines.append(
                (
                    "Speakers",
                    record.speakerEntityIDs.map(entityLabel)
                        .joined(separator: ", ")
                )
            )
            if let method = record.verificationMethod {
                lines.append(("Method", method.rawValue))
            }
            lines.append(("Observed", record.observedAtUTC))
        case .projectorCommissioning(let record):
            lines.append(
                (
                    "Projector",
                    entityLabel(record.projectorEntityID)
                )
            )
            if let throwObservation = record.throwObservation {
                lines.append(
                    ("Throw", settingText(throwObservation))
                )
                if let endpoints = record.throwEndpointSemantics {
                    lines.append(("Endpoints", endpoints))
                }
            }
            if let mount = record.mountOrientation {
                lines.append(("Mount", mount.rawValue))
            }
            if let focus = record.focusState {
                lines.append(("Focus", focus.rawValue))
            }
            lines.append(("Observed", record.observedAtUTC))
        case .installationAlignment(let record):
            lines.append(("Target", record.targetPlannedEntityID))
            lines.append(("Mode", record.guidanceMode.rawValue))
            lines.append(
                ("Precision", record.precisionSufficiency.rawValue)
            )
            lines.append(
                ("Final entity", entityLabel(record.finalEntityID))
            )
            if let deviation = record.reportedDeviation {
                lines.append(
                    (
                        "Deviation",
                        String(
                            format: "%.3f m",
                            deviation.distanceMeters
                        )
                    )
                )
            }
            lines.append(("Observed", record.observedAtUTC))
        }
        return lines
    }

    private func bindingLines(
        _ binding: SurfaceRegionBinding
    ) -> [(String, String)] {
        var lines: [(String, String)] = []
        if let surface = binding.roomPlanSurfaceID {
            lines.append(("RoomPlan surface", surface))
        }
        if let object = binding.roomPlanObjectID {
            lines.append(("RoomPlan object", object))
        }
        if let anchor = binding.meshAnchorID {
            lines.append(("Mesh anchor", anchor.uuidString))
        }
        if let semantic = binding.semanticEntityID {
            lines.append(("Semantic entity", semantic))
        }
        return lines
    }

    private func entityLabel(_ entityID: AnnotationEntityID) -> String {
        entities.first(where: { $0.entityID == entityID })?.label
            ?? entityID.description
    }

    private func settingText(_ value: AttestedSettingValue) -> String {
        switch value.state {
        case .unknown:
            return String(localized: "unknown")
        case .attested:
            var text = value.textValue ?? ""
            if let numeric = value.numericValue {
                if !text.isEmpty { text += " " }
                text += String(format: "%.3f", numeric)
            }
            return text
        }
    }
}

/// The staged record produced by an add/edit sheet. `apply` is an
/// upsert keyed on the record's own identity so edits stay correctable
/// (#357); `removed` rebuilds without the record so the validating
/// collection init still refuses a delete that would strand a
/// cross-reference.
enum AuthorityRecordDraft: Identifiable {
    case surfaceSemantics(SurfaceSemanticAuthority)
    case surfaceConstruction(SurfaceConstructionObservation)
    case problemSurface(ProblemSurfaceObservation)
    case constructionFeature(ConstructionFeatureCandidate)
    case roomStateObservation(RoomStateObservation)
    case roomStateSnapshot(RoomStateSnapshot)
    case inventoryItem(SystemInventoryItem)
    case furnitureSemantics(FurnitureSemanticConfirmation)
    case speakerInstallation(SpeakerInstallationAuthority)
    case screenSemantics(ProjectionScreenSemantics)
    case seatLayout(SeatLayoutAuthority)
    case routingVerification(RoutingVerificationAuthority)
    case projectorCommissioning(ProjectorCommissioningAuthority)
    case installationAlignment(InstallationAlignmentRecord)

    var id: AuthorityRecordID { recordID }

    /// The record's identity in the shared record-id namespace.
    var recordID: AuthorityRecordID {
        switch self {
        case .surfaceSemantics(let record):
            return record.authorityID
        case .surfaceConstruction(let record):
            return record.authorityID
        case .problemSurface(let record):
            return record.authorityID
        case .constructionFeature(let record):
            return record.authorityID
        case .roomStateObservation(let record):
            return AuthorityRecordID(
                rawValue: record.observationID.rawValue
            )
        case .roomStateSnapshot(let record):
            return AuthorityRecordID(
                rawValue: record.snapshotID.rawValue
            )
        case .inventoryItem(let record):
            return record.itemID
        case .furnitureSemantics(let record):
            return record.authorityID
        case .speakerInstallation(let record):
            return record.authorityID
        case .screenSemantics(let record):
            return record.authorityID
        case .seatLayout(let record):
            return record.authorityID
        case .routingVerification(let record):
            return record.authorityID
        case .projectorCommissioning(let record):
            return record.authorityID
        case .installationAlignment(let record):
            return record.authorityID
        }
    }

    var authorityKind: TheaterAuthoritySection.AuthorityKind {
        switch self {
        case .surfaceSemantics: return .surfaceSemantics
        case .surfaceConstruction: return .surfaceConstruction
        case .problemSurface: return .problemSurface
        case .constructionFeature: return .constructionFeature
        case .roomStateObservation: return .roomStateObservation
        case .roomStateSnapshot: return .roomStateSnapshot
        case .inventoryItem: return .inventoryItem
        case .furnitureSemantics: return .furnitureSemantics
        case .speakerInstallation: return .speakerInstallation
        case .screenSemantics: return .screenSemantics
        case .seatLayout: return .seatLayout
        case .routingVerification: return .routingVerification
        case .projectorCommissioning: return .projectorCommissioning
        case .installationAlignment: return .installationAlignment
        }
    }

    /// Human-facing label for undo/error affordances (#357).
    var title: String {
        switch self {
        case .surfaceSemantics(let record):
            return record.label ?? record.authorityID.description
        case .surfaceConstruction(let record):
            return record.constructionKind.rawValue
        case .problemSurface(let record):
            return record.kind.rawValue
        case .constructionFeature(let record):
            return record.label ?? record.kind.rawValue
        case .roomStateObservation(let record):
            return record.kind.rawValue
        case .roomStateSnapshot(let record):
            return record.label
        case .inventoryItem(let record):
            return record.userLabel
        case .furnitureSemantics(let record):
            return record.category.rawValue
        case .speakerInstallation(let record):
            return record.speakerEntityID.description
        case .screenSemantics(let record):
            return record.screenEntityID.description
        case .seatLayout(let record):
            return record.seatEntityID.description
        case .routingVerification(let record):
            return record.channelRole?.rawValue
                ?? record.outputLabel
                ?? record.authorityID.description
        case .projectorCommissioning(let record):
            return record.projectorEntityID.description
        case .installationAlignment(let record):
            return record.targetPlannedEntityID
        }
    }

    /// Resolves a descriptor back to a full draft so records are
    /// inspectable/editable and deletions are undoable (#357).
    init?(
        descriptor: AuthorityRecordDescriptor,
        in collection: TheaterAuthorityCollection
    ) {
        switch descriptor.kind {
        case .surfaceSemantics:
            guard let record = collection.surfaceSemantics.first(
                where: { $0.authorityID == descriptor.recordID }
            ) else { return nil }
            self = .surfaceSemantics(record)
        case .surfaceConstruction:
            guard let record = collection.surfaceConstructions.first(
                where: { $0.authorityID == descriptor.recordID }
            ) else { return nil }
            self = .surfaceConstruction(record)
        case .problemSurface:
            guard let record = collection.problemSurfaces.first(
                where: { $0.authorityID == descriptor.recordID }
            ) else { return nil }
            self = .problemSurface(record)
        case .constructionFeature:
            guard let record = collection.constructionFeatures.first(
                where: { $0.authorityID == descriptor.recordID }
            ) else { return nil }
            self = .constructionFeature(record)
        case .roomStateObservation:
            guard let record = collection.roomStateObservations
                .first(where: {
                    AuthorityRecordID(rawValue: $0.observationID.rawValue)
                        == descriptor.recordID
                })
            else { return nil }
            self = .roomStateObservation(record)
        case .roomStateSnapshot:
            guard let record = collection.roomStateSnapshots
                .first(where: {
                    AuthorityRecordID(rawValue: $0.snapshotID.rawValue)
                        == descriptor.recordID
                })
            else { return nil }
            self = .roomStateSnapshot(record)
        case .inventoryItem:
            guard let record = collection.inventoryItems.first(
                where: { $0.itemID == descriptor.recordID }
            ) else { return nil }
            self = .inventoryItem(record)
        case .furnitureSemantics:
            guard let record = collection.furnitureSemantics.first(
                where: { $0.authorityID == descriptor.recordID }
            ) else { return nil }
            self = .furnitureSemantics(record)
        case .speakerInstallation:
            guard let record = collection.speakerInstallations.first(
                where: { $0.authorityID == descriptor.recordID }
            ) else { return nil }
            self = .speakerInstallation(record)
        case .screenSemantics:
            guard let record = collection.screenSemantics.first(
                where: { $0.authorityID == descriptor.recordID }
            ) else { return nil }
            self = .screenSemantics(record)
        case .seatLayout:
            guard let record = collection.seatLayouts.first(
                where: { $0.authorityID == descriptor.recordID }
            ) else { return nil }
            self = .seatLayout(record)
        case .routingVerification:
            guard let record = collection.routingVerifications.first(
                where: { $0.authorityID == descriptor.recordID }
            ) else { return nil }
            self = .routingVerification(record)
        case .projectorCommissioning:
            guard let record = collection.projectorCommissionings
                .first(where: {
                    $0.authorityID == descriptor.recordID
                })
            else { return nil }
            self = .projectorCommissioning(record)
        case .installationAlignment:
            guard let record = collection.installationAlignments
                .first(where: {
                    $0.authorityID == descriptor.recordID
                })
            else { return nil }
            self = .installationAlignment(record)
        }
    }

    /// Mutable copy of the collection's sections so apply/remove share
    /// one rebuild site and the validating init re-checks every
    /// cross-reference.
    private struct Sections {
        var surfaceSemantics: [SurfaceSemanticAuthority]
        var surfaceConstructions: [SurfaceConstructionObservation]
        var problemSurfaces: [ProblemSurfaceObservation]
        var constructionFeatures: [ConstructionFeatureCandidate]
        var roomStateObservations: [RoomStateObservation]
        var roomStateSnapshots: [RoomStateSnapshot]
        var inventoryItems: [SystemInventoryItem]
        var furnitureSemantics: [FurnitureSemanticConfirmation]
        var speakerInstallations: [SpeakerInstallationAuthority]
        var screenSemantics: [ProjectionScreenSemantics]
        var seatLayouts: [SeatLayoutAuthority]
        var routingVerifications: [RoutingVerificationAuthority]
        var projectorCommissionings: [ProjectorCommissioningAuthority]
        var installationAlignments: [InstallationAlignmentRecord]

        init(_ collection: TheaterAuthorityCollection) {
            surfaceSemantics = collection.surfaceSemantics
            surfaceConstructions = collection.surfaceConstructions
            problemSurfaces = collection.problemSurfaces
            constructionFeatures = collection.constructionFeatures
            roomStateObservations = collection.roomStateObservations
            roomStateSnapshots = collection.roomStateSnapshots
            inventoryItems = collection.inventoryItems
            furnitureSemantics = collection.furnitureSemantics
            speakerInstallations = collection.speakerInstallations
            screenSemantics = collection.screenSemantics
            seatLayouts = collection.seatLayouts
            routingVerifications = collection.routingVerifications
            projectorCommissionings =
                collection.projectorCommissionings
            installationAlignments = collection.installationAlignments
        }

        func build() throws -> TheaterAuthorityCollection {
            try TheaterAuthorityCollection(
                surfaceSemantics: surfaceSemantics,
                surfaceConstructions: surfaceConstructions,
                problemSurfaces: problemSurfaces,
                constructionFeatures: constructionFeatures,
                roomStateObservations: roomStateObservations,
                roomStateSnapshots: roomStateSnapshots,
                inventoryItems: inventoryItems,
                furnitureSemantics: furnitureSemantics,
                speakerInstallations: speakerInstallations,
                screenSemantics: screenSemantics,
                seatLayouts: seatLayouts,
                routingVerifications: routingVerifications,
                projectorCommissionings: projectorCommissionings,
                installationAlignments: installationAlignments
            )
        }
    }

    private static func upsert<Record, ID: Hashable>(
        _ records: inout [Record],
        _ record: Record,
        _ id: KeyPath<Record, ID>
    ) {
        if let index = records.firstIndex(where: {
            $0[keyPath: id] == record[keyPath: id]
        }) {
            records[index] = record
        } else {
            records.append(record)
        }
    }

    /// Upserts this record into the collection — a record carrying an
    /// existing identity replaces it, otherwise it appends.
    func apply(
        to collection: TheaterAuthorityCollection
    ) throws -> TheaterAuthorityCollection {
        var sections = Sections(collection)
        switch self {
        case .surfaceSemantics(let record):
            Self.upsert(
                &sections.surfaceSemantics, record, \.authorityID
            )
        case .surfaceConstruction(let record):
            Self.upsert(
                &sections.surfaceConstructions, record, \.authorityID
            )
        case .problemSurface(let record):
            Self.upsert(
                &sections.problemSurfaces, record, \.authorityID
            )
        case .constructionFeature(let record):
            Self.upsert(
                &sections.constructionFeatures, record, \.authorityID
            )
        case .roomStateObservation(let record):
            Self.upsert(
                &sections.roomStateObservations, record, \.observationID
            )
        case .roomStateSnapshot(let record):
            Self.upsert(
                &sections.roomStateSnapshots, record, \.snapshotID
            )
        case .inventoryItem(let record):
            Self.upsert(&sections.inventoryItems, record, \.itemID)
        case .furnitureSemantics(let record):
            Self.upsert(
                &sections.furnitureSemantics, record, \.authorityID
            )
        case .speakerInstallation(let record):
            Self.upsert(
                &sections.speakerInstallations, record, \.authorityID
            )
        case .screenSemantics(let record):
            Self.upsert(
                &sections.screenSemantics, record, \.authorityID
            )
        case .seatLayout(let record):
            Self.upsert(&sections.seatLayouts, record, \.authorityID)
        case .routingVerification(let record):
            Self.upsert(
                &sections.routingVerifications, record, \.authorityID
            )
        case .projectorCommissioning(let record):
            Self.upsert(
                &sections.projectorCommissionings, record, \.authorityID
            )
        case .installationAlignment(let record):
            Self.upsert(
                &sections.installationAlignments, record, \.authorityID
            )
        }
        return try sections.build()
    }

    /// Rebuilds the collection without the descriptor's record. The
    /// validating init throws when another record still references it
    /// — the caller surfaces that as a refused delete, never a
    /// dangling link.
    static func removed(
        _ descriptor: AuthorityRecordDescriptor,
        from collection: TheaterAuthorityCollection
    ) throws -> TheaterAuthorityCollection {
        var sections = Sections(collection)
        let recordID = descriptor.recordID
        switch descriptor.kind {
        case .surfaceSemantics:
            sections.surfaceSemantics.removeAll {
                $0.authorityID == recordID
            }
        case .surfaceConstruction:
            sections.surfaceConstructions.removeAll {
                $0.authorityID == recordID
            }
        case .problemSurface:
            sections.problemSurfaces.removeAll {
                $0.authorityID == recordID
            }
        case .constructionFeature:
            sections.constructionFeatures.removeAll {
                $0.authorityID == recordID
            }
        case .roomStateObservation:
            sections.roomStateObservations.removeAll {
                AuthorityRecordID(rawValue: $0.observationID.rawValue)
                    == recordID
            }
        case .roomStateSnapshot:
            sections.roomStateSnapshots.removeAll {
                AuthorityRecordID(rawValue: $0.snapshotID.rawValue)
                    == recordID
            }
        case .inventoryItem:
            sections.inventoryItems.removeAll {
                $0.itemID == recordID
            }
        case .furnitureSemantics:
            sections.furnitureSemantics.removeAll {
                $0.authorityID == recordID
            }
        case .speakerInstallation:
            sections.speakerInstallations.removeAll {
                $0.authorityID == recordID
            }
        case .screenSemantics:
            sections.screenSemantics.removeAll {
                $0.authorityID == recordID
            }
        case .seatLayout:
            sections.seatLayouts.removeAll {
                $0.authorityID == recordID
            }
        case .routingVerification:
            sections.routingVerifications.removeAll {
                $0.authorityID == recordID
            }
        case .projectorCommissioning:
            sections.projectorCommissionings.removeAll {
                $0.authorityID == recordID
            }
        case .installationAlignment:
            sections.installationAlignments.removeAll {
                $0.authorityID == recordID
            }
        }
        return try sections.build()
    }
}

private func authorityUTCNow() -> String {
    BundleTimestamp.utcString(from: Date())
}

private func parsePolygonText(
    _ text: String
) throws -> [SpatialVector3F] {
    try text.split(whereSeparator: \.isNewline)
        .map(String.init)
        .map { line in
            let parts = line.split(separator: ",")
            guard parts.count == 3,
                  let x = Double(parts[0]
                        .trimmingCharacters(in: .whitespaces)),
                  let y = Double(parts[1]
                        .trimmingCharacters(in: .whitespaces)),
                  let z = Double(parts[2]
                        .trimmingCharacters(in: .whitespaces))
            else {
                throw TheaterAuthorityError.invalidPatchGeometry
            }
            return try SpatialVector3F(Float(x), Float(y), Float(z))
        }
}

private struct EntityPicker: View {
    let title: String
    let entities: [CaptureAnnotationEntity]
    let types: Set<AnnotationEntityType>
    @Binding var selection: AnnotationEntityID?

    var body: some View {
        let candidates = entities.filter {
            types.isEmpty || types.contains($0.type)
        }
        if candidates.isEmpty {
            LabeledContent(
                title,
                value: String(localized: "no matching annotation")
            )
            .foregroundStyle(.secondary)
        } else {
            Picker(title, selection: $selection) {
                Text(String(localized: "None"))
                    .tag(AnnotationEntityID?.none)
                ForEach(candidates, id: \.entityID) { entity in
                    Text(entity.label + " · " + entity.type.rawValue)
                        .tag(AnnotationEntityID?.some(entity.entityID))
                }
            }
        }
    }
}

/// One add/edit-sheet per authority kind; all record validation lives
/// in the model initializers so the form stays a thin staging surface.
/// `editing` seeds the fields from an existing record so the record
/// stays correctable before Save (#357); `prefilledEntityID` carries
/// the object-context selection into the matching pickers.
private struct AuthorityRecordForm: View {
    let kind: TheaterAuthoritySection.AuthorityKind
    let coordinateSpaceID: CoordinateSpaceID
    let captureRevisionID: CaptureRevisionID
    let availableEvidenceRefs: [String]
    let entities: [CaptureAnnotationEntity]
    let roomPlanSurfaces: [CapturedSurfaceOption]
    let meshAnchors: [CapturedSurfaceOption]
    let authorities: TheaterAuthorityCollection
    /// Design targets for placement-verification records (#346).
    let plannedTargets: [PlannedAsBuiltSpec]
    /// Proven plan alignment the session established, when any.
    let establishedAlignment: PlanAlignmentAuthority?
    /// Existing record being edited — nil means a new record.
    let editing: AuthorityRecordDraft?
    /// Entity the flow was opened from (object-context entry, #357).
    let prefilledEntityID: AnnotationEntityID?
    /// Mission task label this record answers to, when opened from a
    /// semantic plan item (#357/#359).
    let missionLabel: String?
    let onProduce: (AuthorityRecordDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var seeded = false

    // Shared surface-binding fields (#218 family).
    @State private var roomPlanSurfaceID = ""
    @State private var roomPlanObjectID = ""
    @State private var meshAnchorText = ""
    @State private var roomPlanPick = ""
    @State private var meshAnchorPick = ""
    @State private var semanticEntityID = ""
    @State private var polygonText = ""
    @State private var evidenceSelection: Set<String> = []

    // Per-kind fields.
    @State private var label = ""
    @State private var notes = ""
    @State private var hostClassification:
        SurfaceHostClassification = .roomBoundary
    @State private var includeTreatment = false
    @State private var treatmentWidth = ""
    @State private var treatmentHeight = ""
    @State private var treatmentOffset = ""
    @State private var treatmentAirGap = ""
    @State private var constructionKind:
        SurfaceConstructionKind = .gypsumDrywall
    @State private var constructionSource:
        ConstructionObservationSource = .userObservation
    @State private var materialDetail = ""
    @State private var problemKind: ProblemSurfaceKind = .mirror
    @State private var featureKind:
        ConstructionFeatureKind = .riser
    @State private var confirmationSource:
        SemanticConfirmationSource = .userConfirmed
    @State private var roomStateKind:
        RoomStateKind = .curtain
    @State private var roomStateValue:
        RoomStateValue = .unknown
    @State private var stateDetail = ""
    @State private var targetEntitySelection:
        AnnotationEntityID?
    @State private var targetAuthoritySelection:
        AuthorityRecordID?
    @State private var snapshotObservations:
        Set<RoomStateObservationID> = []
    @State private var campaignID = ""
    @State private var inventoryClass:
        InventoryEquipmentClass = .avReceiver
    @State private var manufacturer = ""
    @State private var model = ""
    @State private var userLabel = ""
    @State private var serialNumber = ""
    @State private var hostRackSelection:
        AnnotationEntityID?
    @State private var includePosition = false
    @State private var posX = ""
    @State private var posY = ""
    @State private var posZ = ""
    @State private var includeEquipmentRef = false
    @State private var equipmentID = ""
    @State private var equipmentVersion = ""
    @State private var equipmentHash = ""
    @State private var furnitureCategory:
        FurnitureCategory = .table
    @State private var furnitureRelevance:
        FurnitureRelevance = .movable
    @State private var furnitureEntitySelection:
        AnnotationEntityID?
    @State private var furnitureUsesBinding = false
    @State private var mountingMode:
        SpeakerMountingMode = .freestanding
    @State private var speakerEntitySelection:
        AnnotationEntityID?
    @State private var includeHostSurface = false
    @State private var insertionDepth = ""
    @State private var hardwareNote = ""
    @State private var screenEntitySelection:
        AnnotationEntityID?
    @State private var apertureWidth = ""
    @State private var apertureHeight = ""
    @State private var frameWidth = ""
    @State private var frameHeight = ""
    @State private var transparency:
        AcousticTransparencyState = .unknown
    @State private var transparencySource:
        TransparencyAuthoritySource = .userAttestation
    @State private var maskingObservationSelection:
        RoomStateObservationID?
    @State private var behindScreenSpeakers:
        Set<AnnotationEntityID> = []
    @State private var seatEntitySelection:
        AnnotationEntityID?
    @State private var rowIdentifier = ""
    @State private var seatOrdinal = ""
    @State private var riserSelection: AuthorityRecordID?
    @State private var earEntitySelection: AnnotationEntityID?
    @State private var eyeEntitySelection: AnnotationEntityID?
    @State private var headObstructionHeight = ""
    @State private var headObstructionRadius = ""
    @State private var facingAzimuth = ""
    @State private var facingElevation = ""

    // Routing verification (#316).
    @State private var channelRoleText = ""
    @State private var outputLabelText = ""
    @State private var sourceItemSelection: AuthorityRecordID?
    @State private var bandScope: RoutingBandScope = .fullRange
    @State private var routingSpeakerIDs: Set<AnnotationEntityID> = []
    @State private var routingState:
        RoutingVerificationState = .unknown
    @State private var routingMethod:
        RoutingVerificationMethod = .userAttestation
    @State private var deviceContextText = ""
    @State private var supersedesSelection: AuthorityRecordID?

    // Projector commissioning (#335).
    @State private var projectorEntitySelection: AnnotationEntityID?
    @State private var lensCenterEntitySelection: AnnotationEntityID?
    @State private var mountOrientationChoice = "not_recorded"
    @State private var focusStateChoice = "not_recorded"
    @State private var throwEntry = SettingEntry()
    @State private var throwEndpointsText = ""
    @State private var zoomEntry = SettingEntry()
    @State private var shiftHEntry = SettingEntry()
    @State private var shiftVEntry = SettingEntry()
    @State private var presetEntry = SettingEntry()
    @State private var opticalAzimuth = ""
    @State private var opticalElevation = ""
    @State private var imageAlignmentNoteText = ""
    @State private var plannedSpecRefText = ""
    @State private var screenAuthoritySelection: AuthorityRecordID?

    // Install alignment assist (#346).
    @State private var alignmentTargetID = ""
    @State private var alignmentTargetType:
        AnnotationEntityType = .speaker
    @State private var aimAtSelection: AnnotationEntityID?
    @State private var guidanceMode:
        AlignmentGuidanceMode = .textualInstructions
    @State private var useEstablishedAlignment = true
    @State private var alignmentMechanism:
        PlanAlignmentMechanism = .manualSurvey
    @State private var alignmentAuthorityRef = ""
    @State private var surveyX = ""
    @State private var surveyY = ""
    @State private var surveyZ = ""
    @State private var precision:
        PrecisionSufficiency = .unknown
    @State private var finalEntitySelection: AnnotationEntityID?

    @State private var errorText: String?

    var body: some View {
        Form {
            missionBanner
            if usesBinding {
                Section("Surface binding") {
                    if !roomPlanSurfaces.isEmpty {
                        Picker(
                            "Captured RoomPlan element",
                            selection: $roomPlanPick
                        ) {
                            Text(String(localized: "None"))
                                .tag("")
                            ForEach(roomPlanSurfaces) { option in
                                Text(option.label)
                                    .tag(option.identifier)
                            }
                        }
                        .onChange(of: roomPlanPick) { _, value in
                            guard
                                let option = roomPlanSurfaces
                                    .first(where: {
                                        $0.identifier == value
                                    })
                            else {
                                return
                            }
                            if option.kind == .roomPlanObject {
                                roomPlanObjectID = value
                            } else {
                                roomPlanSurfaceID = value
                            }
                        }
                    }
                    TextField(
                        "RoomPlan surface ID",
                        text: $roomPlanSurfaceID
                    )
                    TextField(
                        "RoomPlan object ID",
                        text: $roomPlanObjectID
                    )
                    if !meshAnchors.isEmpty {
                        Picker(
                            "Captured mesh anchor",
                            selection: $meshAnchorPick
                        ) {
                            Text(String(localized: "None"))
                                .tag("")
                            ForEach(meshAnchors) { option in
                                Text(option.label)
                                    .tag(option.identifier)
                            }
                        }
                        .onChange(of: meshAnchorPick) { _, value in
                            if !value.isEmpty {
                                meshAnchorText = value
                            }
                        }
                    }
                    TextField(
                        "Mesh anchor UUID",
                        text: $meshAnchorText
                    )
                    TextField(
                        "Semantic entity ID",
                        text: $semanticEntityID
                    )
                    TextField(
                        "Polygon outline, one x,y,z per line",
                        text: $polygonText,
                        axis: .vertical
                    )
                    Text(
                        "At least one lineage anchor is required: a RoomPlan ID, mesh anchor, semantic ID, or polygon."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            kindSections

            if usesEvidence,
               !availableEvidenceRefs.isEmpty
            {
                EvidenceReferenceSelector(
                    availableEvidenceRefs:
                        availableEvidenceRefs,
                    selectedEvidenceRefs: $evidenceSelection
                )
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(kind.title)
        .onAppear { seedIfNeeded() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Add")) {
                    produce()
                }
            }
        }
    }

    private var usesBinding: Bool {
        switch kind {
        case .surfaceSemantics, .surfaceConstruction,
             .problemSurface, .constructionFeature:
            return true
        case .furnitureSemantics:
            return furnitureUsesBinding
        case .speakerInstallation:
            return includeHostSurface
        default:
            return false
        }
    }

    /// The mission task this sheet answers, shown so the operator sees
    /// which plan item the record will fulfill (#357).
    @ViewBuilder private var missionBanner: some View {
        if let missionLabel {
            Section(String(localized: "Mission task")) {
                Text(missionLabel)
            }
        }
    }

    private var usesEvidence: Bool {
        switch kind {
        case .roomStateSnapshot:
            return false
        default:
            return true
        }
    }

    @ViewBuilder private var kindSections: some View {
        switch kind {
        case .surfaceSemantics:
            surfaceSemanticsSection
        case .surfaceConstruction:
            surfaceConstructionSection
        case .problemSurface:
            problemSurfaceSection
        case .constructionFeature:
            constructionFeatureSection
        case .roomStateObservation:
            roomStateObservationSection
        case .roomStateSnapshot:
            roomStateSnapshotSection
        case .inventoryItem:
            inventoryItemSection
        case .furnitureSemantics:
            furnitureSemanticsSection
        case .speakerInstallation:
            speakerInstallationSection
        case .screenSemantics:
            screenSemanticsSection
        case .seatLayout:
            seatLayoutSection
        case .routingVerification:
            routingVerificationSection
        case .projectorCommissioning:
            projectorCommissioningSection
        case .installationAlignment:
            installationAlignmentSection
        }
    }

    private var surfaceSemanticsSection: some View {
        Group {
            Section("Surface authority") {
                TextField("Label", text: $label)
                Picker(
                    "Host classification",
                    selection: $hostClassification
                ) {
                    ForEach(
                        [
                            SurfaceHostClassification.roomBoundary,
                            .objectSurface,
                            .unknown,
                        ],
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
            Section("Treatment placement") {
                Toggle(
                    "Attach treatment placement",
                    isOn: $includeTreatment
                )
                if includeTreatment {
                    TextField(
                        "Footprint width (m)",
                        text: $treatmentWidth
                    )
                    TextField(
                        "Footprint height (m)",
                        text: $treatmentHeight
                    )
                    TextField(
                        "Surface offset (m)",
                        text: $treatmentOffset
                    )
                    TextField(
                        "Air gap (m)",
                        text: $treatmentAirGap
                    )
                    TextField("Notes", text: $notes)
                    Text(
                        "Placement metadata only — no acoustic coefficients are synthesized."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var surfaceConstructionSection: some View {
        Section("Construction observation") {
            Picker(
                "Construction",
                selection: $constructionKind
            ) {
                ForEach(
                    SurfaceConstructionKind.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            TextField(
                "Material detail (optional)",
                text: $materialDetail
            )
            Picker("Source", selection: $constructionSource) {
                ForEach(
                    ConstructionObservationSource.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
        }
    }

    private var problemSurfaceSection: some View {
        Section("Problem surface") {
            Picker("Kind", selection: $problemKind) {
                ForEach(
                    ProblemSurfaceKind.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            TextField(
                "Notes (optional)",
                text: $notes
            )
        }
    }

    private var constructionFeatureSection: some View {
        Section("Construction feature") {
            Picker("Kind", selection: $featureKind) {
                ForEach(
                    ConstructionFeatureKind.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            Picker(
                "Confirmation",
                selection: $confirmationSource
            ) {
                ForEach(
                    SemanticConfirmationSource.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            TextField(
                "Label (optional)",
                text: $label
            )
        }
    }

    private var roomStateObservationSection: some View {
        Group {
            Section("Room state observation") {
                Picker("Kind", selection: $roomStateKind) {
                    ForEach(
                        RoomStateKind.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker("State", selection: $roomStateValue) {
                    ForEach(
                        RoomStateValue.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                TextField(
                    "State detail (optional)",
                    text: $stateDetail
                )
            }
            Section("Targets (optional)") {
                EntityPicker(
                    title: String(localized: "Entity"),
                    entities: entities,
                    types: [],
                    selection: $targetEntitySelection
                )
                Picker(
                    "Authority record",
                    selection: $targetAuthoritySelection
                ) {
                    Text(String(localized: "None"))
                        .tag(AuthorityRecordID?.none)
                    ForEach(
                        authorityRecordOptions,
                        id: \.id
                    ) { option in
                        Text(option.label)
                            .tag(
                                AuthorityRecordID?.some(option.id)
                            )
                    }
                }
            }
        }
    }

    private var roomStateSnapshotSection: some View {
        Group {
            Section("Snapshot") {
                TextField("Label", text: $label)
                TextField(
                    "Campaign ID (optional)",
                    text: $campaignID
                )
            }
            Section("Observations") {
                if authorities.roomStateObservations
                    .isEmpty
                {
                    Text(
                        "Add room state observations first; a snapshot binds an immutable set."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        authorities.roomStateObservations,
                        id: \.observationID
                    ) { observation in
                        Toggle(
                            isOn: Binding(
                                get: {
                                    snapshotObservations
                                        .contains(
                                            observation
                                                .observationID
                                        )
                                },
                                set: { on in
                                    if on {
                                        snapshotObservations
                                            .insert(
                                                observation
                                                    .observationID
                                            )
                                    } else {
                                        snapshotObservations
                                            .remove(
                                                observation
                                                    .observationID
                                            )
                                    }
                                }
                            )
                        ) {
                            Text(
                                observation.kind.rawValue
                                    + " · "
                                    + observation.state.rawValue
                            )
                        }
                    }
                }
            }
        }
    }

    private var inventoryItemSection: some View {
        Group {
            Section("Inventory item") {
                Picker(
                    "Class",
                    selection: $inventoryClass
                ) {
                    ForEach(
                        InventoryEquipmentClass.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                TextField(
                    "Label (required)",
                    text: $userLabel
                )
                TextField(
                    "Manufacturer (optional)",
                    text: $manufacturer
                )
                TextField(
                    "Model (optional)",
                    text: $model
                )
                TextField(
                    "Serial (optional)",
                    text: $serialNumber
                )
            }
            Section("Hosting") {
                EntityPicker(
                    title: String(localized: "Rack"),
                    entities: entities,
                    types: [.equipmentRack],
                    selection: $hostRackSelection
                )
                Toggle(
                    "Attach captured position",
                    isOn: $includePosition
                )
                if includePosition {
                    TextField("X (m)", text: $posX)
                    TextField("Y (m)", text: $posY)
                    TextField("Z (m)", text: $posZ)
                }
            }
            Section("Equipment authority") {
                Toggle(
                    "Attach equipment reference",
                    isOn: $includeEquipmentRef
                )
                if includeEquipmentRef {
                    TextField(
                        "Equipment ID",
                        text: $equipmentID
                    )
                    TextField(
                        "Equipment version",
                        text: $equipmentVersion
                    )
                    TextField(
                        "Equipment SHA-256",
                        text: $equipmentHash
                    )
                }
            }
        }
    }

    private var furnitureSemanticsSection: some View {
        Group {
            Section("Furniture confirmation") {
                EntityPicker(
                    title: String(localized: "Entity"),
                    entities: entities,
                    types: [],
                    selection: $furnitureEntitySelection
                )
                Toggle(
                    "Bind a surface instead/as well",
                    isOn: $furnitureUsesBinding
                )
                Picker(
                    "Category",
                    selection: $furnitureCategory
                ) {
                    ForEach(
                        FurnitureCategory.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker(
                    "Relevance",
                    selection: $furnitureRelevance
                ) {
                    ForEach(
                        FurnitureRelevance.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker(
                    "Confirmation",
                    selection: $confirmationSource
                ) {
                    ForEach(
                        SemanticConfirmationSource.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
        }
    }

    private var speakerInstallationSection: some View {
        Group {
            Section("Speaker installation") {
                EntityPicker(
                    title: String(localized: "Speaker"),
                    entities: entities,
                    types: [.speaker, .subwoofer],
                    selection: $speakerEntitySelection
                )
                Picker(
                    "Mounting",
                    selection: $mountingMode
                ) {
                    ForEach(
                        SpeakerMountingMode.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                TextField(
                    "Insertion depth (m, optional)",
                    text: $insertionDepth
                )
                TextField(
                    "Hardware note (optional)",
                    text: $hardwareNote
                )
                Toggle(
                    "Bind host surface",
                    isOn: $includeHostSurface
                )
            }
        }
    }

    private var screenSemanticsSection: some View {
        Group {
            Section("Screen semantics") {
                EntityPicker(
                    title: String(localized: "Screen"),
                    entities: entities,
                    types: [.projectionScreen],
                    selection: $screenEntitySelection
                )
                Picker(
                    "Acoustically transparent",
                    selection: $transparency
                ) {
                    ForEach(
                        AcousticTransparencyState.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                if transparency != .unknown {
                    Picker(
                        "Transparency source",
                        selection: $transparencySource
                    ) {
                        ForEach(
                            TransparencyAuthoritySource
                                .allCases,
                            id: \.self
                        ) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                }
            }
            Section("Dimensions (m, optional)") {
                TextField(
                    "Visible aperture width",
                    text: $apertureWidth
                )
                TextField(
                    "Visible aperture height",
                    text: $apertureHeight
                )
                TextField(
                    "Outer frame width",
                    text: $frameWidth
                )
                TextField(
                    "Outer frame height",
                    text: $frameHeight
                )
            }
            Section("Relations") {
                Picker(
                    "Masking observation",
                    selection: $maskingObservationSelection
                ) {
                    Text(String(localized: "None"))
                        .tag(RoomStateObservationID?.none)
                    ForEach(
                        authorities.roomStateObservations
                            .filter {
                                $0.kind == .screenMasking
                            },
                        id: \.observationID
                    ) { observation in
                        Text(observation.state.rawValue)
                            .tag(
                                RoomStateObservationID?
                                    .some(observation.observationID)
                            )
                    }
                }
                ForEach(
                    entities.filter {
                        $0.type == .speaker
                            || $0.type == .subwoofer
                    },
                    id: \.entityID
                ) { entity in
                    Toggle(
                        isOn: Binding(
                            get: {
                                behindScreenSpeakers
                                    .contains(entity.entityID)
                            },
                            set: { on in
                                if on {
                                    behindScreenSpeakers
                                        .insert(entity.entityID)
                                } else {
                                    behindScreenSpeakers
                                        .remove(entity.entityID)
                                }
                            }
                        )
                    ) {
                        Text(entity.label)
                    }
                }
                Text(
                    "Toggle speakers mounted behind the screen."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var seatLayoutSection: some View {
        Group {
            Section("Seat layout") {
                EntityPicker(
                    title: String(localized: "Seat"),
                    entities: entities,
                    types: [.seat],
                    selection: $seatEntitySelection
                )
                TextField(
                    "Row identifier (optional)",
                    text: $rowIdentifier
                )
                TextField(
                    "Seat ordinal (optional)",
                    text: $seatOrdinal
                )
                Picker(
                    "Riser feature",
                    selection: $riserSelection
                ) {
                    Text(String(localized: "None"))
                        .tag(AuthorityRecordID?.none)
                    ForEach(
                        riserOptions,
                        id: \.id
                    ) { option in
                        Text(option.label)
                            .tag(
                                AuthorityRecordID?.some(option.id)
                            )
                    }
                }
            }
            Section("Listening linkage") {
                EntityPicker(
                    title: String(localized: "Ear position"),
                    entities: entities,
                    types: [.listeningPosition],
                    selection: $earEntitySelection
                )
                EntityPicker(
                    title: String(localized: "Eye reference"),
                    entities: entities,
                    types: [.referencePoint],
                    selection: $eyeEntitySelection
                )
                TextField(
                    "Facing azimuth deg (optional)",
                    text: $facingAzimuth
                )
                TextField(
                    "Facing elevation deg (optional)",
                    text: $facingElevation
                )
            }
            Section("Head obstruction (m, optional)") {
                TextField(
                    "Height",
                    text: $headObstructionHeight
                )
                TextField(
                    "Radius",
                    text: $headObstructionRadius
                )
            }
        }
    }

    // MARK: Routing verification (#316)

    private var routingVerificationSection: some View {
        Group {
            Section(String(localized: "Output channel")) {
                TextField(
                    "Channel role (L, LFE1, ...)",
                    text: $channelRoleText
                )
                TextField(
                    "Output label (as printed)",
                    text: $outputLabelText
                )
                Picker(
                    "Source unit",
                    selection: $sourceItemSelection
                ) {
                    Text(String(localized: "None"))
                        .tag(AuthorityRecordID?.none)
                    ForEach(
                        authorities.inventoryItems.filter {
                            [
                                InventoryEquipmentClass.avReceiver,
                                .avProcessor, .powerAmplifier,
                                .dspUnit, .other,
                            ].contains($0.equipmentClass)
                        }.map {
                            (
                                id: $0.itemID,
                                label: $0.userLabel
                            )
                        },
                        id: \.id
                    ) { option in
                        Text(option.label)
                            .tag(
                                AuthorityRecordID?.some(option.id)
                            )
                    }
                }
                TextField(
                    "Device context (preset/config ref)",
                    text: $deviceContextText
                )
            }
            Section(String(localized: "Driven speakers")) {
                let speakers = entities.filter {
                    $0.type == .speaker || $0.type == .subwoofer
                }
                if speakers.isEmpty {
                    Text(
                        "Add speaker/subwoofer annotations first."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                ForEach(speakers, id: \.entityID) { entity in
                    Toggle(
                        isOn: Binding(
                            get: {
                                routingSpeakerIDs.contains(
                                    entity.entityID
                                )
                            },
                            set: { on in
                                if on {
                                    routingSpeakerIDs.insert(
                                        entity.entityID
                                    )
                                } else {
                                    routingSpeakerIDs.remove(
                                        entity.entityID
                                    )
                                }
                            }
                        )
                    ) {
                        Text(
                            entity.label + " · "
                                + entity.type.rawValue
                        )
                    }
                }
            }
            Section(String(localized: "Verification")) {
                Picker("State", selection: $routingState) {
                    ForEach(
                        RoutingVerificationState.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                if routingState != .unknown {
                    Picker("Method", selection: $routingMethod) {
                        ForEach(
                            RoutingVerificationMethod.allCases,
                            id: \.self
                        ) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    if routingState == .verified,
                       routingMethod == .cableLabelEvidence
                    {
                        Text(
                            "A printed cable label never verifies the live signal path."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Picker("Band scope", selection: $bandScope) {
                    ForEach(
                        RoutingBandScope.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
            Section(String(localized: "Revision")) {
                Picker(
                    "Supersedes",
                    selection: $supersedesSelection
                ) {
                    Text(String(localized: "None"))
                        .tag(AuthorityRecordID?.none)
                    ForEach(
                        authorities.routingVerifications.filter {
                            $0.authorityID != editing?.recordID
                        }.map {
                            (
                                id: $0.authorityID,
                                label: $0.channelRole?.rawValue
                                    ?? $0.outputLabel
                                    ?? $0.authorityID.description
                            )
                        },
                        id: \.id
                    ) { option in
                        Text(option.label)
                            .tag(
                                AuthorityRecordID?.some(option.id)
                            )
                    }
                }
                TextField("Notes (optional)", text: $notes)
            }
        }
    }

    // MARK: Projector commissioning (#335)

    private var projectorCommissioningSection: some View {
        Group {
            Section(String(localized: "Projector")) {
                EntityPicker(
                    title: String(localized: "Projector"),
                    entities: entities,
                    types: [.projector],
                    selection: $projectorEntitySelection
                )
                EntityPicker(
                    title: String(
                        localized: "Lens-center reference"
                    ),
                    entities: entities,
                    types: [.projector, .referencePoint, .custom],
                    selection: $lensCenterEntitySelection
                )
                Picker(
                    "Mount orientation",
                    selection: $mountOrientationChoice
                ) {
                    Text(String(localized: "Not recorded"))
                        .tag("not_recorded")
                    ForEach(
                        ProjectorMountOrientation.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value.rawValue)
                    }
                }
            }
            Section(String(localized: "Optics")) {
                AttestedSettingEditor(
                    title: String(localized: "Throw distance (m)"),
                    entry: $throwEntry
                )
                if throwEntry.state == .attested {
                    TextField(
                        "Throw endpoints",
                        text: $throwEndpointsText
                    )
                    Text(
                        "e.g. lens_center_to_screen_aperture — the exact two points the distance runs between."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                AttestedSettingEditor(
                    title: String(localized: "Zoom"),
                    entry: $zoomEntry
                )
                AttestedSettingEditor(
                    title: String(localized: "Lens shift horizontal"),
                    entry: $shiftHEntry
                )
                AttestedSettingEditor(
                    title: String(localized: "Lens shift vertical"),
                    entry: $shiftVEntry
                )
                AttestedSettingEditor(
                    title: String(localized: "Lens memory preset"),
                    entry: $presetEntry
                )
            }
            Section(String(localized: "Image")) {
                Picker(
                    "Focus",
                    selection: $focusStateChoice
                ) {
                    Text(String(localized: "Not recorded"))
                        .tag("not_recorded")
                    ForEach(
                        ProjectorFocusState.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value.rawValue)
                    }
                }
                TextField(
                    "Optical axis azimuth deg (optional)",
                    text: $opticalAzimuth
                )
                TextField(
                    "Optical axis elevation deg (optional)",
                    text: $opticalElevation
                )
                TextField(
                    "Alignment note (optional)",
                    text: $imageAlignmentNoteText
                )
            }
            Section(String(localized: "Relations")) {
                Picker(
                    "Screen semantics record",
                    selection: $screenAuthoritySelection
                ) {
                    Text(String(localized: "None"))
                        .tag(AuthorityRecordID?.none)
                    ForEach(
                        authorities.screenSemantics.map {
                            (
                                id: $0.authorityID,
                                label: $0.authorityID.description
                            )
                        },
                        id: \.id
                    ) { option in
                        Text(option.label)
                            .tag(
                                AuthorityRecordID?.some(option.id)
                            )
                    }
                }
                TextField(
                    "Planned spec ref (optional)",
                    text: $plannedSpecRefText
                )
                TextField(
                    "Device context (preset/config ref)",
                    text: $deviceContextText
                )
            }
        }
    }

    // MARK: Install alignment assist (#346)

    private var installationAlignmentSection: some View {
        Group {
            Section(String(localized: "Design target")) {
                if !plannedTargets.isEmpty {
                    Picker(
                        "Planned target",
                        selection: $alignmentTargetID
                    ) {
                        Text(String(localized: "None")).tag("")
                        ForEach(
                            plannedTargets,
                            id: \.plannedEntityID
                        ) { spec in
                            Text(
                                (spec.label
                                    ?? spec.plannedEntityID)
                                    + " · " + spec.entityType.rawValue
                            )
                            .tag(spec.plannedEntityID)
                        }
                    }
                    .onChange(of: alignmentTargetID) { _, value in
                        if let spec = plannedTargets.first(where: {
                            $0.plannedEntityID == value
                        }) {
                            alignmentTargetType = spec.entityType
                        }
                    }
                }
                TextField(
                    "Planned entity ID",
                    text: $alignmentTargetID
                )
                Picker(
                    "Entity type",
                    selection: $alignmentTargetType
                ) {
                    ForEach(
                        AnnotationEntityType.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                EntityPicker(
                    title: String(localized: "Aimed-at entity"),
                    entities: entities,
                    types: [
                        .listeningPosition, .referencePoint,
                        .seat, .measurementPoint,
                    ],
                    selection: $aimAtSelection
                )
                Text(
                    "Only record an aim when the design defines one — e.g. the MLP."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section(String(localized: "Guidance")) {
                Picker(
                    "Guidance mode",
                    selection: $guidanceMode
                ) {
                    ForEach(
                        AlignmentGuidanceMode.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                if guidanceMode == .spatialDelta {
                    if let establishedAlignment {
                        Toggle(
                            isOn: $useEstablishedAlignment
                        ) {
                            Text(
                                "Use established alignment ("
                                    + establishedAlignment
                                        .authorityRef + ")"
                            )
                        }
                    }
                    if !useEstablishedAlignment
                        || establishedAlignment == nil
                    {
                        Picker(
                            "Mechanism",
                            selection: $alignmentMechanism
                        ) {
                            ForEach(
                                [
                                    PlanAlignmentMechanism
                                        .manualSurvey,
                                    .roomReferenceFrame,
                                    .referenceTarget,
                                ],
                                id: \.self
                            ) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                        TextField(
                            "Authority reference",
                            text: $alignmentAuthorityRef
                        )
                        TextField(
                            "Survey offset X (m)",
                            text: $surveyX
                        )
                        TextField(
                            "Survey offset Y (m)",
                            text: $surveyY
                        )
                        TextField(
                            "Survey offset Z (m)",
                            text: $surveyZ
                        )
                        Text(
                            "Manual survey translation with identity rotation."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text(
                        "Without a proven alignment the assist gives textual instructions only — no metric deltas are fabricated."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Picker(
                    "Precision",
                    selection: $precision
                ) {
                    ForEach(
                        PrecisionSufficiency.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
            Section(String(localized: "Independent verification")) {
                EntityPicker(
                    title: String(localized: "Final as-built entity"),
                    entities: entities,
                    types: [],
                    selection: $finalEntitySelection
                )
                Text(
                    "The final entity is an independent observation — advisory guidance is never the recorded position."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let deviation = liveDeviation {
                    Text(
                        String(
                            format: "Deviation %.3f m · Δ(%.3f, %.3f, %.3f)",
                            deviation.distanceMeters,
                            deviation.translationScene.x,
                            deviation.translationScene.y,
                            deviation.translationScene.z
                        )
                        + (deviation.headingDeltaRadians.map {
                            String(
                                format: " · heading %.1f°",
                                $0 * 180.0 / .pi
                            )
                        } ?? "")
                    )
                    .font(.caption)
                } else {
                    Text(
                        "Deviation appears once target, alignment, and the final entity are known."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Helpers

    /// Live preview of the deviation the record would store — only
    /// computable under spatial guidance with a proven alignment
    /// (#346); textual guidance never shows metric deltas.
    private var liveDeviation: AsBuiltDeviation? {
        try? deviationPreview(alignment: try? buildAlignment())
    }

    private var editingAuthorityID: AuthorityRecordID {
        editing?.recordID ?? AuthorityRecordID()
    }

    private var editingObservationID: RoomStateObservationID {
        if case .roomStateObservation(let record) = editing {
            return record.observationID
        }
        return RoomStateObservationID()
    }

    private var editingSnapshotID: RoomStateSnapshotID {
        if case .roomStateSnapshot(let record) = editing {
            return record.snapshotID
        }
        return RoomStateSnapshotID()
    }

    private var editingItemID: AuthorityRecordID {
        if case .inventoryItem(let record) = editing {
            return record.itemID
        }
        return editingAuthorityID
    }

    private func settingValue(
        _ entry: SettingEntry
    ) throws -> AttestedSettingValue? {
        switch entry.state {
        case .notRecorded:
            return nil
        case .attested:
            var numeric: Double?
            if !entry.numeric.isEmpty {
                guard let value = Double(entry.numeric),
                      value.isFinite
                else {
                    throw TheaterAuthorityError.invalidPatchGeometry
                }
                numeric = value
            }
            return try AttestedSettingValue(
                state: .attested,
                textValue: entry.text.isEmpty ? nil : entry.text,
                numericValue: numeric
            )
        case .unknown:
            return try AttestedSettingValue(state: .unknown)
        }
    }

    /// The attested alignment the record runs under — the session's
    /// established authority when chosen, else the manually surveyed
    /// translation entered here. nil for textual guidance (#346).
    private func buildAlignment() throws -> PlanAlignmentAuthority? {
        guard guidanceMode == .spatialDelta else { return nil }
        if useEstablishedAlignment, let establishedAlignment {
            return establishedAlignment
        }
        let ref = alignmentAuthorityRef.trimmingCharacters(
            in: .whitespaces
        )
        guard !ref.isEmpty else { return nil }
        func meter(_ text: String) throws -> Float {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return 0 }
            guard let value = Double(trimmed), value.isFinite else {
                throw TheaterAuthorityError.invalidPatchGeometry
            }
            return Float(value)
        }
        let transform = try Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            try meter(surveyX), try meter(surveyY),
            try meter(surveyZ), 1,
        ])
        return try PlanAlignmentAuthority(
            mechanism: alignmentMechanism,
            sceneFromCapture: transform,
            authorityRef: ref,
            evidenceRefs: evidenceSelection.sorted(),
            establishedAtUTC: authorityUTCNow()
        )
    }

    /// Deviation of the final entity from the planned pose, through
    /// the alignment — only computable once target, alignment, and
    /// final entity are all known (#346).
    private func deviationPreview(
        alignment: PlanAlignmentAuthority?
    ) throws -> AsBuiltDeviation? {
        guard let alignment,
              let spec = plannedTargets.first(where: {
                  $0.plannedEntityID == alignmentTargetID
              }),
              let entity = entities.first(where: {
                  $0.entityID == finalEntitySelection
              })
        else { return nil }
        let translation = entity.worldFromAnnotation.translationWorld
        let observation = try AsBuiltObservation(
            plannedEntityID: spec.plannedEntityID,
            positionWorld: try SpatialVector3F(
                translation.x, translation.y, translation.z
            ),
            orientationWorld: entity.orientation,
            coordinateSpaceID: entity.coordinateSpaceID
        )
        return try AsBuiltVerificationSession.deviation(
            spec: spec,
            observation: observation,
            sceneFromCapture: alignment.sceneFromCapture
        )
    }

    // MARK: Editing/prefill seed (#357)

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        if let prefilledEntityID {
            applyPrefill(prefilledEntityID)
        }
        if let editing {
            applyEditingSeed(editing)
        }
    }

    private func applyPrefill(_ entityID: AnnotationEntityID) {
        guard
            let entity = entities.first(where: {
                $0.entityID == entityID
            })
        else { return }
        switch kind {
        case .speakerInstallation:
            speakerEntitySelection = entityID
        case .routingVerification:
            if entity.type == .speaker || entity.type == .subwoofer {
                routingSpeakerIDs = [entityID]
            }
        case .projectorCommissioning:
            projectorEntitySelection = entityID
        case .screenSemantics:
            screenEntitySelection = entityID
        case .seatLayout:
            seatEntitySelection = entityID
        case .furnitureSemantics:
            furnitureEntitySelection = entityID
        case .roomStateObservation:
            targetEntitySelection = entityID
        case .installationAlignment:
            finalEntitySelection = entityID
        case .inventoryItem:
            if entity.type == .equipmentRack {
                hostRackSelection = entityID
            }
        default:
            break
        }
    }

    private func seedBinding(_ binding: SurfaceRegionBinding?) {
        guard let binding else { return }
        roomPlanSurfaceID = binding.roomPlanSurfaceID ?? ""
        roomPlanObjectID = binding.roomPlanObjectID ?? ""
        meshAnchorText = binding.meshAnchorID?.uuidString ?? ""
        semanticEntityID = binding.semanticEntityID ?? ""
        polygonText = binding.polygonWorld.map {
            "\($0.x), \($0.y), \($0.z)"
        }.joined(separator: "\n")
        evidenceSelection = Set(binding.evidenceRefs)
    }

    private func seedSetting(
        _ value: AttestedSettingValue?
    ) -> SettingEntry {
        guard let value else { return SettingEntry() }
        var entry = SettingEntry()
        switch value.state {
        case .attested:
            entry.state = .attested
            entry.text = value.textValue ?? ""
            entry.numeric = value.numericValue.map {
                String(format: "%.4f", $0)
            } ?? ""
        case .unknown:
            entry.state = .unknown
        }
        return entry
    }

    /// Recovers the azimuth/elevation fields an
    /// `OrientationAxes.frontAxisLocal` encodes under the
    /// speaker-orientation convention (yaw about +Y, front toward -Z).
    private func headingText(
        _ axes: OrientationAxes
    ) -> (azimuth: String, elevation: String) {
        let front = axes.frontAxisLocal
        let elevation = asin(Double(front.y)) * 180.0 / .pi
        let azimuth =
            atan2(Double(front.x), Double(-front.z)) * 180.0 / .pi
        return (
            String(format: "%.2f", azimuth),
            String(format: "%.2f", elevation)
        )
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func applyEditingSeed(_ draft: AuthorityRecordDraft) {
        switch draft {
        case .surfaceSemantics(let record):
            label = record.label ?? ""
            hostClassification = record.hostClassification
            seedBinding(record.binding)
            if let treatment = record.treatment {
                includeTreatment = true
                treatmentWidth = metersText(
                    treatment.footprintWidthMeters
                )
                treatmentHeight = metersText(
                    treatment.footprintHeightMeters
                )
                treatmentOffset = metersText(
                    treatment.surfaceOffsetMeters
                )
                treatmentAirGap = metersText(treatment.airGapMeters)
                notes = treatment.notes ?? ""
            }
        case .surfaceConstruction(let record):
            constructionKind = record.constructionKind
            materialDetail = record.materialDetail ?? ""
            constructionSource = record.source
            seedBinding(record.binding)
        case .problemSurface(let record):
            problemKind = record.kind
            notes = record.notes ?? ""
            seedBinding(record.binding)
        case .constructionFeature(let record):
            featureKind = record.kind
            confirmationSource = record.confirmationSource
            label = record.label ?? ""
            seedBinding(record.binding)
        case .roomStateObservation(let record):
            roomStateKind = record.kind
            roomStateValue = record.state
            stateDetail = record.stateDetail ?? ""
            targetEntitySelection = record.targetEntityID
            targetAuthoritySelection = record.targetAuthorityID
            evidenceSelection = Set(record.evidenceRefs)
        case .roomStateSnapshot(let record):
            label = record.label
            campaignID = record.campaignID ?? ""
            snapshotObservations = Set(record.observationIDs)
        case .inventoryItem(let record):
            inventoryClass = record.equipmentClass
            manufacturer = record.manufacturer ?? ""
            model = record.model ?? ""
            userLabel = record.userLabel
            serialNumber = record.serialNumber ?? ""
            hostRackSelection = record.hostRackEntityID
            evidenceSelection = Set(record.evidenceRefs)
            if let transform = record.worldFromItem {
                includePosition = true
                let t = transform.translationWorld
                posX = String(format: "%.4f", t.x)
                posY = String(format: "%.4f", t.y)
                posZ = String(format: "%.4f", t.z)
            }
            if let ref = record.equipmentRef {
                includeEquipmentRef = true
                equipmentID = ref.equipmentID
                equipmentVersion = ref.equipmentVersion
                equipmentHash = ref.equipmentHash.value
            }
        case .furnitureSemantics(let record):
            furnitureEntitySelection = record.targetEntityID
            furnitureCategory = record.category
            furnitureRelevance = record.relevance
            confirmationSource = record.source
            furnitureUsesBinding = record.binding != nil
            seedBinding(record.binding)
        case .speakerInstallation(let record):
            speakerEntitySelection = record.speakerEntityID
            mountingMode = record.mountingMode
            insertionDepth = metersText(record.insertionDepthMeters)
            hardwareNote = record.hardwareNote ?? ""
            includeHostSurface = record.hostSurface != nil
            seedBinding(record.hostSurface)
        case .screenSemantics(let record):
            screenEntitySelection = record.screenEntityID
            apertureWidth = metersText(
                record.visibleApertureWidthMeters
            )
            apertureHeight = metersText(
                record.visibleApertureHeightMeters
            )
            frameWidth = metersText(record.frameWidthMeters)
            frameHeight = metersText(record.frameHeightMeters)
            transparency = record.acousticallyTransparent
            transparencySource =
                record.transparencySource ?? .userAttestation
            maskingObservationSelection = record.maskingObservationID
            behindScreenSpeakers = Set(
                record.behindScreenSpeakerEntityIDs
            )
        case .seatLayout(let record):
            seatEntitySelection = record.seatEntityID
            rowIdentifier = record.rowIdentifier ?? ""
            seatOrdinal = record.seatOrdinal.map(String.init) ?? ""
            riserSelection = record.riserAuthorityID
            earEntitySelection = record.earListeningEntityID
            eyeEntitySelection = record.eyeReferenceEntityID
            headObstructionHeight = metersText(
                record.headObstructionHeightMeters
            )
            headObstructionRadius = metersText(
                record.headObstructionRadiusMeters
            )
            if let facing = record.facingOrientation {
                let heading = headingText(facing)
                facingAzimuth = heading.azimuth
                facingElevation = heading.elevation
            }
        case .routingVerification(let record):
            channelRoleText = record.channelRole?.rawValue ?? ""
            outputLabelText = record.outputLabel ?? ""
            sourceItemSelection = record.sourceInventoryItemID
            bandScope = record.bandScope
            routingSpeakerIDs = Set(record.speakerEntityIDs)
            routingState = record.verificationState
            routingMethod = record.verificationMethod ?? .userAttestation
            deviceContextText = record.deviceContextRef ?? ""
            supersedesSelection = record.supersedesRecordID
            notes = record.notes ?? ""
            evidenceSelection = Set(record.evidenceRefs)
        case .projectorCommissioning(let record):
            projectorEntitySelection = record.projectorEntityID
            lensCenterEntitySelection = record.lensCenterEntityID
            throwEntry = seedSetting(record.throwObservation)
            throwEndpointsText = record.throwEndpointSemantics ?? ""
            zoomEntry = seedSetting(record.zoom)
            shiftHEntry = seedSetting(record.lensShiftHorizontal)
            shiftVEntry = seedSetting(record.lensShiftVertical)
            presetEntry = seedSetting(record.lensMemoryPreset)
            mountOrientationChoice =
                record.mountOrientation?.rawValue ?? "not_recorded"
            focusStateChoice =
                record.focusState?.rawValue ?? "not_recorded"
            if let axis = record.opticalAxis {
                let heading = headingText(axis)
                opticalAzimuth = heading.azimuth
                opticalElevation = heading.elevation
            }
            imageAlignmentNoteText = record.imageAlignmentNote ?? ""
            plannedSpecRefText = record.plannedSpecRef ?? ""
            deviceContextText = record.deviceContextRef ?? ""
            screenAuthoritySelection = record.screenSemanticsAuthorityID
            evidenceSelection = Set(record.evidenceRefs)
        case .installationAlignment(let record):
            alignmentTargetID = record.targetPlannedEntityID
            alignmentTargetType = record.targetEntityType
            aimAtSelection = record.aimAtEntityID
            guidanceMode = record.guidanceMode
            precision = record.precisionSufficiency
            finalEntitySelection = record.finalEntityID
            evidenceSelection = Set(record.evidenceRefs)
            if let alignment = record.alignment {
                alignmentMechanism = alignment.mechanism
                alignmentAuthorityRef = alignment.authorityRef
                let t = alignment.sceneFromCapture.translationWorld
                surveyX = String(format: "%.4f", t.x)
                surveyY = String(format: "%.4f", t.y)
                surveyZ = String(format: "%.4f", t.z)
                useEstablishedAlignment = false
            }
        }
    }

    private func metersText(_ value: Double?) -> String {
        value.map { String(format: "%.4f", $0) } ?? ""
    }

    private var authorityRecordOptions:
        [(id: AuthorityRecordID, label: String)]
    {
        func rows(
            _ records: [(AuthorityRecordID, String)]
        ) -> [(AuthorityRecordID, String)] {
            records
        }
        var options: [(AuthorityRecordID, String)] = []
        options += rows(
            authorities.surfaceSemantics.map {
                ($0.authorityID, "surface · " + ($0.label ?? ""))
            }
        )
        options += rows(
            authorities.surfaceConstructions.map {
                (
                    $0.authorityID,
                    "construction · "
                        + $0.constructionKind.rawValue
                )
            }
        )
        options += rows(
            authorities.problemSurfaces.map {
                ($0.authorityID, "problem · " + $0.kind.rawValue)
            }
        )
        options += rows(
            authorities.constructionFeatures.map {
                (
                    $0.authorityID,
                    "feature · " + $0.kind.rawValue
                )
            }
        )
        options += rows(
            authorities.inventoryItems.map {
                (
                    $0.itemID,
                    "inventory · " + $0.userLabel
                )
            }
        )
        options += rows(
            authorities.speakerInstallations.map {
                (
                    $0.authorityID,
                    "installation · "
                        + $0.mountingMode.rawValue
                )
            }
        )
        return options
    }

    private var riserOptions:
        [(id: AuthorityRecordID, label: String)]
    {
        authorities.constructionFeatures
            .filter { $0.kind == .riser || $0.kind == .stage }
            .map {
                (
                    $0.authorityID,
                    $0.kind.rawValue
                        + " · "
                        + ($0.label ?? "")
                )
            }
    }

    private func buildBinding() throws -> SurfaceRegionBinding? {
        guard usesBinding else {
            return nil
        }
        let meshAnchor: UUID? = try {
            let text = meshAnchorText.trimmingCharacters(
                in: .whitespaces
            )
            if text.isEmpty {
                return nil
            }
            guard let uuid = UUID(uuidString: text) else {
                throw TheaterAuthorityError
                    .invalidPatchGeometry
            }
            return uuid
        }()
        return try SurfaceRegionBinding(
            coordinateSpaceID: coordinateSpaceID,
            roomPlanSurfaceID:
                roomPlanSurfaceID.isEmpty
                    ? nil : roomPlanSurfaceID,
            roomPlanObjectID:
                roomPlanObjectID.isEmpty
                    ? nil : roomPlanObjectID,
            meshAnchorID: meshAnchor,
            semanticEntityID:
                semanticEntityID.isEmpty
                    ? nil : semanticEntityID,
            polygonWorld: try parsePolygonText(polygonText),
            evidenceRefs: evidenceSelection.sorted()
        )
    }

    private func optionalMeters(
        _ text: String
    ) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let value = Double(trimmed), value.isFinite
        else {
            throw TheaterAuthorityError.invalidPatchGeometry
        }
        return value
    }

    private func equipmentReference() throws
        -> HTDTEquipmentReference?
    {
        guard includeEquipmentRef else {
            return nil
        }
        return try HTDTEquipmentReference(
            equipmentID: equipmentID,
            equipmentVersion: equipmentVersion,
            equipmentHash: try EvidenceSHA256(
                equipmentHash
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
            )
        )
    }

    private func produce() {
        do {
            let binding = try buildBinding()
            let draft: AuthorityRecordDraft
            switch kind {
            case .surfaceSemantics:
                draft = .surfaceSemantics(
                    try SurfaceSemanticAuthority(
                        authorityID: editingAuthorityID,
                        label: label.isEmpty ? nil : label,
                        binding: binding!,
                        hostClassification:
                            hostClassification,
                        treatment:
                            try includeTreatment
                            ? TreatmentPlacementAuthority(
                                footprintWidthMeters:
                                    optionalMeters(
                                        treatmentWidth
                                    ),
                                footprintHeightMeters:
                                    optionalMeters(
                                        treatmentHeight
                                    ),
                                surfaceOffsetMeters:
                                    optionalMeters(
                                        treatmentOffset
                                    ),
                                airGapMeters:
                                    optionalMeters(
                                        treatmentAirGap
                                    ),
                                notes:
                                    notes.isEmpty
                                        ? nil : notes
                            )
                            : nil
                    )
                )
            case .surfaceConstruction:
                draft = .surfaceConstruction(
                    try SurfaceConstructionObservation(
                        authorityID: editingAuthorityID,
                        binding: binding!,
                        constructionKind: constructionKind,
                        materialDetail:
                            materialDetail.isEmpty
                                ? nil : materialDetail,
                        source: constructionSource
                    )
                )
            case .problemSurface:
                draft = .problemSurface(
                    try ProblemSurfaceObservation(
                        authorityID: editingAuthorityID,
                        binding: binding!,
                        kind: problemKind,
                        notes: notes.isEmpty ? nil : notes
                    )
                )
            case .constructionFeature:
                draft = .constructionFeature(
                    try ConstructionFeatureCandidate(
                        authorityID: editingAuthorityID,
                        binding: binding!,
                        kind: featureKind,
                        confirmationSource:
                            confirmationSource,
                        label: label.isEmpty ? nil : label
                    )
                )
            case .roomStateObservation:
                draft = .roomStateObservation(
                    try RoomStateObservation(
                        observationID: editingObservationID,
                        kind: roomStateKind,
                        state: roomStateValue,
                        stateDetail:
                            stateDetail.isEmpty
                                ? nil : stateDetail,
                        targetEntityID:
                            targetEntitySelection,
                        targetAuthorityID:
                            targetAuthoritySelection,
                        coordinateSpaceID:
                            evidenceSelection.isEmpty
                                ? nil : coordinateSpaceID,
                        observedAtUTC: authorityUTCNow(),
                        evidenceRefs:
                            evidenceSelection.sorted()
                    )
                )
            case .roomStateSnapshot:
                let selected =
                    authorities.roomStateObservations
                        .filter {
                            snapshotObservations
                                .contains($0.observationID)
                        }
                draft = .roomStateSnapshot(
                    try TheaterAuthorityBuilder
                        .roomStateSnapshot(
                            snapshotID: editingSnapshotID,
                            label: label,
                            captureRevisionID:
                                captureRevisionID,
                            observedAtUTC:
                                authorityUTCNow(),
                            observations: selected,
                            campaignID:
                                campaignID.isEmpty
                                    ? nil : campaignID
                        )
                )
            case .inventoryItem:
                var transform: Matrix4x4F?
                var itemSpace: CoordinateSpaceID?
                if includePosition {
                    guard let x = Double(posX),
                          let y = Double(posY),
                          let z = Double(posZ)
                    else {
                        throw ManualAuthorityBuilderError
                            .invalidPosition
                    }
                    transform = try Matrix4x4F(values: [
                        1, 0, 0, 0,
                        0, 1, 0, 0,
                        0, 0, 1, 0,
                        Float(x), Float(y), Float(z), 1,
                    ])
                    itemSpace = coordinateSpaceID
                }
                draft = .inventoryItem(
                    try SystemInventoryItem(
                        itemID: editingItemID,
                        equipmentClass: inventoryClass,
                        manufacturer:
                            manufacturer.isEmpty
                                ? nil : manufacturer,
                        model: model.isEmpty ? nil : model,
                        userLabel: userLabel,
                        equipmentRef:
                            try equipmentReference(),
                        serialNumber:
                            serialNumber.isEmpty
                                ? nil : serialNumber,
                        hostRackEntityID: hostRackSelection,
                        coordinateSpaceID: itemSpace,
                        worldFromItem: transform,
                        evidenceRefs:
                            evidenceSelection.sorted()
                    )
                )
            case .furnitureSemantics:
                draft = .furnitureSemantics(
                    try FurnitureSemanticConfirmation(
                        authorityID: editingAuthorityID,
                        targetEntityID:
                            furnitureEntitySelection,
                        binding: binding,
                        category: furnitureCategory,
                        relevance: furnitureRelevance,
                        source: confirmationSource
                    )
                )
            case .speakerInstallation:
                guard let speakerEntitySelection else {
                    errorText = String(
                        localized:
                            "Add a speaker annotation first."
                    )
                    return
                }
                draft = .speakerInstallation(
                    try SpeakerInstallationAuthority(
                        authorityID: editingAuthorityID,
                        speakerEntityID:
                            speakerEntitySelection,
                        mountingMode: mountingMode,
                        hostSurface: binding,
                        insertionDepthMeters:
                            try optionalMeters(
                                insertionDepth
                            ),
                        hardwareNote:
                            hardwareNote.isEmpty
                                ? nil : hardwareNote
                    )
                )
            case .screenSemantics:
                guard let screenEntitySelection else {
                    errorText = String(
                        localized:
                            "Add a projection screen annotation first."
                    )
                    return
                }
                draft = .screenSemantics(
                    try ProjectionScreenSemantics(
                        authorityID: editingAuthorityID,
                        screenEntityID:
                            screenEntitySelection,
                        visibleApertureWidthMeters:
                            try optionalMeters(
                                apertureWidth
                            ),
                        visibleApertureHeightMeters:
                            try optionalMeters(
                                apertureHeight
                            ),
                        frameWidthMeters:
                            try optionalMeters(frameWidth),
                        frameHeightMeters:
                            try optionalMeters(
                                frameHeight
                            ),
                        acousticallyTransparent:
                            transparency,
                        transparencySource:
                            transparency == .unknown
                                ? nil : transparencySource,
                        maskingObservationID:
                            maskingObservationSelection,
                        behindScreenSpeakerEntityIDs:
                            behindScreenSpeakers
                                .sorted {
                                    $0.description
                                        < $1.description
                                }
                    )
                )
            case .seatLayout:
                guard let seatEntitySelection else {
                    errorText = String(
                        localized:
                            "Add a seat annotation first."
                    )
                    return
                }
                var facing: OrientationAxes?
                if !facingAzimuth.isEmpty {
                    facing = try ManualAuthorityBuilder
                        .speakerOrientationAxes(
                            azimuthDegrees:
                                Double(facingAzimuth),
                            elevationDegrees:
                                facingElevation.isEmpty
                                    ? nil
                                    : Double(facingElevation)
                        )
                }
                draft = .seatLayout(
                    try SeatLayoutAuthority(
                        authorityID: editingAuthorityID,
                        seatEntityID: seatEntitySelection,
                        rowIdentifier:
                            rowIdentifier.isEmpty
                                ? nil : rowIdentifier,
                        seatOrdinal:
                            seatOrdinal.isEmpty
                                ? nil : Int(seatOrdinal),
                        riserAuthorityID: riserSelection,
                        earListeningEntityID:
                            earEntitySelection,
                        eyeReferenceEntityID:
                            eyeEntitySelection,
                        headObstructionHeightMeters:
                            try optionalMeters(
                                headObstructionHeight
                            ),
                        headObstructionRadiusMeters:
                            try optionalMeters(
                                headObstructionRadius
                            ),
                        facingOrientation: facing
                    )
                )
            case .routingVerification:
                let roleText = channelRoleText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).uppercased()
                var role: ChannelRole?
                if !roleText.isEmpty {
                    guard let parsed = ChannelRole(rawValue: roleText)
                    else {
                        throw TheaterAuthorityError
                            .invalidPatchGeometry
                    }
                    role = parsed
                }
                guard !routingSpeakerIDs.isEmpty else {
                    errorText = String(
                        localized:
                            "Select at least one speaker entity."
                    )
                    return
                }
                draft = .routingVerification(
                    try RoutingVerificationAuthority(
                        authorityID: editingAuthorityID,
                        channelRole: role,
                        outputLabel:
                            outputLabelText.isEmpty
                                ? nil : outputLabelText,
                        sourceInventoryItemID: sourceItemSelection,
                        bandScope: bandScope,
                        speakerEntityIDs: routingSpeakerIDs
                            .sorted {
                                $0.description < $1.description
                            },
                        verificationState: routingState,
                        verificationMethod:
                            routingState == .unknown
                                ? nil : routingMethod,
                        deviceContextRef:
                            deviceContextText.isEmpty
                                ? nil : deviceContextText,
                        observedAtUTC: authorityUTCNow(),
                        coordinateSpaceID:
                            evidenceSelection.isEmpty
                                ? nil : coordinateSpaceID,
                        evidenceRefs: evidenceSelection.sorted(),
                        supersedesRecordID: supersedesSelection,
                        notes: notes.isEmpty ? nil : notes
                    )
                )
            case .projectorCommissioning:
                guard let projectorEntitySelection else {
                    errorText = String(
                        localized:
                            "Add a projector annotation first."
                    )
                    return
                }
                let throwValue = try settingValue(throwEntry)
                var opticalAxis: OrientationAxes?
                if !opticalAzimuth.isEmpty {
                    opticalAxis = try ManualAuthorityBuilder
                        .speakerOrientationAxes(
                            azimuthDegrees: Double(opticalAzimuth),
                            elevationDegrees:
                                opticalElevation.isEmpty
                                    ? nil : Double(opticalElevation)
                        )
                }
                draft = .projectorCommissioning(
                    try ProjectorCommissioningAuthority(
                        authorityID: editingAuthorityID,
                        projectorEntityID: projectorEntitySelection,
                        lensCenterEntityID: lensCenterEntitySelection,
                        throwObservation: throwValue,
                        throwEndpointSemantics:
                            throwValue == nil
                                ? nil
                                : (throwEndpointsText.isEmpty
                                    ? nil : throwEndpointsText),
                        zoom: try settingValue(zoomEntry),
                        lensShiftHorizontal:
                            try settingValue(shiftHEntry),
                        lensShiftVertical:
                            try settingValue(shiftVEntry),
                        lensMemoryPreset:
                            try settingValue(presetEntry),
                        mountOrientation:
                            mountOrientationChoice == "not_recorded"
                                ? nil
                                : ProjectorMountOrientation(
                                    rawValue: mountOrientationChoice
                                ),
                        focusState:
                            focusStateChoice == "not_recorded"
                                ? nil
                                : ProjectorFocusState(
                                    rawValue: focusStateChoice
                                ),
                        opticalAxis: opticalAxis,
                        imageAlignmentNote:
                            imageAlignmentNoteText.isEmpty
                                ? nil : imageAlignmentNoteText,
                        plannedSpecRef:
                            plannedSpecRefText.isEmpty
                                ? nil : plannedSpecRefText,
                        deviceContextRef:
                            deviceContextText.isEmpty
                                ? nil : deviceContextText,
                        screenSemanticsAuthorityID:
                            screenAuthoritySelection,
                        observedAtUTC: authorityUTCNow(),
                        coordinateSpaceID:
                            evidenceSelection.isEmpty
                                ? nil : coordinateSpaceID,
                        evidenceRefs: evidenceSelection.sorted()
                    )
                )
            case .installationAlignment:
                guard !alignmentTargetID.isEmpty else {
                    errorText = String(
                        localized:
                            "Choose the planned target first."
                    )
                    return
                }
                guard let finalEntitySelection else {
                    errorText = String(
                        localized:
                            "Select the final as-built entity."
                    )
                    return
                }
                let alignment = try buildAlignment()
                draft = .installationAlignment(
                    try InstallationAlignmentRecord(
                        authorityID: editingAuthorityID,
                        targetPlannedEntityID: alignmentTargetID,
                        targetEntityType: alignmentTargetType,
                        aimAtEntityID: aimAtSelection,
                        guidanceMode: guidanceMode,
                        alignment: alignment,
                        precisionSufficiency: precision,
                        finalEntityID: finalEntitySelection,
                        reportedDeviation:
                            try deviationPreview(
                                alignment: alignment
                            ),
                        observedAtUTC: authorityUTCNow(),
                        coordinateSpaceID: coordinateSpaceID,
                        evidenceRefs: evidenceSelection.sorted()
                    )
                )
            }
            onProduce(draft)
        } catch {
            errorText = String(describing: error)
        }
    }
}

/// Toggle list binding free-form `path:`/`entity:` evidence refs —
/// shared by authority sheets that take plain evidence references
/// rather than decoded frame presentations.
struct EvidenceReferenceSelector: View {
    let availableEvidenceRefs: [String]
    @Binding var selectedEvidenceRefs: Set<String>

    var body: some View {
        Section(String(localized: "Linked evidence frames")) {
            ForEach(availableEvidenceRefs, id: \.self) { reference in
                Toggle(
                    isOn: Binding(
                        get: {
                            selectedEvidenceRefs.contains(reference)
                        },
                        set: { selected in
                            if selected {
                                selectedEvidenceRefs.insert(reference)
                            } else {
                                selectedEvidenceRefs.remove(reference)
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.frameLabel(reference))
                        Text(reference)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(
                "Links reference exact canonical frame descriptors already persisted in this working revision."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private static func frameLabel(_ reference: String) -> String {
        let path = reference.hasPrefix("path:")
            ? String(reference.dropFirst(5))
            : reference
        return URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
    }
}

/// Form-side state of one attested-optics field (#335): not recorded,
/// an attested value (text and/or numeric), or an explicit unknown.
private struct SettingEntry: Equatable {
    enum State: Equatable {
        case notRecorded
        case attested
        case unknown
    }
    var state: State = .notRecorded
    var text = ""
    var numeric = ""
}

/// `AttestedSettingValue` editor — the operator either attests a value
/// or records an explicit `unknown`; a missing entry stays nil so a
/// planned value never silently becomes installed truth (#335).
private struct AttestedSettingEditor: View {
    let title: String
    @Binding var entry: SettingEntry

    var body: some View {
        Picker(title, selection: $entry.state) {
            Text(String(localized: "Not recorded"))
                .tag(SettingEntry.State.notRecorded)
            Text(String(localized: "Attested"))
                .tag(SettingEntry.State.attested)
            Text(String(localized: "Unknown"))
                .tag(SettingEntry.State.unknown)
        }
        if entry.state == .attested {
            TextField(
                title + String(localized: " value"),
                text: $entry.text
            )
            TextField(
                title + String(localized: " numeric"),
                text: $entry.numeric
            )
        }
    }
}

/// Read-only inspection of one staged authority record (#357) —
/// human-term rows plus Edit/Delete so a staged record is correctable
/// before the workspace's canonical Save.
private struct AuthorityRecordDetailView: View {
    let descriptor: AuthorityRecordDescriptor
    let kindTitle: String
    let lines: [(String, String)]
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section(String(localized: "Record")) {
                LabeledContent("Kind", value: kindTitle)
                if let detail = descriptor.detail {
                    LabeledContent("Detail", value: detail)
                }
            }
            Section(String(localized: "Details")) {
                ForEach(lines, id: \.0) { pair in
                    LabeledContent(pair.0, value: pair.1)
                }
            }
            Section {
                Button(String(localized: "Edit record")) {
                    onEdit()
                }
                Button(
                    String(localized: "Delete record"),
                    role: .destructive
                ) {
                    onDelete()
                }
            }
        }
        .navigationTitle(descriptor.title)
    }
}

extension HTDTTaskPlanSemanticItem: Identifiable {
    public var id: String { itemID }
}

extension HTDTTaskPlanEvidenceItem: Identifiable {
    public var id: String { itemID }
}
