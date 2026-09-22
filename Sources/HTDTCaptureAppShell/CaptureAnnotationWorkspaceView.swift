import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore

/// The canonical annotation/measurement authority already committed in
/// the working revision, reloaded so a pre-finalization correction
/// pass starts from the persisted values instead of blank state (#163).
/// A seed produced from a recovered draft is marked so the workspace
/// shows the records as unsaved (#266).
public struct AnnotationWorkspaceSeed: Sendable, Equatable {
    public let annotations: [CaptureAnnotationEntity]
    public let measurements: [CaptureMeasurement]
    /// Equipment-identity attestations committed for this revision
    /// (#239) — persisted beside the canonical collections on save.
    public let equipmentIdentityRecords: [EquipmentIdentityRecord]
    /// The speaker-layout plan in progress, when a draft recorded one
    /// (#266/#278).
    public let speakerLayoutPlan: SpeakerLayoutPlan?
    /// True when this seed was restored from an on-disk non-canonical
    /// draft rather than committed authority.
    public let isRestoredDraft: Bool
    /// Committed theater-semantic authorities, when an
    /// `annotations/authorities.json` file exists in the revision.
    public let authorities: TheaterAuthorityCollection?

    public init(
        annotations: [CaptureAnnotationEntity] = [],
        measurements: [CaptureMeasurement] = [],
        equipmentIdentityRecords: [EquipmentIdentityRecord] = [],
        speakerLayoutPlan: SpeakerLayoutPlan? = nil,
        isRestoredDraft: Bool = false,
        authorities: TheaterAuthorityCollection? = nil
    ) {
        self.annotations = annotations
        self.measurements = measurements
        self.equipmentIdentityRecords = equipmentIdentityRecords
        self.speakerLayoutPlan = speakerLayoutPlan
        self.isRestoredDraft = isRestoredDraft
        self.authorities = authorities
    }
}

/// The annotation/measurement authoring surface (#5 Phase 4). Stages
/// records against the committed workspace, edits existing rows
/// in-place (#245), links visual evidence (#255), binds exact catalog
/// equipment via a searchable picker (#265), records optional
/// physical-device identity attestations (#239), and offers the guided
/// speaker-layout flow (#278). Placement/heading captures run through
/// the shared live AR session with a visible reticle (#214) and can
/// target mesh or RoomPlan objects, never only planes (#246).
///
/// Staged state is autosaved to an app-private draft bound to the
/// exact working revision + coordinate space (#266); the canonical
/// `annotations/`/`measurements/` payloads are written only by Save.
public struct CaptureAnnotationWorkspaceView: View {
    public let coordinateSpaceID: CoordinateSpaceID
    /// Working revision identity — room-state snapshot records bind
    /// it so a state set can never outlive the revision it describes.
    public let captureRevisionID: CaptureRevisionID
    /// Every `path:` evidence ref currently persisted in the working
    /// revision (kept for compatibility — superseded visually by
    /// `evidenceFrames`).
    public let availableEvidenceRefs: [String]
    /// Visual presentation data for each evidence frame (#255).
    public let evidenceFrames: [EvidenceFramePresentation]
    /// Captured RoomPlan elements/mesh anchors offered as binding
    /// targets in the authority sheets (#218).
    public let roomPlanSurfaces: [CapturedSurfaceOption]
    public let meshAnchors: [CapturedSurfaceOption]
    public let statusMessage: String?
    public let replacesCommittedAuthority: Bool
    /// Spatial authority sealed for finalization (#276): live capture
    /// affordances stay hidden (cameraPreview is nil) while label,
    /// role, equipment, and scalar corrections remain editable.
    public let spatialCaptureSealed: Bool
    /// Shared AR preview for the camera capture sheets (#214).
    public let cameraPreview: AnyView?
    /// Pollable reticle probe (#214/#246).
    public let probePlacementTarget:
        () async -> AnnotationPlacementProbe
    /// Pollable camera heading in degrees (#214).
    public let probeCameraHeading: () async -> Float?
    /// Targeted placement capture (#246) — nil result means no hit.
    public let captureTargetedPlacement: (
        PlacementTargetPreference
    ) async throws -> AnnotationPlacementAuthority?
    public let captureSpeakerOrientation:
        () async throws -> AnnotationOrientationAuthority
    /// Full-3D orientation capture for measurement-point direction
    /// authority (issue #271); distinct from the horizontal-heading
    /// `captureSpeakerOrientation` convention.
    public let capturePointOrientation:
        () async throws -> AnnotationOrientationAuthority
    /// Captures a plain evidence frame for equipment-identity photos
    /// (#239); returns the canonical `path:` ref.
    public let captureIdentityPhoto: () async throws -> String
    /// Recognized RoomPlan objects offered for direct binding (#246).
    public let roomPlanObjects: [RoomPlanBindableObject]
    /// Advisory plausibility context for live flags (#247).
    public let plausibilityContext: SpatialPlausibilityContext
    /// Session equipment picker recents (#265).
    public let equipmentRecents: EquipmentRecents
    /// Available speaker-layout plans (#278); empty hides the flow.
    public let speakerLayoutPlans: [SpeakerLayoutPlan]
    /// Draft persistence + binding for autosave (#266). A draft only
    /// ever seeds the workspace when both IDs match exactly.
    public let draftStore: AnnotationWorkspaceDraftStore?
    public let draftRevisionID: CaptureRevisionID?
    /// Validates and adopts an imported catalog snapshot through the
    /// host (#211). The host keeps the catalog alive across this view's
    /// lifecycle (and relaunch, via an app-support cache); the default
    /// only decodes through the validating initializer.
    public let onImportEquipmentCatalog:
        (Data) throws -> HTDTEquipmentCatalogSnapshot
    /// Current capture-task profile (#217); nil means geometry-only.
    public let taskProfile: CaptureTaskProfile?
    public let onSelectTaskProfile:
        (CaptureTaskProfile?, Set<String>) -> Void
    /// True while the host is committing the staged authority
    /// (#309): Save stays disabled and shows progress instead of
    /// looking tappable while `onCommit` would be guarded out.
    public let commitInFlight: Bool
    public let onCommit: (
        [CaptureAnnotationEntity],
        [CaptureMeasurement],
        [EquipmentIdentityRecord],
        TheaterAuthorityCollection
    ) -> Void
    public let onCancel: () -> Void
    /// Operator-initiated capture discard (#254): asks the host to
    /// confirm, stop, and remove the whole working revision.
    public let onDiscard: () -> Void

    /// One snapshot of every staged collection (#330). Undo/redo
    /// operate only on these staged values — never on committed
    /// canonical authority, which changes only through `onCommit`.
    private struct StagedSnapshot: Equatable {
        var annotations: [CaptureAnnotationEntity]
        var measurements: [CaptureMeasurement]
        var identityRecords: [EquipmentIdentityRecord]
        var speakerLayoutPlan: SpeakerLayoutPlan?
        var authorities: TheaterAuthorityCollection
    }

    /// Staged state at workspace open: the committed authority seed,
    /// or a recovered draft (#266). Dirty means staged ≠ baseline;
    /// a restored draft is treated as dirty until Save commits it.
    private let seedBaseline: StagedSnapshot

    @State private var annotations: [CaptureAnnotationEntity]
    @State private var measurements: [CaptureMeasurement]
    @State private var identityRecords: [EquipmentIdentityRecord]
    @State private var speakerLayoutPlan: SpeakerLayoutPlan?
    @State private var restoredFromDraft: Bool
    @State private var authorities: TheaterAuthorityCollection
    /// Bounded local undo/redo over staged snapshots (#330).
    @State private var undoStack: [StagedSnapshot] = []
    @State private var redoStack: [StagedSnapshot] = []
    @State private var confirmingCancel = false
    @State private var addingAnnotation = false
    @State private var editingAnnotationID: AnnotationEntityID?
    @State private var addingMeasurement = false
    @State private var editingMeasurementID: MeasurementID?
    @State private var layoutFlowPlan: SpeakerLayoutPlan?
    /// The catalog snapshot currently adopted by the host, seeded when
    /// this workspace opens (#211). Selecting "Replace equipment
    /// catalog" always runs through `onImportEquipmentCatalog`, so an
    /// unsupported file never silently substitutes the kept snapshot.
    @State private var equipmentCatalog:
        HTDTEquipmentCatalogSnapshot?
    @State private var importingEquipmentCatalog = false
    @State private var equipmentCatalogError: String?
    @State private var draftSaveTask: Task<Void, Never>?

    /// Undo-history bound (#330): snapshots are deep value copies, so
    /// the stack is capped at a deterministic depth.
    private let maxUndoDepth = 64

    public init(
        coordinateSpaceID: CoordinateSpaceID,
        captureRevisionID: CaptureRevisionID,
        commitInFlight: Bool = false,
        availableEvidenceRefs: [String] = [],
        evidenceFrames: [EvidenceFramePresentation] = [],
        roomPlanSurfaces: [CapturedSurfaceOption] = [],
        meshAnchors: [CapturedSurfaceOption] = [],
        statusMessage: String? = nil,
        seed: AnnotationWorkspaceSeed? = nil,
        replacesCommittedAuthority: Bool = false,
        spatialCaptureSealed: Bool = false,
        equipmentCatalog: HTDTEquipmentCatalogSnapshot? = nil,
        cameraPreview: AnyView? = nil,
        probePlacementTarget: @escaping
            () async -> AnnotationPlacementProbe =
            { .unavailable },
        probeCameraHeading: @escaping
            () async -> Float? = { nil },
        captureTargetedPlacement: @escaping (
            PlacementTargetPreference
        ) async throws -> AnnotationPlacementAuthority? = { _ in
            nil
        },
        captureSpeakerOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError.invalidSpeakerYaw
            },
        capturePointOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError
                    .pointDirectionUnavailable
            },
        captureIdentityPhoto: @escaping
            () async throws -> String = {
                throw ManualAuthorityBuilderError.invalidPosition
            },
        roomPlanObjects: [RoomPlanBindableObject] = [],
        plausibilityContext: SpatialPlausibilityContext =
            SpatialPlausibilityContext(),
        equipmentRecents: EquipmentRecents = EquipmentRecents(),
        speakerLayoutPlans: [SpeakerLayoutPlan] = [],
        draftStore: AnnotationWorkspaceDraftStore? = nil,
        draftRevisionID: CaptureRevisionID? = nil,
        onImportEquipmentCatalog: @escaping
            (Data) throws -> HTDTEquipmentCatalogSnapshot = { data in
                try JSONDecoder().decode(
                    HTDTEquipmentCatalogSnapshot.self,
                    from: data
                )
            },
        onCommit: @escaping (
            [CaptureAnnotationEntity],
            [CaptureMeasurement],
            [EquipmentIdentityRecord],
            TheaterAuthorityCollection
        ) -> Void,
        taskProfile: CaptureTaskProfile? = nil,
        onSelectTaskProfile: @escaping
            (CaptureTaskProfile?, Set<String>) -> Void = { _, _ in },
        onCancel: @escaping () -> Void,
        onDiscard: @escaping () -> Void = {}
    ) {
        self.coordinateSpaceID = coordinateSpaceID
        self.captureRevisionID = captureRevisionID
        self.availableEvidenceRefs =
            availableEvidenceRefs.sorted()
        self.evidenceFrames = evidenceFrames
        self.roomPlanSurfaces = roomPlanSurfaces
        self.meshAnchors = meshAnchors
        self.statusMessage = statusMessage
        self.replacesCommittedAuthority =
            replacesCommittedAuthority
        self.spatialCaptureSealed = spatialCaptureSealed
        self.cameraPreview = cameraPreview
        self.probePlacementTarget = probePlacementTarget
        self.probeCameraHeading = probeCameraHeading
        self.captureTargetedPlacement = captureTargetedPlacement
        self.captureSpeakerOrientation =
            captureSpeakerOrientation
        self.capturePointOrientation = capturePointOrientation
        self.captureIdentityPhoto = captureIdentityPhoto
        self.roomPlanObjects = roomPlanObjects
        self.plausibilityContext = plausibilityContext
        self.equipmentRecents = equipmentRecents
        self.speakerLayoutPlans = speakerLayoutPlans
        self.draftStore = draftStore
        self.draftRevisionID = draftRevisionID
        self.onImportEquipmentCatalog = onImportEquipmentCatalog
        self.taskProfile = taskProfile
        self.onSelectTaskProfile = onSelectTaskProfile
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onDiscard = onDiscard
        _annotations = State(
            initialValue: seed?.annotations ?? []
        )
        _measurements = State(
            initialValue: seed?.measurements ?? []
        )
        _identityRecords = State(
            initialValue: seed?.equipmentIdentityRecords ?? []
        )
        _speakerLayoutPlan = State(
            initialValue: seed?.speakerLayoutPlan
        )
        _restoredFromDraft = State(
            initialValue: seed?.isRestoredDraft ?? false
        )
        _authorities = State(
            initialValue: seed?.authorities ?? .empty
        )
        _equipmentCatalog = State(initialValue: equipmentCatalog)
        self.commitInFlight = commitInFlight
        seedBaseline = StagedSnapshot(
            annotations: seed?.annotations ?? [],
            measurements: seed?.measurements ?? [],
            identityRecords: seed?.equipmentIdentityRecords ?? [],
            speakerLayoutPlan: seed?.speakerLayoutPlan,
            authorities: seed?.authorities ?? .empty
        )
    }

    /// Frame presentations for refs the loader could decode; the rest
    /// keep a text row.
    private var frameRefs: Set<String> {
        Set(evidenceFrames.map(\.reference))
    }
    private var otherEvidenceRefs: [String] {
        availableEvidenceRefs.filter { !frameRefs.contains($0) }
    }

    public var body: some View {
        // #362: on regular width the staged records (annotations,
        // measurements, speaker layout) sit beside the context and
        // commit controls; compact width composes into one list.
        CaptureAdaptivePanes {
            statusSection
            sealedSpatialNotice
            restoredDraftNotice
            annotationsSection
            measurementsSection
            speakerLayoutSection
        } trailing: {
            equipmentCatalogSection
            taskProfileSection
            theaterAuthoritySection
            commitSection
        }
        .sheet(isPresented: $addingAnnotation) {
            NavigationStack {
                annotationAddForm()
            }
        }
        .sheet(item: $editingAnnotationID) { entityID in
            NavigationStack {
                annotationEditForm(entityID: entityID)
            }
        }
        .sheet(isPresented: $addingMeasurement) {
            NavigationStack {
                MeasurementFormView(
                    coordinateSpaceID: coordinateSpaceID,
                    endpointCandidates: annotations,
                    evidenceFrames: evidenceFrames,
                    otherEvidenceRefs: otherEvidenceRefs
                ) { measurement in
                    recordUndoableEdit()
                    measurements.append(measurement)
                    scheduleDraftSave()
                }
            }
        }
        .sheet(item: $editingMeasurementID) { measurementID in
            NavigationStack {
                measurementEditForm(measurementID: measurementID)
            }
        }
        .sheet(item: $layoutFlowPlan) { plan in
            NavigationStack {
                layoutFlowForm(plan: plan)
            }
        }
        .fileImporter(
            isPresented: $importingEquipmentCatalog,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importEquipmentCatalog(result)
        }
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: $confirmingCancel,
            titleVisibility: .visible
        ) {
            Button(
                "Discard changes",
                role: .destructive
            ) {
                cancel()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(
                "Staged annotations, measurements, and identity records that have not been saved are dropped. This does not change the previously saved authority."
            )
        }
        // Autosave drafts on any staged change and when the workspace
        // disappears (#266).
        .onChange(of: annotations) { _, _ in scheduleDraftSave() }
        .onChange(of: measurements) { _, _ in scheduleDraftSave() }
        .onChange(of: identityRecords) { _, _ in scheduleDraftSave() }
        .onDisappear {
            // Final flush — an interrupting view teardown must still
            // leave the draft durable.
            writeDraft()
        }
    }

    private func upsertIdentityRecord(
        _ record: EquipmentIdentityRecord?
    ) {
        identityRecords.removeAll {
            $0.entityID == record?.entityID
        }
        if let record {
            identityRecords.append(record)
        }
    }

    private func removeAnnotations(
        at offsets: IndexSet
    ) {
        recordUndoableEdit()
        let removedIDs = offsets.map {
            annotations[$0].entityID
        }
        annotations.remove(atOffsets: offsets)
        // An attestation bound to a deleted entity can never outlive
        // it (#239).
        identityRecords.removeAll {
            removedIDs.contains($0.entityID)
        }
        scheduleDraftSave()
    }

    // MARK: Workspace edit transaction (#330)

    private var stagedSnapshot: StagedSnapshot {
        StagedSnapshot(
            annotations: annotations,
            measurements: measurements,
            identityRecords: identityRecords,
            speakerLayoutPlan: speakerLayoutPlan,
            authorities: authorities
        )
    }

    /// Staged ≠ seed baseline, or the seed itself was a recovered
    /// draft that was never committed authority (#266).
    private var isDirty: Bool {
        restoredFromDraft || stagedSnapshot != seedBaseline
    }

    /// Push the pre-mutation staged state onto the bounded undo stack
    /// and clear redo — a fresh edit branch invalidates it.
    private func recordUndoableEdit() {
        undoStack.append(stagedSnapshot)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst(
                undoStack.count - maxUndoDepth
            )
        }
        redoStack.removeAll()
    }

    private func applyStagedSnapshot(
        _ snapshot: StagedSnapshot
    ) {
        annotations = snapshot.annotations
        measurements = snapshot.measurements
        identityRecords = snapshot.identityRecords
        speakerLayoutPlan = snapshot.speakerLayoutPlan
        authorities = snapshot.authorities
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else {
            return
        }
        redoStack.append(stagedSnapshot)
        applyStagedSnapshot(snapshot)
        scheduleDraftSave()
    }

    private func redo() {
        guard let snapshot = redoStack.popLast() else {
            return
        }
        undoStack.append(stagedSnapshot)
        applyStagedSnapshot(snapshot)
        scheduleDraftSave()
    }

    /// Concise replacement preview (#330): how the staged collections
    /// differ from the committed seed, by stable entity/measurement
    /// identity.
    private var stagedChangeSummary: String? {
        guard isDirty else {
            return nil
        }

        var added = 0
        var removed = 0
        var edited = 0

        func diffIdentified<ID: Hashable, T: Equatable>(
            staged: [T],
            baseline: [T],
            identity: (T) -> ID
        ) {
            let baselineByID = Dictionary(
                baseline.map { (identity($0), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let stagedIDs = Set(staged.map(identity))
            for item in staged {
                if let before = baselineByID[identity(item)] {
                    if before != item {
                        edited += 1
                    }
                } else {
                    added += 1
                }
            }
            removed += baseline.filter {
                !stagedIDs.contains(identity($0))
            }.count
        }

        diffIdentified(
            staged: annotations,
            baseline: seedBaseline.annotations,
            identity: { $0.entityID }
        )
        diffIdentified(
            staged: measurements,
            baseline: seedBaseline.measurements,
            identity: { $0.measurementID }
        )
        diffIdentified(
            staged: identityRecords,
            baseline: seedBaseline.identityRecords,
            identity: { $0.entityID }
        )

        if speakerLayoutPlan != seedBaseline.speakerLayoutPlan
            || authorities != seedBaseline.authorities
        {
            edited += 1
        }

        var parts: [String] = []
        if added > 0 {
            parts.append(
                String(
                    format: String(localized: "+%d added"),
                    added
                )
            )
        }
        if removed > 0 {
            parts.append(
                String(
                    format: String(localized: "−%d removed"),
                    removed
                )
            )
        }
        if edited > 0 {
            parts.append(
                String(
                    format: String(localized: "%d edited"),
                    edited
                )
            )
        }
        if parts.isEmpty, restoredFromDraft {
            return String(localized: "Unsaved restored draft")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// #276 seal notice: every raycast/orientation/scan affordance is
    /// already hidden via `cameraPreview == nil`; this names why.
    @ViewBuilder
    private var sealedSpatialNotice: some View {
        if spatialCaptureSealed {
            Section {
                Text(
                    "Live spatial capture is sealed for finalization. Labels, roles, equipment, and scalar values can still be corrected; raycast placement, orientation capture, and additional scanning are unavailable."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Draft autosave (#266)

    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            writeDraft()
        }
    }

    private func writeDraft() {
        guard let draftStore, let draftRevisionID else {
            return
        }
        let draft = AnnotationWorkspaceDraft(
            captureRevisionID: draftRevisionID,
            coordinateSpaceID: coordinateSpaceID,
            savedAtUTC: BundleTimestamp.utcString(from: Date()),
            annotations: annotations,
            measurements: measurements,
            equipmentIdentityRecords: identityRecords,
            speakerLayoutPlan: speakerLayoutPlan
        )
        try? draftStore.save(draft)
    }

    private func discardDraft() {
        if let draftStore, let draftRevisionID {
            draftStore.discard(revisionID: draftRevisionID)
        }
    }

    private func commit() {
        discardDraft()
        onCommit(annotations, measurements, identityRecords, authorities)
    }

    /// Cancel is one tap when nothing was staged (#330); a dirty
    /// workspace requires an explicit discard decision first.
    private func requestCancel() {
        if isDirty {
            confirmingCancel = true
        } else {
            cancel()
        }
    }

    private func cancel() {
        discardDraft()
        onCancel()
    }

    private func importEquipmentCatalog(
        _ result: Result<[URL], Error>
    ) {
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                return
            }
            let accessing =
                url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            // The host validates (schema + authority version), adopts
            // and durably caches the snapshot (#211). A failed import
            // keeps the previously adopted catalog instead of clearing
            // it: the error is shown and nothing is silently replaced.
            equipmentCatalog = try onImportEquipmentCatalog(data)
            equipmentCatalogError = nil
        } catch {
            equipmentCatalogError =
                String(localized: "Catalog import failed: ")
                + AnnotationPresentation.errorText(error)
        }
    }

    /// Preset capture-task profiles (#217): geometry-only stays valid,
    /// theater presets pick a speaker-role set the operator expects; a
    /// host may substitute any custom `CaptureTaskProfile` since the
    /// completeness model is driven by requirements, not presets.
    @ViewBuilder
    private var taskProfilePicker: some View {
        Picker(
            String(localized: "Capture task profile"),
            selection: Binding<String>(
                get: {
                    taskProfile?.identifier ?? "geometry_only"
                },
                set: { identifier in
                    onSelectTaskProfile(
                        Self.profile(forIdentifier: identifier),
                        []
                    )
                }
            )
        ) {
            Text(
                String(
                    localized: "Geometry only (no task requirements)"
                )
            )
            .tag("geometry_only")
            Text(
                String(
                    localized: "Room + listening position"
                )
            )
            .tag("room_and_listening_position")
            Text(String(localized: "Theater layout"))
                .tag("theater_layout")
        }
        if let taskProfile, !taskProfile.requirements.isEmpty {
            ForEach(
                taskProfile.requirements,
                id: \.identifier
            ) { requirement in
                HStack {
                    Text(requirement.identifier)
                        .font(.caption.monospaced())
                    Spacer()
                    Text(
                        requirement.minimumCount
                            == requirement.maximumCount
                            && requirement.maximumCount != nil
                            ? String(
                                format: String(
                                    localized: "exactly %d"
                                ),
                                requirement.minimumCount
                            )
                            : String(
                                format: String(
                                    localized: "min %d"
                                ),
                                requirement.minimumCount
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func profile(
        forIdentifier identifier: String
    ) -> CaptureTaskProfile? {
        switch identifier {
        case "geometry_only":
            return nil
        case "room_and_listening_position":
            return .roomAndListeningPosition
        case "theater_layout":
            return .theaterLayout(
                speakerRoles: [
                    "L", "C", "R", "SL", "SR", "SBL", "SBR",
                    "TFL", "TFR", "TML", "TMR",
                ],
                subwooferCount: 1
            )
        default:
            return nil
        }
    }


    @ViewBuilder
    private var statusSection: some View {
        if let statusMessage {
            Section(String(localized: "Status")) {
                Text(statusMessage)
                    .font(.callout)
            }
        }
    }
    @ViewBuilder
    private var restoredDraftNotice: some View {
        if restoredFromDraft {
            Section {
                CaptureNotice(
                    status: .draft,
                    title: "Draft restored",
                    message:
                        "Unsaved draft restored — records below are not yet saved authority"
                )
                .listRowSeparator(.hidden)
            }
        }
    }
    @ViewBuilder
    private var equipmentCatalogSection: some View {
        Section(
            String(localized: "HTDT equipment catalog")
        ) {
            if let equipmentCatalog {
                LabeledContent(
                    String(localized: "Definitions"),
                    value: String(
                        equipmentCatalog.definitions.count
                    )
                )
                Text(
                    "Selections bind exact ID/version/SHA-256 only. The imported catalog is not stored as equipment authority in the capture bundle; it is kept on this device as reference context and can be replaced explicitly."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(
                    "Optional. Import a catalog snapshot exported from the HTDT backend. Once imported it stays available for later annotation sessions on this device."
                )
                .foregroundStyle(.secondary)
            }

            Button(
                equipmentCatalog == nil
                ? String(localized: "Import equipment catalog")
                : String(localized: "Replace equipment catalog")
            ) {
                importingEquipmentCatalog = true
            }

            if let equipmentCatalogError {
                Text(equipmentCatalogError)
                    .foregroundStyle(.red)
            }
        }
    }
    @ViewBuilder
    private var taskProfileSection: some View {
        Section("Capture task profile") {
            taskProfilePicker
            Text(
                "Select the information this capture intends to collect. This is advisory and never gates HTDT ingestion readiness."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private var speakerLayoutSection: some View {
        if !speakerLayoutPlans.isEmpty {
            Section(String(localized: "Speaker layout")) {
                ForEach(
                    speakerLayoutPlans,
                    id: \.planName
                ) { plan in
                    Button {
                        layoutFlowPlan = plan
                    } label: {
                        Label(
                            speakerLayoutTitle(plan),
                            systemImage: "speaker.wave.3"
                        )
                    }
                }
                if speakerLayoutPlan != nil {
                    Text(
                        "A layout plan is in progress; reopen it to continue."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
    @ViewBuilder
    private var annotationsSection: some View {
        Section(String(localized: "Spatial annotations")) {
            if annotations.isEmpty {
                Text(
                    String(localized:
                        "No spatial annotations staged.")
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(annotations, id: \.entityID) { entity in
                    Button {
                        editingAnnotationID = entity.entityID
                    } label: {
                        annotationRow(entity)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    removeAnnotations(at: offsets)
                }
            }

            Button(String(localized: "Add spatial annotation")) {
                addingAnnotation = true
            }
        }
    }
    @ViewBuilder
    private var measurementsSection: some View {
        Section(String(localized: "Measurements")) {
            if measurements.isEmpty {
                Text(
                    String(localized: "No measurements staged.")
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(
                    measurements,
                    id: \.measurementID
                ) { measurement in
                    Button {
                        editingMeasurementID =
                            measurement.measurementID
                    } label: {
                        measurementRow(measurement)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    recordUndoableEdit()
                    measurements.remove(atOffsets: offsets)
                    scheduleDraftSave()
                }
            }

            Button(String(localized: "Add measurement")) {
                addingMeasurement = true
            }
        }
    }
    @ViewBuilder
    private var commitSection: some View {
        Section {
            // #330: the workspace edit transaction — undo/redo over
            // staged state, a dirty marker, and a replacement preview
            // before the single canonical commit.
            HStack(spacing: 16) {
                Button {
                    undo()
                } label: {
                    Label(
                        String(localized: "Undo"),
                        systemImage: "arrow.uturn.backward"
                    )
                }
                .disabled(undoStack.isEmpty || commitInFlight)
                Button {
                    redo()
                } label: {
                    Label(
                        String(localized: "Redo"),
                        systemImage: "arrow.uturn.forward"
                    )
                }
                .disabled(redoStack.isEmpty || commitInFlight)
                Spacer()
                if isDirty {
                    Text(String(localized: "Unsaved changes"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)

            if let stagedChangeSummary {
                Text(stagedChangeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if commitInFlight {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(
                        String(
                            localized: "Saving annotation authority…"
                        )
                    )
                }
            }
            Button(
                replacesCommittedAuthority
                ? String(
                    localized:
                        "Replace saved annotation authority"
                )
                : String(
                    localized: "Save annotation authority"
                )
            ) {
                commit()
            }
            .capturePrimaryAction()
            .disabled(!isDirty || commitInFlight)
            Button(
                String(localized: "Cancel"),
                role: .cancel
            ) {
                requestCancel()
            }
            .disabled(commitInFlight)
        } footer: {
            if replacesCommittedAuthority {
                Text(
                    "Save replaces the canonical annotation and measurement collections committed earlier in this revision. Cancelling leaves the previous save unchanged."
                )
            } else {
                Text(
                    "Save writes the canonical annotation and measurement collections once. Edit or delete staged records before saving."
                )
            }
        }
    }

    private func layoutFlowForm(
        plan: SpeakerLayoutPlan
    ) -> some View {
        SpeakerLayoutFlowView(
            plan: plan,
            existingAnnotations: annotations,
            coordinateSpaceID: coordinateSpaceID,
            evidenceFrames: evidenceFrames,
            equipmentCatalogEntries:
                equipmentCatalog?.definitions ?? [],
            equipmentRecents: equipmentRecents,
            roomPlanObjects: roomPlanObjects,
            cameraPreview: cameraPreview,
            probePlacementTarget: probePlacementTarget,
            probeCameraHeading: probeCameraHeading,
            captureTargetedPlacement:
                captureTargetedPlacement,
            captureSpeakerOrientation:
                captureSpeakerOrientation,
            captureIdentityPhoto: captureIdentityPhoto,
            onEntity: { entity, record in
                recordUndoableEdit()
                annotations.append(entity)
                if let record {
                    upsertIdentityRecord(record)
                }
                scheduleDraftSave()
            },
            onPlan: { updatedPlan in
                recordUndoableEdit()
                speakerLayoutPlan = updatedPlan
                scheduleDraftSave()
            }
        )
    }

    private func annotationAddForm() -> some View {
        AnnotationEntityForm(
            coordinateSpaceID: coordinateSpaceID,
            evidenceFrames: evidenceFrames,
            otherEvidenceRefs: otherEvidenceRefs,
            equipmentCatalogEntries:
                equipmentCatalog?.definitions ?? [],
            equipmentRecents: equipmentRecents,
            roomPlanObjects: roomPlanObjects,
            cameraPreview: cameraPreview,
            probePlacementTarget: probePlacementTarget,
            probeCameraHeading: probeCameraHeading,
            captureTargetedPlacement:
                captureTargetedPlacement,
            captureSpeakerOrientation:
                captureSpeakerOrientation,
            capturePointOrientation: capturePointOrientation,
            captureIdentityPhoto: captureIdentityPhoto
        ) { entity, record in
            recordUndoableEdit()
            annotations.append(entity)
            if let record {
                upsertIdentityRecord(record)
            }
            scheduleDraftSave()
        }
    }

    private func measurementEditForm(
        measurementID: MeasurementID
    ) -> some View {
        Group {
            if let measurement = measurements.first(where: {
                $0.measurementID == measurementID
            }) {
                MeasurementFormView(
                    editingMeasurement: measurement,
                    coordinateSpaceID: coordinateSpaceID,
                    endpointCandidates: annotations,
                    evidenceFrames: evidenceFrames,
                    otherEvidenceRefs: otherEvidenceRefs
                ) { updated in
                    recordUndoableEdit()
                    measurements.replaceAll(
                        where: {
                            $0.measurementID == updated.measurementID
                        },
                        with: updated
                    )
                    scheduleDraftSave()
                }
            }
        }
    }

    @ViewBuilder
    private var theaterAuthoritySection: some View {
        Section(String(localized: "Theater authorities")) {
            TheaterAuthoritySection(
                coordinateSpaceID: coordinateSpaceID,
                captureRevisionID: captureRevisionID,
                availableEvidenceRefs: availableEvidenceRefs,
                entities: annotations,
                roomPlanSurfaces: roomPlanSurfaces,
                meshAnchors: meshAnchors,
                authorities: Binding(
                    get: { authorities },
                    set: { newValue in
                        // #330: theater-authority edits join the same
                        // staged undo transaction.
                        guard newValue != authorities else {
                            return
                        }
                        recordUndoableEdit()
                        authorities = newValue
                        scheduleDraftSave()
                    }
                )
            )
        }
    }

    private func annotationEditForm(
        entityID: AnnotationEntityID
    ) -> some View {
        Group {
            if let entity = annotations.first(where: {
                $0.entityID == entityID
            }) {
                let identityRecord = identityRecords.first(where: {
                    $0.entityID == entityID
                })
                AnnotationEntityForm(
                    editingEntity: entity,
                    editingIdentityRecord: identityRecord,
                    coordinateSpaceID: coordinateSpaceID,
                    evidenceFrames: evidenceFrames,
                    otherEvidenceRefs: otherEvidenceRefs,
                    equipmentCatalogEntries:
                        equipmentCatalog?.definitions ?? [],
                    equipmentRecents: equipmentRecents,
                    roomPlanObjects: roomPlanObjects,
                    cameraPreview: cameraPreview,
                    probePlacementTarget: probePlacementTarget,
                    probeCameraHeading: probeCameraHeading,
                    captureTargetedPlacement:
                        captureTargetedPlacement,
                    captureSpeakerOrientation:
                        captureSpeakerOrientation,
                    capturePointOrientation:
                        capturePointOrientation,
                    captureIdentityPhoto: captureIdentityPhoto
                ) { updated, record in
                    recordUndoableEdit()
                    annotations.replaceAll(
                        where: { $0.entityID == updated.entityID },
                        with: updated
                    )
                    upsertIdentityRecord(record)
                    scheduleDraftSave()
                }
            }
        }
    }

    private func speakerLayoutTitle(
        _ plan: SpeakerLayoutPlan
    ) -> String {
        String(localized: "Capture layout: ") + plan.planName
    }

    @ViewBuilder
    private func annotationRow(
        _ entity: CaptureAnnotationEntity
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entity.label)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(
                [
                    AnnotationPresentation
                        .entityTypeName(entity.type),
                    entity.channelRole?.rawValue,
                    AnnotationPresentation
                        .placementMethodName(
                            entity.placement.method
                        ),
                ]
                .compactMap { $0 }
                .joined(separator: " · ")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if identityRecords.contains(where: {
                $0.entityID == entity.entityID
            }) {
                Label(
                    String(localized: "Identity attested"),
                    systemImage: "checkmark.shield"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func measurementRow(
        _ measurement: CaptureMeasurement
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(
                    AnnotationPresentation.measurementTitle(
                        forQuantityType: measurement.quantityType
                    )
                )
                .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(measurementDetail(measurement))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func endpointLabel(_ ref: String) -> String {
        guard ref.hasPrefix("entity:"),
              let entity = annotations.first(where: {
                  "entity:" + $0.entityID.description == ref
              })
        else {
            return ref
        }
        return entity.label
    }

    private func measurementDetail(
        _ measurement: CaptureMeasurement
    ) -> String {
        var detail: String
        switch measurement.value {
        case let .scalar(value):
            detail = String(value) + " "
                + measurement.unit.rawValue
        case let .vector3(x, y, z):
            detail = "[\(x), \(y), \(z)] "
                + measurement.unit.rawValue
        }
        if let sourceValueText = measurement.sourceValueText,
           sourceValueText != detail
        {
            detail += " (source: " + sourceValueText + ")"
        }
        detail +=
            " · " + measurement.acquisitionMethod.rawValue
            + " · " + measurement.provenanceClass.rawValue
        if !measurement.endpointRefs.isEmpty {
            detail += " · "
                + measurement.endpointRefs
                    .map(endpointLabel)
                    .joined(separator: " → ")
        }
        return detail
    }

}

private extension Array {
    mutating func replaceAll(
        where predicate: (Element) -> Bool,
        with element: Element
    ) {
        if let index = firstIndex(where: predicate) {
            self[index] = element
        } else {
            append(element)
        }
    }
}

extension AnnotationEntityID: Identifiable {
    public var id: UUID { rawValue }
}

extension MeasurementID: Identifiable {
    public var id: UUID { rawValue }
}

extension SpeakerLayoutPlan: Identifiable {
    public var id: String { planName }
}
