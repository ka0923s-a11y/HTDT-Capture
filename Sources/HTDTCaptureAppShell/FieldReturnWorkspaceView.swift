import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore
#if canImport(UIKit)
import UIKit
#endif

/// The non-spatial field-return workspace (issues #400, #417,
/// #418): the operator-facing surface for completing a mission's
/// inventory/photo/settings/wiring tasks without a RoomPlan capture
/// revision. Each task row leads with the authoring action its
/// `task_kind` maps to — inventory units, wiring routes, settings
/// observations, room states and evidence land as typed authority
/// records in the workspace and fulfill the task by reference.
///
/// Finalization freezes the workspace into the immutable
/// `.htdtfieldreturn` container: once `isFinalized` every mutation
/// control is hidden and the ledger renders read-only — corrections
/// flow through a new contribution, never an in-place edit.
struct HTDTFieldReturnWorkspaceView: View {
    let record: HTDTMissionRecord
    let actions: CaptureRootActions

    /// Identifiable share payload for the finalized `.htdtfieldreturn`
    /// — `URL` is not `Identifiable` on this SDK, so the sheet binds a
    /// small wrapper.
    private struct ShareTarget: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// Bounded operator-facing error with the technical detail kept
    /// under a disclosure (issue #417) — the headline never carries
    /// a raw `error` description.
    private struct StatusNotice {
        let message: String
        let detail: String
    }

    /// Which typed authoring sheet a task row is presenting.
    private enum AuthoringSheet: Identifiable {
        case evidenceNote(itemRef: String)
        case inventoryItem(itemRef: String)
        case settings(itemRef: String)
        case wiring(itemRef: String)
        case roomState(itemRef: String)
        case outcomeReason(
            itemRef: String,
            outcome: HTDTFieldReturnTaskLedgerEntry.Outcome
        )
        #if canImport(UIKit)
        case camera(itemRef: String)
        #endif

        var id: String {
            switch self {
            case .evidenceNote(let r): "evidence:\(r)"
            case .inventoryItem(let r): "inventory:\(r)"
            case .settings(let r): "settings:\(r)"
            case .wiring(let r): "wiring:\(r)"
            case .roomState(let r): "room:\(r)"
            case .outcomeReason(let r, let o):
                "reason:\(r):\(o.rawValue)"
            #if canImport(UIKit)
            case .camera(let r): "camera:\(r)"
            #endif
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var workspace: HTDTFieldReturnWorkspace?
    @State private var loadError: String?
    @State private var notice: StatusNotice?
    @State private var finalizedShare: ShareTarget?
    @State private var authoringSheet: AuthoringSheet?
    @State private var importingFileForItemRef: String?
    @State private var evidenceKind: FieldEvidenceKind =
        .generalNote
    @State private var evidenceTitle = ""
    @State private var evidenceNote = ""
    @State private var reasonDraft = ""

    var body: some View {
        Group {
            if let workspace {
                workspaceBody(workspace)
            } else if let loadError {
                ContentUnavailableView(
                    "Field return unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Preparing field return…")
            }
        }
        .navigationTitle(
            String(localized: "Field return")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task {
            if workspace == nil {
                if let opened = await actions
                    .openFieldReturnWorkspace(record.recordID)
                {
                    workspace = opened
                } else {
                    loadError = String(
                        localized:
                            "The field-return workspace could not be opened."
                    )
                }
            }
        }
        .sheet(item: $authoringSheet) { sheet in
            authoringSheetView(sheet)
        }
        .fileImporter(
            isPresented: Binding(
                get: { importingFileForItemRef != nil },
                set: { if !$0 { importingFileForItemRef = nil } }
            ),
            allowedContentTypes: [.data]
        ) { result in
            if case .success(let url) = result,
               let itemRef = importingFileForItemRef
            {
                attachFile(url, itemRef: itemRef)
            }
            importingFileForItemRef = nil
        }
        #if os(iOS)
        .sheet(item: $finalizedShare) { share in
            DiagnosticsShareSheet(items: [share.url])
        }
        #endif
    }

    @ViewBuilder
    private func workspaceBody(
        _ workspace: HTDTFieldReturnWorkspace
    ) -> some View {
        List {
            Section(String(localized: "Contribution")) {
                LabeledContent(
                    String(localized: "Mission"),
                    value: record.missionID
                )
                LabeledContent(
                    String(localized: "Plan"),
                    value: record.planID + " v"
                        + record.planVersion
                )
                LabeledContent(
                    String(localized: "Created"),
                    value: workspace.createdAtUTC
                )
                if workspace.isFinalized {
                    Label(
                        String(localized: "Finalized"),
                        systemImage: "lock.fill"
                    )
                    .foregroundStyle(.secondary)
                }
                DisclosureGroup(
                    String(localized: "Details")
                ) {
                    LabeledContent(
                        String(localized: "Contribution ID"),
                        value: workspace.contributionID
                            .description
                    )
                    .font(.caption.monospaced())
                    if let superseded =
                        workspace.supersedesContributionID
                    {
                        LabeledContent(
                            String(localized: "Supersedes"),
                            value: superseded.description
                        )
                        .font(.caption.monospaced())
                    }
                }
                .font(.caption)
            }

            readinessSection(workspace)

            if workspace.taskLedger.isEmpty {
                Section {
                    Text(
                        String(
                            localized:
                                "This mission has no field-return tasks — every task needs spatial capture or is already covered."
                        )
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                Section(
                    String(localized: "Task fulfillment")
                ) {
                    ForEach(
                        workspace.taskLedger,
                        id: \.itemRef
                    ) { entry in
                        ledgerRow(
                            entry,
                            finalized: workspace.isFinalized
                        )
                    }
                }
            }

            Section(String(localized: "Field authority")) {
                authoritySummary(
                    workspace,
                    finalized: workspace.isFinalized
                )
            }

            Section {
                if workspace.isFinalized {
                    Text(
                        String(
                            localized:
                                "Finalized — corrections go into a new field return."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await finalize() }
                    } label: {
                        Label(
                            String(
                                localized:
                                    "Finalize field return"
                            ),
                            systemImage: "checkmark.seal"
                        )
                    }
                    .disabled(
                        !hasCompletions(workspace)
                    )
                    if !hasCompletions(workspace) {
                        Text(
                            String(
                                localized:
                                    "Record at least one task outcome before finalizing."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if let notice {
                Section {
                    Text(notice.message)
                        .font(.caption)
                    DisclosureGroup(
                        String(localized: "Details")
                    ) {
                        Text(notice.detail)
                            .font(.caption2.monospaced())
                    }
                }
            }
        }
    }

    private func hasCompletions(
        _ workspace: HTDTFieldReturnWorkspace
    ) -> Bool {
        workspace.taskLedger.contains {
            $0.outcome != .unfulfilled
                && $0.outcome != .notApplicable
        } || workspace.authority.hasContent
            || !workspace.inventoryItems.isEmpty
            || !workspace.roomStateObservations.isEmpty
    }

    // MARK: - Readiness

    /// Finalization readiness (issue #418): how many required tasks
    /// are fulfilled, which are still open, and whether any ledger
    /// ref is broken. Artifact validity ≠ mission completeness —
    /// this panel reports both without blocking.
    @ViewBuilder
    private func readinessSection(
        _ workspace: HTDTFieldReturnWorkspace
    ) -> some View {
        let required = workspace.taskLedger.filter {
            $0.requirement == .required
        }
        let requiredDone = required.filter {
            $0.outcome == .fulfilled
        }.count
        let requiredDeclined = required.filter {
            $0.outcome == .declined
                || $0.outcome == .notApplicable
        }.count
        let requiredOpen = required.count
            - requiredDone - requiredDeclined
        let optionalOpen = workspace.taskLedger.filter {
            $0.requirement == .optional
                && $0.outcome == .unfulfilled
        }.count
        let brokenRefs = brokenLedgerRefs(workspace)

        if !workspace.taskLedger.isEmpty {
            Section(
                String(localized: "Finalization readiness")
            ) {
                LabeledContent(
                    String(localized: "Required fulfilled"),
                    value: "\(requiredDone)/\(required.count)"
                )
                if requiredDeclined > 0 {
                    LabeledContent(
                        String(localized: "Required declined"),
                        value: String(requiredDeclined)
                    )
                }
                if requiredOpen > 0 {
                    Label(
                        String(
                            format: String(
                                localized:
                                    "%lld required task(s) still open"
                            ),
                            requiredOpen
                        ),
                        systemImage:
                            "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if optionalOpen > 0 {
                    LabeledContent(
                        String(
                            localized: "Optional open"
                        ),
                        value: String(optionalOpen)
                    )
                }
                if !brokenRefs.isEmpty {
                    Label(
                        String(
                            format: String(
                                localized:
                                    "%lld fulfillment ref(s) point at records not in this field return"
                            ),
                            brokenRefs.count
                        ),
                        systemImage: "link.badge.plus"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    /// Ledger fulfillment refs that do not resolve against the
    /// staged authority collections — surfaced pre-finalization so
    /// the validator's rejection is never a surprise (issue #418).
    private func brokenLedgerRefs(
        _ workspace: HTDTFieldReturnWorkspace
    ) -> [String] {
        let known = Set(fulfillmentCandidates(workspace)
            .map(\.ref))
        return workspace.taskLedger.flatMap(\.fulfilledByRefs)
            .filter { !known.contains($0) }
    }

    // MARK: - Task ledger

    @ViewBuilder
    private func ledgerRow(
        _ entry: HTDTFieldReturnTaskLedgerEntry,
        finalized: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.title)
                    .font(.callout)
                Spacer()
                requirementBadge(entry.requirement)
            }
            if let taskKind = entry.taskKind {
                Text(
                    FieldReturnPresentation.taskKindName(
                        taskKind
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if finalized {
                Label(
                    entry.outcome.displayName,
                    systemImage: "lock.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(
                            HTDTFieldReturnTaskLedgerEntry
                                .Outcome.allCases,
                            id: \.self
                        ) { outcome in
                            Button(outcome.displayName) {
                                pickOutcome(
                                    itemRef: entry.itemRef,
                                    outcome: outcome,
                                    hasNote: entry.note?
                                        .isEmpty == false
                                )
                            }
                        }
                    } label: {
                        Label(
                            entry.outcome.displayName,
                            systemImage:
                                "chevron.up.chevron.down"
                        )
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    authoringButton(
                        for: entry
                    )
                }
            }
            ForEach(
                entry.fulfilledByRefs,
                id: \.self
            ) { ref in
                fulfillmentRefRow(
                    ref,
                    workspace: workspace
                )
            }
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier(
            "fieldreturn.ledger.\(entry.itemRef)"
        )
    }

    /// The lead authoring control for a task row (issue #418): the
    /// action is shaped by the task's kind — an inventory task adds
    /// an inventory unit, a routing task records a wiring route, and
    /// so on — and committing it attaches the typed ref.
    @ViewBuilder
    private func authoringButton(
        for entry: HTDTFieldReturnTaskLedgerEntry
    ) -> some View {
        switch entry.taskKind ?? .otherSemantic {
        case .inventoryItem:
            taskActionButton(
                String(localized: "Add inventory item"),
                systemImage: "shippingbox",
                itemRef: entry.itemRef
            ) {
                authoringSheet =
                    .inventoryItem(itemRef: entry.itemRef)
            }
        case .routingVerification:
            taskActionButton(
                String(localized: "Record wiring route"),
                systemImage: "cable.connector",
                itemRef: entry.itemRef
            ) {
                authoringSheet =
                    .wiring(itemRef: entry.itemRef)
            }
        case .projectorCommissioning:
            taskActionButton(
                String(
                    localized: "Record settings observation"
                ),
                systemImage: "slider.horizontal.3",
                itemRef: entry.itemRef
            ) {
                authoringSheet =
                    .settings(itemRef: entry.itemRef)
            }
        case .roomStateObservation:
            taskActionButton(
                String(localized: "Record room state"),
                systemImage: "house",
                itemRef: entry.itemRef
            ) {
                authoringSheet =
                    .roomState(itemRef: entry.itemRef)
            }
        case .evidenceTask, .measurement:
            Menu {
                Button {
                    beginEvidenceNote(
                        itemRef: entry.itemRef
                    )
                } label: {
                    Label(
                        String(
                            localized: "Evidence note"
                        ),
                        systemImage: "square.and.pencil"
                    )
                }
                #if canImport(UIKit)
                Button {
                    authoringSheet =
                        .camera(itemRef: entry.itemRef)
                } label: {
                    Label(
                        String(localized: "Take photo"),
                        systemImage: "camera"
                    )
                }
                #endif
                Button {
                    importingFileForItemRef = entry.itemRef
                } label: {
                    Label(
                        String(
                            localized: "Attach file"
                        ),
                        systemImage: "paperclip"
                    )
                }
            } label: {
                Label(
                    String(localized: "Add evidence"),
                    systemImage: "photo.badge.plus"
                )
                .font(.caption)
            }
            .buttonStyle(.bordered)
        case .entityChecklist, .surfaceReview,
             .otherSemantic:
            taskActionButton(
                String(localized: "Link record"),
                systemImage: "link",
                itemRef: entry.itemRef
            ) {
                authoringSheet =
                    .evidenceNote(itemRef: entry.itemRef)
            }
        }
    }

    @ViewBuilder
    private func taskActionButton(
        _ title: String,
        systemImage: String,
        itemRef: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
        }
        .buttonStyle(.bordered)
    }

    /// One fulfillment ref rendered as its human label with the
    /// exact ref under it (issue #417) — unresolved refs keep the
    /// raw token visible since nothing else identifies them.
    @ViewBuilder
    private func fulfillmentRefRow(
        _ ref: String,
        workspace: HTDTFieldReturnWorkspace?
    ) -> some View {
        let candidates = workspace.map {
            fulfillmentCandidates($0)
        } ?? []
        let resolved = FieldNoteBindingResolver.resolve(
            ref: ref,
            in: candidates
        )
        VStack(alignment: .leading, spacing: 1) {
            Text(resolved.title)
                .font(.caption2)
            Text(ref)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resolved.title)
    }

    @ViewBuilder
    private func requirementBadge(
        _ requirement: TaskPlanRequirement
    ) -> some View {
        Text(
            requirement == .required
                ? String(localized: "Required")
                : String(localized: "Optional")
        )
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            (requirement == .required
                ? Color.orange : Color.secondary)
                .opacity(0.15),
            in: Capsule()
        )
        .foregroundStyle(
            requirement == .required
                ? Color.orange : Color.secondary
        )
    }

    /// Operator picked an outcome directly — `declined` and
    /// `notApplicable` carry a required reason (issue #418), so the
    /// reason sheet interposes before the record is written.
    private func pickOutcome(
        itemRef: String,
        outcome: HTDTFieldReturnTaskLedgerEntry.Outcome,
        hasNote: Bool
    ) {
        switch outcome {
        case .declined, .notApplicable
        where !hasNote:
            reasonDraft = ""
            authoringSheet = .outcomeReason(
                itemRef: itemRef,
                outcome: outcome
            )
        default:
            updateLedger(itemRef: itemRef, outcome: outcome)
        }
    }

    private func updateLedger(
        itemRef: String,
        outcome: HTDTFieldReturnTaskLedgerEntry.Outcome,
        note: String? = nil
    ) {
        guard var draft = workspace,
              let entry = draft.taskLedger.first(where: {
                  $0.itemRef == itemRef
              })
        else {
            return
        }
        do {
            try draft.recordTaskOutcome(
                itemRef: itemRef,
                outcome: outcome,
                fulfilledByRefs: entry.fulfilledByRefs,
                note: note ?? entry.note
            )
            workspace = draft
            persist(draft)
        } catch {
            notice = StatusNotice(
                message: String(
                    localized:
                        "The task outcome could not be recorded."
                ),
                detail: String(describing: error)
            )
        }
    }

    /// Commit a typed record and fulfill the task with its ref —
    /// the shared path every authoring sheet funnels into.
    private func commitRecord(
        itemRef: String,
        ref: String,
        mutate: (inout HTDTFieldReturnWorkspace) throws
            -> Void
    ) {
        guard var draft = workspace else { return }
        do {
            try mutate(&draft)
            try draft.recordTaskOutcome(
                itemRef: itemRef,
                outcome: .fulfilled,
                fulfilledByRefs: [ref]
            )
            workspace = draft
            persist(draft)
            authoringSheet = nil
        } catch {
            notice = StatusNotice(
                message: String(
                    localized:
                        "The record could not be saved."
                ),
                detail: String(describing: error)
            )
        }
    }

    /// Typed refs the staged workspace offers as fulfillment basis —
    /// labels come from the shared authority-ref resolver so no raw
    /// namespace token reaches the surface (issues #417/#418).
    private func fulfillmentCandidates(
        _ workspace: HTDTFieldReturnWorkspace
    ) -> [FieldNoteBindingCandidate] {
        FieldNoteBindingResolver
            .fieldReturnCandidates(
                inventoryItems: workspace.inventoryItems,
                fieldEvidence:
                    workspace.authority.fieldEvidence,
                instruments:
                    workspace.authority.instruments,
                operatorProfiles:
                    workspace.authority.operatorProfiles,
                settingsObservations:
                    workspace.authority.settingsObservations,
                wiringRoutes:
                    workspace.authority.wiringRoutes,
                roomStateObservations:
                    workspace.roomStateObservations
            )
    }

    private func persist(
        _ draft: HTDTFieldReturnWorkspace
    ) {
        Task {
            await actions.persistFieldReturnDraft(draft)
        }
    }

    // MARK: - Authority section

    @ViewBuilder
    private func authoritySummary(
        _ workspace: HTDTFieldReturnWorkspace,
        finalized: Bool
    ) -> some View {
        let authority = workspace.authority
        if authority.hasContent
            || !workspace.inventoryItems.isEmpty
            || !workspace.roomStateObservations.isEmpty
        {
            if !workspace.inventoryItems.isEmpty {
                LabeledContent(
                    String(localized: "Inventory items"),
                    value: String(
                        workspace.inventoryItems.count
                    )
                )
                ForEach(
                    workspace.inventoryItems,
                    id: \.itemID
                ) { item in
                    VStack(alignment: .leading, spacing: 2)
                    {
                        Text(item.userLabel)
                            .font(.caption)
                        Text(
                            FieldReturnPresentation
                                .equipmentClassName(
                                    item.equipmentClass
                                )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if !workspace.roomStateObservations.isEmpty {
                LabeledContent(
                    String(
                        localized: "Room-state observations"
                    ),
                    value: String(
                        workspace.roomStateObservations
                            .count
                    )
                )
            }
            LabeledContent(
                String(localized: "Evidence records"),
                value: String(authority.fieldEvidence.count)
            )
            LabeledContent(
                String(localized: "Attached files"),
                value: String(
                    authority.fieldEvidenceAssets.filter {
                        !$0.removal
                    }.count
                )
            )
            if !authority.instruments.isEmpty {
                LabeledContent(
                    String(localized: "Instruments"),
                    value: String(authority.instruments.count)
                )
            }
            if !authority.settingsObservations.isEmpty {
                LabeledContent(
                    String(localized: "Settings observations"),
                    value: String(
                        authority.settingsObservations.count
                    )
                )
            }
            if !authority.wiringRoutes.isEmpty {
                LabeledContent(
                    String(localized: "Wiring routes"),
                    value: String(
                        authority.wiringRoutes.count
                    )
                )
            }
            ForEach(authority.fieldEvidence, id: \.evidenceID) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).font(.caption)
                    Text(
                        FieldAuthorityPresentation
                            .evidenceKindName(record.kind)
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                if !finalized {
                    removeEvidence(at: offsets)
                }
            }
        } else {
            Text(
                String(
                    localized:
                        "No field-authority records yet — use a task action above to add one."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func removeEvidence(
        at offsets: IndexSet
    ) {
        guard var draft = workspace else { return }
        draft.authority.fieldEvidence.remove(
            atOffsets: offsets
        )
        workspace = draft
        persist(draft)
    }

    private func beginEvidenceNote(itemRef: String) {
        evidenceTitle = ""
        evidenceNote = ""
        evidenceKind = .generalNote
        authoringSheet = .evidenceNote(itemRef: itemRef)
    }

    // MARK: - Authoring sheets

    @ViewBuilder
    private func authoringSheetView(
        _ sheet: AuthoringSheet
    ) -> some View {
        switch sheet {
        case .evidenceNote(let itemRef):
            evidenceComposer(itemRef: itemRef)
        case .inventoryItem(let itemRef):
            inventoryItemComposer(itemRef: itemRef)
        case .settings(let itemRef):
            if let workspace {
                NavigationStack {
                    SettingsObservationFormView(
                        captureRevisionID:
                            workspace.recordCarrierID,
                        inventoryItems:
                            workspace.inventoryItems,
                        onCommit: { observation in
                            commitRecord(
                                itemRef: itemRef,
                                ref: "settings_observation:"
                                    + observation
                                        .observationID
                                        .description
                            ) { draft in
                                draft.authority
                                    .settingsObservations
                                    .append(observation)
                            }
                        }
                    )
                }
            }
        case .wiring(let itemRef):
            if let workspace {
                NavigationStack {
                    WiringRouteFormView(
                        captureRevisionID:
                            workspace.recordCarrierID,
                        inventoryItems:
                            workspace.inventoryItems,
                        onCommit: { route in
                            commitRecord(
                                itemRef: itemRef,
                                ref: "wiring_route:"
                                    + route.routeID
                                        .description
                            ) { draft in
                                draft.authority.wiringRoutes
                                    .append(route)
                            }
                        }
                    )
                }
            }
        case .roomState(let itemRef):
            roomStateComposer(itemRef: itemRef)
        case .outcomeReason(let itemRef, let outcome):
            reasonSheet(itemRef: itemRef, outcome: outcome)
        #if canImport(UIKit)
        case .camera(let itemRef):
            FieldReturnCameraSheet(
                onPhoto: { data in
                    attachCameraPhoto(
                        data,
                        itemRef: itemRef
                    )
                }
            )
            .ignoresSafeArea()
        #endif
        }
    }

    // MARK: - Evidence note composer

    @ViewBuilder
    private func evidenceComposer(
        itemRef: String
    ) -> some View {
        NavigationStack {
            Form {
                Picker(
                    String(localized: "Kind"),
                    selection: $evidenceKind
                ) {
                    ForEach(
                        FieldEvidenceKind.allCases,
                        id: \.self
                    ) { kind in
                        Text(
                            FieldAuthorityPresentation
                                .evidenceKindName(kind)
                        ).tag(kind)
                    }
                }
                TextField(
                    String(localized: "Title"),
                    text: $evidenceTitle
                )
                TextField(
                    String(localized: "Note (optional)"),
                    text: $evidenceNote
                )
            }
            .navigationTitle(
                String(localized: "Evidence note")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        authoringSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveEvidenceNote(itemRef: itemRef)
                    }
                    .disabled(
                        evidenceTitle.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveEvidenceNote(itemRef: String) {
        do {
            guard let carrier = workspace?.recordCarrierID
            else { return }
            let record = try FieldEvidenceRecord(
                kind: evidenceKind,
                title: evidenceTitle,
                note: evidenceNote.isEmpty ? nil : evidenceNote,
                targetRefs: [itemRef],
                asset: nil,
                captureRevisionID: carrier
            )
            commitRecord(
                itemRef: itemRef,
                ref: "field_evidence:"
                    + record.evidenceID.description
            ) { draft in
                draft.authority.fieldEvidence.append(record)
            }
        } catch {
            notice = StatusNotice(
                message: String(
                    localized:
                        "Evidence note could not be saved."
                ),
                detail: String(describing: error)
            )
        }
    }

    // MARK: - File attach / camera

    private func attachFile(
        _ source: URL,
        itemRef: String
    ) {
        let needsScope = source
            .startAccessingSecurityScopedResource()
        defer {
            if needsScope {
                source.stopAccessingSecurityScopedResource()
            }
        }
        let filename = source.lastPathComponent
        do {
            let data = try Data(contentsOf: source)
            stageAsset(
                data: data,
                filename: filename,
                title: filename,
                kind: .externalDocument,
                itemRef: itemRef
            )
        } catch {
            notice = StatusNotice(
                message: String(
                    format: String(
                        localized:
                            "Could not attach \"%@\". The file could not be read."
                    ),
                    filename
                ),
                detail: String(describing: error)
            )
        }
    }

    #if canImport(UIKit)
    private func attachCameraPhoto(
        _ data: Data,
        itemRef: String
    ) {
        let filename = "photo-"
            + UUID().uuidString.lowercased() + ".jpg"
        stageAsset(
            data: data,
            filename: filename,
            title: filename,
            kind: .installationPhoto,
            itemRef: itemRef
        )
    }
    #endif

    /// Stage asset bytes + record a `field_evidence` row bound to
    /// the task — shared by file import and the camera capture
    /// path so both land in the same schema (issue #418).
    private func stageAsset(
        data: Data,
        filename: String,
        title: String,
        kind: FieldEvidenceKind,
        itemRef: String
    ) {
        guard let carrier = workspace?.recordCarrierID
        else { return }
        let ext = (filename as NSString)
            .pathExtension.lowercased()
        let mediaType: FieldEvidenceMediaType =
            switch ext {
            case "heic": .heic
            case "jpg", "jpeg": .jpeg
            case "png": .png
            case "pdf": .pdf
            default: .binary
            }
        do {
            let stagedPath = "evidence/field/"
                + UUID().uuidString.lowercased() + "."
                + mediaType.fileExtension
            let asset = try FieldEvidenceAsset.importedFile(
                assetPath: stagedPath,
                sha256: EvidenceIntegrity.sha256(of: data),
                mediaType: mediaType,
                originalFilename: filename
            )
            let record = try FieldEvidenceRecord(
                kind: kind,
                title: title,
                targetRefs: [itemRef],
                asset: asset,
                captureRevisionID: carrier
            )
            let staged = StagedFieldAsset(
                path: stagedPath,
                data: data
            )
            commitRecord(
                itemRef: itemRef,
                ref: "field_evidence:"
                    + record.evidenceID.description
            ) { draft in
                draft.authority.fieldEvidenceAssets
                    .append(staged)
                draft.authority.fieldEvidence.append(record)
            }
        } catch {
            notice = StatusNotice(
                message: String(
                    localized:
                        "The selected file could not be attached."
                ),
                detail: String(describing: error)
            )
        }
    }

    // MARK: - Inventory item composer

    @State private var inventoryLabel = ""
    @State private var inventoryClass:
        InventoryEquipmentClass = .avReceiver
    @State private var inventoryModel = ""
    @State private var inventorySerial = ""

    /// Bounded inventory authoring for `inventory_item` tasks
    /// (issue #418): the operator labels the physical unit — class
    /// + label + optional model/serial — and the record lands in
    /// `inventory_items.json` as a `SystemInventoryItem`, never as
    /// a freeform evidence title.
    @ViewBuilder
    private func inventoryItemComposer(
        itemRef: String
    ) -> some View {
        NavigationStack {
            Form {
                Picker(
                    String(localized: "Equipment class"),
                    selection: $inventoryClass
                ) {
                    ForEach(
                        InventoryEquipmentClass.allCases,
                        id: \.self
                    ) { value in
                        Text(
                            FieldReturnPresentation
                                .equipmentClassName(value)
                        ).tag(value)
                    }
                }
                TextField(
                    String(localized: "Label"),
                    text: $inventoryLabel
                )
                TextField(
                    String(localized: "Model (optional)"),
                    text: $inventoryModel
                )
                TextField(
                    String(localized: "Serial (optional)"),
                    text: $inventorySerial
                )
            }
            .navigationTitle(
                String(localized: "Inventory item")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        authoringSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveInventoryItem(itemRef: itemRef)
                    }
                    .disabled(
                        inventoryLabel.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveInventoryItem(itemRef: String) {
        do {
            let item = try SystemInventoryItem(
                equipmentClass: inventoryClass,
                model: inventoryModel.isEmpty
                    ? nil : inventoryModel,
                userLabel: inventoryLabel,
                serialNumber: inventorySerial.isEmpty
                    ? nil : inventorySerial
            )
            commitRecord(
                itemRef: itemRef,
                ref: "inventory_item:"
                    + item.itemID.description
            ) { draft in
                draft.inventoryItems.append(item)
            }
        } catch {
            notice = StatusNotice(
                message: String(
                    localized:
                        "The inventory item could not be saved."
                ),
                detail: String(describing: error)
            )
        }
    }

    // MARK: - Room-state composer

    @State private var roomStateKind: RoomStateKind = .other
    @State private var roomStateValue: RoomStateValue = .other
    @State private var roomStateDetail = ""

    /// Bounded room-state authoring (issue #418): a `room_state`
    /// observation with a closed kind/value vocabulary — never a
    /// freeform evidence title standing in for the room state.
    @ViewBuilder
    private func roomStateComposer(
        itemRef: String
    ) -> some View {
        NavigationStack {
            Form {
                Picker(
                    String(localized: "Kind"),
                    selection: $roomStateKind
                ) {
                    ForEach(
                        RoomStateKind.allCases,
                        id: \.self
                    ) { value in
                        Text(
                            FieldReturnPresentation
                                .roomStateKindName(value)
                        ).tag(value)
                    }
                }
                Picker(
                    String(localized: "State"),
                    selection: $roomStateValue
                ) {
                    ForEach(
                        RoomStateValue.allCases,
                        id: \.self
                    ) { value in
                        Text(
                            FieldReturnPresentation
                                .roomStateValueName(value)
                        ).tag(value)
                    }
                }
                TextField(
                    String(localized: "Detail (optional)"),
                    text: $roomStateDetail
                )
            }
            .navigationTitle(
                String(localized: "Room state")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        authoringSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveRoomState(itemRef: itemRef)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveRoomState(itemRef: String) {
        do {
            let observation = try RoomStateObservation(
                kind: roomStateKind,
                state: roomStateValue,
                stateDetail: roomStateDetail.isEmpty
                    ? nil : roomStateDetail,
                observedAtUTC: BundleTimestamp.utcString(
                    from: Date()
                )
            )
            commitRecord(
                itemRef: itemRef,
                ref: "room_state:"
                    + observation.observationID.description
            ) { draft in
                draft.roomStateObservations.append(observation)
            }
        } catch {
            notice = StatusNotice(
                message: String(
                    localized:
                        "The room state could not be saved."
                ),
                detail: String(describing: error)
            )
        }
    }

    // MARK: - Outcome reason

    /// `declined`/`notApplicable` require a structured reason
    /// (issue #418) — collected before the outcome is written so a
    /// reason-less outcome can never reach the ledger.
    @ViewBuilder
    private func reasonSheet(
        itemRef: String,
        outcome: HTDTFieldReturnTaskLedgerEntry.Outcome
    ) -> some View {
        NavigationStack {
            Form {
                TextField(
                    String(localized: "Reason"),
                    text: $reasonDraft,
                    axis: .vertical
                )
            }
            .navigationTitle(
                String(localized: "Outcome reason")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        authoringSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        updateLedger(
                            itemRef: itemRef,
                            outcome: outcome,
                            note: reasonDraft
                        )
                        authoringSheet = nil
                    }
                    .disabled(
                        reasonDraft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Finalize

    private func finalize() async {
        guard let draft = workspace else { return }
        if let url = await actions
            .finalizeFieldReturn(draft)
        {
            var marked = draft
            marked.finalizedAtUTC =
                BundleTimestamp.utcString(
                    from: Date()
                )
            workspace = marked
            #if os(iOS)
            finalizedShare = ShareTarget(url: url)
            #else
            notice = StatusNotice(
                message: String(
                    localized: "Field return finalized."
                ),
                detail: url.path
            )
            #endif
        } else {
            notice = StatusNotice(
                message: String(
                    localized:
                        "Field return could not be finalized."
                ),
                detail: String(
                    localized:
                        "The finalized container was not produced."
                )
            )
        }
    }
}

extension HTDTFieldReturnTaskLedgerEntry.Outcome:
    CaseIterable
{
    public static var allCases: [Self] {
        [.unfulfilled, .fulfilled, .partiallyFulfilled,
         .declined, .notApplicable]
    }

    var displayName: String {
        switch self {
        case .fulfilled:
            String(localized: "Fulfilled")
        case .partiallyFulfilled:
            String(localized: "Partially fulfilled")
        case .declined:
            String(localized: "Declined")
        case .notApplicable:
            String(localized: "Not applicable")
        case .unfulfilled:
            String(localized: "Unfulfilled")
        }
    }
}

/// Localized human labels for field-return surfaces (issue #417):
/// task kinds, equipment classes, room-state vocabularies. Core
/// enums stay serialization tokens — every user-facing name maps
/// here.
enum FieldReturnPresentation {
    static func taskKindName(
        _ kind: HTDTFieldTaskKind
    ) -> String {
        switch kind {
        case .entityChecklist:
            String(localized: "Entity checklist")
        case .surfaceReview:
            String(localized: "Surface review")
        case .inventoryItem:
            String(localized: "Inventory item")
        case .evidenceTask:
            String(localized: "Evidence")
        case .measurement:
            String(localized: "Measurement")
        case .routingVerification:
            String(localized: "Routing verification")
        case .projectorCommissioning:
            String(localized: "Projector commissioning")
        case .roomStateObservation:
            String(localized: "Room-state observation")
        case .otherSemantic:
            String(localized: "Task")
        }
    }

    static func equipmentClassName(
        _ value: InventoryEquipmentClass
    ) -> String {
        switch value {
        case .avReceiver:
            String(localized: "AV receiver")
        case .avProcessor:
            String(localized: "AV processor")
        case .powerAmplifier:
            String(localized: "Power amplifier")
        case .dspUnit:
            String(localized: "DSP unit")
        case .projector:
            String(localized: "Projector")
        case .display:
            String(localized: "Display")
        case .sourceDevice:
            String(localized: "Source device")
        case .measurementInterface:
            String(localized: "Measurement interface")
        case .other:
            String(localized: "Other equipment")
        }
    }

    static func roomStateKindName(
        _ kind: RoomStateKind
    ) -> String {
        switch kind {
        case .curtain:
            String(localized: "Curtain")
        case .movablePanel:
            String(localized: "Movable panel")
        case .door:
            String(localized: "Door")
        case .window:
            String(localized: "Window")
        case .screenMasking:
            String(localized: "Screen masking")
        case .seatPosture:
            String(localized: "Seat posture")
        case .hvac:
            String(localized: "HVAC")
        case .airPurifier:
            String(localized: "Air purifier")
        case .lighting:
            String(localized: "Lighting")
        case .removableElement:
            String(localized: "Removable element")
        case .other:
            String(localized: "Other")
        }
    }

    static func roomStateValueName(
        _ value: RoomStateValue
    ) -> String {
        switch value {
        case .open:
            String(localized: "Open")
        case .closed:
            String(localized: "Closed")
        case .deployed:
            String(localized: "Deployed")
        case .stowed:
            String(localized: "Stowed")
        case .on:
            String(localized: "On")
        case .off:
            String(localized: "Off")
        case .reclined:
            String(localized: "Reclined")
        case .upright:
            String(localized: "Upright")
        case .present:
            String(localized: "Present")
        case .absent:
            String(localized: "Absent")
        case .unknown:
            String(localized: "Unknown")
        case .other:
            String(localized: "Other")
        }
    }
}

#if canImport(UIKit)
/// Camera capture for field-return evidence (issue #418): a plain
/// `UIImagePickerController` — permission is requested lazily by
/// the system on first use, and no RoomPlan/AR session is touched.
/// The photo lands as a staged `field_evidence` asset bound to the
/// task that launched it.
struct FieldReturnCameraSheet: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(
        context: Context
    ) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(
            .camera
        ) else {
            let fallback = UIViewController()
            fallback.view.backgroundColor = .systemBackground
            return fallback
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPhoto: onPhoto, dismiss: dismiss)
    }

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        let onPhoto: (Data) -> Void
        let dismiss: DismissAction

        init(
            onPhoto: @escaping (Data) -> Void,
            dismiss: DismissAction
        ) {
            self.onPhoto = onPhoto
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info:
                [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage]
                as? UIImage,
               let data = image.jpegData(
                   compressionQuality: 0.85
               )
            {
                onPhoto(data)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            dismiss()
        }
    }
}
#endif
