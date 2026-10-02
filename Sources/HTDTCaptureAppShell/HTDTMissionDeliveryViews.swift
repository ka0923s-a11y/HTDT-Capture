import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore
import HTDTCapturePlatform

/// Mission inbox detail/list surface (issue #386): missions grouped
/// project → room, each record showing lifecycle, plan identity,
/// declared dependencies, and its associated captures. Start is the
/// only action that can begin a mission's capture work and it is
/// refused by the store when required dependencies are unmet.
struct HTDTMissionInboxView: View {
    let records: [HTDTMissionRecord]
    let activeMissionRecordID: String?
    /// Replayed mission progress per record id (#397) — never a
    /// stored percentage.
    let progressEvaluations: [String: MissionProgressEvaluation]
    let actions: CaptureRootActions
    /// #422/#423: active paired receivers — the Mission pull refresh
    /// and the Field Return send surface both key off this list.
    var pairedDestinations: [PairedHTDTDestination] = []
    /// Idle-only import/action outcomes (`workingSetStatus` on the
    /// host) — the missions surface is where mission imports land,
    /// so their results must stay visible here.
    var workingSetStatus: String? = nil

    @State private var importingMission = false
    @State private var missionCheckSummary: String?
    @State private var selectedRecord: HTDTMissionRecord?
    @State private var fieldReturnRecord: HTDTMissionRecord?
    /// A field return to open once the detail sheet dismisses —
    /// presenting `fieldReturnRecord` over `selectedRecord` is dead
    /// because both sheets share one host.
    @State private var pendingFieldReturnRecord:
        HTDTMissionRecord?
    @State private var fieldReturnDocuments:
        [HTDTFieldReturnDocument] = []
    @State private var dependencyReport:
        HTDTMissionDependencyReport?
    @State private var dependencyError: String?
    @State private var confirmingArchive = false
    /// Operator note draft for the detail sheet (#463) — seeded
    /// from the record when the sheet opens.
    @State private var userNoteDraft = ""
    /// Pending "waive with reason" prompt (#364 §10) — the waiver
    /// records the operator's reason as its audited note.
    @State private var waivingItem: WaivePrompt?
    @State private var waiveReasonDraft = ""

    private struct WaivePrompt: Identifiable {
        let recordID: String
        let taskItemID: String
        var id: String {
            recordID + "\u{0}" + taskItemID
        }
    }

    private var grouped:
        [String: [String: [HTDTMissionRecord]]]
    {
        var groups: [String: [String: [HTDTMissionRecord]]] = [:]
        for record in records where
            record.lifecycle != .archived
            && record.lifecycle != .superseded
        {
            groups[record.projectRef, default: [:]][
                record.roomName,
                default: []
            ].append(record)
        }
        return groups
    }

    private var supersededRecords: [HTDTMissionRecord] {
        records.filter { $0.lifecycle == .superseded }
    }

    var body: some View {
        List {
            if let workingSetStatus {
                Section {
                    Text(workingSetStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    importingMission = true
                } label: {
                    Label(
                        "Import mission",
                        systemImage: "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .captureSecondaryAction()
                // #422: the receive leg's bounded pull refresh —
                // enumerates each paired receiver's pending-Mission
                // listing and stages verified packages here. No
                // polling; runs only on demand (and on refresh below).
                Button {
                    Task { await checkHTDTForMissions() }
                } label: {
                    Label(
                        "Check HTDT for missions",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .frame(maxWidth: .infinity)
                }
                .captureSecondaryAction()
                .disabled(pairedDestinations.isEmpty)
                if pairedDestinations.isEmpty {
                    Text(
                        "Pair an HTDT receiver on the Destinations surface to pull missions from it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let missionCheckSummary {
                    Text(missionCheckSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if grouped.isEmpty {
                Section {
                    Text(
                        "No missions yet. HTDT issues missions as task-plan packages — import one to begin."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                ForEach(
                    grouped.keys.sorted(),
                    id: \.self
                ) { project in
                    ForEach(
                        grouped[project]!.keys.sorted(),
                        id: \.self
                    ) { room in
                        Section(
                            String(
                                format: String(
                                    localized: "%@ — %@"
                                ),
                                project,
                                room
                            )
                        ) {
                            ForEach(
                                grouped[project]![room]!
                            ) { record in
                                missionRow(record)
                            }
                        }
                    }
                }
            }
            if !supersededRecords.isEmpty {
                Section("Superseded") {
                    ForEach(supersededRecords) { record in
                        missionRow(record)
                    }
                }
            }
        }
        .navigationTitle("Missions")
        .refreshable {
            await checkHTDTForMissions()
        }
        .fileImporter(
            isPresented: $importingMission,
            // #457: the dedicated `.htdtmission` package type is
            // pickable alongside plain JSON payloads.
            allowedContentTypes: [.json, .htdtMission],
            allowsMultipleSelection: false
        ) { result in
            guard let urls = try? result.get(),
                  let url = urls.first
            else {
                return
            }
            Task {
                await actions.importMissionPackage(url)
            }
        }
        .sheet(item: $selectedRecord) {
            // Promote a queued field-return handoff once the detail
            // sheet is gone — two sheets cannot stack on one host.
            if let pendingFieldReturnRecord {
                fieldReturnRecord = pendingFieldReturnRecord
                self.pendingFieldReturnRecord = nil
            }
        } content: { record in
            NavigationStack {
                missionDetail(record)
            }
            .presentationDetents([.medium, .large])
            .onAppear {
                userNoteDraft = record.userNote ?? ""
            }
        }
        .sheet(item: $fieldReturnRecord) { record in
            NavigationStack {
                HTDTFieldReturnWorkspaceView(
                    record: record,
                    actions: actions,
                    pairedDestinations: pairedDestinations
                )
            }
        }
        .task(id: selectedRecord?.recordID) {
            guard let selectedRecord else { return }
            dependencyReport = nil
            dependencyError = nil
            fieldReturnDocuments = await actions
                .listFieldReturns()
            do {
                dependencyReport = try await actions
                    .evaluateMissionDependencies(
                        selectedRecord.recordID
                    )
            } catch {
                dependencyError = String(describing: error)
            }
        }
    }

    /// Aggregated field progress replayed from the mission progress
    /// ledger (#397): per-kind tallies, outstanding items with the
    /// explicit waiver action (mission-level, auditable — never a
    /// revision-local skip), contested items where two heads claimed
    /// the same item, and the field-complete verdict kept separate
    /// from delivered.
    @ViewBuilder
    private func missionProgressSection(
        _ record: HTDTMissionRecord,
        _ progress: MissionProgressEvaluation
    ) -> some View {
        Section("Field progress") {
            if progress.fieldComplete {
                Label(
                    "Field complete",
                    systemImage: "checkmark.seal"
                )
                .foregroundStyle(CaptureColorRole.success.color)
            } else if progress.requiredItemsResolved {
                Label(
                    "All required resolved — some via waiver",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(CaptureColorRole.attention.color)
            }
            ForEach(progress.kinds, id: \.kind) { kind in
                LabeledContent(
                    kindLabel(kind.kind),
                    value: MissionPresentation.kindProgressText(
                        completedCount: kind.completedCount,
                        itemCount: kind.itemCount,
                        requiredOutstandingCount:
                            kind.requiredOutstandingCount
                    )
                )
                .font(.caption)
            }
            if !progress.contestedItemIDs.isEmpty {
                let contestedItems = progress.contestedItemIDs
                    .joined(separator: ", ")
                Label(
                    "Contested: \(contestedItems)",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(CaptureColorRole.attention.color)
            }
            ForEach(
                progress.items.filter { !$0.resolved },
                id: \.taskItemID
            ) { item in
                HStack {
                    Text(
                        MissionPresentation.taskItemName(
                            item.taskItemID
                        )
                    )
                    .font(.caption)
                    .lineLimit(1)
                    Spacer()
                    if item.requirement == .required {
                        Text("required")
                            .font(.caption2)
                            .foregroundStyle(CaptureColorRole.attention.color)
                    }
                    Button(
                        String(localized: "Waive with reason…")
                    ) {
                        waiveReasonDraft = ""
                        waivingItem = WaivePrompt(
                            recordID: record.recordID,
                            taskItemID: item.taskItemID
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            ForEach(
                progress.items.filter { $0.waived },
                id: \.taskItemID
            ) { item in
                Label(
                    String(
                        format: String(
                            localized: "%@ — waived"
                        ),
                        MissionPresentation.taskItemName(
                            item.taskItemID
                        )
                    ),
                    systemImage: "flag"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func kindLabel(
        _ kind: MissionLedgerTaskKind
    ) -> String {
        switch kind {
        case .entityChecklist:
            String(localized: "Entity checklist")
        case .measurementRequest:
            String(localized: "Measurement request")
        case .surfaceReview:
            String(localized: "Surface review")
        case .semanticTask:
            String(localized: "Semantic task")
        case .evidenceTask:
            String(localized: "Evidence task")
        }
    }

    @ViewBuilder
    private func missionRow(
        _ record: HTDTMissionRecord
    ) -> some View {
        Button {
            selectedRecord = record
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.roomName)
                        .font(.headline)
                    Spacer()
                    lifecycleBadge(record.lifecycle)
                }
                Text(record.missionID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label(
                        MissionPresentation.missionKindName(
                            record.missionKind
                        ),
                        systemImage: "tag"
                    )
                    if !record.associatedCaptureRevisionIDs
                        .isEmpty
                    {
                        Label(
                            captureCountPhrase(
                                record
                                    .associatedCaptureRevisionIDs
                                    .count,
                                singular: String(
                                    localized: "%lld capture"
                                ),
                                plural: String(
                                    localized: "%lld captures"
                                )
                            ),
                            systemImage: "cube"
                        )
                    }
                    if !record.fieldReturnIDs.isEmpty {
                        Label(
                            captureCountPhrase(
                                record.fieldReturnIDs.count,
                                singular: String(
                                    localized: "%lld field return"
                                ),
                                plural: String(
                                    localized: "%lld field returns"
                                )
                            ),
                            systemImage:
                                "checklist.unchecked"
                        )
                    }
                    if record.followUpOfMissionID != nil {
                        Label(
                            "Follow-up",
                            systemImage: "arrow.uturn.forward"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(
            "mission.row.\(record.missionID)"
        )
    }

    @ViewBuilder
    private func missionDetail(
        _ record: HTDTMissionRecord
    ) -> some View {
        List {
            Section("Mission") {
                LabeledContent("Mission ID", value: record.missionID)
                LabeledContent(
                    "Kind",
                    value: MissionPresentation.missionKindName(
                        record.missionKind
                    )
                )
                LabeledContent("Plan", value: record.planID)
                LabeledContent(
                    "Plan version",
                    value: record.planVersion
                )
                LabeledContent(
                    "Project",
                    value: record.projectRef
                )
                if let purpose = record.purpose {
                    Text(purpose).font(.callout)
                }
                if let issued = record.issuedAtUTC {
                    LabeledContent("Issued", value: issued)
                }
                LabeledContent("Imported", value: record.importedAtUTC)
                if let supersededBy = record.supersededByMissionID {
                    LabeledContent(
                        "Superseded by",
                        value: supersededBy
                    )
                }
                if let followUpOf = record.followUpOfMissionID {
                    LabeledContent(
                        "Follow-up of",
                        value: followUpOf
                    )
                }
                if let origin = record.followUpOriginRef {
                    LabeledContent(
                        "Follow-up origin",
                        value: origin
                    )
                }
            }

            Section("Status") {
                lifecycleBadge(record.lifecycle)
                if !record.associatedCaptureRevisionIDs.isEmpty {
                    DisclosureGroup(
                        String(
                            format: String(
                                localized: "Associated captures (%lld)"
                            ),
                            record.associatedCaptureRevisionIDs.count
                        )
                    ) {
                        ForEach(
                            record.associatedCaptureRevisionIDs,
                            id: \.self
                        ) { revisionID in
                            // #461: the revision row opens its persisted
                            // capture — never a dead text id.
                            if let parsed = CaptureRevisionID(
                                canonicalString: revisionID
                            ) {
                                Button {
                                    selectedRecord = nil
                                    actions.openPersistedCapture(parsed)
                                } label: {
                                    Label(
                                        revisionID,
                                        systemImage:
                                            "arrow.up.forward.square"
                                    )
                                    .font(.caption.monospaced())
                                }
                            } else {
                                Text(revisionID)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !record.deliveryJobIDs.isEmpty {
                    LabeledContent(
                        "Delivery jobs",
                        value: String(record.deliveryJobIDs.count)
                    )
                }
            }

            // #463: the record's operator annotation — editable,
            // never issuer truth.
            Section("Mission note") {
                TextField(
                    String(localized: "Operator note"),
                    text: $userNoteDraft,
                    axis: .vertical
                )
                .lineLimit(2...4)
                if userNoteDraft != (record.userNote ?? "") {
                    Button {
                        Task {
                            await actions.updateMissionUserNote(
                                record.recordID,
                                userNoteDraft
                            )
                        }
                    } label: {
                        Label(
                            "Save note",
                            systemImage: "checkmark.circle"
                        )
                    }
                    .captureSecondaryAction()
                }
            }

            if let progress = progressEvaluations[record.recordID] {
                missionProgressSection(record, progress)
            }

            // #400: finalized field returns list separately from
            // capture revisions in mission history — the non-spatial
            // completion path stays visible on its own terms.
            if !record.fieldReturnIDs.isEmpty
                || record.lifecycle.canStart
                || record.lifecycle == .inProgress
            {
                Section("Field return") {
                    Button {
                        // Queue the handoff: presenting the field
                        // return sheet directly would stack a second
                        // sheet on the detail sheet's host and die.
                        pendingFieldReturnRecord = record
                        selectedRecord = nil
                    } label: {
                        Label(
                            "Open field return",
                            systemImage:
                                "checklist.unchecked"
                        )
                    }
                    ForEach(
                        fieldReturnDocuments.filter { doc in
                            record.fieldReturnIDs.contains(
                                doc.contributionID.description
                            )
                        },
                        id: \.contributionID
                    ) { doc in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                CaptureSeriesPresentation.dateLabel(
                                    for: doc.finalizedAtUTC
                                ) ?? String(
                                    localized: "Finalized"
                                )
                            )
                            .font(.subheadline)
                            CaptureTechnicalText(
                                doc.contributionID.description
                            )
                        }
                    }
                }
            }

            if let report = dependencyReport {
                if report.missingRequired.isEmpty,
                   report.missingOptional.isEmpty,
                   report.receiverGaps.isEmpty,
                   report.catalogRequirement.isSatisfied
                {
                    Section("Dependencies") {
                        Label(
                            "All requirements satisfied",
                            systemImage: "checkmark.circle"
                        )
                        .foregroundStyle(CaptureColorRole.success.color)
                    }
                } else {
                    Section("Dependencies") {
                        ForEach(
                            report.missingRequired,
                            id: \.self
                        ) { ref in
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Label(
                                    "Missing required dependency",
                                    systemImage: "xmark.octagon"
                                )
                                .foregroundStyle(CaptureColorRole.blocked.color)
                                Text(ref)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(
                            report.missingOptional,
                            id: \.self
                        ) { ref in
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Label(
                                    "Missing optional dependency",
                                    systemImage:
                                        "exclamationmark.triangle"
                                )
                                .foregroundStyle(CaptureColorRole.attention.color)
                                Text(ref)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(
                            report.receiverGaps,
                            id: \.self
                        ) { gap in
                            Text(gap)
                                .font(.caption)
                                .foregroundStyle(CaptureColorRole.attention.color)
                        }
                        if !report.catalogRequirement.isSatisfied {
                            Text(
                                "The plan pins an equipment catalog that is not satisfied by the active catalog."
                            )
                            .font(.caption)
                            .foregroundStyle(CaptureColorRole.attention.color)
                        }
                    }
                }
            } else if let dependencyError {
                Section("Dependencies") {
                    Text(
                        MissionPresentation
                            .dependencyCheckFailedText
                    )
                    Text(dependencyError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if record.lifecycle.canStart {
                    Button {
                        Task {
                            await actions.startMission(record.recordID)
                        }
                        selectedRecord = nil
                    } label: {
                        Label(
                            record.lifecycle == .inProgress
                                ? "Resume mission"
                                : "Start mission",
                            systemImage: "play.fill"
                        )
                    }
                    .disabled(
                        dependencyReport?.startBlocked == true
                    )
                }
                if activeMissionRecordID == record.recordID {
                    Button {
                        Task {
                            await actions.deactivateMission()
                        }
                        selectedRecord = nil
                    } label: {
                        Label(
                            "Deactivate",
                            systemImage: "pause.fill"
                        )
                    }
                }
                // #456: explicit close once field work or delivery
                // landed — missions otherwise stay open forever.
                if record.lifecycle.canMarkCompleted {
                    Button {
                        Task {
                            await actions.completeMission(
                                record.recordID
                            )
                        }
                        selectedRecord = nil
                    } label: {
                        Label(
                            "Mark completed",
                            systemImage: "checkmark.seal"
                        )
                    }
                }
            } footer: {
                Text(
                    "Starting a mission resumes its workflow record and plan; a live AR session is never resumed — scanning always begins fresh."
                )
                .font(.caption)
            }

            // Destructive: kept in its own section away from the
            // routine start/deactivate actions, and confirmed (#445).
            if record.lifecycle != .archived,
               record.lifecycle != .superseded
            {
                Section {
                    Button(role: .destructive) {
                        confirmingArchive = true
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .confirmationDialog(
                        "Archive this mission?",
                        isPresented: $confirmingArchive,
                        titleVisibility: .visible
                    ) {
                        Button("Archive", role: .destructive) {
                            Task {
                                await actions.archiveMission(
                                    record.recordID
                                )
                            }
                            selectedRecord = nil
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "The mission leaves the inbox and stays in history. This cannot be undone."
                        )
                    }
                }
            }
        }
        .navigationTitle(record.roomName)
        // #364 §10: waiving records the operator's reason as the
        // waiver's audited note — the sheet stacks on the detail
        // sheet's own host, not the inbox root's.
        .sheet(item: $waivingItem) { prompt in
            NavigationStack {
                Form {
                    TextField(
                        String(localized: "Reason"),
                        text: $waiveReasonDraft,
                        axis: .vertical
                    )
                }
                .navigationTitle(
                    String(localized: "Waive with reason")
                )
                .toolbar {
                    ToolbarItem(
                        placement: .cancellationAction
                    ) {
                        Button(String(localized: "Cancel")) {
                            waivingItem = nil
                        }
                    }
                    ToolbarItem(
                        placement: .confirmationAction
                    ) {
                        Button(String(localized: "Waive")) {
                            let reason = waiveReasonDraft
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            let item = prompt
                            waivingItem = nil
                            Task {
                                await actions.waiveMissionItem(
                                    item.recordID,
                                    item.taskItemID,
                                    reason.isEmpty ? nil : reason
                                )
                            }
                        }
                        .disabled(
                            waiveReasonDraft.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func lifecycleBadge(
        _ lifecycle: HTDTMissionLifecycle
    ) -> some View {
        Text(MissionPresentation.missionLifecycleName(lifecycle))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                lifecycleColor(lifecycle).opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(lifecycleColor(lifecycle))
    }

    private func lifecycleColor(
        _ lifecycle: HTDTMissionLifecycle
    ) -> Color {
        switch lifecycle {
        case .received, .ready:
            return CaptureColorRole.informational.color
        case .blockedDependency, .needsFollowUp:
            return CaptureColorRole.attention.color
        case .inProgress, .fieldCaptureCompleted:
            return CaptureColorRole.accent.color
        case .finalized, .delivered, .completed:
            return CaptureColorRole.success.color
        case .superseded, .archived:
            return CaptureColorRole.secondary.color
        }
    }

    /// #422: runs the bounded Mission pull and summarizes the
    /// reports into one operator-readable line — counts only; the
    /// receipt ledger holds the per-package detail.
    private func checkHTDTForMissions() async {
        let reports = await actions.checkHTDTForMissions()
        guard !reports.isEmpty else {
            missionCheckSummary = String(
                localized:
                    "No paired HTDT receivers — pair a receiver or import the mission file"
            )
            return
        }
        let imported = reports.reduce(0) { $0 + $1.imported }
        let superseded = reports.reduce(0) { $0 + $1.superseded }
        let conflicts = reports.reduce(0) { $0 + $1.conflicts.count }
        let rejected = reports.reduce(0) { $0 + $1.rejected.count }
        let pending = reports.reduce(0) { $0 + $1.enumerated }
        let failures = reports.reduce(0) {
            $0 + $1.notes.filter { $0 != "destination_revoked" }.count
        }
        if conflicts + rejected > 0 {
            missionCheckSummary = captureCountPhrase(
                conflicts + rejected,
                singular: String(
                    localized: "Checked HTDT — %lld pending mission could not be staged; receipt ledger has details"
                ),
                plural: String(
                    localized: "Checked HTDT — %lld pending missions could not be staged; receipt ledger has details"
                )
            )
        } else if imported + superseded > 0 {
            missionCheckSummary = captureCountPhrase(
                imported + superseded,
                singular: String(
                    localized: "Checked HTDT — %lld new mission received into the inbox"
                ),
                plural: String(
                    localized: "Checked HTDT — %lld new missions received into the inbox"
                )
            )
        } else if pending > 0 {
            missionCheckSummary = captureCountPhrase(
                pending,
                singular: String(
                    localized: "Checked HTDT — %lld mission already staged or pending"
                ),
                plural: String(
                    localized: "Checked HTDT — %lld missions already staged or pending"
                )
            )
        } else if failures > 0 {
            missionCheckSummary = String(
                localized:
                    "Checked HTDT — receiver unreachable; import the mission file instead"
            )
        } else {
            missionCheckSummary = String(
                localized: "Checked HTDT — nothing pending"
            )
        }
    }
}

/// QR-paired, identity-pinned HTDT destinations (issue #379): each
/// record shows the pinned receiver identity, when pairing happened,
/// last contact, and the cached capability snapshot labeled with its
/// fetch time. Forget deletes the pairing; re-pair replaces it.
struct PairedHTDTDestinationsView: View {
    let destinations: [PairedHTDTDestination]
    /// Legacy `handoff-destinations.json` raw-URL entries kept for
    /// reference — never selectable once pairing replaces them.
    let actions: CaptureRootActions
    /// Idle-only import/action outcomes (`workingSetStatus` on the
    /// host) — pairing imports report through it, so this surface
    /// must render the status too.
    var workingSetStatus: String? = nil

    @State private var pairingSheetShown = false
    @State private var pastePayloadText = ""
    @State private var pendingPayload:
        HTDTReceiverPairingPayload?
    @State private var pairingError: String?
    @State private var forgetCandidate: PairedHTDTDestination?

    var body: some View {
        List {
            if let workingSetStatus {
                Section {
                    Text(workingSetStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    pairingSheetShown = true
                } label: {
                    Label(
                        "Pair a receiver",
                        systemImage: "qrcode.viewfinder"
                    )
                    .frame(maxWidth: .infinity)
                }
                .captureSecondaryAction()
            }
            if destinations.isEmpty {
                Section {
                    Text(
                        "No paired receivers. Scan or paste a receiver's pairing QR payload to add one — destinations keep their pinned identity so sends only ever trust the exact certificate paired."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                Section("Paired receivers") {
                    ForEach(destinations) { destination in
                        destinationRow(destination)
                    }
                }
            }
            Section {
                Text(
                    "Pinned identity, HTTPS endpoint and capability snapshot are bound to the receiver's QR ceremony. Nothing here weakens TLS — a changed certificate blocks the send until you re-pair."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Destinations")
        .sheet(isPresented: $pairingSheetShown) {
            NavigationStack {
                pairingSheet
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var pairingSheet: some View {
        List {
            if let payload = pendingPayload {
                Section("Confirm pairing") {
                    LabeledContent(
                        "Receiver",
                        value: payload.displayName
                    )
                    LabeledContent(
                        "Endpoint",
                        value: payload.endpointURL
                    )
                    if let project = payload.projectRef {
                        LabeledContent(
                            "Project",
                            value: project
                        )
                    }
                    LabeledContent(
                        "Verification code",
                        value: payload.verificationCode
                    )
                    .font(.title3.monospaced())
                    Text(
                        "Confirm this code matches the one shown on the receiver's display. Pairing stores the pinned certificate identity — sends to this destination refuse any other TLS identity."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button("Confirm pairing") {
                        let payload = payload
                        Task {
                            await actions.confirmPairing(payload)
                        }
                        pendingPayload = nil
                        pairingSheetShown = false
                    }
                    Button("Discard", role: .cancel) {
                        pendingPayload = nil
                    }
                }
            } else {
                Section("Paste pairing payload") {
                    TextEditor(text: $pastePayloadText)
                        .frame(minHeight: 140)
                        .font(.caption.monospaced())
                    if let pairingError {
                        Text(pairingError)
                            .font(.caption)
                            .foregroundStyle(CaptureColorRole.blocked.color)
                    }
                    Button("Review pairing") {
                        do {
                            pendingPayload = try actions
                                .pairDestinationPayload(
                                    Data(pastePayloadText.utf8)
                                )
                            pairingError = nil
                        } catch {
                            pairingError =
                                MissionPresentation
                                    .pairingErrorText(error)
                        }
                    }
                    .disabled(pastePayloadText.isEmpty)
                }
            }
        }
        .navigationTitle("Pair receiver")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    pairingSheetShown = false
                    pendingPayload = nil
                    pairingError = nil
                }
            }
        }
    }

    @ViewBuilder
    private func destinationRow(
        _ destination: PairedHTDTDestination
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(destination.displayName).font(.headline)
                Spacer()
                if destination.revoked {
                    Text("revoked")
                        .font(.caption2)
                        .foregroundStyle(CaptureColorRole.blocked.color)
                }
            }
            Text(destination.endpointURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            LabeledContent(
                "Pinned",
                value: String(
                    destination.pinnedIdentity.prefix(19)
                ) + "…"
            )
            .font(.caption)
            LabeledContent("Paired", value: destination.pairedAtUTC)
                .font(.caption)
            if let seen = destination.lastSeenAtUTC {
                LabeledContent("Last seen", value: seen)
                    .font(.caption)
            }
            if let snapshot = destination.cachedCapability {
                LabeledContent(
                    "Capabilities fetched",
                    value: snapshot.fetchedAtUTC
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button("Refresh capabilities") {
                Task {
                    await actions
                        .refreshEndpointCapabilities(
                            destination.destinationID
                        )
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            // Destructive: separated from the routine refresh action
            // and confirmed before the pairing is dropped (#445).
            Button("Forget", role: .destructive) {
                forgetCandidate = destination
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .confirmationDialog(
                "Forget this receiver?",
                isPresented: Binding(
                    get: { forgetCandidate != nil },
                    set: { if !$0 { forgetCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) {
                    if let candidate = forgetCandidate {
                        Task {
                            await actions.forgetDestination(
                                candidate.destinationID
                            )
                        }
                    }
                    forgetCandidate = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The paired endpoint and its pinned identity are deleted. Re-pair before sending to this receiver again."
                )
            }
        }
    }
}

/// Delivery queue surface (issue #387): the durable job ledger —
/// every queued/retrying/blocked/delivered send, outside the send
/// sheet, with operator controls for retry-now, pause, resume,
/// cancel, and payload purge.
struct HTDTDeliveryQueueView: View {
    let jobs: [HTDTDeliveryJob]
    let actions: CaptureRootActions

    private enum PendingJobAction: Int, Equatable {
        case cancel
        case purge
    }
    @State private var pendingJobAction:
        (HTDTDeliveryJob, PendingJobAction)?

    /// #462: queue filters + text search — the queue only grows, so
    /// the view needs the same triage affordances the evidence
    /// contact sheet already has.
    @State private var filter: HTDTDeliveryQueueFilter = .all
    @State private var searchText = ""

    private var ordered: [HTDTDeliveryJob] {
        jobs.filter { filter.matches($0) }
            .filter { job in
                let query = searchText.trimmingCharacters(
                    in: .whitespaces
                )
                guard !query.isEmpty else { return true }
                return job.displayTitle.localizedCaseInsensitiveContains(
                    query
                )
                || job.displaySubtitle.localizedCaseInsensitiveContains(
                    query
                )
                || job.artifactIDText.localizedCaseInsensitiveContains(
                    query
                )
                || job.destination.name
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.createdAtUTC > $1.createdAtUTC }
    }

    var body: some View {
        List {
            if ordered.isEmpty {
                Section {
                    Text(
                        jobs.isEmpty
                            ? "No deliveries queued. Endpoint sends are recorded here before any bytes move and survive app restarts."
                            : "No deliveries match this filter."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                ForEach(ordered) { job in
                    jobRow(job)
                }
            }
        }
        .searchable(
            text: $searchText,
            prompt: Text("Search deliveries")
        )
        .safeAreaInset(edge: .top) {
            Picker("Filter", selection: $filter) {
                ForEach(
                    HTDTDeliveryQueueFilter.allCases,
                    id: \.self
                ) { value in
                    Text(
                        MissionPresentation
                            .deliveryQueueFilterName(value)
                    )
                    .tag(value)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.regularMaterial)
        }
        .navigationTitle("Deliveries")
    }

    @ViewBuilder
    private func jobRow(_ job: HTDTDeliveryJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Human artifact type + context — never a bare
                // revision id as the only label (#423).
                Text(job.displayTitle).font(.headline)
                Spacer()
                stateBadge(job.state)
            }
            HStack {
                Text(job.displaySubtitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(job.artifactKind.displayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        CaptureColorRole.informational.color
                            .opacity(0.12),
                        in: Capsule()
                    )
            }
            Text(job.artifactIDText)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            LabeledContent(
                "Attempts",
                value: String(job.attemptCount)
            )
            .font(.caption)
            if let next = job.nextAttemptAtUTC {
                LabeledContent("Next attempt", value: next)
                    .font(.caption)
            }
            if let staged = job.serverStagingRef {
                LabeledContent("Staged as", value: staged)
                    .font(.caption)
            }
            LabeledContent(
                "Destination",
                value: job.destination.name
            )
            .font(.caption)
            if let endpoint = job.destination.url {
                Text(endpoint)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if let detail = job.lastErrorDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let summary = job.compatibilitySummary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if job.state == .retryWait || job.state == .queued {
                    Button("Retry now") {
                        Task {
                            await actions.deliveryRetryNow(
                                job.deliveryJobID
                            )
                        }
                    }
                }
                if job.state == .queued
                    || job.state == .retryWait
                {
                    Button("Pause") {
                        Task {
                            await actions.deliveryPause(
                                job.deliveryJobID
                            )
                        }
                    }
                }
                if job.state == .paused || job.state == .blocked {
                    Button("Resume") {
                        Task {
                            await actions.deliveryResume(
                                job.deliveryJobID
                            )
                        }
                    }
                }
                if !job.isTerminal {
                    Button("Cancel", role: .destructive) {
                        pendingJobAction = (job, .cancel)
                    }
                }
                if job.isTerminal {
                    Button("Free payload") {
                        pendingJobAction = (job, .purge)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .confirmationDialog(
                pendingJobAction?.1 == .cancel
                    ? "Cancel this delivery?"
                    : "Free the staged payload?",
                isPresented: Binding(
                    get: { pendingJobAction != nil },
                    set: { if !$0 { pendingJobAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                // Each branch carries its own Cancel — iOS 26
                // renders only the first action-producing child, so
                // a button written after the `if` never appears.
                if let (job, action) = pendingJobAction {
                    if action == .cancel {
                        Button("Cancel delivery", role: .destructive) {
                            Task {
                                await actions.deliveryCancel(
                                    job.deliveryJobID
                                )
                            }
                            pendingJobAction = nil
                        }
                        Button("Cancel", role: .cancel) {}
                    } else {
                        Button("Free payload", role: .destructive) {
                            Task {
                                await actions.deliveryPurgePayload(
                                    job.deliveryJobID
                                )
                            }
                            pendingJobAction = nil
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                } else {
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                if pendingJobAction?.1 == .cancel {
                    Text(
                        "The job stops and its queued payload copy is deleted; the capture itself stays on this device."
                    )
                } else {
                    Text(
                        "Deletes the staged bytes for this delivery; the job record stays."
                    )
                }
            }
            // #462: reach the artifact the job transports — a queued
            // capture opens its Library record; a field return
            // offers its finalized container via ShareLink.
            HStack {
                if job.artifactKind == .captureBundle,
                   let revisionID = job.captureRevisionID
                {
                    Button {
                        actions.openPersistedCapture(revisionID)
                    } label: {
                        Label(
                            "Open capture",
                            systemImage: "arrow.up.forward.square"
                        )
                    }
                    .font(.caption)
                }
                if job.artifactKind == .fieldReturn,
                   let returnID = HTDTFieldReturnID(
                    canonicalString: job.artifactIDText
                   ),
                   let artifactURL = actions
                    .fieldReturnArtifactURL(returnID)
                {
                    ShareLink(item: artifactURL) {
                        Label(
                            "Field return artifact",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func stateBadge(
        _ state: HTDTDeliveryJobState
    ) -> some View {
        Text(MissionPresentation.deliveryJobStateName(state))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                stateColor(state).opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(stateColor(state))
    }

    private func stateColor(
        _ state: HTDTDeliveryJobState
    ) -> Color {
        switch state {
        case .queued, .sending:
            return CaptureColorRole.informational.color
        case .retryWait, .blocked:
            return CaptureColorRole.attention.color
        case .paused, .cancelled:
            return CaptureColorRole.secondary.color
        case .deliveredStaged:
            return CaptureColorRole.success.color
        case .rejected, .failed:
            return CaptureColorRole.blocked.color
        }
    }
}
