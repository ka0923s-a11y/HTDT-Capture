import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore
#if canImport(UIKit)
import UIKit
#endif

/// The non-spatial field-return workspace (issue #400): the
/// operator-facing surface for completing a mission's
/// inventory/photo/settings/wiring tasks without a RoomPlan capture
/// revision. The ledger mirrors the bound plan — spatial tasks are
/// pre-marked `not_applicable` with the capability reason on device;
/// every other task accepts an outcome, fulfilling authority refs,
/// and an operator note. Staged field-authority records (evidence,
/// instruments, settings observations, wiring routes) bind the
/// contribution id in their `capture_revision_id` slot.
///
/// All edits persist through `persistFieldReturnDraft`; Finalize
/// produces the immutable `.htdtfieldreturn` container.
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

    @Environment(\.dismiss) private var dismiss
    @State private var workspace: HTDTFieldReturnWorkspace?
    @State private var loadError: String?
    @State private var statusMessage: String?
    @State private var finalizedShare: ShareTarget?
    @State private var importingFile = false
    @State private var composingEvidence = false
    @State private var evidenceKind: FieldEvidenceKind =
        .generalNote
    @State private var evidenceTitle = ""
    @State private var evidenceNote = ""
    @State private var evidenceTargetRef: String?
    @State private var freeRefDraft = ""
    @State private var addingRefToItem: String?

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
        .fileImporter(
            isPresented: $importingFile,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result)
        }
        .sheet(
            isPresented: $composingEvidence
        ) {
            evidenceComposer()
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
                    String(localized: "Contribution ID"),
                    value: workspace.contributionID.description
                )
                .font(.caption.monospaced())
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
            }

            if !workspace.taskLedger.isEmpty {
                Section(
                    String(localized: "Task fulfillment")
                ) {
                    ForEach(
                        workspace.taskLedger,
                        id: \.itemRef
                    ) { entry in
                        ledgerRow(entry)
                    }
                }
            }

            Section(String(localized: "Field authority")) {
                authoritySummary(workspace)
                Button {
                    evidenceTitle = ""
                    evidenceNote = ""
                    evidenceKind = .generalNote
                    evidenceTargetRef = workspace.taskLedger
                        .first?.itemRef
                    composingEvidence = true
                } label: {
                    Label(
                        String(localized: "Add evidence note"),
                        systemImage: "square.and.pencil"
                    )
                }
                Button {
                    importingFile = true
                } label: {
                    Label(
                        String(
                            localized:
                                "Attach evidence file"
                        ),
                        systemImage: "paperclip"
                    )
                }
            }

            Section {
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
                    workspace.isFinalized
                        || !hasCompletions(workspace)
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

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    }

    // MARK: - Task ledger

    @ViewBuilder
    private func ledgerRow(
        _ entry: HTDTFieldReturnTaskLedgerEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.title)
                    .font(.callout)
                Spacer()
                requirementBadge(entry.requirement)
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(
                        HTDTFieldReturnTaskLedgerEntry.Outcome
                            .allCases,
                        id: \.self
                    ) { outcome in
                        Button(outcome.displayName) {
                            updateLedger(
                                itemRef: entry.itemRef,
                                outcome: outcome
                            )
                        }
                    }
                } label: {
                    Label(
                        entry.outcome.displayName,
                        systemImage: "chevron.up.chevron.down"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                ForEach(
                    entry.fulfilledByRefs,
                    id: \.self
                ) { ref in
                    Text(ref)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 8) {
                Menu {
                    let candidates = refCandidates()
                    ForEach(candidates, id: \.self) { ref in
                        Button(ref) {
                            addLedgerRef(
                                itemRef: entry.itemRef,
                                ref: ref
                            )
                        }
                    }
                } label: {
                    Label(
                        String(localized: "Link ref"),
                        systemImage: "link"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(refCandidates().isEmpty)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier(
            "fieldreturn.ledger.\(entry.itemRef)"
        )
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

    /// Authority refs present in the staged workspace that a ledger
    /// item may point at — never a fabricated `entity:`/`frame:` ref.
    private func refCandidates() -> [String] {
        guard let workspace else { return [] }
        var refs: [String] = []
        refs += workspace.authority.fieldEvidence.map {
            "field_evidence:" + $0.evidenceID.description
        }
        refs += workspace.authority.instruments.map {
            "instrument:" + $0.instrumentID.description
        }
        refs += workspace.authority.settingsObservations.map {
            "settings_observation:"
                + $0.observationID.description
        }
        refs += workspace.authority.wiringRoutes.map {
            "wiring_route:" + $0.routeID.description
        }
        refs += workspace.authority.operatorProfiles.map {
            "operator:" + $0.operatorID.description
        }
        return refs.sorted()
    }

    private func updateLedger(
        itemRef: String,
        outcome: HTDTFieldReturnTaskLedgerEntry.Outcome
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
                fulfilledByRefs: entry.fulfilledByRefs
            )
            workspace = draft
            persist(draft)
        } catch {
            statusMessage = String(describing: error)
        }
    }

    private func addLedgerRef(itemRef: String, ref: String) {
        guard var draft = workspace,
              let entry = draft.taskLedger.first(where: {
                  $0.itemRef == itemRef
              })
        else {
            return
        }
        var refs = entry.fulfilledByRefs
        if !refs.contains(ref) {
            refs.append(ref)
        }
        do {
            try draft.recordTaskOutcome(
                itemRef: itemRef,
                outcome: entry.outcome,
                fulfilledByRefs: refs
            )
            workspace = draft
            persist(draft)
        } catch {
            statusMessage = String(describing: error)
        }
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
        _ workspace: HTDTFieldReturnWorkspace
    ) -> some View {
        let authority = workspace.authority
        if authority.hasContent {
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
                        record.kind.rawValue
                            .replacingOccurrences(
                                of: "_", with: " "
                            )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                removeEvidence(at: offsets)
            }
        } else {
            Text(
                String(
                    localized:
                        "No field-authority records yet — add an evidence note or attach a file."
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

    @ViewBuilder
    private func evidenceComposer() -> some View {
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
                            kind.rawValue.replacingOccurrences(
                                of: "_", with: " "
                            )
                        ).tag(kind)
                    }
                }
                TextField(
                    String(localized: "Title"),
                    text: $evidenceTitle
                )
                Picker(
                    String(localized: "Bound task"),
                    selection: Binding(
                        get: {
                            evidenceTargetRef
                                ?? workspace?.taskLedger
                                .first?.itemRef
                        },
                        set: { evidenceTargetRef = $0 }
                    )
                ) {
                    ForEach(
                        workspace?.taskLedger ?? [],
                        id: \.itemRef
                    ) { entry in
                        Text(entry.title).tag(entry.itemRef)
                    }
                }
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
                        composingEvidence = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveEvidenceNote()
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

    private func saveEvidenceNote() {
        guard var draft = workspace,
              let targetRef = evidenceTargetRef
                ?? draft.taskLedger.first?.itemRef
        else {
            return
        }
        do {
            let record = try FieldEvidenceRecord(
                kind: evidenceKind,
                title: evidenceTitle,
                note: evidenceNote.isEmpty ? nil : evidenceNote,
                targetRefs: [targetRef],
                asset: nil,
                captureRevisionID: draft.bindingRevisionID
            )
            draft.authority.fieldEvidence.append(record)
            workspace = draft
            persist(draft)
            composingEvidence = false
        } catch {
            statusMessage = String(
                localized:
                    "Evidence note could not be saved: \(String(describing: error))"
            )
        }
    }

    private func handleImportedFile(
        _ result: Result<[URL], Error>
    ) {
        guard var draft = workspace else { return }
        switch result {
        case .failure(let error):
            statusMessage = String(describing: error)
        case .success(let urls):
            guard let source = urls.first else { return }
            let needsScope = source
                .startAccessingSecurityScopedResource()
            defer {
                if needsScope {
                    source.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: source)
                let ext = source.pathExtension.lowercased()
                let mediaType: FieldEvidenceMediaType =
                    switch ext {
                    case "heic": .heic
                    case "jpg", "jpeg": .jpeg
                    case "png": .png
                    case "pdf": .pdf
                    default: .binary
                    }
                let filename = source.lastPathComponent
                let stagedPath = "evidence/field/"
                    + UUID().uuidString.lowercased() + "."
                    + mediaType.fileExtension
                draft.authority.fieldEvidenceAssets.append(
                    StagedFieldAsset(
                        path: stagedPath,
                        data: data
                    )
                )
                let asset = try FieldEvidenceAsset.importedFile(
                    assetPath: stagedPath,
                    sha256: EvidenceIntegrity.sha256(
                        of: data
                    ),
                    mediaType: mediaType,
                    originalFilename: filename
                )
                let targetRef = draft.taskLedger.first?.itemRef
                    ?? "task_item:general"
                let record = try FieldEvidenceRecord(
                    kind: .externalDocument,
                    title: filename,
                    targetRefs: [targetRef],
                    asset: asset,
                    captureRevisionID:
                        draft.bindingRevisionID
                )
                draft.authority.fieldEvidence.append(record)
                workspace = draft
                persist(draft)
            } catch {
                statusMessage = String(
                    localized:
                        "The file could not be attached: \(String(describing: error))"
                )
            }
        }
    }

    // MARK: - Finalize

    private func finalize() async {
        guard let draft = workspace else { return }
        if let url = await actions
            .finalizeFieldReturn(draft)
        {
            var marked = draft
            marked.finalizedAtUTC = BundleTimestamp.utcString(
                from: Date()
            )
            workspace = marked
            #if os(iOS)
            finalizedShare = ShareTarget(url: url)
            #else
            statusMessage = url.path
            #endif
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
