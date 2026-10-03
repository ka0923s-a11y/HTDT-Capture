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
    /// skipped/unavailable from Review. #364 §10: the optional third
    /// argument carries the collected reason to the mission waiver
    /// ledger; `canRecordTaskPlanReason` gates the prompt.
    public let markTaskPlanItem:
        (String, TaskPlanItemOutcome, String?) -> Void
    /// Whether the bound plan maps to a mission record so a marking
    /// reason can persist — the checklist only offers "with reason"
    /// items when the waiver channel exists.
    public let canRecordTaskPlanReason: Bool
    /// #232: confirms a field/install datum derived from the
    /// committed room reference frame. Returns false when the room
    /// frame is missing or the commit failed.
    public let confirmFieldDatumFromRoomFrame:
        () async -> Bool
    /// #232: removes the committed field datum payload.
    public let removeRoomFieldDatum: () async -> Void
    /// #232: commits a field datum declared from bounded operands —
    /// entity/measurement/room-frame/stated picks resolved by the
    /// host into the persisted document. Returns false on a failed
    /// or rejected commit.
    public let commitFieldDatum:
        (RoomFieldDatumAuthoringRequest) async -> Bool
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
    /// #460: clears a frame's privacy flag — the paired action of
    /// `flagEvidenceFrameForPrivacy`.
    public let unflagEvidenceFrameForPrivacy:
        (EvidenceFrameID) -> Void
    /// #408/#409: the accepted RoomPlan bindable objects (loaded by
    /// the host from `roomplan/captured-room.json`) — they drive
    /// both the 3D scene's surface elements and the survey's
    /// boundary targets. Empty on hosts that cannot decode RoomPlan.
    public let roomPlanObjects: [RoomPlanBindableObject]

    @State private var openings: [RoomOpeningCandidate]?
    @State private var openingSaveState: String?
    @State private var confirmingFrameRemoval:
        EvidenceFrameID?
    @State private var newOpeningKind: RoomOpeningKind = .hvacGrille
    @State private var newOpeningState: RoomOpeningState = .open
    @State private var newOpeningWidth = "0.30"
    @State private var newOpeningHeight = "0.30"
    /// Plan selection is UI state only — it never persists (#367).
    @State private var planSelection:
        RoomPlanPreviewModel.PlanMarker?
    @State private var planFocusToken = 0
    @State private var planLabelMode: ReviewPlanLabelMode = .off
    @State private var composingFieldNote = false
    @State private var authoringDatum = false
    @State private var supersedingFieldNote: CaptureFieldNote?
    @State private var bindingFieldNote: CaptureFieldNote?
    /// #408: Plan stays the default surface; the accepted-geometry
    /// 3D scene is the second tab over the same committed data.
    @State private var geometryMode: ReviewGeometryMode = .plan

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
            (String, TaskPlanItemOutcome, String?) -> Void =
                { _, _, _ in },
        canRecordTaskPlanReason: Bool = false,
        confirmFieldDatumFromRoomFrame: @escaping
            () async -> Bool = { false },
        removeRoomFieldDatum: @escaping () async -> Void = {},
        commitFieldDatum: @escaping
            (RoomFieldDatumAuthoringRequest) async -> Bool =
            { _ in false },
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
            (EvidenceFrameID) -> Void = { _ in },
        unflagEvidenceFrameForPrivacy: @escaping
            (EvidenceFrameID) -> Void = { _ in },
        roomPlanObjects: [RoomPlanBindableObject] = []
    ) {
        self.model = model
        self.roomPlanObjects = roomPlanObjects
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
        self.canRecordTaskPlanReason = canRecordTaskPlanReason
        self.confirmFieldDatumFromRoomFrame =
            confirmFieldDatumFromRoomFrame
        self.removeRoomFieldDatum = removeRoomFieldDatum
        self.commitFieldDatum = commitFieldDatum
        self.captureOpeningCenter = captureOpeningCenter
        self.clearOpeningCenter = clearOpeningCenter
        self.recordReviewFieldNote = recordReviewFieldNote
        self.resolveFieldNote = resolveFieldNote
        self.supersedeFieldNote = supersedeFieldNote
        self.bindFieldNote = bindFieldNote
        self.flagEvidenceFrameForPrivacy =
            flagEvidenceFrameForPrivacy
        self.unflagEvidenceFrameForPrivacy =
            unflagEvidenceFrameForPrivacy
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

            Section("Geometry") {
                // #408: the same committed evidence through two
                // surfaces — the 2D plan stays default; 3D renders
                // accepted geometry only (never speculative).
                if sceneModel.elements.isEmpty,
                   model.planPreview == nil
                {
                    Text(
                        "No room plan is stored in this capture"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Surface",
                        selection: $geometryMode
                    ) {
                        Text("Plan")
                            .tag(ReviewGeometryMode.plan)
                        Text("3D")
                            .tag(ReviewGeometryMode.threeD)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(
                        geometryMode == .plan
                            ? "Flat 2D plan view of the room and its markers."
                            : "Interactive 3D view of the captured room geometry."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if geometryMode == .plan {
                        if let plan = model.planPreview {
                            ReviewPlanSurface(
                                model: plan,
                                markers: planMarkers(plan),
                                selection: $planSelection,
                                focusToken: $planFocusToken,
                                labelMode: $planLabelMode
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
                                "No room plan is stored in this capture"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        AcceptedGeometrySceneView(
                            scene: sceneModel,
                            readOnly: model.readOnly
                        )
                    }
                }
            }

            // #409: the spatial survey pass — object-first review of
            // every committed target with its attributed records.
            Section {
                NavigationLink {
                    SpatialSurveyView(
                        readOnly: model.readOnly
                    ) { mode in
                        surveyModel(mode: mode)
                    }
                } label: {
                    Label {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text("Spatial survey")
                            Text(
                                surveyBadgeText
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(
                            systemName:
                                "checklist.checked"
                        )
                    }
                }
            } footer: {
                Text(
                    "Object-first review state over every committed surface, object, and entity — derived from existing records, never a parallel schema."
                )
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
                                flagEvidenceFrameForPrivacy,
                            unflagForPrivacy:
                                unflagEvidenceFrameForPrivacy
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
                        let entityMarker = marker(
                            forEntityID: entity.entityID
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entity.label)
                                    .font(.headline)
                                Spacer()
                                if let entityMarker {
                                    Button("Show on plan") {
                                        planSelection = entityMarker
                                        planFocusToken += 1
                                    }
                                    .font(.caption)
                                }
                            }
                            Text(
                                TheaterAuthorityPresentation
                                    .entityTypeName(entity.type)
                                    + operatorSuffix(
                                        entity.authorOperatorID
                                    )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            CaptureTechnicalText(
                                entity.entityID.description
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let entityMarker {
                                planSelection = entityMarker
                                planFocusToken += 1
                            }
                        }
                        .listRowBackground(
                            isSelectedMarker(entityMarker)
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
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
                            Text(
                                FieldNoteBindingResolver
                                    .measurementTitle(measurement)
                            )
                            .font(.subheadline)
                            CaptureTechnicalText(
                                measurement.measurementID
                                    .description
                            )
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
                                    TheaterAuthorityPresentation
                                        .fieldEvidenceAcquisitionName(
                                            record.acquisition
                                        ),
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
                            Text(
                                FieldNoteBindingResolver
                                    .settingsTitle(observation)
                            )
                            .font(.subheadline)
                            Text(
                                String(
                                    format: String(
                                        localized: "%@ · %@"
                                    ),
                                    captureCountPhrase(
                                        observation.settings
                                            .count,
                                        singular: String(
                                            localized: "%lld setting"
                                        ),
                                        plural: String(
                                            localized: "%lld settings"
                                        )
                                    ),
                                    observation.recordedAtUTC
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            CaptureTechnicalText(
                                observation.targetRef
                            )
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
                                    captureCountPhrase(
                                        route.segments.count,
                                        singular: String(
                                            localized: "%lld segment"
                                        ),
                                        plural: String(
                                            localized: "%lld segments"
                                        )
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

            referenceTargetsSection

            Section("Opening review") {
                if let review = model.openingReview {
                    Text(
                        captureCountPhrase(
                            review.openings.count,
                            singular: String(
                                localized: "%lld candidate recorded"
                            ),
                            plural: String(
                                localized: "%lld candidates recorded"
                            )
                        )
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
                                DescribedPickerOption(
                                    title: TheaterAuthorityPresentation
                                        .openingKindName(kind),
                                    detail: TheaterAuthorityPresentation
                                        .openingKindDescription(kind)
                                )
                                .tag(kind)
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
                                Text(
                                    TheaterAuthorityPresentation
                                        .openingStateName(state)
                                )
                                .tag(state)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(
                            TheaterAuthorityPresentation
                                .openingStateDescription(
                                    newOpeningState
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        // Spatial affordance — sealed or recovered
                        // working sets have no live camera pose to
                        // capture; the coordinator would silently
                        // no-op.
                        .disabled(
                            openingCenterPending != nil
                                || model.spatialCaptureSealed
                        )
                        if let center = openingCenterPending {
                            Button("Add candidate") {
                                addUserOpeningCandidate(
                                    center: center
                                )
                            }
                            // A pending center belongs to the live
                            // capture it was marked in — a sealed
                            // working set must not commit it.
                            .disabled(model.spatialCaptureSealed)
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
                        value: TheaterAuthorityPresentation
                            .datumOriginKindName(
                                datum.origin.kind
                            )
                    )
                    LabeledContent(
                        "Axis",
                        value: TheaterAuthorityPresentation
                            .datumAxisKindName(
                                datum.axis.kind
                            )
                    )
                    LabeledContent(
                        "Vertical datum",
                        value: TheaterAuthorityPresentation
                            .datumVerticalKindName(
                                datum.verticalDatum.kind
                            )
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
                                return String(
                                    localized: "Current"
                                )
                            case .stale(let refs):
                                return captureCountPhrase(
                                    refs.count,
                                    singular: String(
                                        localized: "Stale — %lld unresolved reference"
                                    ),
                                    plural: String(
                                        localized: "Stale — %lld unresolved references"
                                    )
                                )
                            case nil:
                                return String(
                                    localized: "Current"
                                )
                            }
                        }()
                    )
                    Text(
                        "Promotion reference only: records the convention that maps capture-world coordinates onto the field datum, plus its exact transform. It is not the scene-to-capture-world transform."
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
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
                        Button("Author datum from evidence") {
                            authoringDatum = true
                        }
                        .disabled(
                            model.roomReferenceFrame == nil
                                && model.annotations.isEmpty
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
        .sheet(isPresented: $authoringDatum) {
            RoomFieldDatumAuthoringSheet(
                annotations: model.annotations,
                measurements: model.measurements,
                roomReferenceFrame: model.roomReferenceFrame,
                onCommit: commitFieldDatum
            )
        }
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
            // Supersession lineage (#420): the correction preloads
            // the original category and bindings so a small fix
            // does not silently drop the subject.
            FieldNoteComposeSheet(
                allowsEvidenceAttachment: false,
                bindingCandidates: fieldNoteBindingCandidates,
                preselectedCategory: note.category,
                preselectedBindingRefs: note.bindingRefs
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
            // One action-producing child — iOS 26 renders only
            // the first child, so a bare second Button's Cancel
            // never appears.
            Group {
                Button("Remove frame", role: .destructive) {
                    Task {
                        await removeEvidenceFrame(frameID)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: { _ in
            Text(
                "Permanently deletes this frame's pixels, depth, confidence, and preview from the working capture."
            )
        }
    }

    /// Preview-first evidence row (issue #367): thumbnail, human
    /// retention label, linked subjects, status symbols. Exact refs —
    /// frame ID, byte count, source paths — stay one disclosure away,
    /// and removal lives in the context menu, never in the primary
    /// row.
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
                        canRecordReason:
                            canRecordTaskPlanReason,
                        canMark: !model.readOnly,
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

    /// #227: declared reference targets, their sighting counts, and
    /// the scale-revisit diagnostics the builder computed at commit
    /// time. Rendered only when a targets document was committed.
    @ViewBuilder
    private var referenceTargetsSection: some View {
        if let document = model.referenceTargets,
           !document.targets.isEmpty
        {
            Section("Reference targets") {
                ForEach(document.targets, id: \.targetID) { target in
                    referenceTargetRow(
                        target: target,
                        observations: document.observations.filter {
                            $0.targetID == target.targetID
                        },
                        diagnostic: document.diagnostics.first {
                            $0.targetID == target.targetID
                        }
                    )
                }
            }
        }
    }

    private func referenceTargetRow(
        target: ReferenceTargetDeclaration,
        observations: [ReferenceTargetObservation],
        diagnostic: ReferenceTargetDiagnostics?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(target.targetType)
            Text(
                [
                    String(
                        format: "%.3f m",
                        target.knownDimensionMeters
                    ),
                    FieldAuthorityPresentation
                        .targetDimensionAuthorityName(
                            target.dimensionAuthority
                        ),
                    captureCountPhrase(
                        observations.count,
                        singular: String(
                            localized: "%lld sighting"
                        ),
                        plural: String(
                            localized: "%lld sightings"
                        )
                    ),
                ]
                .joined(separator: " · ")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if let diagnostic {
                Text(
                    [
                        diagnostic.scaleResidualFraction.map {
                            String(
                                format: String(
                                    localized:
                                        "scale residual %+.2f%%"
                                ),
                                $0 * 100
                            )
                        },
                        diagnostic.revisitDisplacementMeters.map {
                            String(
                                format: String(
                                    localized: "revisit %.3f m"
                                ),
                                $0
                            )
                        },
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                            captureCountPhrase(
                                attention,
                                singular: String(
                                    localized: "%lld note needs attention before finalize"
                                ),
                                plural: String(
                                    localized: "%lld notes need attention before finalize"
                                )
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

    /// Resolved labels for this workspace's authority refs — the
    /// shared resolver every note surface uses (issue #420).
    private var fieldNoteResolverCandidates:
        [FieldNoteBindingCandidate]
    { fieldNoteBindingCandidates }

    @ViewBuilder
    private func fieldNoteRow(
        _ note: CaptureFieldNote
    ) -> some View {
        let noteMarker = marker(forFieldNoteID: note.noteID)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(
                    FieldNoteBindingResolver.categoryName(
                        note.category
                    )
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
                if let position = note.spatialPosition {
                    Label(
                        FieldNoteBindingResolver.anchorName(
                            position.anchorKind
                        ),
                        systemImage: position.anchorKind
                            == .subjectPoint
                            ? "mappin.circle"
                            : "location.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if position.anchorKind == .subjectPoint,
                       let noteMarker = marker(
                           forFieldNoteID: note.noteID
                       )
                    {
                        Button("Show on plan") {
                            planSelection = noteMarker
                            planFocusToken += 1
                        }
                        .font(.caption2)
                        .accessibilityLabel(
                            String(
                                localized:
                                    "Show note location on plan"
                            )
                        )
                    }
                }
                Spacer()
                Text(
                    FieldNoteBindingResolver.statusName(
                        note.status
                    )
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Text(note.text)
                .font(.callout)
            if note.bindingRefs.isEmpty {
                Text("Not linked to a specific item")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(
                        note.bindingRefs,
                        id: \.self
                    ) { ref in
                        let candidate = FieldNoteBindingResolver
                            .resolve(
                                ref: ref,
                                in: fieldNoteResolverCandidates
                            )
                        Text(candidate.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(
                                String(
                                    format: String(
                                        localized:
                                            "Bound to %@"
                                    ),
                                    candidate.title
                                )
                            )
                    }
                }
            }
            if !note.evidenceRefs.isEmpty {
                // Evidence summaries resolve to record titles when
                // the ref names a committed record; an unresolvable
                // ref stays honest rather than vanishing (issue
                // #420).
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(
                        note.evidenceRefs,
                        id: \.self
                    ) { ref in
                        if let evidence = model.fieldEvidence
                            .first(where: {
                                "field_evidence:"
                                    + $0.evidenceID.description
                                    == ref
                            }) {
                            Text(evidence.title)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(
                                "Linked evidence unavailable"
                            )
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(
                        "Recorded",
                        value: note.createdAtUTC
                    )
                    LabeledContent(
                        "Authored",
                        value: FieldNoteBindingResolver
                            .authoringMethodName(
                                note.authoringMethod
                            )
                    )
                    if let position = note.spatialPosition {
                        LabeledContent(
                            "Anchor",
                            value: FieldNoteBindingResolver
                                .anchorName(
                                    position.anchorKind
                                )
                        )
                        Text(
                            "x "
                                + position.pointMeters.x.formatted()
                                + ", y "
                                + position.pointMeters.y.formatted()
                                + ", z "
                                + position.pointMeters.z.formatted()
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    }
                    ForEach(
                        note.bindingRefs
                            + note.evidenceRefs,
                        id: \.self
                    ) { ref in
                        Text(ref)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            } label: {
                Text("Details")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !model.readOnly, note.status == .active {
                HStack(spacing: 12) {
                    Button("Resolve") {
                        resolveFieldNote(note.noteID)
                    }
                    Button("Correct…") {
                        supersedingFieldNote = note
                    }
                    if note.bindingRefs.isEmpty {
                        Button("Bind…") {
                            bindingFieldNote = note
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if let noteMarker {
                planSelection = noteMarker
                planFocusToken += 1
            }
        }
        .listRowBackground(
            isSelectedMarker(noteMarker)
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
    }

    /// #375: binds an unbound note by superseding it with the same
    /// text + the chosen ref — the stored lineage shows the intent.
    /// #420: candidates group by authority kind under localized
    /// section headers, lead with the human label, and keep the
    /// exact ref as secondary context.
    @ViewBuilder
    private func fieldNoteBindingSheet(
        _ note: CaptureFieldNote
    ) -> some View {
        NavigationStack {
            List {
                ForEach(
                    FieldNoteBindingCandidate.Kind.allCases,
                    id: \.self
                ) { kind in
                    let group = fieldNoteBindingCandidates
                        .filter { $0.kind == kind }
                    if !group.isEmpty {
                        Section(kind.sectionTitle) {
                            ForEach(group) { candidate in
                                Button {
                                    bindFieldNote(
                                        note.noteID,
                                        candidate.ref
                                    )
                                    bindingFieldNote = nil
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(
                                            systemName:
                                                candidate
                                                    .systemImage
                                        )
                                        VStack(alignment: .leading) {
                                            Text(candidate.title)
                                            if let subtitle =
                                                candidate.subtitle {
                                                Text(subtitle)
                                                    .font(.caption2)
                                                    .foregroundStyle(
                                                        .secondary
                                                    )
                                            }
                                            Text(candidate.ref)
                                                .font(
                                                    .caption2
                                                        .monospaced()
                                                )
                                                .foregroundStyle(
                                                    .tertiary
                                                )
                                        }
                                    }
                                }
                            }
                        }
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

    /// Binding candidates drawn from this revision's committed
    /// authority + evidence, resolved to human labels (issue #420).
    private var fieldNoteBindingCandidates:
        [FieldNoteBindingCandidate]
    {
        FieldNoteBindingResolver.candidates(
            annotations: model.annotations,
            measurements: model.measurements,
            fieldEvidence: model.fieldEvidence,
            instruments: model.instruments,
            operatorProfiles: model.operatorProfiles,
            settingsObservations: model.settingsObservations,
            wiringRoutes: model.wiringRoutes
        )
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
                        MissionPresentation
                            .scanRevisitFlagCategoryName($0)
                    } ?? String(localized: "Flag")
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text(
                    MissionPresentation.scanRevisitFlagStatusName(
                        flag.status
                    )
                )
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
                        Button("Skip") {
                            resolveRevisitFlag(
                                flag.flagID,
                                .acknowledged,
                                nil
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                case .resolved, .skipped, .unavailable:
                    Button("Reopen") {
                        reopenRevisitFlag(flag.flagID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
            return CaptureColorRole.attention.color
        case .resolved:
            return CaptureColorRole.success.color
        case .skipped:
            return CaptureColorRole.secondary.color
        case .unavailable:
            return CaptureColorRole.unknown.color
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

    @ViewBuilder
    private func evidenceRow(
        _ item: ReviewEvidenceItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(
                alignment: .top,
                spacing: CaptureDesign.Spacing.group
            ) {
                #if os(iOS)
                AsyncPreviewImage(
                    url: item.previewFileURL
                )
                .frame(width: 72, height: 54)
                .clipShape(
                    RoundedRectangle(cornerRadius: 6)
                )
                #endif
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        TheaterAuthorityPresentation
                            .retentionReasonName(
                                item.retentionReason
                            )
                    )
                    .font(CaptureDesign.Typography.body)
                    if !item.referencedBy.isEmpty {
                        Text(
                            referencedSubjects(item.referencedBy)
                        )
                        .font(CaptureDesign.Typography.secondary)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 2) {
                    CaptureTechnicalDetail(
                        "Frame",
                        value: item.frameID.description
                    )
                    LabeledContent(
                        "Bytes",
                        value: ByteCountFormatter.string(
                            fromByteCount: item.byteCount,
                            countStyle: .file
                        )
                    )
                    .font(.caption)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .contextMenu {
            if item.removable {
                Button("Remove frame", role: .destructive) {
                    confirmingFrameRemoval = item.frameID
                }
            }
        }
    }

    /// "Referenced by" names in human terms (issue #367): entity
    /// labels, measurement types, opening kinds — never the raw
    /// `entity:<id>` / `measurement:<id>` tokens.
    private func referencedSubjects(
        _ refs: [String]
    ) -> String {
        refs.map { ref in
            TheaterAuthorityPresentation.referencedSubjectLabel(
                forRef: ref,
                in: model
            )
        }
        .joined(separator: ", ")
    }

    @ViewBuilder
    private func openingRow(
        _ opening: RoomOpeningCandidate,
        interactive: Bool
    ) -> some View {
        let openingMarker = marker(forOpening: opening)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                LabeledContent(
                    TheaterAuthorityPresentation
                        .openingKindName(opening.kind),
                    value: TheaterAuthorityPresentation
                        .openingDispositionName(
                            opening.disposition
                        )
                        + " · "
                        + TheaterAuthorityPresentation
                            .openingStateName(
                                opening.openState
                            )
                )
                if let openingMarker {
                    Button("Show on plan") {
                        planSelection = openingMarker
                        planFocusToken += 1
                    }
                    .font(.caption)
                }
            }
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
        .contentShape(Rectangle())
        .onTapGesture {
            if let openingMarker {
                planSelection = openingMarker
                planFocusToken += 1
            }
        }
        .listRowBackground(
            isSelectedMarker(openingMarker)
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
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

    /// The composed plan markers — base RoomPlan geometry overlaid
    /// with the workspace's review items (issue #367). A reviewed
    /// opening replaces its raw candidate dot via the shared
    /// `roomplan:<token>:<uuid>` identifier.
    private func planMarkers(
        _ plan: RoomPlanPreviewModel
    ) -> [RoomPlanPreviewModel.PlanMarker] {
        ReviewPlanPresentation.composedMarkers(
            base: plan.markers,
            overlay: ReviewPlanPresentation
                .overlayMarkers(for: model)
        )
    }

    /// #364 §7.4: a list row reflects plan-marker selection —
    /// tapping the row focuses the same marker on the plan, and
    /// selecting the marker there highlights the row.
    private func isSelectedMarker(
        _ marker: RoomPlanPreviewModel.PlanMarker?
    ) -> Bool {
        marker?.identifier != nil
            && planSelection?.identifier == marker?.identifier
    }

    private func marker(
        forEntityID id: AnnotationEntityID
    ) -> RoomPlanPreviewModel.PlanMarker? {
        guard let plan = model.planPreview else { return nil }
        return planMarkers(plan).first {
            $0.identifier == "entity:\(id.description)"
        }
    }

    private func marker(
        forFieldNoteID id: CaptureFieldNoteID
    ) -> RoomPlanPreviewModel.PlanMarker? {
        guard let plan = model.planPreview else { return nil }
        return planMarkers(plan).first {
            $0.identifier == "field_note:\(id)"
        }
    }

    private func marker(
        forOpening opening: RoomOpeningCandidate
    ) -> RoomPlanPreviewModel.PlanMarker? {
        guard let plan = model.planPreview else { return nil }
        return planMarkers(plan).first {
            $0.identifier == opening.sourceRef
        }
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

    // MARK: #408/#409 derived surfaces

    /// The accepted-geometry 3D scene (issue #408): every element is
    /// committed evidence or a committed authority — mesh snapshots,
    /// RoomPlan bindables, derived candidates, entities, measurements
    /// all come straight off `model`/`roomPlanObjects`.
    private var sceneModel: AcceptedGeometrySceneModel {
        AcceptedGeometrySceneModel(
            coordinateSpaceID: nil,
            meshSnapshots: model.meshSnapshots,
            roomPlanObjects: roomPlanObjects,
            derivedCandidates:
                model.derivedGeometryCandidates,
            entities: model.annotations,
            measurements: model.measurements
        )
    }

    /// The spatial survey over the same committed set (issue #409):
    /// RoomPlan/mesh/entity targets with their attributed records.
    private func surveyModel(
        mode: SurveyMode
    ) -> SpatialSurveyModel {
        SpatialSurveyModel(
            roomPlanObjects: roomPlanObjects,
            meshAnchorIDs: model.meshSnapshots
                .map(\.anchorID),
            annotations: model.annotations,
            authorities: model.theaterAuthorities,
            fieldEvidence: model.fieldEvidence,
            instruments: model.instruments,
            settingsObservations: model.settingsObservations,
            wiringRoutes: model.wiringRoutes,
            measurements: model.measurements,
            fieldNotes: model.fieldNotes,
            revisitFlags: model.revisitFlags,
            taskPlan: model.captureTaskPlan,
            taskPlanStatus: model.taskPlanStatus,
            mode: mode
        )
    }

    /// Row caption: honest remaining-work count for the survey link
    /// — badges only count what still needs a decision (#406 §5).
    private var surveyBadgeText: String {
        let summary = surveyModel(mode: .all).summary
        if summary.remainingCount == 0 {
            return String(localized: "All targets reviewed")
        }
        return captureCountPhrase(
            summary.remainingCount,
            singular: String(
                localized: "%lld target still needs review"
            ),
            plural: String(
                localized: "%lld targets still need review"
            )
        )
    }

}

/// The geometry surface toggle (issue #408): Plan is the default;
/// the accepted-geometry 3D scene is the second tab.
private enum ReviewGeometryMode: String {
    case plan
    case threeD
}



#if os(iOS)
/// Loads a preview HEIC lazily for the evidence gallery. Previews are
/// derived convenience artifacts; a missing/unreadable preview degrades
/// to a stable placeholder — never a hidden failure and never a row
/// jump (issue #367).
struct AsyncPreviewImage: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
            if let url,
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .clipped()
    }
}
#endif

// MARK: #232 bounded field-datum authoring

/// The bounded field-datum authoring sheet (issue #232 refinement):
/// every operand maps to workspace evidence — an authored entity, a
/// committed measurement, the confirmed room frame, or an
/// operator-stated value — never a free arbitrary vector. The host
/// resolves operands into the persisted record.
struct RoomFieldDatumAuthoringSheet: View {
    let annotations: [CaptureAnnotationEntity]
    let measurements: [CaptureMeasurement]
    let roomReferenceFrame: RoomReferenceFrameDocument?
    let onCommit: (RoomFieldDatumAuthoringRequest) async -> Bool

    @Environment(\.dismiss) private var dismiss

    private enum OriginMode: String, CaseIterable {
        case roomFrame, entity, stated
    }
    private enum AxisMode: String, CaseIterable {
        case roomFrame, facing, twoPoints, measurement, stated
    }
    private enum VerticalMode: String, CaseIterable {
        case roomFrame, entity, stated
    }

    @State private var originMode: OriginMode
    @State private var originKind: RoomFieldDatumOriginKind =
        .surveyedPoint
    @State private var originEntityID = ""
    @State private var originX = "0"
    @State private var originY = "0"
    @State private var originZ = "0"

    @State private var axisMode: AxisMode
    @State private var axisKind: RoomFieldDatumAxisKind =
        .wallDirection
    @State private var facingEntityID = ""
    @State private var pointAID = ""
    @State private var pointBID = ""
    @State private var axisMeasurementID = ""
    @State private var axisDirX = "1"
    @State private var axisDirZ = "0"

    @State private var verticalKind: RoomFieldDatumVerticalKind =
        .finishedFloor
    @State private var verticalMode: VerticalMode
    @State private var verticalEntityID = ""
    @State private var zeroText = "0"

    @State private var saveError: String?
    @State private var saving = false

    /// Entities that can back a facing operand — facing requires a
    /// recorded orientation.
    private var facedEntities: [CaptureAnnotationEntity] {
        annotations.filter { $0.orientation != nil }
    }

    /// Measurements resolvable into an axis — at least two `entity:`
    /// endpoint refs.
    private var axisMeasurements: [CaptureMeasurement] {
        measurements.filter {
            $0.endpointRefs.filter {
                $0.hasPrefix("entity:")
            }.count >= 2
        }
    }

    private func entityRow(_ e: CaptureAnnotationEntity) -> some View {
        Text(
            e.label.isEmpty
                ? TheaterAuthorityPresentation.entityTypeName(e.type)
                : e.label
        ).tag(e.entityID.description)
    }

    init(
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        roomReferenceFrame: RoomReferenceFrameDocument?,
        onCommit: @escaping (RoomFieldDatumAuthoringRequest)
            async -> Bool
    ) {
        self.annotations = annotations
        self.measurements = measurements
        self.roomReferenceFrame = roomReferenceFrame
        self.onCommit = onCommit
        _originMode = State(
            initialValue: roomReferenceFrame != nil
                ? .roomFrame
                : .entity
        )
        _axisMode = State(
            initialValue: roomReferenceFrame != nil
                ? .roomFrame
                : .facing
        )
        _verticalMode = State(
            initialValue: roomReferenceFrame != nil
                ? .roomFrame
                : .stated
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Origin")) {
                    Picker(
                        String(localized: "Source"),
                        selection: $originMode
                    ) {
                        if roomReferenceFrame != nil {
                            Text(String(localized: "Room frame"))
                                .tag(OriginMode.roomFrame)
                        }
                        Text(String(localized: "Annotated point"))
                            .tag(OriginMode.entity)
                        Text(String(localized: "Stated point"))
                            .tag(OriginMode.stated)
                    }
                    if originMode == .entity {
                        Picker(
                            String(localized: "Point"),
                            selection: $originEntityID
                        ) {
                            ForEach(
                                annotations, id: \.entityID
                            ) { entityRow($0) }
                        }
                        originKindPicker
                    } else if originMode == .stated {
                        originKindPicker
                        HStack {
                            TextField(String(localized: "X (m)"), text: $originX)
                                .decimalKeyboard()
                            TextField(String(localized: "Y (m)"), text: $originY)
                                .decimalKeyboard()
                            TextField(String(localized: "Z (m)"), text: $originZ)
                                .decimalKeyboard()
                        }
                    }
                }

                Section(String(localized: "Front axis")) {
                    Picker(
                        String(localized: "Source"),
                        selection: $axisMode
                    ) {
                        if roomReferenceFrame != nil {
                            Text(String(localized: "Room frame front"))
                                .tag(AxisMode.roomFrame)
                        }
                        Text(String(localized: "Item facing"))
                            .tag(AxisMode.facing)
                        Text(String(localized: "Two points"))
                            .tag(AxisMode.twoPoints)
                        Text(String(localized: "Measurement"))
                            .tag(AxisMode.measurement)
                        Text(String(localized: "Stated direction"))
                            .tag(AxisMode.stated)
                    }
                    switch axisMode {
                    case .facing:
                        Picker(
                            String(localized: "Item"),
                            selection: $facingEntityID
                        ) {
                            ForEach(
                                facedEntities, id: \.entityID
                            ) { entityRow($0) }
                        }
                        axisKindPicker
                    case .twoPoints:
                        Picker(
                            String(localized: "From point"),
                            selection: $pointAID
                        ) {
                            ForEach(
                                annotations, id: \.entityID
                            ) { entityRow($0) }
                        }
                        Picker(
                            String(localized: "Toward point"),
                            selection: $pointBID
                        ) {
                            ForEach(
                                annotations, id: \.entityID
                            ) { entityRow($0) }
                        }
                    case .measurement:
                        Picker(
                            String(localized: "Measurement"),
                            selection: $axisMeasurementID
                        ) {
                            ForEach(
                                axisMeasurements,
                                id: \.measurementID
                            ) {
                                Text($0.quantityType)
                                    .tag($0.measurementID.description)
                            }
                        }
                    case .stated:
                        axisKindPicker
                        HStack {
                            TextField(String(localized: "X"), text: $axisDirX)
                                .decimalKeyboard()
                            TextField(String(localized: "Z"), text: $axisDirZ)
                                .decimalKeyboard()
                        }
                    case .roomFrame:
                        EmptyView()
                    }
                }

                Section(String(localized: "Vertical datum")) {
                    Picker(
                        String(localized: "Kind"),
                        selection: $verticalKind
                    ) {
                        Text(String(localized: "Finished floor"))
                            .tag(RoomFieldDatumVerticalKind.finishedFloor)
                        Text(String(localized: "Platform top"))
                            .tag(RoomFieldDatumVerticalKind.platformTop)
                    }
                    Picker(
                        String(localized: "Zero level from"),
                        selection: $verticalMode
                    ) {
                        if roomReferenceFrame != nil {
                            Text(String(localized: "Room frame"))
                                .tag(VerticalMode.roomFrame)
                        }
                        Text(String(localized: "Annotated point"))
                            .tag(VerticalMode.entity)
                        Text(String(localized: "Stated elevation"))
                            .tag(VerticalMode.stated)
                    }
                    if verticalMode == .entity {
                        Picker(
                            String(localized: "Point"),
                            selection: $verticalEntityID
                        ) {
                            ForEach(
                                annotations, id: \.entityID
                            ) { entityRow($0) }
                        }
                    } else if verticalMode == .stated {
                        TextField(
                            String(localized: "Elevation (m)"),
                            text: $zeroText
                        )
                        .decimalKeyboard()
                    }
                }

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(String(localized: "Field datum"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Confirm")) {
                        commit()
                    }
                    .disabled(saving)
                }
            }
        }
    }

    @ViewBuilder
    private var originKindPicker: some View {
        Picker(
            String(localized: "Kind"),
            selection: $originKind
        ) {
            ForEach(
                RoomFieldDatumOriginKind.allCases.filter {
                    $0 != .roomFrameOrigin
                },
                id: \.self
            ) {
                Text(
                    TheaterAuthorityPresentation
                        .datumOriginKindName($0)
                ).tag($0)
            }
        }
    }

    @ViewBuilder
    private var axisKindPicker: some View {
        Picker(
            String(localized: "Kind"),
            selection: $axisKind
        ) {
            ForEach(
                [
                    RoomFieldDatumAxisKind.wallDirection,
                    .screenDirection,
                ],
                id: \.self
            ) {
                Text(
                    TheaterAuthorityPresentation
                        .datumAxisKindName($0)
                ).tag($0)
            }
        }
    }

    private func entity(_ id: String) -> AnnotationEntityID? {
        AnnotationEntityID(canonicalString: id)
    }

    private func commit() {
        let request: RoomFieldDatumAuthoringRequest
        do {
            request = try buildRequest()
        } catch {
            saveError = String(
                localized: "Check the datum inputs and try again."
            )
            return
        }
        saving = true
        Task {
            let ok = await onCommit(request)
            saving = false
            if ok {
                dismiss()
            } else {
                saveError = String(
                    localized: "The field datum could not be saved."
                )
            }
        }
    }

    private func meters(
        _ x: String, _ y: String, _ z: String
    ) throws -> WorldPoint3D {
        guard let xv = Double(x), let yv = Double(y),
              let zv = Double(z)
        else {
            throw RoomFieldDatumAuthoringError.missingStatedValue
        }
        return WorldPoint3D(x: xv, y: yv, z: zv)
    }

    private func buildRequest(
    ) throws -> RoomFieldDatumAuthoringRequest {
        let origin: RoomFieldDatumOriginOperand
        var statedOrigin: WorldPoint3D?
        switch originMode {
        case .roomFrame:
            origin = .roomFrame
        case .entity:
            guard let id = entity(originEntityID) else {
                throw RoomFieldDatumAuthoringError.entityNotFound
            }
            origin = .entity(id, originKind)
        case .stated:
            statedOrigin = try meters(originX, originY, originZ)
            origin = .statedPoint(originKind)
        }

        let axis: RoomFieldDatumAxisOperand
        var statedDirection: WorldPoint3D?
        switch axisMode {
        case .roomFrame:
            axis = .roomFrameFront
        case .facing:
            guard let id = entity(facingEntityID) else {
                throw RoomFieldDatumAuthoringError.entityNotFound
            }
            axis = .entityFacing(id, axisKind)
        case .twoPoints:
            guard let a = entity(pointAID),
                  let b = entity(pointBID)
            else {
                throw RoomFieldDatumAuthoringError.entityNotFound
            }
            axis = .twoSurveyedEntities(a, b)
        case .measurement:
            guard let id = MeasurementID(
                canonicalString: axisMeasurementID
            ) else {
                throw RoomFieldDatumAuthoringError
                    .measurementNotFound
            }
            axis = .measuredDirection(id)
        case .stated:
            statedDirection = try meters(axisDirX, "0", axisDirZ)
            axis = .statedDirection(axisKind)
        }

        let vertical: RoomFieldDatumVerticalOperand
        switch verticalMode {
        case .roomFrame:
            vertical = .fromRoomFrame(verticalKind)
        case .entity:
            guard let id = entity(verticalEntityID) else {
                throw RoomFieldDatumAuthoringError.entityNotFound
            }
            vertical = .fromEntity(verticalKind, id)
        case .stated:
            guard let zero = Double(zeroText) else {
                throw RoomFieldDatumAuthoringError
                    .missingStatedValue
            }
            vertical = .stated(verticalKind, zero)
        }

        return RoomFieldDatumAuthoringRequest(
            origin: origin,
            statedOriginMeters: statedOrigin,
            axis: axis,
            statedDirectionMeters: statedDirection,
            vertical: vertical
        )
    }
}
