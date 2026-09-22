import Foundation
import SwiftUI
import HTDTCaptureCore
#if os(iOS)
import UIKit
#endif

/// The post-End Review workspace (issue #213), reused read-only for
/// persisted captures (issue #294). Presents the captured room as a
/// visual artifact first: plan preview, per-frame evidence gallery,
/// committed annotations, opening review, and the room reference
/// frame. When `readOnly` is false, per-frame privacy deletion (#241),
/// room-frame capture (#232), and opening disposition (#231) remain
/// live; when `spatialCaptureSealed` is true, live-capture actions are
/// additionally hidden (issue #276).
public struct CaptureReviewWorkspaceView: View {
    public let model: CaptureReviewWorkspaceModel
    /// Live-edit actions; unused in read-only mode.
    public let removeEvidenceFrame: (EvidenceFrameID) async -> Void
    public let openingReviewCandidates:
        () async -> [RoomOpeningCandidate]?
    public let commitOpeningReview:
        ([RoomOpeningCandidate]) async -> Bool
    public let captureRoomFrameOrigin: () -> Void
    public let confirmRoomReferenceFrame: () -> Void
    public let roomFrameOriginPending: WorldPoint3D?
    /// #325: resolves a revisit flag — the outcome names the real
    /// authority it resolved to (or acknowledge/unavailable); the
    /// marker itself is never mutated into an annotation.
    public let resolveRevisitFlag:
        (
            String,
            ScanRevisitFlagResolution.Outcome,
            String?
        ) -> Void
    /// #325: reopens a resolved/skipped flag when the marker needs
    /// review again.
    public let reopenRevisitFlag: (String) -> Void
    /// #352: marks one imported task-plan checklist item
    /// skipped/unavailable from Review.
    public let markTaskPlanItem:
        (String, TaskPlanItemOutcome) -> Void
    /// #232: confirms a field/install datum derived from the
    /// committed room reference frame. Returns false when the room
    /// frame is missing or the commit failed.
    public let confirmFieldDatumFromRoomFrame:
        () async -> Bool
    /// #232: removes the committed field datum payload.
    public let removeRoomFieldDatum: () async -> Void
    /// #231: captures the camera position as the center for a
    /// user-declared opening candidate.
    public let captureOpeningCenter: () -> Void
    /// Clears a pending opening-center capture so another candidate
    /// can be marked.
    public let clearOpeningCenter: () -> Void
    /// Pending center point for a user-declared opening candidate.
    public let openingCenterPending: WorldPoint3D?
    /// #375: author a note in Review — (text, category,
    /// needsAttention, bindingRefs). Resolve/supersede/bind actions
    /// follow the note lifecycle; notes are never edited in place.
    public let recordReviewFieldNote:
        (String, CaptureFieldNoteCategory, Bool, [String]) -> Void
    public let resolveFieldNote: (CaptureFieldNoteID) -> Void
    public let supersedeFieldNote:
        (CaptureFieldNoteID, String, CaptureFieldNoteCategory) -> Void
    public let bindFieldNote: (CaptureFieldNoteID, String) -> Void
    /// #376: advisory privacy flag on an evidence frame.
    public let flagEvidenceFrameForPrivacy:
        (EvidenceFrameID) -> Void

    @State private var openings: [RoomOpeningCandidate]?
    @State private var openingSaveState: String?
    @State private var confirmingFrameRemoval:
        EvidenceFrameID?
    @State private var newOpeningKind: RoomOpeningKind = .hvacGrille
    @State private var newOpeningState: RoomOpeningState = .open
    @State private var newOpeningWidth = "0.30"
    @State private var newOpeningHeight = "0.30"
    @State private var composingFieldNote = false
    @State private var supersedingFieldNote: CaptureFieldNote?
    @State private var bindingFieldNote: CaptureFieldNote?

    public init(
        model: CaptureReviewWorkspaceModel,
        roomFrameOriginPending: WorldPoint3D? = nil,
        openingCenterPending: WorldPoint3D? = nil,
        removeEvidenceFrame: @escaping
            (EvidenceFrameID) async -> Void = { _ in },
        openingReviewCandidates: @escaping
            () async -> [RoomOpeningCandidate]? = { nil },
        commitOpeningReview: @escaping
            ([RoomOpeningCandidate]) async -> Bool = { _ in false },
        captureRoomFrameOrigin: @escaping () -> Void = {},
        confirmRoomReferenceFrame: @escaping () -> Void = {},
        resolveRevisitFlag: @escaping
            (
                String,
                ScanRevisitFlagResolution.Outcome,
                String?
            ) -> Void = { _, _, _ in },
        reopenRevisitFlag: @escaping (String) -> Void = { _ in },
        markTaskPlanItem: @escaping
            (String, TaskPlanItemOutcome) -> Void = { _, _ in },
        confirmFieldDatumFromRoomFrame: @escaping
            () async -> Bool = { false },
        removeRoomFieldDatum: @escaping () async -> Void = {},
        captureOpeningCenter: @escaping () -> Void = {},
        clearOpeningCenter: @escaping () -> Void = {},
        recordReviewFieldNote: @escaping
            (String, CaptureFieldNoteCategory, Bool, [String])
                -> Void = { _, _, _, _ in },
        resolveFieldNote: @escaping
            (CaptureFieldNoteID) -> Void = { _ in },
        supersedeFieldNote: @escaping
            (CaptureFieldNoteID, String, CaptureFieldNoteCategory)
                -> Void = { _, _, _ in },
        bindFieldNote: @escaping
            (CaptureFieldNoteID, String) -> Void = { _, _ in },
        flagEvidenceFrameForPrivacy: @escaping
            (EvidenceFrameID) -> Void = { _ in }
    ) {
        self.model = model
        self.roomFrameOriginPending = roomFrameOriginPending
        self.openingCenterPending = openingCenterPending
        self.removeEvidenceFrame = removeEvidenceFrame
        self.openingReviewCandidates = openingReviewCandidates
        self.commitOpeningReview = commitOpeningReview
        self.captureRoomFrameOrigin = captureRoomFrameOrigin
        self.confirmRoomReferenceFrame = confirmRoomReferenceFrame
        self.resolveRevisitFlag = resolveRevisitFlag
        self.reopenRevisitFlag = reopenRevisitFlag
        self.markTaskPlanItem = markTaskPlanItem
        self.confirmFieldDatumFromRoomFrame =
            confirmFieldDatumFromRoomFrame
        self.removeRoomFieldDatum = removeRoomFieldDatum
        self.captureOpeningCenter = captureOpeningCenter
        self.clearOpeningCenter = clearOpeningCenter
        self.recordReviewFieldNote = recordReviewFieldNote
        self.resolveFieldNote = resolveFieldNote
        self.supersedeFieldNote = supersedeFieldNote
        self.bindFieldNote = bindFieldNote
        self.flagEvidenceFrameForPrivacy =
            flagEvidenceFrameForPrivacy
    }

    public var body: some View {
        // #362: regular-width splits the capture's *visual* evidence
        // (plan preview + frame gallery) from its *detail* rows; on
        // compact width the same sections compose back into one list.
        CaptureAdaptivePanes {
            if model.spatialCaptureSealed && !model.readOnly {
                Section {
                    CaptureNotice(
                        status: .advisory,
                        title: "Spatial capture sealed",
                        message:
                            "Live spatial capture is sealed for finalization. Labels, roles, equipment, and scalar values can still be corrected; raycast placement, orientation capture, and additional scanning are unavailable."
                    )
                    .listRowSeparator(.hidden)
                }
            }

            if !model.fieldNotes.isEmpty,
               !CaptureFieldNoteCollection(notes: model.fieldNotes)
                   .unresolvedAttention.isEmpty
            {
                Section {
                    CaptureNotice(
                        status: .advisory,
                        title: "Field notes need attention",
                        message:
                            "Unresolved attention notes are listed under Field notes. They surface here for review — they never block finalization on their own."
                    )
                    .listRowSeparator(.hidden)
                }
            }

            Section("Plan preview") {
                if let plan = model.planPreview {
                    RoomPlanPreviewCanvas(model: plan)
                        .frame(
                            minHeight: 220,
                            idealHeight: 300
                        )
                        .accessibilityLabel(
                            "Room plan preview"
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 8,
                                leading: 0,
                                bottom: 8,
                                trailing: 0
                            )
                        )
                } else {
                    Text(
                        "Plan preview unavailable on this platform or payload"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            captureMissionSection

            revisitFlagsSection

            Section(
                model.readOnly
                    ? "Evidence frames"
                    : "Visual evidence review"
            ) {
                if model.evidenceItems.isEmpty {
                    Text("No evidence frames retained")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.evidenceItems) { item in
                    evidenceRow(item)
                }
                if !model.readOnly {
                    Text(
                        "Removing an unreferenced frame deletes its pixels, depth, confidence, and preview permanently. Closing and referenced evidence is always retained."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if model.contactSheet != nil {
                    NavigationLink {
                        EvidenceContactSheetView(
                            model: model,
                            removeEvidenceFrame:
                                removeEvidenceFrame,
                            flagForPrivacy:
                                flagEvidenceFrameForPrivacy
                        )
                    } label: {
                        Label(
                            "Evidence contact sheet",
                            systemImage:
                                "rectangle.grid.2x2"
                        )
                    }
                }
            }
        } trailing: {
            Section("RoomPlan result") {
                if let metadata = model.roomMetadata {
                    CaptureTechnicalDetail(
                        "Raw payload",
                        value: metadata.rawPayloadPath
                    )
                    CaptureTechnicalDetail(
                        "Processed",
                        value:
                            metadata.processedPayloadPath ?? "—"
                    )
                    if let summary = metadata.summary,
                       let dims = summary.dimensionsMeters
                    {
                        LabeledContent(
                            "Dimensions",
                            value: String(
                                format: "%.2f × %.2f × %.2f m",
                                dims.xMeters,
                                dims.yMeters,
                                dims.zMeters
                            )
                        )
                    }
                } else {
                    Text("No RoomPlan lineage in this capture")
                        .foregroundStyle(.secondary)
                }
            }

            if !model.annotations.isEmpty {
                Section("Annotations") {
                    ForEach(
                        model.annotations,
                        id: \.entityID
                    ) { entity in
                        let entityType = entity.type.rawValue
                        let entityID =
                            entity.entityID.description
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entity.label)
                                .font(.headline)
                            Text(
                                entityType + " · " + entityID
                                    + operatorSuffix(
                                        entity.authorOperatorID
                                    )
                            )
                            .font(.caption.monospaced())
                        }
                    }
                }
            }

            if !model.measurements.isEmpty {
                Section("Measurements") {
                    ForEach(
                        model.measurements,
                        id: \.measurementID
                    ) { measurement in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            LabeledContent(
                                measurement.quantityType,
                                value: measurement.measurementID
                                    .description
                            )
                            .font(.caption)
                            if let authority =
                                measurement.instrumentAuthority,
                               let profile = model.instruments
                                   .first(where: {
                                       $0.instrumentID
                                           == authority
                                           .instrumentID
                                           && $0.profileVersion
                                           == authority
                                           .profileVersion
                                   })
                            {
                                Text(
                                    [
                                        profile.manufacturer,
                                        profile.model,
                                        profile.serialOrAssetID
                                            .map {
                                                "serial " + $0
                                            },
                                        "v"
                                            + String(
                                                authority
                                                    .profileVersion
                                            ),
                                    ]
                                    .compactMap { $0 }
                                    .joined(separator: " ")
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !model.operatorProfiles.isEmpty {
                Section("Operators") {
                    ForEach(
                        model.operatorProfiles,
                        id: \.operatorID
                    ) { profile in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(profile.displayName)
                            Text(
                                [
                                    profile.organization,
                                    profile.role,
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.fieldEvidence.isEmpty {
                Section("Field evidence") {
                    ForEach(
                        model.fieldEvidence,
                        id: \.evidenceID
                    ) { record in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(record.title)
                            Text(
                                [
                                    FieldAuthorityPresentation
                                        .evidenceKindName(
                                            record.kind
                                        ),
                                    record.acquisition.rawValue,
                                    record.asset?.assetPath
                                        ?? record.asset?.frameRef,
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption.monospaced())
                            if let operatorID = record.operatorID {
                                Text(
                                    "author: "
                                        + operatorName(
                                            operatorID
                                        )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !model.instruments.isEmpty {
                Section("Measurement instruments") {
                    ForEach(
                        model.instruments,
                        id: \.id
                    ) { instrument in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                [
                                    instrument.manufacturer,
                                    instrument.model,
                                ]
                                .compactMap { $0 }
                                .joined(separator: " ")
                            )
                            Text(
                                [
                                    instrument
                                        .serialOrAssetID
                                        .map {
                                            "serial " + $0
                                        },
                                    FieldAuthorityPresentation
                                        .calibrationStateName(
                                            instrument
                                                .calibrationState
                                        ),
                                    instrument.calibrationDate,
                                    "v"
                                        + String(
                                            instrument
                                                .profileVersion
                                        ),
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.settingsObservations.isEmpty {
                Section("Installed settings") {
                    ForEach(
                        model.settingsObservations,
                        id: \.observationID
                    ) { observation in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(observation.targetRef)
                                .font(.caption.monospaced())
                            Text(
                                "\(observation.settings.count) setting(s) · "
                                    + observation.recordedAtUTC
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.wiringRoutes.isEmpty {
                Section("As-built wiring") {
                    ForEach(
                        model.wiringRoutes,
                        id: \.routeID
                    ) { route in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(route.cableType)
                            Text(
                                [
                                    FieldAuthorityPresentation
                                        .routeStateName(
                                            route.state
                                        ),
                                    route.serviceType,
                                    "\(route.segments.count) segment(s)",
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Opening review") {
                if let review = model.openingReview {
                    Text(
                        "\(review.openings.count) candidate(s) recorded"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if model.readOnly {
                    ForEach(
                        model.openingReview?.openings ?? [],
                        id: \.openingID
                    ) { opening in
                        openingRow(opening, interactive: false)
                    }
                } else {
                    Button("Load opening candidates") {
                        Task {
                            openings =
                                await openingReviewCandidates()
                        }
                    }
                    ForEach(
                        openings
                            ?? model.openingReview?.openings
                                ?? [],
                        id: \.openingID
                    ) { opening in
                        openingRow(opening, interactive: true)
                    }
                    if openings != nil {
                        Button("Save opening review") {
                            guard let openings else { return }
                            Task {
                                let ok =
                                    await commitOpeningReview(
                                        openings
                                    )
                                openingSaveState = ok
                                    ? "Saved"
                                    : "Save failed"
                            }
                        }
                    }
                    // User-declared boundary openings (issue #231):
                    // vents, grilles, undercuts, and penetrations
                    // RoomPlan never infers. A captured camera point
                    // supplies the center; these never promote into
                    // solver Portal physics automatically.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add opening candidate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker(
                            "Kind",
                            selection: $newOpeningKind
                        ) {
                            ForEach(
                                RoomOpeningKind.allCases,
                                id: \.self
                            ) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker(
                            "State",
                            selection: $newOpeningState
                        ) {
                            ForEach(
                                RoomOpeningState.allCases,
                                id: \.self
                            ) { state in
                                Text(state.rawValue).tag(state)
                            }
                        }
                        .pickerStyle(.segmented)
                        HStack(spacing: 8) {
                            TextField(
                                "Width m",
                                text: $newOpeningWidth
                            )
                            TextField(
                                "Height m",
                                text: $newOpeningHeight
                            )
                        }
                        .font(.caption)
                        Button(
                            openingCenterPending == nil
                                ? "Mark opening center"
                                : "Center captured"
                        ) {
                            captureOpeningCenter()
                        }
                        .disabled(openingCenterPending != nil)
                        if let center = openingCenterPending {
                            Button("Add candidate") {
                                addUserOpeningCandidate(
                                    center: center
                                )
                            }
                        }
                    }
                    if let openingSaveState {
                        Text(openingSaveState)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Room reference frame") {
                if let frame = model.roomReferenceFrame {
                    LabeledContent(
                        "Origin (m)",
                        value: String(
                            format: "%.2f, %.2f, %.2f",
                            frame.originMeters.x,
                            frame.originMeters.y,
                            frame.originMeters.z
                        )
                    )
                    LabeledContent(
                        "Front",
                        value: String(
                            format: "%.2f, %.2f, %.2f",
                            frame.frontDirection.x,
                            frame.frontDirection.y,
                            frame.frontDirection.z
                        )
                    )
                    LabeledContent(
                        "Confirmed",
                        value: frame.confirmedAtUTC
                    )
                } else {
                    Text("No room reference frame confirmed")
                        .foregroundStyle(.secondary)
                }
                if !model.readOnly
                    && !model.spatialCaptureSealed
                {
                    Text(
                        "Stand at the intended room origin, confirm, then aim toward the room front and confirm the second point. The frame binds to the current coordinate space only."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button(
                        roomFrameOriginPending == nil
                            ? "Mark room origin"
                            : "Room origin captured"
                    ) {
                        captureRoomFrameOrigin()
                    }
                    .disabled(roomFrameOriginPending != nil)
                    if roomFrameOriginPending != nil {
                        Button("Confirm room front") {
                            confirmRoomReferenceFrame()
                        }
                    }
                }
            }

            Section("Field datum (HTDT promotion)") {
                if let datum = model.roomFieldDatum {
                    LabeledContent(
                        "Origin",
                        value: datum.origin.kind.rawValue
                    )
                    LabeledContent(
                        "Axis",
                        value: datum.axis.kind.rawValue
                    )
                    LabeledContent(
                        "Vertical datum",
                        value: datum.verticalDatum.kind
                            .rawValue
                    )
                    LabeledContent(
                        "Origin (m)",
                        value: String(
                            format: "%.2f, %.2f, %.2f",
                            datum.fieldFromCaptureWorld
                                .originMeters.x,
                            datum.fieldFromCaptureWorld
                                .originMeters.y,
                            datum.fieldFromCaptureWorld
                                .originMeters.z
                        )
                    )
                    LabeledContent(
                        "Status",
                        value: {
                            switch model
                                .roomFieldDatumStaleness
                            {
                            case .current:
                                return "current"
                            case .stale(let refs):
                                return "stale — "
                                    + "\(refs.count)"
                                    + " unresolved ref(s)"
                            case nil:
                                return "current"
                            }
                        }()
                    )
                    Text(
                        "Promotion reference only: records the capture-world→field datum convention and its exact transform. It is not T_scene_from_capture_world."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if !model.readOnly
                        && !model.spatialCaptureSealed
                    {
                        Button(
                            "Remove field datum",
                            role: .destructive
                        ) {
                            Task {
                                await removeRoomFieldDatum()
                            }
                        }
                        .font(.caption)
                    }
                } else {
                    Text("No field datum confirmed")
                        .foregroundStyle(.secondary)
                    if !model.readOnly
                        && !model.spatialCaptureSealed
                    {
                        Button("Confirm from room frame") {
                            Task {
                                _ = await
                                    confirmFieldDatumFromRoomFrame()
                            }
                        }
                        .disabled(
                            model.roomReferenceFrame == nil
                        )
                        if model.roomReferenceFrame == nil {
                            Text(
                                "Confirm a room reference frame first."
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            fieldNotesSection

            if !model.issues.isEmpty {
                Section("Workspace issues") {
                    ForEach(model.issues, id: \.self) { issue in
                        Text(issue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(
            model.readOnly ? "Persisted capture" : "Review workspace"
        )
        .sheet(isPresented: $composingFieldNote) {
            FieldNoteComposeSheet(
                allowsEvidenceAttachment: false,
                bindingCandidates: fieldNoteBindingCandidates
            ) { draft in
                recordReviewFieldNote(
                    draft.text,
                    draft.category,
                    draft.needsAttention,
                    draft.bindingRefs
                )
            }
        }
        .sheet(item: $supersedingFieldNote) { note in
            FieldNoteComposeSheet(
                allowsEvidenceAttachment: false,
                bindingCandidates: fieldNoteBindingCandidates
            ) { draft in
                supersedeFieldNote(
                    note.noteID,
                    draft.text,
                    draft.category
                )
            }
            .id(note.noteID)
        }
        .sheet(item: $bindingFieldNote) { note in
            fieldNoteBindingSheet(note)
        }
        .confirmationDialog(
            "Remove evidence frame?",
            isPresented: Binding(
                get: { confirmingFrameRemoval != nil },
                set: { shown in
                    if !shown { confirmingFrameRemoval = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: confirmingFrameRemoval
        ) { frameID in
            Button("Remove frame", role: .destructive) {
                Task {
                    await removeEvidenceFrame(frameID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(
                "Permanently deletes this frame's pixels, depth, confidence, and preview from the working capture."
            )
        }
    }

    /// #352: the mission bound before acquisition. Mission
    /// completeness is displayed against committed outcomes and stays
    /// distinct from the technical `ready_for_htdt_ingestion` verdict.
    @ViewBuilder
    private var captureMissionSection: some View {
        if let plan = model.captureTaskPlan {
            Section {
                LabeledContent(
                    "Plan",
                    value: "\(plan.planID) · v\(plan.planVersion)"
                )
                LabeledContent("Room", value: plan.roomName)
                LabeledContent(
                    "Issued",
                    value: plan.issuedAtUTC ?? "—"
                )
                if let status = model.taskPlanStatus {
                    let done = status.items.filter {
                        $0.outcome == .completed
                    }.count
                    let pending = status.items.filter {
                        $0.outcome == .pending
                    }.count
                    LabeledContent(
                        "Checklist",
                        value: String(
                            format: String(
                                localized:
                                    "%d complete · %d pending · %d items"
                            ),
                            done,
                            pending,
                            status.items.count
                        )
                    )
                } else {
                    Text("No checklist outcomes recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                NavigationLink("Review mission checklist") {
                    CaptureTaskPlanChecklistView(
                        plan: plan,
                        outcomes:
                            model.taskPlanStatus?.items ?? [],
                        onMark: markTaskPlanItem
                    )
                }
            } header: {
                Text("Capture mission")
            } footer: {
                Text(
                    "Mission completeness is reviewed against the bound plan — it is workflow intent, not observed truth, and never replaces technical readiness."
                )
            }
        }
    }

    /// #375: operator field notes bound to this revision. Notes are
    /// append-only — corrections supersede — and the unresolved
    /// attention subset also surfaces in the banner above the plan
    /// preview. Binding candidates cover the authority refs the
    /// shared grammar accepts (entities, measurements, field
    /// evidence, instruments, wiring, settings).
    @ViewBuilder
    private var fieldNotesSection: some View {
        let collection = CaptureFieldNoteCollection(
            notes: model.fieldNotes
        )
        if !model.fieldNotes.isEmpty || !model.readOnly {
            Section {
                if !model.readOnly {
                    Button {
                        composingFieldNote = true
                    } label: {
                        Label(
                            "Add field note",
                            systemImage: "note.text.badge.plus"
                        )
                    }
                }
                if collection.chronological.isEmpty {
                    Text("No field notes")
                        .foregroundStyle(.secondary)
                } else {
                    let attention = collection
                        .unresolvedAttention.count
                    if attention > 0 {
                        Label(
                            String(
                                format: String(
                                    localized:
                                        "%d note(s) need attention before finalize"
                                ),
                                attention
                            ),
                            systemImage:
                                "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            CaptureColorRole.attention.color
                        )
                    }
                    ForEach(
                        collection.chronological
                    ) { note in
                        fieldNoteRow(note)
                    }
                }
            } header: {
                Text("Field notes")
            } footer: {
                Text(
                    "Notes are operator context carried in the bundle — superseded and resolved notes stay in the document so a receiver sees the full record."
                )
            }
        }
    }

    @ViewBuilder
    private func fieldNoteRow(
        _ note: CaptureFieldNote
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(
                    note.category.rawValue
                        .replacingOccurrences(
                            of: "_",
                            with: " "
                        ).capitalized
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                if note.needsAttention,
                   note.status == .active
                {
                    Label(
                        "Attention",
                        systemImage:
                            "exclamationmark.circle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        CaptureColorRole.attention.color
                    )
                }
                Spacer()
                Text(note.status.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(note.text)
                .font(.callout)
            Text(
                [
                    note.createdAtUTC,
                    note.authoringMethod.rawValue,
                    note.bindingRefs.isEmpty
                        ? "unbound"
                        : "\(note.bindingRefs.count) binding(s)",
                ].joined(separator: " · ")
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            if !note.evidenceRefs.isEmpty {
                Text(
                    "Evidence: "
                        + note.evidenceRefs
                            .joined(separator: ", ")
                )
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            }
            if !model.readOnly, note.status == .active {
                HStack(spacing: 12) {
                    Button("Resolve") {
                        resolveFieldNote(note.noteID)
                    }
                    .font(.caption)
                    Button("Correct…") {
                        supersedingFieldNote = note
                    }
                    .font(.caption)
                    if note.bindingRefs.isEmpty {
                        Button("Bind…") {
                            bindingFieldNote = note
                        }
                        .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
    }

    /// #375: binds an unbound note by superseding it with the same
    /// text + the chosen ref — the stored lineage shows the intent.
    @ViewBuilder
    private func fieldNoteBindingSheet(
        _ note: CaptureFieldNote
    ) -> some View {
        NavigationStack {
            List {
                Section("Bind note to") {
                    ForEach(
                        fieldNoteBindingCandidates,
                        id: \.self
                    ) { ref in
                        Button(ref) {
                            bindFieldNote(note.noteID, ref)
                            bindingFieldNote = nil
                        }
                        .font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Bind note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        bindingFieldNote = nil
                    }
                }
            }
        }
    }

    /// Binding refs the grammar accepts, drawn from this revision's
    /// committed authority + evidence.
    private var fieldNoteBindingCandidates: [String] {
        var refs: [String] = []
        refs += model.annotations.map {
            "entity:" + $0.entityID.description
        }
        refs += model.measurements.map {
            "measurement:" + $0.measurementID.description
        }
        refs += model.fieldEvidence.map {
            "field_evidence:" + $0.evidenceID.description
        }
        refs += model.instruments.map {
            "instrument:" + $0.instrumentID.description
        }
        refs += model.operatorProfiles.map {
            "operator:" + $0.operatorID.description
        }
        refs += model.settingsObservations.map {
            "settings_observation:" + $0.observationID.description
        }
        refs += model.wiringRoutes.map {
            "wiring_route:" + $0.routeID.description
        }
        return refs
    }

    /// #325: every unresolved flag dropped during scanning is listed
    /// for mandatory review, each with its location, suggested
    /// remediation route, and explicit resolve/skip actions. Resolving
    /// links a real authority rather than editing the marker.
    @ViewBuilder
    private var revisitFlagsSection: some View {
        if !model.revisitFlags.isEmpty {
            Section {
                ForEach(model.revisitFlags) { flag in
                    revisitFlagRow(flag)
                }
            } header: {
                Text("Review flags")
            } footer: {
                Text(
                    "Flags are operator intent markers, not measurements. Resolve each against a remediation workflow or acknowledge it; unresolved flags stay listed until explicit disposition."
                )
            }
        }
    }

    @ViewBuilder
    private func revisitFlagRow(
        _ flag: ScanRevisitFlag
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(
                    systemName: flag.status == .unresolved
                        ? "flag.fill"
                        : "flag"
                )
                .foregroundStyle(revisitFlagTint(flag))
                Text(
                    flag.category.map {
                        revisitFlagCategoryLabel($0)
                    } ?? String(localized: "Flag")
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text(flag.status.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(flag.locationSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if let note = flag.note {
                Text(note)
                    .font(.caption)
            }

            Text(
                revisitFlagRemediationLabel(
                    flag.suggestedRemediation
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            if !model.readOnly {
                switch flag.status {
                case .unresolved:
                    HStack(spacing: 10) {
                        Menu("Resolve") {
                            Button(
                                "Link to authority"
                            ) {
                                resolveRevisitFlag(
                                    flag.flagID,
                                    .linkedAuthority,
                                    nil
                                )
                            }
                            Button("Acknowledged") {
                                resolveRevisitFlag(
                                    flag.flagID,
                                    .acknowledged,
                                    nil
                                )
                            }
                            Button(
                                "Mark unavailable"
                            ) {
                                resolveRevisitFlag(
                                    flag.flagID,
                                    .markedUnavailable,
                                    nil
                                )
                            }
                        }
                        .font(.caption)
                        Button("Skip") {
                            resolveRevisitFlag(
                                flag.flagID,
                                .acknowledged,
                                nil
                            )
                        }
                        .font(.caption)
                    }
                case .resolved, .skipped, .unavailable:
                    Button("Reopen") {
                        reopenRevisitFlag(flag.flagID)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func revisitFlagTint(
        _ flag: ScanRevisitFlag
    ) -> Color {
        switch flag.status {
        case .unresolved:
            return .orange
        case .resolved:
            return .green
        case .skipped:
            return .secondary
        case .unavailable:
            return .gray
        }
    }

    private func revisitFlagRemediationLabel(
        _ remediation: ScanRevisitRemediation
    ) -> String {
        switch remediation {
        case .targetedRescan:
            return String(
                localized:
                    "Suggested: targeted rescan"
            )
        case .annotation:
            return String(
                localized:
                    "Suggested: annotate in Review"
            )
        case .reobserve:
            return String(
                localized:
                    "Suggested: re-observe region"
            )
        case .measurement:
            return String(
                localized:
                    "Suggested: re-measure"
            )
        case .equipmentNote:
            return String(
                localized:
                    "Suggested: equipment note"
            )
        case .generalReview:
            return String(
                localized:
                    "Suggested: general review"
            )
        }
    }

    private func revisitFlagCategoryLabel(
        _ category: ScanRevisitFlagCategory
    ) -> String {
        switch category {
        case .geometry:
            return String(localized: "Geometry")
        case .opening:
            return String(localized: "Opening")
        case .reflectiveTransparent:
            return String(
                localized: "Reflective / transparent"
            )
        case .objectDetail:
            return String(localized: "Object detail")
        case .measurement:
            return String(localized: "Measurement")
        case .equipment:
            return String(localized: "Equipment")
        case .other:
            return String(localized: "Other")
        }
    }

    @ViewBuilder
    private func evidenceRow(
        _ item: ReviewEvidenceItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CaptureTechnicalText(item.frameID.description)
            LabeledContent(
                "Bytes",
                value: ByteCountFormatter.string(
                    fromByteCount: item.byteCount,
                    countStyle: .file
                )
            )
            LabeledContent(
                "Kept because",
                value: retentionLabel(item.retentionReason)
            )
            if !item.referencedBy.isEmpty {
                Text(
                    "Referenced by "
                        + item.referencedBy.joined(
                            separator: ", "
                        )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            #if os(iOS)
            if let url = item.previewFileURL {
                AsyncPreviewImage(url: url)
                    .frame(height: 140)
            }
            #endif
            if item.removable {
                Button("Remove frame", role: .destructive) {
                    confirmingFrameRemoval = item.frameID
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func openingRow(
        _ opening: RoomOpeningCandidate,
        interactive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(
                opening.kind.rawValue,
                value: opening.disposition.rawValue
                    + " · "
                    + opening.openState.rawValue
            )
            Text(opening.sourceRef)
                .font(.caption2.monospaced())
            if interactive {
                HStack(spacing: 8) {
                    Button("Confirm") {
                        setDisposition(.confirmed, on: opening)
                    }
                    Button("Needs scan") {
                        setDisposition(
                            .needsMoreScanning,
                            on: opening
                        )
                    }
                    Button("Ignore") {
                        setDisposition(
                            .intentionallyIgnored,
                            on: opening
                        )
                    }
                }
                .font(.caption)
                HStack(spacing: 8) {
                    Text("State")
                    Button("Open") {
                        setOpenState(.open, on: opening)
                    }
                    Button("Closed") {
                        setOpenState(.closed, on: opening)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private func setDisposition(
        _ disposition: RoomOpeningDisposition,
        on opening: RoomOpeningCandidate
    ) {
        guard var current = openings
            ?? model.openingReview?.openings
        else { return }
        current = OpeningReviewEditor.setDisposition(
            disposition,
            openingID: opening.openingID,
            in: current,
            reviewedAtUTC: BundleTimestamp.utcString(
                from: Date()
            )
        ) ?? current
        openings = current
    }

    private func setOpenState(
        _ state: RoomOpeningState,
        on opening: RoomOpeningCandidate
    ) {
        guard var current = openings
            ?? model.openingReview?.openings
        else { return }
        current = OpeningReviewEditor.setOpenState(
            state,
            openingID: opening.openingID,
            in: current
        ) ?? current
        openings = current
    }

    private func addUserOpeningCandidate(
        center: WorldPoint3D
    ) {
        let width = Double(newOpeningWidth) ?? 0.3
        let height = Double(newOpeningHeight) ?? 0.3
        var current = openings
            ?? model.openingReview?.openings
            ?? []
        if let updated = OpeningReviewEditor
            .addUserDeclaredCandidate(
                kind: newOpeningKind,
                sourceRef: "user:"
                    + UUID()
                        .uuidString.lowercased(),
                centerMeters: center,
                widthMeters: width,
                heightMeters: height,
                openState: newOpeningState,
                evidenceRefs: [],
                to: current
            )
        {
            current = updated
            clearOpeningCenter()
        }
        openings = current
    }

    private func operatorName(
        _ id: OperatorProfileID
    ) -> String {
        model.operatorProfiles.first(where: {
            $0.operatorID == id
        })?.displayName ?? id.description
    }

    private func operatorSuffix(
        _ id: OperatorProfileID?
    ) -> String {
        guard let id else { return "" }
        return " · author: " + operatorName(id)
    }

    private func retentionLabel(
        _ reason: EvidenceRetentionReason
    ) -> String {
        switch reason {
        case .endBoundary:
            return "Closing evidence"
        case .linkedToAuthority:
            return "Referenced evidence"
        case .automaticKeyframe:
            return "Automatic keyframe"
        case .operatorSaved:
            return "Optional visual frame"
        }
    }
}

/// The plan-projection canvas for the Review workspace (issue #213):
/// walls as segments, openings/objects as markers, drawn from the
/// platform-independent `RoomPlanPreviewModel`.
public struct RoomPlanPreviewCanvas: View {
    public let model: RoomPlanPreviewModel

    public init(model: RoomPlanPreviewModel) {
        self.model = model
    }

    public var body: some View {
        Canvas { context, size in
            let spanX = max(model.maxX - model.minX, 0.01)
            let spanZ = max(model.maxZ - model.minZ, 0.01)
            let scale = min(
                Double(size.width) / spanX,
                Double(size.height) / spanZ
            ) * 0.9
            let offsetX =
                (Double(size.width) - spanX * scale) / 2
            let offsetY =
                (Double(size.height) - spanZ * scale) / 2

            func point(_ x: Double, _ z: Double) -> CGPoint {
                CGPoint(
                    x: offsetX
                        + (x - model.minX) * scale,
                    y: offsetY
                        + (z - model.minZ) * scale
                )
            }

            for wall in model.walls {
                var path = Path()
                path.move(
                    to: point(wall.startX, wall.startZ)
                )
                path.addLine(
                    to: point(wall.endX, wall.endZ)
                )
                context.stroke(
                    path,
                    with: .color(.primary),
                    lineWidth: 2
                )
            }

            for marker in model.markers {
                let p = point(marker.x, marker.z)
                let color: Color =
                    switch marker.kind {
                    case .door: .green
                    case .window: .blue
                    case .opening: .teal
                    case .object: .gray
                    case .annotation: .orange
                    case .roomFrameOrigin: .red
                    case .roomFrameFront: .purple
                    case .revisitFlag: .pink
                    }
                let rect = CGRect(
                    x: p.x - 4,
                    y: p.y - 4,
                    width: 8,
                    height: 8
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(color)
                )
                if let dirX = marker.dirX,
                   let dirZ = marker.dirZ
                {
                    let len = max(
                        (dirX * dirX + dirZ * dirZ)
                            .squareRoot(),
                        0.001
                    )
                    var arrow = Path()
                    arrow.move(to: p)
                    arrow.addLine(
                        to: CGPoint(
                            x: p.x + dirX / len * 14,
                            y: p.y + dirZ / len * 14
                        )
                    )
                    context.stroke(
                        arrow,
                        with: .color(color),
                        lineWidth: 1
                    )
                }
            }
        }
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#if os(iOS)
/// Loads a preview HEIC lazily for the evidence gallery. Previews are
/// derived convenience artifacts; a missing/unreadable preview degrades
/// to a placeholder, never to a hidden failure.
struct AsyncPreviewImage: View {
    let url: URL

    var body: some View {
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Text("Preview unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
