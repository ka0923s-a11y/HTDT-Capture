import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore
import HTDTCapturePlatform
#if os(iOS)
import UIKit
#endif

/// Library filter for acquisition origin (#317): imported/received
/// captures are always visually distinct from device-created ones, so
/// the filter narrows on that axis rather than on file presence.
private enum CaptureOriginFilter: String, CaseIterable, Identifiable {
    case all
    case device
    case external
    var id: String { rawValue }
}

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
    /// Support & Diagnostics center (#389): privacy-reviewed
    /// diagnostic package export, independent of capture bundles.
    case diagnostics
}

/// The pending delete-local-capture confirmation: which validated
/// revision is selected, whether its canonical export slot exists,
/// and how many descendant revisions declare it as parent (#396 —
/// deleting a parent leaves their `parent_revision_id` refs
/// unresolved, so the confirmation names the lineage cost).
struct PendingCaptureDeletion: Equatable {
    let revisionID: CaptureRevisionID
    let includesExport: Bool
    var descendantCount: Int = 0
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
    /// #390: notice when a durable document was preserved instead of
    /// upgraded — its bytes are kept, never silently emptied.
    public let localStateUpgradeNotice: String?
    /// #378: staged library-package import preview awaiting confirm.
    public let libraryImportPreview:
        CaptureLibraryImportPreview?
    /// #378: the `.htdtcapturelibrary` the host last wrote.
    public let libraryExportURL: URL?
    /// Read-only workspace for the persisted viewer (#294).
    public let persistedWorkspace: CaptureReviewWorkspaceModel?
    /// RoomPlan bindables for the persisted workspace's read-only
    /// 3D scene and survey (#408/#409).
    public let persistedWorkspaceRoomPlanObjects:
        [RoomPlanBindableObject]
    /// Handoff receipts (#225) — the historical send record the
    /// retention previews cite (#394).
    public let handoffReceipts: [HTDTHandoffReceipt]
    /// App-local acquisition provenance per revision (#317):
    /// imported or received captures read differently from
    /// device-created ones everywhere the library surfaces them.
    public let captureOrigins:
        [CaptureRevisionID: CaptureAcquisitionOriginRecord]
    /// Mission inbox records (#386) and the active record id.
    public let missionRecords: [HTDTMissionRecord]
    public let activeMissionRecordID: String?
    /// QR-paired HTDT receivers (#379).
    public let pairedDestinations: [PairedHTDTDestination]
    /// Durable delivery-queue jobs (#387).
    public let deliveryJobs: [HTDTDeliveryJob]
    /// Accepted cross-revision spatial registrations (#395).
    public let crossRevisionRegistrations:
        [CrossRevisionRegistration]
    /// Replayed mission progress keyed by inbox record id (#397).
    public let missionProgressEvaluations:
        [String: MissionProgressEvaluation]
    public let actions: CaptureRootActions

    @State private var selection: CaptureHomeSelection?
    @State private var libraryQuery = ""
    @State private var libraryOriginFilter: CaptureOriginFilter = .all
    @State private var importingCaptureArchive = false
    @State private var metadataEditorTarget:
        LibraryMetadataEditorTarget?
    @State private var pendingDeletion: PendingCaptureDeletion?
    @State private var persistedViewerShown = false
    /// Series whose retention preview sheet is open (#394).
    @State private var retentionSeriesID: CaptureSeriesID?
    /// Series whose whole-series delete preview is open (#394).
    @State private var pendingSeriesDeletion:
        CaptureSeriesID?
    /// The explicit protected-marks override for a series delete
    /// (#394): armable only when the preview reports marked
    /// revisions.
    @State private var deleteSeriesIncludeProtected = false
    @State private var derived3DTarget: DerivedExportTarget?
    @State private var surveyReportTarget: DerivedExportTarget?
    /// Disposable bounded decode cache for library-row previews
    /// (#411) — tied to this view's lifetime, never authority.
    @State private var thumbnailCache = SeriesThumbnailCache()

    public init(
        capabilities: CaptureCapabilityMatrix,
        cameraPermission: CameraPermissionStatus? = nil,
        persistedInventory:
            PersistedCaptureInventoryResult
                = PersistedCaptureInventoryResult(),
        libraryMetadata: CaptureLibraryMetadataDocument
            = CaptureLibraryMetadataDocument(),
        localStateUpgradeNotice: String? = nil,
        libraryImportPreview:
            CaptureLibraryImportPreview? = nil,
        libraryExportURL: URL? = nil,
        persistedWorkspace: CaptureReviewWorkspaceModel? = nil,
        persistedWorkspaceRoomPlanObjects:
            [RoomPlanBindableObject] = [],
        handoffReceipts: [HTDTHandoffReceipt] = [],
        captureOrigins:
            [CaptureRevisionID: CaptureAcquisitionOriginRecord] = [:],
        missionRecords: [HTDTMissionRecord] = [],
        activeMissionRecordID: String? = nil,
        pairedDestinations: [PairedHTDTDestination] = [],
        deliveryJobs: [HTDTDeliveryJob] = [],
        crossRevisionRegistrations:
            [CrossRevisionRegistration] = [],
        missionProgressEvaluations:
            [String: MissionProgressEvaluation] = [:],
        actions: CaptureRootActions = CaptureRootActions()
    ) {
        self.capabilities = capabilities
        self.cameraPermission = cameraPermission
        self.persistedInventory = persistedInventory
        self.libraryMetadata = libraryMetadata
        self.localStateUpgradeNotice = localStateUpgradeNotice
        self.libraryImportPreview = libraryImportPreview
        self.libraryExportURL = libraryExportURL
        self.persistedWorkspace = persistedWorkspace
        self.persistedWorkspaceRoomPlanObjects =
            persistedWorkspaceRoomPlanObjects
        self.handoffReceipts = handoffReceipts
        self.captureOrigins = captureOrigins
        self.missionRecords = missionRecords
        self.activeMissionRecordID = activeMissionRecordID
        self.pairedDestinations = pairedDestinations
        self.deliveryJobs = deliveryJobs
        self.crossRevisionRegistrations =
            crossRevisionRegistrations
        self.missionProgressEvaluations =
            missionProgressEvaluations
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
            allowedContentTypes: [
                .htdtCapture, .htdtCaptureLibrary,
            ],
            allowsMultipleSelection: false
        ) { result in
            guard let urls = try? result.get(),
                  let url = urls.first
            else {
                return
            }
            // #393: the home importer uses the same inbound boundary
            // as onOpenURL — the router identifies the kind.
            actions.importInboundDocument(url)
        }
        .sheet(item: $metadataEditorTarget) { target in
            LibraryMetadataEditor(
                revisionID: target.revisionID,
                seriesID: target.seriesID,
                document: libraryMetadata,
                onSave: actions.updateLibraryEntry
            )
        }
        .sheet(
            isPresented: Binding(
                get: { libraryImportPreview != nil },
                set: { presented in
                    if !presented {
                        actions.dismissLibraryImport()
                    }
                }
            )
        ) {
            if let preview = libraryImportPreview {
                CaptureLibraryImportPreviewView(
                    preview: preview,
                    onConfirm: actions.confirmLibraryImport,
                    onDismiss: actions.dismissLibraryImport
                )
            }
        }
        .sheet(item: $retentionSeriesID) { seriesID in
            if let group = libraryGroups.first(where: {
                $0.captureSeriesID == seriesID
            }) {
                CaptureSeriesRetentionView(
                    group: group,
                    allRecords: persistedInventory.captures,
                    libraryMetadata: libraryMetadata,
                    deliveryJobs: deliveryJobs,
                    missionRecords: missionRecords,
                    handoffReceipts: handoffReceipts,
                    actions: actions,
                    onDeleteSeries: {
                        retentionSeriesID = nil
                        pendingSeriesDeletion = seriesID
                    }
                )
            }
        }
        .sheet(item: $pendingSeriesDeletion) { seriesID in
            let records = persistedInventory.captures.filter {
                $0.captureSeriesID == seriesID
            }
            let preview =
                CaptureLibraryRetentionPlanner.deletionPreview(
                    records: records,
                    allRecords: persistedInventory.captures,
                    metadata: libraryMetadata,
                    deliveryJobs: deliveryJobs,
                    missionRecords: missionRecords,
                    receipts: handoffReceipts
                )
            CaptureSeriesDeleteSheet(
                seriesID: seriesID,
                preview: preview,
                includeProtected:
                    $deleteSeriesIncludeProtected,
                onDelete: {
                    actions.deleteSeries(
                        seriesID,
                        deleteSeriesIncludeProtected
                    )
                    deleteSeriesIncludeProtected = false
                },
                onCancel: {
                    deleteSeriesIncludeProtected = false
                }
            )
        }
        .sheet(item: $derived3DTarget) { target in
            Derived3DExportSheet(target: target, actions: actions)
        }
        .sheet(item: $surveyReportTarget) { target in
            SurveyReportExportSheet(target: target, actions: actions)
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
        } message: { pending in
            if pending.descendantCount > 0 {
                Text(
                    "This permanently deletes the finalized capture and any export archive stored for it from this device. \(pending.descendantCount) revision(s) declare it as their parent — their lineage link will no longer resolve."
                )
            } else {
                Text(
                    "This permanently deletes the finalized capture and any export archive stored for it from this device."
                )
            }
        }
    }

    // MARK: Sidebar — capture-first actions + series-first library

    @ViewBuilder
    private var librarySidebar: some View {
        List(selection: $selection) {
            Section {
                heroHeader
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

            // #406: the landing answers "what next?" — one dominant
            // action card chosen by the Core presentation model,
            // never a stacked list of every possibility.
            Section {
                if homeModel.nextAction != .none {
                    Button {
                        performNextAction()
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName:
                                    nextActionSymbol
                            )
                            .font(.title3)
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(nextActionTitle)
                                    .font(
                                        CaptureDesign.Typography
                                            .taskHeadline
                                    )
                                Text(nextActionSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(
                                systemName: "chevron.right"
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .capturePrimaryAction()
                    .accessibilityIdentifier("home.nextAction")
                } else {
                    Button(action: actions.beginCapture) {
                        Label(
                            "New capture",
                            systemImage: "plus.viewfinder"
                        )
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
                }
                // The rest of the Work queue — every row is
                // actionable, informational items never list.
                ForEach(
                    remainingWorkItems
                ) { item in
                    Button {
                        performWorkItem(item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName: workItemSymbol(
                                    item.kind
                                )
                            )
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                            VStack(
                                alignment: .leading,
                                spacing: 1
                            ) {
                                Text(item.title)
                                    .font(.callout)
                                    .lineLimit(1)
                                if let subtitle = item.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(
                                systemName: "chevron.right"
                            )
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                NavigationLink(
                    value: CaptureHomeSelection.missions
                ) {
                    Label {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text("Missions")
                            Text(
                                missionsCaption
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tray.full")
                    }
                }
                Button {
                    importingCaptureArchive = true
                } label: {
                    Label(
                        "Import bundle or library",
                        systemImage: "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .captureSecondaryAction()
            } header: {
                Text("Work")
            } footer: {
                Text(
                    "Drafts, missions, and deliveries that still need you — everything else stays out of the way."
                )
            }

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

            // #390: a durable document preserved instead of upgraded
            // is surfaced once, plainly — its bytes were kept, never
            // silently emptied.
            if let localStateUpgradeNotice {
                Section {
                    Label {
                        Text(localStateUpgradeNotice)
                            .font(.caption)
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
                if activeLibraryGroups.isEmpty
                    && archivedLibraryGroups.isEmpty
                {
                    Text("No captures yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeLibraryGroups) { group in
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
                // #406: the Library intent keeps its series-first
                // identity — header carries honest totals, not the
                // full record dump.
                HStack {
                    Text("Library")
                    Text(
                        String(
                            format: String(
                                localized:
                                    "%d capture(s) · %d series"
                            ),
                            homeModel.libraryCaptureCount,
                            homeModel.librarySeriesCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.none)
                    Menu {
                        Picker(
                            String(localized: "Capture origin"),
                            selection: $libraryOriginFilter
                        ) {
                            Text(String(localized: "All"))
                                .tag(CaptureOriginFilter.all)
                            Text(
                                String(localized: "This device")
                            )
                            .tag(CaptureOriginFilter.device)
                            Text(
                                String(
                                    localized: "Imported or received"
                                )
                            )
                            .tag(CaptureOriginFilter.external)
                        }
                    } label: {
                        Image(
                            systemName:
                                libraryOriginFilter == .all
                                    ? "line.3.horizontal.decrease.circle"
                                    : "line.3.horizontal.decrease.circle.fill"
                        )
                        .accessibilityLabel(
                            String(localized: "Capture origin")
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
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

            // #394: archived series leave the default view but keep
            // every revision, receipt and mission link — searchable
            // under their own section.
            if !archivedLibraryGroups.isEmpty {
                Section("Archived") {
                    ForEach(archivedLibraryGroups) { group in
                        NavigationLink(
                            value: CaptureHomeSelection.series(
                                group.captureSeriesID
                            )
                        ) {
                            seriesRow(group)
                        }
                    }
                }
            }

            // #406: the Send & connections intent — pairing,
            // transfers, and package export. The delivery badge
            // counts only actionable jobs.
            Section {
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
                            .foregroundStyle(
                                homeModel.send
                                    .actionableCount > 0
                                    ? CaptureColorRole
                                        .attention.color
                                    : .secondary
                            )
                        }
                    } icon: {
                        Image(
                            systemName:
                                "arrow.up.circle"
                        )
                    }
                }
                // #378: one-tap whole-library package export; the
                // written `.htdtcapturelibrary` shares via the same
                // affordance once the host publishes it.
                Button {
                    actions.exportLibraryPackage()
                } label: {
                    Label(
                        "Export library package",
                        systemImage:
                            "square.and.arrow.up.on.square"
                    )
                    .frame(maxWidth: .infinity)
                }
                .captureSecondaryAction()
                if let libraryExportURL {
                    ShareLink(item: libraryExportURL) {
                        Label(
                            "Share library package",
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .captureSecondaryAction()
                }
            } header: {
                Text("Send & connections")
            }

            // #406: device administration stays contextual —
            // readiness surfaces only when something needs a
            // decision; diagnostics is the always-available support
            // entry at the very bottom.
            Section {
                if !homeModel.readinessAttentions
                    .isEmpty
                {
                    NavigationLink(
                        value: CaptureHomeSelection.readiness
                    ) {
                        Label {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text("Device readiness")
                                Text(
                                    homeModel
                                        .readinessAttentions
                                        .first?.label
                                        ?? ""
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    CaptureColorRole
                                        .attention.color
                                )
                            }
                        } icon: {
                            Image(
                                systemName:
                                    "exclamationmark.triangle"
                            )
                            .foregroundStyle(
                                CaptureColorRole
                                    .attention.color
                            )
                        }
                    }
                }
                NavigationLink(
                    value: CaptureHomeSelection.diagnostics
                ) {
                    Label(
                        "Support & Diagnostics",
                        systemImage: "stethoscope"
                    )
                }
            } header: {
                Text("Device")
            }
        }
        .modifier(LibrarySearchModifier(query: $libraryQuery))
    }

    /// The Home IA v2 presentation model (issue #406): everything
    /// this surface shows — the dominant next action, the Work
    /// queue, per-intent badges — is derived in Core so the "what do
    /// I do next?" logic is unit-tested and can't drift from the
    /// raw lists.
    private var homeModel: CaptureHomeModel {
        let mostRecentRevision = persistedInventory.captures
            .max {
                $0.finalizedAtUTC < $1.finalizedAtUTC
            }?.captureRevisionID
        return CaptureHomeModel(
            recoverableDrafts: persistedInventory
                .recoverableDrafts,
            missions: missionRecords,
            activeMissionRecordID: activeMissionRecordID,
            deliveryJobs: deliveryJobs,
            pairedDestinationCount: pairedDestinations.count,
            libraryCaptureCount: persistedInventory.captures
                .count,
            librarySeriesCount: Set(
                persistedInventory.captures
                    .map(\.captureSeriesID)
            ).count,
            mostRecentRevisionID: mostRecentRevision,
            maintenance: HomeMaintenanceSummary(
                quarantinedArtifactCount:
                    persistedInventory.quarantinedArtifacts
                        .count,
                workingOrphanCount:
                    persistedInventory
                        .orphanedWorkingArtifacts.count,
                enumerationFailureCount:
                    persistedInventory.enumerationFailures
                        .count
            ),
            readinessAttentions: readinessAttentions,
            captureAvailable: capabilities
                .roomPlanMeshEligible
        )
    }

    /// #406 §5: readiness surfaces only on a real attention item —
    /// denied/restricted camera, or a device that can't scan.
    private var readinessAttentions:
        [HomeReadinessAttention]
    {
        var items: [HomeReadinessAttention] = []
        if cameraPermission == .denied
            || cameraPermission == .restricted
        {
            items.append(
                HomeReadinessAttention(
                    kind: .cameraPermissionDenied,
                    label: "Camera access needs attention"
                )
            )
        }
        if !capabilities.roomPlanMeshEligible {
            items.append(
                HomeReadinessAttention(
                    kind: .spatialCaptureUnavailable,
                    label: "Spatial capture unavailable on this device"
                )
            )
        }
        return items
    }

    /// Work-queue rows minus the one the dominant card already
    /// covers — the card and the list never double-surface the
    /// same item.
    private var remainingWorkItems: [HomeWorkItem] {
        let cardIdentity: String? = {
            switch homeModel.nextAction {
            case .resumeDraft(let draft):
                return draft.url.path
            case .continueMission(let record),
                 .startMission(let record):
                return record.recordID
            case .retryDelivery(let job):
                return job.deliveryJobID
            case .openRecentArtifact(let revisionID):
                return revisionID.description
            case .newCapture, .none:
                return nil
            }
        }()
        return homeModel.workItems.filter {
            $0.identity != cardIdentity
        }
        .prefix(6)
        .map { $0 }
    }

    private var missionsCaption: String {
        let actionable = homeModel.actionableMissions.count
        if actionable > 0 {
            return String(
                format: String(
                    localized: "%d actionable mission(s)"
                ),
                actionable
            )
        }
        let visible = missionRecords.filter {
            $0.lifecycle != .archived
                && $0.lifecycle != .superseded
        }
        return String(
            format: String(
                localized: "%d mission(s)"
            ),
            visible.count
        )
    }

    // MARK: Next-action card

    private var nextActionTitle: String {
        switch homeModel.nextAction {
        case .resumeDraft:
            return String(localized: "Resume draft")
        case .continueMission(let record):
            return record.purpose ?? record.missionID
        case .startMission(let record):
            return record.purpose ?? record.missionID
        case .newCapture:
            return String(localized: "New capture")
        case .openRecentArtifact:
            return String(
                localized: "Review latest capture"
            )
        case .retryDelivery:
            return String(
                localized: "Delivery needs attention"
            )
        case .none:
            return ""
        }
    }

    private var nextActionSubtitle: String {
        switch homeModel.nextAction {
        case .resumeDraft(let draft):
            return draft.revisionID.description
        case .continueMission:
            return String(
                localized: "Mission in progress — continue"
            )
        case .startMission(let record):
            return record.lifecycle == .blockedDependency
                ? String(
                    localized:
                        "Mission ready — dependencies unmet"
                )
                : String(
                    localized: "Mission ready — start"
                )
        case .newCapture:
            return String(
                localized:
                    "Capture a room for Home Theater Digital Twin"
            )
        case .openRecentArtifact(let revisionID):
            return revisionID.description
        case .retryDelivery(let job):
            return job.lastError
                ?? String(
                    localized: "The queue needs a decision"
                )
        case .none:
            return ""
        }
    }

    private var nextActionSymbol: String {
        switch homeModel.nextAction {
        case .resumeDraft:
            return "arrow.clockwise"
        case .continueMission, .startMission:
            return "tray.full"
        case .newCapture:
            return "plus.viewfinder"
        case .openRecentArtifact:
            return "doc.magnifyingglass"
        case .retryDelivery:
            return "exclamationmark.arrow.up.circle"
        case .none:
            return "questionmark"
        }
    }

    private func performNextAction() {
        switch homeModel.nextAction {
        case .resumeDraft(let draft):
            actions.openRecoveredDraft(draft)
        case .continueMission:
            selection = .missions
        case .startMission(let record):
            if record.lifecycle == .blockedDependency {
                selection = .missions
            } else {
                Task {
                    await actions.startMission(
                        record.recordID
                    )
                }
            }
        case .newCapture:
            actions.beginCapture()
        case .openRecentArtifact(let revisionID):
            openRevisionInLibrary(revisionID)
        case .retryDelivery:
            selection = .deliveries
        case .none:
            break
        }
    }

    private func workItemSymbol(
        _ kind: HomeWorkItem.Kind
    ) -> String {
        switch kind {
        case .resumeDraft:
            return "arrow.clockwise"
        case .continueMission, .startMission:
            return "tray.full"
        case .missionFollowUp:
            return "exclamationmark.bubble"
        case .retryDelivery:
            return "exclamationmark.arrow.up.circle"
        case .reviewArtifact:
            return "doc.magnifyingglass"
        }
    }

    private func performWorkItem(
        _ item: HomeWorkItem
    ) {
        switch item.kind {
        case .resumeDraft:
            if let draft = persistedInventory
                .recoverableDrafts.first(where: {
                    $0.url.path == item.identity
                })
            {
                actions.openRecoveredDraft(draft)
            }
        case .continueMission, .startMission,
             .missionFollowUp:
            selection = .missions
        case .retryDelivery:
            selection = .deliveries
        case .reviewArtifact:
            if let revisionID = CaptureRevisionID(
                canonicalString: item.identity
            ) {
                openRevisionInLibrary(revisionID)
            }
        }
    }

    /// Select the series containing a revision — review happens in
    /// the series detail column, keeping the landing
    /// series-first.
    private func openRevisionInLibrary(
        _ revisionID: CaptureRevisionID
    ) {
        guard let record = persistedInventory.captures
            .first(where: {
                $0.captureRevisionID == revisionID
            })
        else {
            return
        }
        selection = .series(record.captureSeriesID)
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
                    persistedWorkspaceRoomPlanObjects:
                        persistedWorkspaceRoomPlanObjects,
                    allRecords: persistedInventory.captures,
                    deliveryJobs: deliveryJobs,
                    missionRecords: missionRecords,
                    handoffReceipts: handoffReceipts,
                    persistedViewerShown: $persistedViewerShown,
                    metadataEditorTarget: $metadataEditorTarget,
                    pendingDeletion: $pendingDeletion,
                    retentionSeriesID: $retentionSeriesID,
                    pendingSeriesDeletion: $pendingSeriesDeletion,
                    derived3DTarget: $derived3DTarget,
                    surveyReportTarget: $surveyReportTarget,
                    captureOrigins: captureOrigins,
                    crossRevisionRegistrations:
                        crossRevisionRegistrations,
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
                    actions.removeWorkingOrphan,
                openRecoveredDraft:
                    actions.openRecoveredDraft,
                discardRecoveredDraft:
                    actions.discardRecoveredDraft
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
                progressEvaluations: missionProgressEvaluations,
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
        case .diagnostics:
            SupportDiagnosticsView(actions: actions)
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
            revisionMetadata: (group.preferredRevision
                ?? group.latestRevision).flatMap {
                libraryMetadata.revisions[
                    $0.captureRevisionID.description
                ]
            }
        )
        return HStack(
            spacing: CaptureDesign.Spacing.group
        ) {
            SeriesThumbnailView(
                group: group,
                cache: thumbnailCache
            )
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
        }.filter { group in
            group.revisions.contains(where: matchesOriginFilter)
        }
    }

    /// Whether a library record matches the selected origin filter
    /// (#317). Records with no origin entry count as device-created
    /// under `.all`/`.device` — pre-tracking captures surface as
    /// "origin unknown" rather than silently claiming local
    /// provenance.
    private func matchesOriginFilter(
        _ record: PersistedCaptureRecord
    ) -> Bool {
        let kind =
            captureOrigins[record.captureRevisionID]?.kind
                ?? .legacyUnknown
        switch libraryOriginFilter {
        case .all:
            return true
        case .device:
            return kind == .createdOnThisDevice
                || kind == .legacyUnknown
        case .external:
            return kind == .importedFile
                || kind == .receivedFromHTDT
                || kind == .sharedOther
        }
    }

    /// #394: archived series are filtered out of the default list
    /// into their own section; archiving never changes which
    /// revisions exist, only where they are listed.
    private var activeLibraryGroups: [CaptureSeriesGroup] {
        filteredLibraryGroups.filter {
            !libraryMetadata.seriesState(
                for: $0.captureSeriesID
            ).archived
        }
    }

    private var archivedLibraryGroups: [CaptureSeriesGroup] {
        filteredLibraryGroups.filter {
            libraryMetadata.seriesState(
                for: $0.captureSeriesID
            ).archived
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
            prompt: Text("Search library")
        )
        #else
        content.searchable(
            text: $query,
            prompt: Text("Search library")
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
    /// RoomPlan bindables for the persisted viewer's read-only
    /// 3D scene and survey (#408/#409).
    let persistedWorkspaceRoomPlanObjects:
        [RoomPlanBindableObject]
    /// Every persisted record — the retention previews read
    /// cross-series lineage (parents) from it (#394).
    let allRecords: [PersistedCaptureRecord]
    let deliveryJobs: [HTDTDeliveryJob]
    let missionRecords: [HTDTMissionRecord]
    let handoffReceipts: [HTDTHandoffReceipt]
    @Binding var persistedViewerShown: Bool
    @Binding var metadataEditorTarget:
        LibraryMetadataEditorTarget?
    @Binding var pendingDeletion: PendingCaptureDeletion?
    @Binding var retentionSeriesID: CaptureSeriesID?
    @Binding var pendingSeriesDeletion: CaptureSeriesID?
    @Binding var derived3DTarget: DerivedExportTarget?
    @Binding var surveyReportTarget: DerivedExportTarget?
    let captureOrigins:
        [CaptureRevisionID: CaptureAcquisitionOriginRecord]
    /// Accepted cross-revision registrations — candidate transform
    /// authorities presented on the detail column (#395); endpoints
    /// are drawn from `allRecords`.
    let crossRevisionRegistrations:
        [CrossRevisionRegistration]
    let actions: CaptureRootActions

    /// Pending registration flow (#395): the revision the operator
    /// chose to align, the picked counterpart, the inspected proposal,
    /// and any failure text.
    @State private var registrationSource:
        PersistedCaptureRecord?
    @State private var registrationTarget:
        PersistedCaptureRecord?
    @State private var registrationProposal:
        CrossRevisionRegistrationSolve?
    @State private var registrationError: String?
    @State private var registrationBusy = false
    @State private var registrationSheetShown = false

    /// The revision the "Latest" surface presents (#396): the stored
    /// preferred head when the graph is branched and the pick is
    /// still valid, the single head otherwise, or nil while a branch
    /// has no accepted pick — newest `finalized_at` never wins on its
    /// own.
    private var presentedRevision: PersistedCaptureRecord? {
        group.preferredRevision
    }

    private var seriesArchived: Bool {
        libraryMetadata.seriesState(
            for: group.captureSeriesID
        ).archived
    }

    var body: some View {
        List {
            Section {
                CaptureTaskHeader(
                    verbatimTitle: seriesTitle,
                    subtitle: LocalizedStringKey(revisionHeader),
                    status: latestStatus
                )
            }

            if let presented = presentedRevision {
                Section(
                    group.isBranched
                        ? "Preferred head" : "Latest"
                ) {
                    revisionRow(presented, isLatest: true)
                }
            }

            if group.isBranched {
                Section("Branch heads") {
                    ForEach(group.headRevisions) { record in
                        headRow(record)
                    }
                    if group.storedPreferredHead == nil {
                        Text(
                            "Several heads exist — pick a preferred head so the series shows one Latest. Newest by date is never assumed."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Button("Clear preferred head") {
                            actions.preferRevisionHead(
                                group.captureSeriesID,
                                nil
                            )
                        }
                        .font(.caption)
                    }
                }
            }

            let history = group.revisions.filter {
                $0.captureRevisionID
                    != presentedRevision?.captureRevisionID
            }.reversed()
            if !history.isEmpty {
                Section("History") {
                    ForEach(Array(history)) { record in
                        revisionRow(record, isLatest: false)
                    }
                }
            }

            spatialLineageSection

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
                if seriesArchived {
                    CaptureTechnicalDetail(
                        "Lifecycle",
                        value: String(localized: "Archived")
                    )
                }
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
                    // #394: archive removes the series from the
                    // default library without touching a single
                    // bundle byte; unarchive restores it.
                    if seriesArchived {
                        Button("Unarchive series") {
                            actions.setSeriesArchived(
                                group.captureSeriesID,
                                false
                            )
                        }
                    } else {
                        Button("Archive series") {
                            actions.setSeriesArchived(
                                group.captureSeriesID,
                                true
                            )
                        }
                    }
                    // #394: the retention preview — bytes,
                    // recommendations, blockers — before any delete
                    // affordance exists.
                    Button("Review storage…") {
                        retentionSeriesID =
                            group.captureSeriesID
                    }
                    Divider()
                    Button("Delete series…", role: .destructive) {
                        pendingSeriesDeletion =
                            group.captureSeriesID
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
                    model: persistedWorkspace,
                    roomPlanObjects:
                        persistedWorkspaceRoomPlanObjects
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
            for: presentedRevision ?? group.latestRevision
        )
    }

    /// One branch head in the heads section (#396): the same identity
    /// treatment as a revision row plus a preferred marker and the
    /// prefer action — the pick writes app-local metadata only.
    private func headRow(
        _ record: PersistedCaptureRecord
    ) -> some View {
        let isPreferred = group.effectivePreferredHeadID
            == record.captureRevisionID
        return HStack(spacing: CaptureDesign.Spacing.row) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    CaptureSeriesPresentation.dateLabel(
                        for: record.finalizedAtUTC
                    ) ?? record.finalizedAtUTC
                )
                .font(CaptureDesign.Typography.sectionHeading)
                .lineLimit(1)
                HStack(spacing: 6) {
                    CaptureStatusView(
                        CaptureSeriesPresentation.status(
                            for: record
                        )
                    )
                    if isPreferred {
                        Text("Preferred head")
                            .font(.caption)
                            .foregroundStyle(
                                CaptureColorRole.accent.color
                            )
                    }
                }
            }
            Spacer(minLength: 4)
            if !isPreferred {
                Button("Prefer") {
                    actions.preferRevisionHead(
                        group.captureSeriesID,
                        record.captureRevisionID
                    )
                }
                .captureSecondaryAction()
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            revisionMenu(record)
        }
    }

    /// Cross-revision spatial registration surface (#395): accepted
    /// registrations involving this series, the resolved path between
    /// every head pair (direct vs chained, with accumulated
    /// uncertainty), and the explicit register action.
    @ViewBuilder
    private var spatialLineageSection: some View {
        let revisionIDs = Set(
            group.revisions.map(\.captureRevisionID)
        )
        let involving = crossRevisionRegistrations.filter {
            revisionIDs.contains($0.sourceRevisionID)
                || revisionIDs.contains($0.targetRevisionID)
        }
        let heads = group.headRevisions
        let graph = CrossRevisionRegistrationGraph(
            registrations: crossRevisionRegistrations
        )
        Section("Spatial lineage") {
            ForEach(involving) { registration in
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "\(shortRevisionID(registration.sourceRevisionID)) → \(shortRevisionID(registration.targetRevisionID))"
                    )
                    .font(CaptureDesign.Typography.sectionHeading)
                    Text(
                        "\(mechanismLabel(registration.mechanism)) · RMS \(metersLabel(registration.rmsMeters)) · max \(metersLabel(registration.maxResidualMeters)) · \(registration.scalePolicy == .rigidOnly ? "rigid" : "scale \(scaleLabel(registration.uniformScale))")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if heads.count > 1 {
                ForEach(0..<(heads.count - 1), id: \.self) { i in
                    ForEach((i + 1)..<heads.count, id: \.self) { j in
                        headPathRow(
                            from: heads[i],
                            to: heads[j],
                            path: graph.resolve(
                                from: heads[i].captureRevisionID,
                                to: heads[j].captureRevisionID
                            )
                        )
                    }
                }
            }
            if involving.isEmpty && heads.count < 2 {
                Text(
                    "No spatial registrations link this series' revisions to other captures yet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button("Register spatial link…") {
                registrationSource = nil
                registrationTarget = nil
                registrationProposal = nil
                registrationError = nil
                registrationSheetShown = true
            }
        }
        .sheet(isPresented: $registrationSheetShown) {
            NavigationStack {
                registrationSheet
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// Resolved transform path between two branch heads — direct
    /// edge, chained path with accumulated uncertainty, or an honest
    /// "no registered path" (#395).
    private func headPathRow(
        from source: PersistedCaptureRecord,
        to target: PersistedCaptureRecord,
        path: CrossRevisionTransformPath
    ) -> some View {
        let label: String
        switch path {
        case .identity:
            label = "same revision"
        case .direct(let registration):
            label = "direct registration · uncertainty \(metersLabel(registration.uncertaintyMeters))"
        case .chained(let registrations, _, let uncertainty):
            label = "chained via \(registrations.count) registration(s) · uncertainty \(metersLabel(uncertainty))"
        case .unresolved:
            label = "no registered spatial path"
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(
                "\(shortRevisionID(source.captureRevisionID)) → \(shortRevisionID(target.captureRevisionID))"
            )
            .font(CaptureDesign.Typography.sectionHeading)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The register-a-spatial-link flow (#395): pick source and
    /// target revisions, inspect the proposed transform's residuals,
    /// then explicitly accept — never registered silently.
    @ViewBuilder
    private var registrationSheet: some View {
        List {
            Section("Source revision") {
                ForEach(allRecords) { record in
                    Button {
                        registrationSource = record
                        registrationProposal = nil
                        registrationError = nil
                    } label: {
                        registrationPickRow(
                            record,
                            selected:
                                registrationSource?
                                .captureRevisionID
                                == record.captureRevisionID
                        )
                    }
                }
            }
            if let source = registrationSource {
                Section("Target revision") {
                    ForEach(
                        allRecords.filter {
                            $0.captureRevisionID
                                != source.captureRevisionID
                        }
                    ) { record in
                        Button {
                            registrationTarget = record
                            registrationProposal = nil
                            registrationError = nil
                        } label: {
                            registrationPickRow(
                                record,
                                selected:
                                    registrationTarget?
                                    .captureRevisionID
                                    == record.captureRevisionID
                            )
                        }
                    }
                }
            }
            if registrationSource != nil,
               registrationTarget != nil
            {
                Section {
                    Button {
                        registrationBusy = true
                        registrationError = nil
                        let source = registrationSource!
                        let target = registrationTarget!
                        Task {
                            let proposal = await actions
                                .proposeRevisionAlignment(
                                    source.captureRevisionID,
                                    target.captureRevisionID
                                )
                            registrationBusy = false
                            if let proposal {
                                registrationProposal = proposal
                            } else {
                                registrationError =
                                    "The pair could not be aligned — a shared field datum must exist in both revisions and yield at least three non-degenerate correspondences."
                            }
                        }
                    } label: {
                        if registrationBusy {
                            ProgressView()
                        } else {
                            Text(
                                "Preview shared-field-datum alignment"
                            )
                        }
                    }
                    .disabled(registrationBusy)
                } footer: {
                    Text(
                        "Alignment is derived from the room field datum recorded in each revision — rigid transform only; residuals are shown before anything is recorded."
                    )
                    .font(.caption)
                }
            }
            if let proposal = registrationProposal {
                Section("Proposed alignment") {
                    ForEach(proposal.residuals) { residual in
                        LabeledContent(
                            residual.ref,
                            value: metersLabel(
                                residual.residualMeters
                            )
                        )
                        .font(.caption.monospaced())
                    }
                    LabeledContent(
                        "RMS residual",
                        value: metersLabel(proposal.rmsMeters)
                    )
                    LabeledContent(
                        "Max residual",
                        value: metersLabel(
                            proposal.maxResidualMeters
                        )
                    )
                    LabeledContent(
                        "Scale policy",
                        value: "rigid"
                    )
                }
                Section {
                    Button("Accept registration") {
                        registrationBusy = true
                        let source = registrationSource!
                        let target = registrationTarget!
                        Task {
                            let accepted = await actions
                                .acceptRevisionAlignment(
                                    source.captureRevisionID,
                                    target.captureRevisionID
                                )
                            registrationBusy = false
                            if accepted != nil {
                                registrationSheetShown = false
                            } else {
                                registrationError =
                                    "The registration was refused — a registration for this revision pair already exists."
                            }
                        }
                    }
                    .disabled(registrationBusy)
                } footer: {
                    Text(
                        "Accepting records an immutable transform authority; it never rewrites either revision."
                    )
                    .font(.caption)
                }
            }
            if let error = registrationError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Register spatial link")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    registrationSheetShown = false
                }
            }
        }
    }

    private func registrationPickRow(
        _ record: PersistedCaptureRecord,
        selected: Bool
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    CaptureSeriesPresentation.dateLabel(
                        for: record.finalizedAtUTC
                    ) ?? record.finalizedAtUTC
                )
                Text(shortRevisionID(record.captureRevisionID))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(
                        CaptureColorRole.accent.color
                    )
            }
        }
    }

    private func shortRevisionID(
        _ revisionID: CaptureRevisionID
    ) -> String {
        String(revisionID.description.prefix(8))
    }

    private func metersLabel(_ meters: Double) -> String {
        String(format: "%.3f m", meters)
    }

    private func scaleLabel(_ scale: Double) -> String {
        String(format: "×%.4f", scale)
    }

    private func mechanismLabel(
        _ kind: CrossRevisionCorrespondenceKind
    ) -> String {
        switch kind {
        case .sharedFieldDatum:
            return String(localized: "shared field datum")
        case .referenceTarget:
            return String(localized: "reference targets")
        case .manualPoint:
            return String(localized: "manual points")
        }
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
                        Text(originLabel(for: record))
                            .font(.caption)
                            .foregroundStyle(
                                isExternalOrigin(record)
                                    ? CaptureColorRole.accent.color
                                    : .secondary
                            )
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
                    includesExport: record.exportArchive != nil,
                    descendantCount: group.revisionGraph
                        .descendants(
                            of: record.captureRevisionID
                        ).count
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

    /// #394: the revision's importance marks — milestone,
    /// keep-local, favorite, pinned. Toggles write through the
    /// metadata store; a marked revision is skipped by any delete
    /// unless the operator explicitly overrides.
    @ViewBuilder
    private func revisionMarksMenu(
        _ record: PersistedCaptureRecord
    ) -> some View {
        let mark = libraryMetadata.revisionMark(
            for: record.captureRevisionID
        )
        Menu {
            Toggle(
                "Milestone",
                isOn: Binding(
                    get: { mark.milestone },
                    set: { value in
                        var updated = mark
                        updated.milestone = value
                        actions.updateRevisionMark(
                            record.captureRevisionID,
                            updated
                        )
                    }
                )
            )
            Toggle(
                "Keep on this device",
                isOn: Binding(
                    get: { mark.keepLocal },
                    set: { value in
                        var updated = mark
                        updated.keepLocal = value
                        actions.updateRevisionMark(
                            record.captureRevisionID,
                            updated
                        )
                    }
                )
            )
            Toggle(
                "Favorite",
                isOn: Binding(
                    get: { mark.favorite },
                    set: { value in
                        var updated = mark
                        updated.favorite = value
                        actions.updateRevisionMark(
                            record.captureRevisionID,
                            updated
                        )
                    }
                )
            )
            Toggle(
                "Pinned",
                isOn: Binding(
                    get: { mark.pinned },
                    set: { value in
                        var updated = mark
                        updated.pinned = value
                        actions.updateRevisionMark(
                            record.captureRevisionID,
                            updated
                        )
                    }
                )
            )
        } label: {
            Label(
                mark.isProtected ? "Marks (protected)" : "Marks…",
                systemImage: mark.isProtected
                    ? "bookmark.fill" : "bookmark"
            )
        }
    }

    /// Acquisition-provenance badge for a row (#317): device
    /// captures carry their ordinary label; anything imported or
    /// received is additionally color-distinguished so external
    /// bundles never read as device-created.
    private func originLabel(
        for record: PersistedCaptureRecord
    ) -> String {
        switch
        captureOrigins[record.captureRevisionID]?.kind
            ?? .legacyUnknown
        {
        case .createdOnThisDevice:
            return String(
                localized: "Created on this device"
            )
        case .importedFile:
            return String(localized: "Imported file")
        case .receivedFromHTDT:
            return String(
                localized: "Received from HTDT"
            )
        case .sharedOther:
            return String(localized: "Shared")
        case .legacyUnknown:
            return String(localized: "Origin unknown")
        }
    }

    private func isExternalOrigin(
        _ record: PersistedCaptureRecord
    ) -> Bool {
        switch
        captureOrigins[record.captureRevisionID]?.kind
            ?? .legacyUnknown
        {
        case .importedFile, .receivedFromHTDT, .sharedOther:
            return true
        case .createdOnThisDevice, .legacyUnknown:
            return false
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
        if group.isBranched,
           group.effectivePreferredHeadID
               != record.captureRevisionID,
           group.revisionGraph.heads.contains(
               record.captureRevisionID
           )
        {
            Button("Prefer as series head") {
                actions.preferRevisionHead(
                    group.captureSeriesID,
                    record.captureRevisionID
                )
            }
        }
        if record.canOpen {
            Button("Correct metadata…") {
                actions.beginSemanticCorrection(record)
            }
            .accessibilityIdentifier(
                "library.correctMetadata"
            )
        }
        Button("Rename…") {
            metadataEditorTarget =
                LibraryMetadataEditorTarget(
                    revisionID: record.captureRevisionID,
                    seriesID: nil
                )
        }
        // #394: importance marks protect the revision in retention
        // previews and block delete unless the operator arms the
        // explicit override.
        revisionMarksMenu(record)
        if record.canOpen {
            Menu("Export…") {
                Button("Derived 3D model…") {
                    derived3DTarget = DerivedExportTarget(
                        revisionID: record.captureRevisionID,
                        displayName:
                            libraryMetadata.revisions[
                                record.captureRevisionID
                                    .description
                            ]?.displayName
                    )
                }
                Button("Survey report…") {
                    surveyReportTarget = DerivedExportTarget(
                        revisionID: record.captureRevisionID,
                        displayName:
                            libraryMetadata.revisions[
                                record.captureRevisionID
                                    .description
                            ]?.displayName
                    )
                }
            }
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
                includesExport: record.exportArchive != nil,
                descendantCount: group.revisionGraph
                    .descendants(
                        of: record.captureRevisionID
                    ).count
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
    let openRecoveredDraft:
        (RecoverableWorkingRevision) -> Void
    let discardRecoveredDraft:
        (RecoverableWorkingRevision) -> Void

    private func localizedRevisionPhase(
        _ phase: WorkingRevisionPhase
    ) -> String {
        switch phase {
        case .liveScanIncomplete:
            return String(localized: "Scan interrupted")
        case .endAccepted:
            return String(localized: "Ended; ready for review")
        case .semanticAuthoring:
            return String(
                localized: "Ended; annotations in progress"
            )
        case .readyToFinalize:
            return String(localized: "Ready to finalize")
        }
    }

    var body: some View {
        List {
            if !inventory.recoverableDrafts.isEmpty {
                Section("Recoverable drafts") {
                    ForEach(inventory.recoverableDrafts) { draft in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(
                                localizedRevisionPhase(draft.phase),
                                value: draft.url.lastPathComponent
                            )
                            LabeledContent(
                                "Retained bytes",
                                value: ByteCountFormatter.string(
                                    fromByteCount: draft.retainedBytes,
                                    countStyle: .file
                                )
                            )
                            if !draft.unsupportedPaths.isEmpty {
                                Text(
                                    String(
                                        format: String(
                                            localized:
                                                "%d unsupported file(s) kept"
                                        ),
                                        draft.unsupportedPaths.count
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Reopen for review") {
                                    openRecoveredDraft(draft)
                                }
                                Button(
                                    "Discard draft",
                                    role: .destructive
                                ) {
                                    discardRecoveredDraft(draft)
                                }
                            }
                            .font(.caption)
                        }
                    }
                    Text(
                        "An Ended capture whose data survived an interruption. Reopening restores Review with spatial capture sealed — you can finish annotations and finalize, but you cannot resume scanning."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
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

/// The staged `.htdtcapturelibrary` import preview (issue #378):
/// every manifest entry with its disposition — new, duplicate,
/// conflict, or invalid — plus the metadata-merge and receipt
/// counts the commit would apply. Commit is explicit; nothing here
/// has touched the capture root yet.
private struct CaptureLibraryImportPreviewView: View {
    let preview: CaptureLibraryImportPreview
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    private func dispositionLabel(
        _ disposition: CaptureLibraryImportDisposition
    ) -> String {
        switch disposition {
        case .newSeries:
            return String(localized: "New series")
        case .newRevisionInKnownSeries:
            return String(localized: "New revision")
        case .duplicate:
            return String(localized: "Duplicate")
        case .conflict:
            return String(localized: "Conflict — kept local")
        case .invalid:
            return String(localized: "Invalid")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(
                        "Revisions to import",
                        value: String(preview.importableCount)
                    )
                    LabeledContent(
                        "Metadata entries adopted",
                        value: String(
                            preview.metadataAdoptions
                        )
                    )
                    LabeledContent(
                        "Receipts to append",
                        value: String(
                            preview.receiptsToAppend
                        )
                    )
                    Text(
                        "Exact archive bytes are installed verbatim; conflicting local revisions are never overwritten."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Section("Revisions") {
                    ForEach(
                        preview.entries,
                        id: \.captureRevisionID
                    ) { entry in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            HStack {
                                Text(
                                    entry.captureRevisionID
                                        .description
                                )
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                Spacer()
                                Text(
                                    dispositionLabel(
                                        entry.disposition
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !preview.metadataConflicts.isEmpty {
                    Section("Metadata kept local") {
                        ForEach(
                            preview.metadataConflicts
                        ) { conflict in
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(conflict.identity)
                                    .font(.caption.monospaced())
                                Text(
                                    "Local values were kept; the package values were not imported."
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import library package")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        preview.importableCount > 0
                            ? "Import \(preview.importableCount) revision(s)"
                            : "Done"
                    ) {
                        if preview.importableCount > 0 {
                            onConfirm()
                        } else {
                            onDismiss()
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Per-revision retention preview for one series (issue #394):
/// latest + marked revisions recommend keep, every byte class is
/// listed separately, blockers and warnings are named before any
/// delete action exists — the derived-archives-only cleanup is
/// always the safest first suggestion.
private struct CaptureSeriesRetentionView: View {
    let group: CaptureSeriesGroup
    let allRecords: [PersistedCaptureRecord]
    let libraryMetadata: CaptureLibraryMetadataDocument
    let deliveryJobs: [HTDTDeliveryJob]
    let missionRecords: [HTDTMissionRecord]
    let handoffReceipts: [HTDTHandoffReceipt]
    let actions: CaptureRootActions
    let onDeleteSeries: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var preview: CaptureSeriesRetentionPreview {
        CaptureLibraryRetentionPlanner.seriesPreview(
            seriesID: group.captureSeriesID,
            records: group.revisions,
            allRecords: allRecords,
            metadata: libraryMetadata,
            deliveryJobs: deliveryJobs,
            missionRecords: missionRecords,
            receipts: handoffReceipts
        )
    }

    private func blockerLabel(
        _ blocker: CaptureRetentionBlocker
    ) -> String {
        switch blocker {
        case .pendingDeliveryJob(let jobID):
            return String(
                format: String(
                    localized:
                        "Pending delivery job %@"
                ),
                jobID
            )
        case .protectedMark:
            return String(
                localized: "Protected mark"
            )
        }
    }

    private func warningLabel(
        _ warning: CaptureRetentionWarning
    ) -> String {
        switch warning {
        case .parentOfRevisions(let count):
            return String(
                format: String(
                    localized:
                        "Parent of %d revision(s) on this device"
                ),
                count
            )
        case .handoffReceipts(let count):
            return String(
                format: String(
                    localized:
                        "%d handoff receipt(s) remain as history; the bytes will no longer be inspectable"
                ),
                count
            )
        case .linkedToMission(let recordID):
            return String(
                format: String(
                    localized: "Linked to mission %@"
                ),
                recordID
            )
        case .onlyLocalCopy:
            return String(
                localized:
                    "No delivered receipt — this is the only local copy"
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(
                        "Revisions",
                        value: String(
                            preview.revisionCount
                        )
                    )
                    LabeledContent(
                        "Finalized bytes",
                        value: ByteCountFormatter.string(
                            fromByteCount:
                                preview.totalFinalizedBytes,
                            countStyle: .file
                        )
                    )
                    LabeledContent(
                        "Derived archive bytes",
                        value: ByteCountFormatter.string(
                            fromByteCount:
                                preview
                                    .totalDerivedArchiveBytes,
                            countStyle: .file
                        )
                    )
                    if preview.blockedCount > 0 {
                        Text(
                            String(
                                format: String(
                                    localized:
                                        "%d revision(s) are protected or blocked"
                                ),
                                preview.blockedCount
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            CaptureColorRole.attention.color
                        )
                    }
                }
                Section("Revisions") {
                    ForEach(preview.rows) { row in
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            HStack {
                                Text(
                                    row.isLatest
                                        ? "Latest"
                                        : row.recommendation
                                            == .keep
                                            ? "Keep"
                                            : "Delete candidate"
                                )
                                .font(.caption.bold())
                                .foregroundStyle(
                                    row.recommendation == .keep
                                        ? .primary
                                        : CaptureColorRole
                                            .attention.color
                                )
                                Spacer()
                                Text(
                                    ByteCountFormatter.string(
                                        fromByteCount:
                                            row
                                                .finalizedByteCount
                                                + row
                                                    .archiveByteCount,
                                        countStyle: .file
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Text(
                                row.captureRevisionID
                                    .description
                            )
                            .font(.caption2.monospaced())
                            if row.mark.isProtected {
                                Text(
                                    "Marked: milestone/keep/favorite/pinned — delete needs the explicit override"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            if row.archiveByteCount > 0 {
                                Text(
                                    ByteCountFormatter.string(
                                        fromByteCount:
                                            row.archiveByteCount,
                                        countStyle: .file
                                    ) + " derived archive"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            ForEach(
                                row.blockers,
                                id: \.self
                            ) { blocker in
                                Label(
                                    blockerLabel(blocker),
                                    systemImage:
                                        "exclamationmark.triangle"
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    CaptureColorRole
                                        .attention.color
                                )
                            }
                            ForEach(
                                row.warnings,
                                id: \.self
                            ) { warning in
                                Text(warningLabel(warning))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section {
                    // The safest first suggestion (#394): derived
                    // archive copies leave nothing unrecoverable —
                    // the canonical finalized bundles stay.
                    Button("Delete derived archives only") {
                        for record in group.revisions
                        where record.exportArchive != nil
                            && record.finalizedDirectory != nil
                        {
                            actions.deleteExportArchive(record)
                        }
                    }
                    .disabled(
                        preview.totalDerivedArchiveBytes == 0
                    )
                    Button(
                        "Delete series…",
                        role: .destructive
                    ) {
                        dismiss()
                        onDeleteSeries()
                    }
                }
            }
            .navigationTitle("Storage review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The whole-series delete preview (issue #394): revision count,
/// finalized + derived bytes, per-revision blockers, and the
/// protected-marks override — explicit and dependency-aware before
/// anything leaves the device.
private struct CaptureSeriesDeleteSheet: View {
    let seriesID: CaptureSeriesID
    let preview: CaptureLibraryDeletionPreview
    @Binding var includeProtected: Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var protectedCount: Int {
        preview.outcomes.filter {
            $0.blockers.contains(.protectedMark)
        }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(
                        "Revisions",
                        value: String(
                            preview.revisionCount
                        )
                    )
                    LabeledContent(
                        "Finalized bytes",
                        value: ByteCountFormatter.string(
                            fromByteCount:
                                preview.finalizedByteCount,
                            countStyle: .file
                        )
                    )
                    LabeledContent(
                        "Derived archive bytes",
                        value: ByteCountFormatter.string(
                            fromByteCount:
                                preview
                                    .derivedArchiveByteCount,
                            countStyle: .file
                        )
                    )
                    if preview.blockedCount > 0 {
                        LabeledContent(
                            "Blocked",
                            value: String(
                                preview.blockedCount
                            )
                        )
                    }
                    if preview.containsExportOnlyRecords {
                        Text(
                            "Some revisions were imported as archives — their local finalized bytes were already absent."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                if protectedCount > 0 {
                    Section {
                        Toggle(
                            "Delete protected revisions too",
                            isOn: $includeProtected
                        )
                        Text(
                            "\(protectedCount) revision(s) carry an importance mark. Leave this off to keep them."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Section("Per revision") {
                    ForEach(preview.outcomes) { outcome in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                outcome.captureRevisionID
                                    .description
                            )
                            .font(.caption.monospaced())
                            ForEach(
                                outcome.blockers,
                                id: \.self
                            ) { blocker in
                                Text(
                                    blockerSummary(blocker)
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    CaptureColorRole
                                        .attention.color
                                )
                            }
                            ForEach(
                                outcome.warnings,
                                id: \.self
                            ) { warning in
                                Text(
                                    warningSummary(warning)
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Delete series?")
            .toolbar {
                ToolbarItem(
                    placement: .destructiveAction
                ) {
                    Button(
                        "Delete \(deletableCount) revision(s)",
                        role: .destructive
                    ) {
                        dismiss()
                        onDelete()
                    }
                    .disabled(deletableCount == 0)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onCancel()
                    }
                }
            }
        }
    }

    private var deletableCount: Int {
        preview.outcomes.filter {
            $0.canDelete || includeProtected
                && $0.blockers.allSatisfy {
                    $0 == .protectedMark
                }
        }.count
    }

    private func blockerSummary(
        _ blocker: CaptureRetentionBlocker
    ) -> String {
        switch blocker {
        case .pendingDeliveryJob(let jobID):
            return String(
                format: String(
                    localized:
                        "Blocked by pending delivery job %@"
                ),
                jobID
            )
        case .protectedMark:
            return String(
                localized: "Protected — kept unless overridden"
            )
        }
    }

    private func warningSummary(
        _ warning: CaptureRetentionWarning
    ) -> String {
        switch warning {
        case .parentOfRevisions(let count):
            return String(
                format: String(
                    localized:
                        "Parent of %d local revision(s); they will show an absent predecessor"
                ),
                count
            )
        case .handoffReceipts(let count):
            return String(
                format: String(
                    localized:
                        "%d receipt(s) stay as history; the bytes will no longer be inspectable"
                ),
                count
            )
        case .linkedToMission(let recordID):
            return String(
                format: String(
                    localized: "Linked to mission %@"
                ),
                recordID
            )
        case .onlyLocalCopy:
            return String(
                localized:
                    "Only local copy — nothing proves it exists elsewhere"
            )
        }
    }
}
