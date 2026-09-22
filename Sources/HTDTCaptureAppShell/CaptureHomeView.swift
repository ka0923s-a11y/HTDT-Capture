import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore
import HTDTCapturePlatform
#if os(iOS)
import UIKit
#endif

/// Sidebar/detail selection for the capture-first home (#360/#362).
/// A `NavigationSplitView` drives both layouts: collapsed on compact
/// width it behaves as the normal push stack; on regular width the
/// library stays visible beside the selected series detail.
private enum CaptureHomeSelection: Hashable {
    /// A capture series in the library.
    case series(CaptureSeriesID)
    /// Quarantined artifacts, orphaned working data, enumeration
    /// failures — one bounded maintenance list instead of forensic
    /// rows inside the normal library.
    case maintenance
    /// Device capability / permission diagnostics — detail level, not
    /// permanent top-level telemetry.
    case readiness
    /// Issued HTDT missions awaiting/between capture runs (#386).
    case missions
    /// QR-paired, identity-pinned HTDT receivers (#379).
    case destinations
    /// Durable endpoint delivery queue (#387).
    case deliveries
}

/// The pending delete-local-capture confirmation: which validated
/// revision is selected and whether its canonical export slot exists.
struct PendingCaptureDeletion: Equatable {
    let revisionID: CaptureRevisionID
    let includesExport: Bool
}

/// Identifiable target for the library-metadata editor sheet (#219):
/// exactly one of `revisionID`/`seriesID` is set.
struct LibraryMetadataEditorTarget: Identifiable {
    let revisionID: CaptureRevisionID?
    let seriesID: CaptureSeriesID?
    var id: String {
        revisionID?.description
            ?? seriesID?.description
            ?? "editor"
    }
}

/// Edits an operator-facing name + note for a capture revision or a
/// whole series (#219). App-local metadata only — the capture bundle
/// on disk is never touched.
struct LibraryMetadataEditor: View {
    let revisionID: CaptureRevisionID?
    let seriesID: CaptureSeriesID?
    let document: CaptureLibraryMetadataDocument
    let onSave:
        (CaptureRevisionID?, CaptureSeriesID?,
         CaptureLibraryEntryMetadata) -> Void

    @State private var displayName: String
    @State private var note: String
    @Environment(\.dismiss) private var dismiss

    init(
        revisionID: CaptureRevisionID?,
        seriesID: CaptureSeriesID?,
        document: CaptureLibraryMetadataDocument,
        onSave: @escaping (
            CaptureRevisionID?,
            CaptureSeriesID?,
            CaptureLibraryEntryMetadata
        ) -> Void
    ) {
        self.revisionID = revisionID
        self.seriesID = seriesID
        self.document = document
        self.onSave = onSave
        let existing = revisionID.flatMap {
            document.revisions[$0.description]
        } ?? seriesID.flatMap {
            document.series[$0.description]
        }
        _displayName = State(
            initialValue: existing?.displayName ?? ""
        )
        _note = State(
            initialValue: existing?.note ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Room or project name", text: $displayName)
                TextField(
                    "Notes",
                    text: $note,
                    axis: .vertical
                )
            }
            .navigationTitle("Capture details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            revisionID,
                            seriesID,
                            CaptureLibraryEntryMetadata(
                                displayName: displayName.isEmpty
                                    ? nil
                                    : displayName,
                                note: note.isEmpty ? nil : note
                            )
                        )
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The capture-first home and series-first capture library
/// (#360/#362). Replaces the diagnostic `List` landing screen: the
/// dominant actions are New capture and Import; device readiness and
/// maintenance appear as contextual notices; the library's visual unit
/// is the theater/series row, and each revision keeps one obvious
/// primary action with the rest in context/swipe menus.
public struct CaptureHomeView: View {
    public let capabilities: CaptureCapabilityMatrix
    public let cameraPermission: CameraPermissionStatus?
    public let persistedInventory: PersistedCaptureInventoryResult
    /// App-local capture names/notes/series metadata (#219).
    public let libraryMetadata: CaptureLibraryMetadataDocument
    /// Read-only workspace for the persisted viewer (#294).
    public let persistedWorkspace: CaptureReviewWorkspaceModel?
    /// Mission inbox records (#386) and the active record id.
    public let missionRecords: [HTDTMissionRecord]
    public let activeMissionRecordID: String?
    /// QR-paired HTDT receivers (#379).
    public let pairedDestinations: [PairedHTDTDestination]
    /// Durable delivery-queue jobs (#387).
    public let deliveryJobs: [HTDTDeliveryJob]
    public let actions: CaptureRootActions

    @State private var selection: CaptureHomeSelection?
    @State private var libraryQuery = ""
    @State private var importingCaptureArchive = false
    @State private var metadataEditorTarget:
        LibraryMetadataEditorTarget?
    @State private var pendingDeletion: PendingCaptureDeletion?
    @State private var persistedViewerShown = false

    public init(
        capabilities: CaptureCapabilityMatrix,
        cameraPermission: CameraPermissionStatus? = nil,
        persistedInventory:
            PersistedCaptureInventoryResult
                = PersistedCaptureInventoryResult(),
        libraryMetadata: CaptureLibraryMetadataDocument
            = CaptureLibraryMetadataDocument(),
        persistedWorkspace: CaptureReviewWorkspaceModel? = nil,
        missionRecords: [HTDTMissionRecord] = [],
        activeMissionRecordID: String? = nil,
        pairedDestinations: [PairedHTDTDestination] = [],
        deliveryJobs: [HTDTDeliveryJob] = [],
        actions: CaptureRootActions = CaptureRootActions()
    ) {
        self.capabilities = capabilities
        self.cameraPermission = cameraPermission
        self.persistedInventory = persistedInventory
        self.libraryMetadata = libraryMetadata
        self.persistedWorkspace = persistedWorkspace
        self.missionRecords = missionRecords
        self.activeMissionRecordID = activeMissionRecordID
        self.pairedDestinations = pairedDestinations
        self.deliveryJobs = deliveryJobs
        self.actions = actions
    }

    public var body: some View {
        NavigationSplitView {
            librarySidebar
                .navigationTitle("HTDT Capture")
        } detail: {
            detailContent
        }
        .fileImporter(
            isPresented: $importingCaptureArchive,
            allowedContentTypes: [.htdtCapture],
            allowsMultipleSelection: false
        ) { result in
            guard let urls = try? result.get(),
                  let url = urls.first
            else {
                return
            }
            actions.importCaptureArchive(url)
        }
        .sheet(item: $metadataEditorTarget) { target in
            LibraryMetadataEditor(
                revisionID: target.revisionID,
                seriesID: target.seriesID,
                document: libraryMetadata,
                onSave: actions.updateLibraryEntry
            )
        }
        .confirmationDialog(
            "Delete local capture?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { presented in
                    if !presented { pendingDeletion = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { pending in
            Button(
                pending.includesExport
                    ? "Delete capture and export"
                    : "Delete capture",
                role: .destructive
            ) {
                actions.deletePersistedCapture(
                    pending.revisionID
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(
                "This permanently deletes the finalized capture and any export archive stored for it from this device."
            )
        }
    }

    // MARK: Sidebar — capture-first actions + series-first library

    @ViewBuilder
    private var librarySidebar: some View {
        List(selection: $selection) {
            Section {
                heroHeader
                Button(action: actions.beginCapture) {
                    Label("New capture", systemImage: "plus.viewfinder")
                        .font(
                            CaptureDesign.Typography
                                .taskHeadline
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .capturePrimaryAction()
                .disabled(
                    !capabilities.roomPlanMeshEligible
                )
                .accessibilityIdentifier("home.newCapture")
                Button {
                    importingCaptureArchive = true
                } label: {
                    Label(
                        "Import .htdtcapture",
                        systemImage: "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .captureSecondaryAction()
            }
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: 4,
                    leading: 0,
                    bottom: 4,
                    trailing: 0
                )
            )

            if !homeNotices.isEmpty {
                Section {
                    ForEach(
                        Array(homeNotices.enumerated()),
                        id: \.offset
                    ) { _, notice in
                        noticeRow(notice)
                    }
                }
            }

            if hasMaintenance {
                Section {
                    NavigationLink(
                        value: CaptureHomeSelection.maintenance
                    ) {
                        Label {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text("Library maintenance")
                                Text(
                                    String(
                                        format: String(
                                            localized:
                                                "%d item(s) need attention"
                                        ),
                                        maintenanceCount
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(
                                systemName:
                                    "exclamationmark.triangle"
                            )
                            .foregroundStyle(
                                CaptureColorRole.attention.color
                            )
                        }
                    }
                }
            }

            Section {
                if libraryGroups.isEmpty {
                    Text("No captures yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredLibraryGroups) { group in
                        NavigationLink(
                            value: CaptureHomeSelection.series(
                                group.captureSeriesID
                            )
                        ) {
                            seriesRow(group)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Captures")
                    Spacer()
                    if persistedInventory.totalRetainedBytes > 0 {
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount:
                                    persistedInventory
                                        .totalRetainedBytes,
                                countStyle: .file
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                    }
                }
            }

            Section {
                NavigationLink(
                    value: CaptureHomeSelection.missions
                ) {
                    Label {
                        missionRowLabel
                    } icon: {
                        Image(systemName: "tray.full")
                    }
                }
                NavigationLink(
                    value: CaptureHomeSelection.destinations
                ) {
                    Label {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text("Destinations")
                            Text(
                                String(
                                    format: String(
                                        localized:
                                            "%d paired receiver(s)"
                                    ),
                                    pairedDestinations.count
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
                NavigationLink(
                    value: CaptureHomeSelection.deliveries
                ) {
                    Label {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text("Deliveries")
                            Text(
                                deliveryRowCaption
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(
                            systemName:
                                "arrow.up.circle"
                        )
                    }
                }
                NavigationLink(
                    value: CaptureHomeSelection.readiness
                ) {
                    Label(
                        "Device readiness",
                        systemImage: "checklist"
                    )
                }
            }
        }
        .modifier(LibrarySearchModifier(query: $libraryQuery))
    }

    /// Mission inbox row caption: active mission first, then counts
    /// (#386).
    @ViewBuilder
    private var missionRowLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Missions")
            let visible = missionRecords.filter {
                $0.lifecycle != .archived
                    && $0.lifecycle != .superseded
            }
            Text(
                String(
                    format: String(
                        localized: "%d mission(s)"
                    ),
                    visible.count
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Delivery queue row caption: honest counts by state (#387).
    private var deliveryRowCaption: String {
        let pending = deliveryJobs.filter { !$0.isTerminal }
        if pending.isEmpty {
            return String(
                format: String(localized: "%d delivery job(s)"),
                deliveryJobs.count
            )
        }
        return String(
            format: String(
                localized: "%d pending of %d delivery job(s)"
            ),
            pending.count,
            deliveryJobs.count
        )
    }

    /// The app tagline + identity block above the primary actions.
    private var heroHeader: some View {
        VStack(
            alignment: .leading,
            spacing: CaptureDesign.Spacing.micro
        ) {
            Text("HTDT Capture")
                .font(.title2.weight(.semibold))
            Text(
                "Capture a room for Home Theater Digital Twin."
            )
            .font(CaptureDesign.Typography.secondary)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, CaptureDesign.Spacing.row)
        .accessibilityElement(children: .combine)
    }

    // MARK: Detail column

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .series(let seriesID):
            if let group = libraryGroups.first(where: {
                $0.captureSeriesID == seriesID
            }) {
                CaptureSeriesDetailView(
                    group: group,
                    libraryMetadata: libraryMetadata,
                    persistedWorkspace: persistedWorkspace,
                    persistedViewerShown: $persistedViewerShown,
                    metadataEditorTarget: $metadataEditorTarget,
                    pendingDeletion: $pendingDeletion,
                    actions: actions
                )
            } else {
                libraryPlaceholder
            }
        case .maintenance:
            CaptureLibraryMaintenanceView(
                inventory: persistedInventory,
                removeQuarantinedArtifact:
                    actions.removeQuarantinedArtifact,
                removeWorkingOrphan:
                    actions.removeWorkingOrphan
            )
        case .readiness:
            CaptureDeviceReadinessView(
                capabilities: capabilities,
                cameraPermission: cameraPermission
            )
        case .missions:
            HTDTMissionInboxView(
                records: missionRecords,
                activeMissionRecordID: activeMissionRecordID,
                actions: actions
            )
        case .destinations:
            PairedHTDTDestinationsView(
                destinations: pairedDestinations,
                actions: actions
            )
        case .deliveries:
            HTDTDeliveryQueueView(
                jobs: deliveryJobs,
                actions: actions
            )
        case nil:
            if libraryGroups.isEmpty {
                CaptureEmptyState(
                    symbolName: "cube.transparent",
                    title: "No captures yet",
                    message:
                        "Capture a room for Home Theater Digital Twin, or open an existing .htdtcapture archive.",
                    primaryActionTitle: "Start new capture",
                    primaryAction: actions.beginCapture,
                    secondaryActionTitle: "Import .htdtcapture",
                    secondaryAction: {
                        importingCaptureArchive = true
                    }
                )
            } else {
                libraryPlaceholder
            }
        }
    }

    private var libraryPlaceholder: some View {
        ContentUnavailableView(
            "Select a capture",
            systemImage: "house",
            description: Text(
                "Choose a theater or series to see its revisions."
            )
        )
    }

    // MARK: Sidebar rows

    @ViewBuilder
    private func noticeRow(
        _ notice: CaptureHomeNotice
    ) -> some View {
        CaptureNotice(
            status: notice.status,
            title: LocalizedStringKey(notice.titleKey),
            message: LocalizedStringKey(notice.messageKey),
            actionTitle: noticeActionTitle(notice),
            action: noticeAction(notice)
        )
        .listRowSeparator(.hidden)
        .listRowInsets(
            EdgeInsets(
                top: 2,
                leading: 0,
                bottom: 2,
                trailing: 0
            )
        )
    }

    private func noticeActionTitle(
        _ notice: CaptureHomeNotice
    ) -> LocalizedStringKey? {
        switch notice {
        case .cameraAccessRequired:
            return "Open Settings"
        default:
            return nil
        }
    }

    private func noticeAction(
        _ notice: CaptureHomeNotice
    ) -> (() -> Void)? {
        switch notice {
        case .cameraAccessRequired:
            return {
                #if os(iOS)
                if let url = URL(
                    string: UIApplication.openSettingsURLString
                ) {
                    UIApplication.shared.open(url)
                }
                #endif
            }
        default:
            return nil
        }
    }

    /// One series row: room/project identity first, then recency +
    /// revision count + concise status — never the raw UUID (#360).
    private func seriesRow(
        _ group: CaptureSeriesGroup
    ) -> some View {
        let presentation = CaptureSeriesPresentation(
            group: group,
            revisionMetadata: group.latestRevision.flatMap {
                libraryMetadata.revisions[
                    $0.captureRevisionID.description
                ]
            }
        )
        return HStack(
            spacing: CaptureDesign.Spacing.group
        ) {
            Image(systemName: "house")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(
                    .quaternary,
                    in: RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(CaptureDesign.Typography.sectionHeading)
                    .lineLimit(1)
                Text(
                    [
                        presentation.latestDateLabel,
                        presentation.revisionSummary,
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if let note = presentation.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            CaptureStatusView(presentation.status)
        }
    }

    // MARK: Derived model

    private var libraryGroups: [CaptureSeriesGroup] {
        CaptureSeriesGrouper.group(
            records: persistedInventory.captures,
            metadata: libraryMetadata
        )
    }

    private var filteredLibraryGroups: [CaptureSeriesGroup] {
        libraryGroups.filter {
            CaptureSeriesGrouper.matches(
                group: $0,
                revisionNotes: libraryMetadata.revisions,
                query: libraryQuery
            )
        }
    }

    private var maintenanceCount: Int {
        CaptureHomePresentation.maintenanceItemCount(
            persistedInventory
        )
    }

    private var hasMaintenance: Bool {
        maintenanceCount > 0
    }

    private var homeNotices: [CaptureHomeNotice] {
        CaptureHomePresentation.notices(
            cameraPermissionDenied: cameraPermission == .denied,
            cameraPermissionRestricted:
                cameraPermission == .restricted,
            deviceCaptureEligible:
                capabilities.roomPlanMeshEligible,
            storageReadiness: .unknown,
            maintenanceItemCount: maintenanceCount
        )
    }
}

/// Sidebar search placement is iPad/iOS idiomatic; elsewhere the
/// search field uses its automatic placement.
private struct LibrarySearchModifier: ViewModifier {
    @Binding var query: String

    func body(content: Content) -> some View {
        #if os(iOS)
        content.searchable(
            text: $query,
            placement: .sidebar,
            prompt: Text("Search captures")
        )
        #else
        content.searchable(
            text: $query,
            prompt: Text("Search captures")
        )
        #endif
    }
}

/// Detail column for one capture series (#360 §3.4): series name +
/// revision count up top, the latest revision's primary Open action,
/// history below; secondary and destructive actions live in
/// context/swipe menus, never as peer primary buttons.
private struct CaptureSeriesDetailView: View {
    let group: CaptureSeriesGroup
    let libraryMetadata: CaptureLibraryMetadataDocument
    let persistedWorkspace: CaptureReviewWorkspaceModel?
    @Binding var persistedViewerShown: Bool
    @Binding var metadataEditorTarget:
        LibraryMetadataEditorTarget?
    @Binding var pendingDeletion: PendingCaptureDeletion?
    let actions: CaptureRootActions

    var body: some View {
        List {
            Section {
                CaptureTaskHeader(
                    verbatimTitle: seriesTitle,
                    subtitle: LocalizedStringKey(revisionHeader),
                    status: latestStatus
                )
            }

            if let latest = group.latestRevision {
                Section("Latest") {
                    revisionRow(latest, isLatest: true)
                }
            }

            let history = Array(
                group.revisions.dropLast().reversed()
            )
            if !history.isEmpty {
                Section("History") {
                    ForEach(history) { record in
                        revisionRow(record, isLatest: false)
                    }
                }
            }

            if let note = group.metadata?.note, !note.isEmpty {
                Section("Notes") {
                    Text(note)
                        .font(CaptureDesign.Typography.secondary)
                }
            }

            Section("Details") {
                CaptureTechnicalDetail(
                    "Series ID",
                    value: group.captureSeriesID.description
                )
            }
        }
        .navigationTitle(seriesTitle)
        .inlineNavigationBarTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit series name") {
                        metadataEditorTarget =
                            LibraryMetadataEditorTarget(
                                revisionID: nil,
                                seriesID: group.captureSeriesID
                            )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(
                    String(localized: "Series actions")
                )
            }
        }
        .navigationDestination(
            isPresented: $persistedViewerShown
        ) {
            if let persistedWorkspace {
                CaptureReviewWorkspaceView(
                    model: persistedWorkspace
                )
            } else {
                ProgressView("Loading capture…")
            }
        }
    }

    private var seriesTitle: String {
        if let name = group.displayName, !name.isEmpty {
            return name
        }
        return String(localized: "Unnamed series")
    }

    private var revisionHeader: String {
        group.revisions.count == 1
            ? String(localized: "1 revision")
            : String(
                format: String(localized: "%d revisions"),
                group.revisions.count
            )
    }

    private var latestStatus: CaptureSemanticStatus {
        CaptureSeriesPresentation.status(
            for: group.latestRevision
        )
    }

    /// One revision row: human identity + concise status + storage,
    /// one primary Open action, everything else in the context menu
    /// or swipe actions (#360 §3.3).
    private func revisionRow(
        _ record: PersistedCaptureRecord,
        isLatest: Bool
    ) -> some View {
        let entry = libraryMetadata.revisions[
            record.captureRevisionID.description
        ]
        let dateLabel = CaptureSeriesPresentation.dateLabel(
            for: record.finalizedAtUTC
        ) ?? record.finalizedAtUTC
        return VStack(
            alignment: .leading,
            spacing: CaptureDesign.Spacing.micro
        ) {
            HStack(spacing: CaptureDesign.Spacing.row) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        (entry?.displayName?.isEmpty == false
                            ? entry?.displayName : nil)
                            ?? dateLabel
                    )
                    .font(CaptureDesign.Typography.sectionHeading)
                    .lineLimit(1)
                    HStack(spacing: 6) {
                        CaptureStatusView(
                            CaptureSeriesPresentation.status(
                                for: record
                            )
                        )
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount:
                                    record.retainedByteCount,
                                countStyle: .file
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let note = entry?.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if record.canOpen {
                    Button("Open") {
                        actions.loadPersistedWorkspace(record)
                        persistedViewerShown = true
                    }
                    .captureSecondaryAction()
                    .accessibilityIdentifier(
                        "library.revision.open"
                    )
                }
            }
            if isLatest {
                Text(
                    "Use this revision for review, rescan, or HTDT handoff."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            revisionMenu(record)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) {
                pendingDeletion = PendingCaptureDeletion(
                    revisionID: record.captureRevisionID,
                    includesExport: record.exportArchive != nil
                )
            }
        }
        .swipeActions(edge: .leading) {
            if record.canOpen {
                Button("Open") {
                    actions.loadPersistedWorkspace(record)
                    persistedViewerShown = true
                }
                .tint(.accentColor)
            }
        }
    }

    /// Secondary/destructive revision actions — present but visually
    /// subordinate until invoked (#360 §3.3).
    @ViewBuilder
    private func revisionMenu(
        _ record: PersistedCaptureRecord
    ) -> some View {
        if record.canOpen {
            Button("Open") {
                actions.loadPersistedWorkspace(record)
                persistedViewerShown = true
            }
            Button("Use this revision") {
                actions.openPersistedCapture(
                    record.captureRevisionID
                )
            }
        }
        if record.canOpen || record.exportArchive != nil {
            Button("Rescan as new revision") {
                actions.revisePersistedCapture(record)
            }
        }
        Button("Rename…") {
            metadataEditorTarget =
                LibraryMetadataEditorTarget(
                    revisionID: record.captureRevisionID,
                    seriesID: nil
                )
        }
        Divider()
        if record.exportArchive != nil,
           record.finalizedDirectory != nil
        {
            // The archive is a derived copy: it can be deleted
            // without touching the canonical finalized capture
            // (#251).
            Button("Delete archive copy") {
                actions.deleteExportArchive(record)
            }
        }
        Button("Delete…", role: .destructive) {
            pendingDeletion = PendingCaptureDeletion(
                revisionID: record.captureRevisionID,
                includesExport: record.exportArchive != nil
            )
        }
    }
}

/// Bounded maintenance list for quarantined artifacts, orphaned
/// working data, and enumeration failures (#360 §7): these stay
/// reachable but out of the normal theater library.
private struct CaptureLibraryMaintenanceView: View {
    let inventory: PersistedCaptureInventoryResult
    let removeQuarantinedArtifact:
        (PersistedCaptureQuarantinedArtifact) -> Void
    let removeWorkingOrphan:
        (PersistedCaptureWorkingOrphan) -> Void

    var body: some View {
        List {
            if !inventory.quarantinedArtifacts.isEmpty {
                Section("Unreadable artifacts") {
                    ForEach(inventory.quarantinedArtifacts) {
                        artifact in
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(artifact.url.lastPathComponent)
                                .font(
                                    CaptureDesign.Typography
                                        .technical
                                )
                                .textSelection(.enabled)
                            Text(artifact.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(
                                "Remove artifact",
                                role: .destructive
                            ) {
                                removeQuarantinedArtifact(
                                    artifact
                                )
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            if !inventory.orphanedWorkingArtifacts.isEmpty {
                Section("Interrupted capture files") {
                    ForEach(
                        inventory.orphanedWorkingArtifacts
                    ) { orphan in
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            LabeledContent(
                                orphan.kind
                                    == .abandonedRevision
                                    ? String(
                                        localized:
                                            "Abandoned revision"
                                    )
                                    : String(
                                        localized:
                                            "Writer temp file"
                                    ),
                                value: orphan.url
                                    .lastPathComponent
                            )
                            LabeledContent(
                                "Retained bytes",
                                value: ByteCountFormatter
                                    .string(
                                        fromByteCount: orphan
                                            .retainedBytes,
                                        countStyle: .file
                                    )
                            )
                            Button(
                                "Delete",
                                role: .destructive
                            ) {
                                removeWorkingOrphan(orphan)
                            }
                            .font(.caption)
                        }
                    }
                    Text(
                        "Left by an interrupted capture. It is never resumed as an active scan and can be safely deleted."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if !inventory.enumerationFailures.isEmpty {
                Section("Inventory issues") {
                    ForEach(
                        inventory.enumerationFailures,
                        id: \.self
                    ) { failure in
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Library maintenance")
        .inlineNavigationBarTitle()
    }
}

/// Detail-level device readiness (#360 §5): capability/permission
/// diagnostics live here instead of permanent landing rows. Problems
/// still surface directly on Home as notices.
private struct CaptureDeviceReadinessView: View {
    let capabilities: CaptureCapabilityMatrix
    let cameraPermission: CameraPermissionStatus?

    var body: some View {
        List {
            Section("Capture capability") {
                CaptureStatusContent(
                    "RoomPlan + mesh",
                    status: capabilities.roomPlanMeshEligible
                        ? .ready
                        : .unavailable
                )
                CaptureStatusContent(
                    "Scene depth",
                    status: capabilities.sceneDepthSupported
                        ? .ready
                        : .unavailable
                )
                if capabilities.requiresCombinedFeatureProbe {
                    Text(
                        "Combined RoomPlan/depth behavior still requires physical-device verification."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if let cameraPermission {
                Section("Permissions") {
                    CaptureStatusContent(
                        "Camera",
                        status: permissionStatus(
                            cameraPermission
                        )
                    )
                    if cameraPermission == .denied
                        || cameraPermission == .restricted
                    {
                        CaptureNotice(
                            status: .blocked,
                            title: "Camera access is required",
                            message:
                                "Enable camera access in Settings to scan a room.",
                            actionTitle: "Open Settings",
                            action: {
                                #if os(iOS)
                                if let url = URL(
                                    string: UIApplication
                                        .openSettingsURLString
                                ) {
                                    UIApplication.shared
                                        .open(url)
                                }
                                #endif
                            }
                        )
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .navigationTitle("Device readiness")
        .inlineNavigationBarTitle()
    }

    private func permissionStatus(
        _ status: CameraPermissionStatus
    ) -> CaptureSemanticStatus {
        switch status {
        case .authorized:
            return .ready
        case .denied, .restricted, .unavailable:
            return .blocked
        case .notDetermined:
            return .unknown
        }
    }
}
