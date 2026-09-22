import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore

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

    @State private var importingMission = false
    @State private var selectedRecord: HTDTMissionRecord?
    @State private var fieldReturnRecord: HTDTMissionRecord?
    @State private var fieldReturnDocuments:
        [HTDTFieldReturnDocument] = []
    @State private var dependencyReport:
        HTDTMissionDependencyReport?
    @State private var dependencyError: String?

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
        .fileImporter(
            isPresented: $importingMission,
            allowedContentTypes: [.json],
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
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                missionDetail(record)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $fieldReturnRecord) { record in
            NavigationStack {
                HTDTFieldReturnWorkspaceView(
                    record: record,
                    actions: actions
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
                .foregroundStyle(.green)
            } else if progress.requiredItemsResolved {
                Label(
                    "All required resolved — some via waiver",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.orange)
            }
            ForEach(progress.kinds, id: \.kind) { kind in
                LabeledContent(
                    kindLabel(kind.kind),
                    value:
                        "\(kind.completedCount)/\(kind.itemCount) completed"
                        + (kind.requiredOutstandingCount > 0
                            ? " · \(kind.requiredOutstandingCount) required open"
                            : "")
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
                .foregroundStyle(.orange)
            }
            ForEach(
                progress.items.filter { !$0.resolved },
                id: \.taskItemID
            ) { item in
                HStack {
                    Text(item.taskItemID)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Spacer()
                    if item.requirement == .required {
                        Text("required")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Button("Waive") {
                        Task {
                            await actions.waiveMissionItem(
                                record.recordID,
                                item.taskItemID,
                                nil
                            )
                        }
                    }
                    .font(.caption)
                }
            }
            ForEach(
                progress.items.filter { $0.waived },
                id: \.taskItemID
            ) { item in
                Label(
                    "\(item.taskItemID) — waived",
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
        kind.rawValue.replacingOccurrences(of: "_", with: " ")
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
                                String(
                                    format: String(
                                        localized: "%lld capture(s)"
                                    ),
                                    record
                                        .associatedCaptureRevisionIDs
                                        .count
                                ),
                                systemImage: "cube"
                        )
                    }
                    if !record.fieldReturnIDs.isEmpty {
                        Label(
                            "\(record.fieldReturnIDs.count) field return(s)",
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
                    ForEach(
                        record.associatedCaptureRevisionIDs,
                        id: \.self
                    ) { revisionID in
                        Text(revisionID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if !record.deliveryJobIDs.isEmpty {
                    LabeledContent(
                        "Delivery jobs",
                        value: String(record.deliveryJobIDs.count)
                    )
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
                        fieldReturnRecord = record
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
                            Text(doc.contributionID.description)
                                .font(.caption.monospaced())
                            Text(
                                "Finalized \(doc.finalizedAtUTC)"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.green)
                    }
                } else {
                    Section("Dependencies") {
                        ForEach(
                            report.missingRequired,
                            id: \.self
                        ) { ref in
                            Label(
                                String(
                                    format: String(
                                        localized: "Required: %@"
                                    ),
                                    ref
                                ),
                                systemImage: "xmark.octagon"
                            )
                            .foregroundStyle(.red)
                            Label(
                                "Required: \(ref)",
                                systemImage: "xmark.octagon"
                            )
                            .foregroundStyle(.red)
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Label(
                                    "Missing required dependency",
                                    systemImage: "xmark.octagon"
                                )
                                .foregroundStyle(.red)
                                Text(ref)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(
                            report.missingOptional,
                            id: \.self
                        ) { ref in
                            Label(
                                String(
                                    format: String(
                                        localized: "Optional: %@"
                                    ),
                                    ref
                                ),
                                systemImage:
                                    "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                            Label(
                                "Optional: \(ref)",
                                systemImage:
                                    "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Label(
                                    "Missing optional dependency",
                                    systemImage:
                                        "exclamationmark.triangle"
                                )
                                .foregroundStyle(.orange)
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
                                .foregroundStyle(.orange)
                        }
                        if !report.catalogRequirement.isSatisfied {
                            Text(
                                "The plan pins an equipment catalog that is not satisfied by the active catalog."
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
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
                if record.lifecycle != .archived,
                   record.lifecycle != .superseded
                {
                    Button(role: .destructive) {
                        Task {
                            await actions.archiveMission(
                                record.recordID
                            )
                        }
                        selectedRecord = nil
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                }
            } footer: {
                Text(
                    "Starting a mission resumes its workflow record and plan; a live AR session is never resumed — scanning always begins fresh."
                )
                .font(.caption)
            }
        }
        .navigationTitle(record.roomName)
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
            return .blue
        case .blockedDependency:
            return .orange
        case .inProgress, .fieldCaptureCompleted:
            return .green
        case .finalized, .delivered:
            return .teal
        case .needsFollowUp:
            return .purple
        case .completed:
            return .green
        case .superseded, .archived:
            return .secondary
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

    @State private var pairingSheetShown = false
    @State private var pastePayloadText = ""
    @State private var pendingPayload:
        HTDTReceiverPairingPayload?
    @State private var pairingError: String?

    var body: some View {
        List {
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
                            .foregroundStyle(.red)
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
                        .foregroundStyle(.red)
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
            HStack {
                Button("Refresh capabilities") {
                    Task {
                        await actions
                            .refreshEndpointCapabilities(
                                destination.destinationID
                            )
                    }
                }
                .font(.caption)
                Spacer()
                Button("Forget", role: .destructive) {
                    Task {
                        await actions.forgetDestination(
                            destination.destinationID
                        )
                    }
                }
                .font(.caption)
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

    private var ordered: [HTDTDeliveryJob] {
        jobs.sorted { $0.createdAtUTC > $1.createdAtUTC }
    }

    var body: some View {
        List {
            if ordered.isEmpty {
                Section {
                    Text(
                        "No deliveries queued. Endpoint sends are recorded here before any bytes move and survive app restarts."
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
        .navigationTitle("Deliveries")
    }

    @ViewBuilder
    private func jobRow(_ job: HTDTDeliveryJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.destination.name).font(.headline)
                Spacer()
                stateBadge(job.state)
            }
            Text(job.captureRevisionID.description)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
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
                    .font(.caption)
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
                    .font(.caption)
                }
                if job.state == .paused || job.state == .blocked {
                    Button("Resume") {
                        Task {
                            await actions.deliveryResume(
                                job.deliveryJobID
                            )
                        }
                    }
                    .font(.caption)
                }
                if !job.isTerminal {
                    Button("Cancel", role: .destructive) {
                        Task {
                            await actions.deliveryCancel(
                                job.deliveryJobID
                            )
                        }
                    }
                    .font(.caption)
                }
                if job.isTerminal {
                    Button("Free payload") {
                        Task {
                            await actions.deliveryPurgePayload(
                                job.deliveryJobID
                            )
                        }
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
            return .blue
        case .retryWait:
            return .orange
        case .paused:
            return .secondary
        case .blocked:
            return .orange
        case .deliveredStaged:
            return .green
        case .rejected, .failed:
            return .red
        case .cancelled:
            return .secondary
        }
    }
}
