import Foundation
import SwiftUI
import HTDTCaptureCore

/// Rack-first equipment inventory workflow (#402): rapid repeated
/// capture over the existing `SystemInventoryItem` authority — catalog
/// selection, #345 label-scan assist, rack-slot placement
/// observations, Mission expected-vs-observed linking, and duplicate
/// warnings. The generic authority editor remains the advanced path;
/// this surface never asks for manual ID/version/SHA entry or spatial
/// XYZ.
struct EquipmentInventoryView: View {
    let coordinateSpaceID: CoordinateSpaceID
    let entities: [CaptureAnnotationEntity]
    let availableEvidenceRefs: [String]
    let equipmentCatalogEntries: [HTDTEquipmentCatalogEntry]
    let equipmentRecents: EquipmentRecents
    let scanEquipmentLabel: (() async throws -> EquipmentLabelScanResult)?
    var taskPlanStatus: Binding<CaptureTaskPlanStatus>?
    @Binding var authorities: TheaterAuthorityCollection

    @State private var query = ""
    @State private var rackFilter: AnnotationEntityID?
    @State private var roomOnlyFilter = false
    @State private var classFilter: InventoryEquipmentClass?
    @State private var unresolvedOnly = false
    @State private var serialMissingOnly = false
    @State private var missionPendingOnly = false
    @State private var presenting = false
    @State private var presentingWithScan = false
    @State private var editingItem: SystemInventoryItem?
    @State private var linkingItem: HTDTTaskPlanSemanticItem?
    @State private var errorText: String?

    /// Rack + class carried across "save & add next" (#402 §2).
    @State private var preservedRack: AnnotationEntityID?
    @State private var preservedClass: InventoryEquipmentClass?
    /// Mission task a freshly saved item should fulfill (#402 §18).
    @State private var pendingMissionItemID: String?

    private var rackEntities: [CaptureAnnotationEntity] {
        entities.filter { $0.type == .equipmentRack }
    }

    private func rackLabel(_ id: AnnotationEntityID?) -> String {
        entities.first(where: { $0.entityID == id })?.label
            ?? String(localized: "Rack")
    }

    private var expectedInventoryTasks: [HTDTTaskPlanSemanticItem] {
        taskPlanStatus?.wrappedValue.planImport.plan.semanticTasks
            .filter { $0.semanticKind == .inventoryItem } ?? []
    }

    private var outcomes:
        [CaptureTaskPlanStatusDocument.ItemOutcome]
    {
        guard let taskPlanStatus else { return [] }
        return taskPlanStatus.wrappedValue.itemOutcomes(
            annotations: entities,
            measurements: [],
            authorities: authorities,
            committedEvidenceRefs: availableEvidenceRefs
        )
    }

    /// Item IDs currently bound to an expected-inventory task.
    private var boundItemIDs: Set<AuthorityRecordID> {
        var ids = Set<AuthorityRecordID>()
        guard let taskPlanStatus else { return ids }
        let expectedIDs = Set(expectedInventoryTasks.map(\.itemID))
        for (itemID, fulfillment) in taskPlanStatus.wrappedValue
            .fulfillments where expectedIDs.contains(itemID)
        {
            if case let .authorityRecord(recordID) = fulfillment {
                ids.insert(recordID)
            }
        }
        return ids
    }

    private func filtered(_ items: [SystemInventoryItem])
        -> [SystemInventoryItem]
    {
        items.filter { item in
            if let classFilter, item.equipmentClass != classFilter {
                return false
            }
            if unresolvedOnly, item.equipmentRef != nil { return false }
            if serialMissingOnly, item.serialNumber != nil {
                return false
            }
            if missionPendingOnly, boundItemIDs.contains(item.itemID) {
                return false
            }
            if !query.isEmpty {
                let haystack = [
                    item.userLabel, item.manufacturer, item.model,
                    item.serialNumber, item.equipmentRef?.equipmentID,
                ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
                guard haystack.contains(query.lowercased()) else {
                    return false
                }
            }
            return true
        }
    }

    private func placementLine(
        for item: SystemInventoryItem
    ) -> String? {
        guard let placement = authorities.rackPlacements(
            for: item.itemID
        ).first else { return nil }
        var parts: [String] = []
        if let position = placement.rackUnitPosition {
            parts.append(
                String(
                    format: String(localized: "U%lld"),
                    position
                )
            )
        }
        if let slot = placement.shelfSlotLabel { parts.append(slot) }
        if let facing = placement.facing {
            parts.append(
                TheaterAuthorityPresentation.rackFacingName(facing)
            )
        }
        if !placement.evidenceRefs.isEmpty {
            parts.append(
                String(
                    format: String(
                        localized: "%lld evidence"
                    ),
                    placement.evidenceRefs.count
                )
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func taskLabel(for itemID: AuthorityRecordID) -> String? {
        guard let taskPlanStatus else { return nil }
        let tasks = expectedInventoryTasks
        for (taskID, fulfillment) in taskPlanStatus.wrappedValue
            .fulfillments
        {
            guard case let .authorityRecord(recordID) = fulfillment,
                  recordID == itemID,
                  let task = tasks.first(where: {
                      $0.itemID == taskID
                  })
            else { continue }
            return task.label ?? task.itemID
        }
        return nil
    }

    var body: some View {
        List {
            summarySection
            expectedSection
            ForEach(rackEntities, id: \.entityID) { rack in
                rackSection(rack)
            }
            roomSection
            actionSection
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(CaptureColorRole.blocked.color)
            }
        }
        .searchable(
            text: $query,
            prompt: String(localized: "Label, model, or serial")
        )
        .navigationTitle(String(localized: "Equipment inventory"))
        .sheet(isPresented: $presenting) {
            formSheet(
                editing: nil,
                rack: preservedRack,
                equipmentClass: preservedClass,
                startWithScan: false
            )
        }
        .sheet(isPresented: $presentingWithScan) {
            formSheet(
                editing: nil,
                rack: preservedRack,
                equipmentClass: preservedClass,
                startWithScan: true
            )
        }
        .sheet(item: $editingItem) { item in
            formSheet(
                editing: item,
                rack: item.hostRackEntityID,
                equipmentClass: item.equipmentClass,
                startWithScan: false
            )
        }
        .sheet(item: $linkingItem) { item in
            linkSheet(item)
        }
    }

    private func formSheet(
        editing: SystemInventoryItem?,
        rack: AnnotationEntityID?,
        equipmentClass: InventoryEquipmentClass?,
        startWithScan: Bool
    ) -> some View {
        NavigationStack {
            InventoryItemFormSheet(
                editing: editing,
                coordinateSpaceID: coordinateSpaceID,
                entities: entities,
                equipmentCatalogEntries: equipmentCatalogEntries,
                equipmentRecents: equipmentRecents,
                scanEquipmentLabel: scanEquipmentLabel,
                authorities: authorities,
                initialRack: rack,
                initialClass: equipmentClass,
                startWithScan: startWithScan,
                onSave: { item, placement in
                    applyItem(item, placement: placement)
                },
                onEditExisting: { item in
                    editingItem = item
                }
            )
        }
    }

    private func applyItem(
        _ item: SystemInventoryItem,
        placement: RackPlacementObservation?
    ) {
        do {
            var next = authorities
            // Rack cleared or moved — stale placements for the item
            // drop first so the pair never disagrees (#402 §9).
            for old in authorities.rackPlacements(for: item.itemID) {
                next = try next.removingRackPlacement(old.placementID)
            }
            next = try next.upsertingInventoryItem(
                item,
                placement: placement
            )
            authorities = next
            // The rack that just saved becomes the next item's
            // default — repeated rack capture (#402 §2).
            preservedRack = item.hostRackEntityID ?? preservedRack
            preservedClass = item.equipmentClass
            if let pendingMissionItemID {
                try taskPlanStatus?.wrappedValue.fulfill(
                    itemID: pendingMissionItemID,
                    with: item.itemID,
                    in: next
                )
                self.pendingMissionItemID = nil
            }
            errorText = nil
        } catch {
            errorText = String(describing: error)
        }
    }

    // MARK: Sections

    private var summarySection: some View {
        let items = authorities.inventoryItems
        let resolved = items.filter { $0.equipmentRef != nil }.count
        let serials = items.filter { $0.serialNumber != nil }.count
        let pendingExpected = expectedInventoryTasks.filter { task in
            outcomes.first(where: { $0.itemID == task.itemID })?.outcome
                != .completed
        }.count
        let duplicates = items.filter {
            !authorities.inventoryDuplicateCandidates(for: $0).isEmpty
        }.count
        return Section {
            LabeledContent(
                String(localized: "Observed"),
                value: String(items.count)
            )
            LabeledContent(
                String(localized: "Exact models resolved"),
                value: String(resolved)
            )
            LabeledContent(
                String(localized: "Serials recorded"),
                value: String(serials)
            )
            if !expectedInventoryTasks.isEmpty {
                LabeledContent(
                    String(localized: "Expected items pending"),
                    value: String(pendingExpected)
                )
            }
            if duplicates > 0 {
                LabeledContent(
                    String(localized: "Possible duplicates"),
                    value: String(duplicates)
                )
                .foregroundStyle(CaptureColorRole.attention.color)
            }
            Text(
                String(localized:
                    "Workflow status — not evidence. Serial-bearing evidence is included in the Field Return sent to HTDT.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var expectedSection: some View {
        if !expectedInventoryTasks.isEmpty {
            Section(String(localized: "Expected / requested")) {
                ForEach(
                    expectedInventoryTasks,
                    id: \.itemID
                ) { task in
                    expectedRow(task)
                }
            }
        }
    }

    private func expectedRow(
        _ task: HTDTTaskPlanSemanticItem
    ) -> some View {
        let outcome = outcomes.first { $0.itemID == task.itemID }
        let completed = outcome?.outcome == .completed
        let boundRecordID: AuthorityRecordID? = {
            guard let taskPlanStatus,
                  case let .authorityRecord(id) = taskPlanStatus
                      .wrappedValue.fulfillments[task.itemID]
            else { return nil }
            return id
        }()
        let boundItem = boundRecordID.flatMap { id in
            authorities.inventoryItems.first { $0.itemID == id }
        }
        let className = task.expectedSubtype.flatMap {
            InventoryEquipmentClass(rawValue: $0)
        }.map(TheaterAuthorityPresentation.inventoryClassName)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(
                    systemName: completed
                        ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(completed ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.label ?? className ?? task.itemID)
                    Text(
                        [
                            className,
                            task.requirement == .required
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
            if completed, let boundItem {
                Text(
                    String(localized: "Observed: ") + boundItem.userLabel
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button(String(localized: "Unbind")) {
                    markResult {
                        try taskPlanStatus?.wrappedValue
                            .clearFulfillment(itemID: task.itemID)
                    }
                }
                .font(.callout)
            } else {
                HStack(spacing: 12) {
                    Button(String(localized: "Add device")) {
                        preservedRack = nil
                        preservedClass = task.expectedSubtype.flatMap {
                            InventoryEquipmentClass(rawValue: $0)
                        }
                        pendingMissionItemID = task.itemID
                        presenting = true
                    }
                    Button(String(localized: "Link observed item")) {
                        linkingItem = task
                    }
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func rackSection(
        _ rack: CaptureAnnotationEntity
    ) -> some View {
        let items = filtered(
            authorities.inventoryItems.filter {
                $0.hostRackEntityID == rack.entityID
            }
        ).sorted { lhs, rhs in
            let lPos = authorities.rackPlacements(for: lhs.itemID)
                .first?.rackUnitPosition
            let rPos = authorities.rackPlacements(for: rhs.itemID)
                .first?.rackUnitPosition
            switch (lPos, rPos) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.userLabel < rhs.userLabel
            }
        }
        if let rackFilter, rackFilter != rack.entityID {
            EmptyView()
        } else if roomOnlyFilter {
            EmptyView()
        } else if !items.isEmpty {
            Section(
                rack.label
                    + String(
                        format: String(localized: " — %lld items"),
                        items.count
                    )
            ) {
                ForEach(items, id: \.itemID) { item in
                    itemRow(item)
                }
            }
        }
    }

    @ViewBuilder private var roomSection: some View {
        let items = filtered(
            authorities.inventoryItems.filter {
                $0.hostRackEntityID == nil
            }
        )
        if !items.isEmpty, rackFilter == nil {
            Section(
                String(localized: "Room / not in rack")
                    + String(
                        format: String(localized: " — %lld items"),
                        items.count
                    )
            ) {
                ForEach(items, id: \.itemID) { item in
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: SystemInventoryItem) -> some View {
        Button {
            editingItem = item
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(itemDisplayName(item))
                    Text(
                        [
                            TheaterAuthorityPresentation
                                .inventoryClassName(item.equipmentClass),
                            placementLine(for: item),
                            item.serialNumber == nil
                                ? nil
                                : String(localized: "serial recorded"),
                            item.equipmentRef == nil
                                ? String(localized: "catalog unresolved")
                                : String(localized: "catalog resolved"),
                            taskLabel(for: item.itemID),
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func itemDisplayName(_ item: SystemInventoryItem) -> String {
        if let ref = item.equipmentRef,
           let entry = equipmentCatalogEntries.first(where: {
               $0.definitionID == ref.equipmentID
                   && $0.version == ref.equipmentVersion
           })
        {
            return entry.displayName
        }
        let text = [item.manufacturer, item.model]
            .compactMap { $0 }
            .joined(separator: " ")
        return text.isEmpty ? item.userLabel : text
    }

    private var actionSection: some View {
        Section {
            Button {
                preservedRack = nil
                preservedClass = nil
                pendingMissionItemID = nil
                presenting = true
            } label: {
                Label(
                    String(localized: "Add device"),
                    systemImage: "plus"
                )
            }
            if let scanEquipmentLabel {
                Button {
                    preservedRack = nil
                    preservedClass = nil
                    pendingMissionItemID = nil
                    presentingWithScan = true
                } label: {
                    Label(
                        String(localized: "Scan next label"),
                        systemImage: "barcode.viewfinder"
                    )
                }
            }
            filterControls
        }
    }

    private var filterControls: some View {
        Group {
            Picker(
                String(localized: "Rack"),
                selection: $rackFilter
            ) {
                DescribedPickerOption(
                    title: String(localized: "All locations"),
                    detail: String(localized:
                        "Show equipment everywhere — racks and room equipment together.")
                )
                .tag(AnnotationEntityID?.none)
                ForEach(rackEntities, id: \.entityID) { rack in
                    DescribedPickerOption(
                        title: rack.label,
                        detail: String(localized:
                            "Show only equipment mounted in this rack.")
                    )
                    .tag(AnnotationEntityID?.some(rack.entityID))
                }
            }
            .disabled(roomOnlyFilter)
            Toggle(
                String(localized: "Room equipment only"),
                isOn: $roomOnlyFilter
            )
            Picker(
                String(localized: "Class"),
                selection: $classFilter
            ) {
                DescribedPickerOption(
                    title: String(localized: "All classes"),
                    detail: String(localized:
                        "Show every equipment class, unfiltered.")
                )
                .tag(InventoryEquipmentClass?.none)
                ForEach(
                    InventoryEquipmentClass.allCases,
                    id: \.self
                ) { value in
                    DescribedPickerOption(
                        title: TheaterAuthorityPresentation
                            .inventoryClassName(value),
                        detail: TheaterAuthorityPresentation
                            .inventoryClassDescription(value)
                    )
                    .tag(InventoryEquipmentClass?.some(value))
                }
            }
            Toggle(
                String(localized: "Unresolved catalog only"),
                isOn: $unresolvedOnly
            )
            Toggle(
                String(localized: "Serial missing only"),
                isOn: $serialMissingOnly
            )
            if !expectedInventoryTasks.isEmpty {
                Toggle(
                    String(localized: "Not linked to Mission"),
                    isOn: $missionPendingOnly
                )
            }
        }
        .font(.callout)
    }

    private func linkSheet(
        _ task: HTDTTaskPlanSemanticItem
    ) -> some View {
        NavigationStack {
            Form {
                let candidates = authorities.inventoryItems.filter {
                    task.expectedSubtype == nil
                        || $0.equipmentClass.rawValue
                            == task.expectedSubtype
                }
                if candidates.isEmpty {
                    Text(
                        String(localized:
                            "No matching items yet — add one first.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                ForEach(candidates, id: \.itemID) { item in
                    Button {
                        markResult {
                            try taskPlanStatus?.wrappedValue.fulfill(
                                itemID: task.itemID,
                                with: item.itemID,
                                in: authorities
                            )
                        }
                        linkingItem = nil
                    } label: {
                        DescribedPickerOption(
                            title: itemDisplayName(item),
                            detail: TheaterAuthorityPresentation
                                .inventoryClassName(
                                    item.equipmentClass
                                )
                        )
                    }
                }
            }
            .navigationTitle(String(localized: "Link item"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        linkingItem = nil
                    }
                }
            }
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
}

/// One inventory-item add/edit form (#402 §2/§3/§4): catalog selection
/// over manual tuples, label-scan assist, rack slot/facing fields
/// producing a `RackPlacementObservation`, duplicate warnings that
/// never auto-merge, and Save&add/scan-next repetition that preserves
/// rack context but clears device identity.
private struct InventoryItemFormSheet: View {
    enum SaveMode { case done, addNext, scanNext }

    let editing: SystemInventoryItem?
    let coordinateSpaceID: CoordinateSpaceID
    let entities: [CaptureAnnotationEntity]
    let equipmentCatalogEntries: [HTDTEquipmentCatalogEntry]
    let equipmentRecents: EquipmentRecents
    let scanEquipmentLabel: (() async throws -> EquipmentLabelScanResult)?
    let authorities: TheaterAuthorityCollection
    let initialRack: AnnotationEntityID?
    let initialClass: InventoryEquipmentClass?
    let startWithScan: Bool
    let onSave: (
        SystemInventoryItem,
        RackPlacementObservation?
    ) -> Void
    let onEditExisting: (SystemInventoryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var seeded = false
    @State private var equipmentClass: InventoryEquipmentClass =
        .avReceiver
    @State private var userLabel = ""
    @State private var manufacturer = ""
    @State private var model = ""
    @State private var serialNumber = ""
    @State private var hostRackSelection: AnnotationEntityID?
    @State private var rackUnitText = ""
    @State private var shelfSlotLabel = ""
    @State private var facing: RackFacing?
    @State private var selectedCatalogKey: String?
    @State private var showingCatalogPicker = false
    @State private var scanningLabel = false
    @State private var scanResult: EquipmentLabelScanResult?
    @State private var scanEvidenceRefs: [String] = []
    @State private var duplicates: [SystemInventoryItem] = []
    @State private var duplicateAcknowledged = false
    @State private var pendingSaveMode: SaveMode = .done
    @State private var editingPlacementID: AuthorityRecordID?
    @State private var editingPlacementEvidence: [String] = []
    @State private var errorText: String?
    @State private var savedNotice: String?

    private var rackEntities: [CaptureAnnotationEntity] {
        entities.filter { $0.type == .equipmentRack }
    }

    private var selectedEntry: HTDTEquipmentCatalogEntry? {
        equipmentCatalogEntries.first {
            $0.selectionKey == selectedCatalogKey
        }
    }

    var body: some View {
        Form {
            if let savedNotice {
                Text(savedNotice)
                    .font(.caption)
                    .foregroundStyle(CaptureColorRole.success.color)
            }
            Section(String(localized: "Device")) {
                Picker(
                    String(localized: "Class"),
                    selection: $equipmentClass
                ) {
                    ForEach(
                        InventoryEquipmentClass.allCases,
                        id: \.self
                    ) { value in
                        DescribedPickerOption(
                            title: TheaterAuthorityPresentation
                                .inventoryClassName(value),
                            detail: TheaterAuthorityPresentation
                                .inventoryClassDescription(value)
                        )
                        .tag(value)
                    }
                }
                TextField(
                    String(localized: "Label (required)"),
                    text: $userLabel
                )
                TextField(
                    String(localized: "Manufacturer (optional)"),
                    text: $manufacturer
                )
                TextField(
                    String(localized: "Model (optional)"),
                    text: $model
                )
                TextField(
                    String(localized: "Serial (optional)"),
                    text: $serialNumber
                )
                Text(
                    String(localized:
                        "Serial is optional evidence — it is included in the Field Return artifact sent to HTDT.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(String(localized: "Catalog")) {
                Button {
                    showingCatalogPicker = true
                } label: {
                    Label(
                        selectedEntry?.displayName
                            ?? String(localized: "Choose from catalog"),
                        systemImage: "shippingbox"
                    )
                }
                .disabled(equipmentCatalogEntries.isEmpty)
                if let selectedEntry {
                    LabeledContent(
                        String(localized: "Definition"),
                        value: selectedEntry.definitionID + " · "
                            + selectedEntry.version
                    )
                    .font(.caption)
                    Button(String(localized: "Clear selection")) {
                        selectedCatalogKey = nil
                    }
                    .font(.callout)
                } else {
                    Text(
                        String(localized:
                            "No catalog match — manufacturer/model stay an unresolved observation.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let scanEquipmentLabel {
                    Button {
                        scanLabel(scanEquipmentLabel)
                    } label: {
                        Label(
                            scanningLabel
                                ? String(localized: "Scanning label…")
                                : String(localized:
                                    "Scan equipment label"),
                            systemImage: "barcode.viewfinder"
                        )
                    }
                    .disabled(scanningLabel)
                }
                if !scanEvidenceRefs.isEmpty {
                    LabeledContent(
                        String(localized: "Label photos"),
                        value: String(scanEvidenceRefs.count)
                    )
                    .font(.caption)
                }
            }

            Section(String(localized: "Rack")) {
                Picker(
                    String(localized: "Rack"),
                    selection: $hostRackSelection
                ) {
                    DescribedPickerOption(
                        title: String(localized: "No rack / room equipment"),
                        detail: String(localized:
                            "The item stands in the room — not mounted in a rack.")
                    )
                    .tag(AnnotationEntityID?.none)
                    ForEach(rackEntities, id: \.entityID) { rack in
                        DescribedPickerOption(
                            title: rack.label,
                            detail: String(localized:
                                "Mount the item in this rack.")
                        )
                        .tag(AnnotationEntityID?.some(rack.entityID))
                    }
                }
                if hostRackSelection != nil {
                    TextField(
                        String(localized: "Rack unit (optional)"),
                        text: $rackUnitText
                    )
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    TextField(
                        String(localized: "Slot label (optional)"),
                        text: $shelfSlotLabel
                    )
                    Picker(
                        String(localized: "Facing (optional)"),
                        selection: $facing
                    ) {
                        DescribedPickerOption(
                            title: String(localized: "Not recorded"),
                            detail: String(localized:
                                "The unit's facing in the rack was not recorded.")
                        )
                        .tag(RackFacing?.none)
                        ForEach(
                            RackFacing.allCases,
                            id: \.self
                        ) { value in
                            DescribedPickerOption(
                                title: TheaterAuthorityPresentation
                                    .rackFacingName(value),
                                detail: TheaterAuthorityPresentation
                                    .rackFacingDescription(value)
                            )
                            .tag(RackFacing?.some(value))
                        }
                    }
                }
                Text(
                    String(localized:
                        "Rack slot is an observation separate from the unit's identity — moving slots never changes model/serial.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !duplicates.isEmpty {
                Section(
                    String(localized: "Possible existing item")
                ) {
                    ForEach(duplicates, id: \.itemID) { candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                [
                                    candidate.manufacturer,
                                    candidate.model,
                                ]
                                .compactMap { $0 }
                                .joined(separator: " ")
                                + " · "
                                + TheaterAuthorityPresentation
                                    .inventoryClassName(
                                        candidate.equipmentClass
                                    )
                            )
                            if let serial = candidate.serialNumber {
                                Text(
                                    String(localized: "Serial: ")
                                        + serial
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Button(
                                String(localized:
                                    "Update / verify existing")
                            ) {
                                onEditExisting(candidate)
                                dismiss()
                            }
                            .font(.callout)
                        }
                    }
                    Button(String(localized: "Create separate unit")) {
                        duplicateAcknowledged = true
                        save(pendingSaveMode)
                    }
                    .font(.callout)
                    Text(
                        String(localized:
                            "Two same-model units may be separate devices — nothing merges automatically.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(CaptureColorRole.blocked.color)
            }

            Section {
                Button(String(localized: "Save & add next")) {
                    save(.addNext)
                }
                .disabled(userLabel.isEmpty)
                if scanEquipmentLabel != nil {
                    Button(String(localized: "Save & scan next")) {
                        save(.scanNext)
                    }
                    .disabled(userLabel.isEmpty)
                }
            }
        }
        .navigationTitle(
            editing == nil
                ? String(localized: "Add device")
                : String(localized: "Edit device")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) { save(.done) }
                    .disabled(userLabel.isEmpty)
            }
        }
        .sheet(isPresented: $showingCatalogPicker) {
            NavigationStack {
                EquipmentCatalogPickerSheet(
                    entries: equipmentCatalogEntries,
                    currentSelectionKey: selectedCatalogKey,
                    recents: equipmentRecents
                ) { entry in
                    selectedCatalogKey = entry.selectionKey
                    if manufacturer.isEmpty {
                        manufacturer = entry.manufacturer ?? ""
                    }
                    if model.isEmpty {
                        model = entry.model ?? ""
                    }
                    if userLabel.isEmpty {
                        userLabel = entry.displayName
                    }
                }
            }
        }
        .sheet(item: $scanResult) { result in
            NavigationStack {
                EquipmentLabelScanSheet(result: result) { candidate in
                    applyScanCandidate(candidate, from: result)
                }
            }
        }
        .onAppear {
            seedIfNeeded()
            if startWithScan, let scanEquipmentLabel {
                scanLabel(scanEquipmentLabel)
            }
        }
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        if let editing {
            equipmentClass = editing.equipmentClass
            userLabel = editing.userLabel
            manufacturer = editing.manufacturer ?? ""
            model = editing.model ?? ""
            serialNumber = editing.serialNumber ?? ""
            hostRackSelection = editing.hostRackEntityID
            if let ref = editing.equipmentRef {
                selectedCatalogKey = equipmentCatalogEntries.first {
                    $0.definitionID == ref.equipmentID
                        && $0.version == ref.equipmentVersion
                }?.selectionKey
            }
            if let placement = authorities.rackPlacements(
                for: editing.itemID
            ).first {
                editingPlacementID = placement.placementID
                rackUnitText = placement.rackUnitPosition
                    .map(String.init) ?? ""
                shelfSlotLabel = placement.shelfSlotLabel ?? ""
                facing = placement.facing
                editingPlacementEvidence = placement.evidenceRefs
            }
        } else {
            hostRackSelection = initialRack
            if let initialClass { equipmentClass = initialClass }
        }
    }

    private func scanLabel(
        _ scan: @escaping () async throws
            -> EquipmentLabelScanResult
    ) {
        guard !scanningLabel else { return }
        scanningLabel = true
        errorText = nil
        Task { @MainActor in
            defer { scanningLabel = false }
            do {
                scanResult = try await scan()
            } catch {
                errorText = String(describing: error)
            }
        }
    }

    /// Applies a confirmed scan candidate (#345/#402 §3): the operator
    /// explicitly picked it — fields fill from the suggestion and the
    /// source photo joins the placement's evidence.
    private func applyScanCandidate(
        _ candidate: EquipmentLabelScanCandidate,
        from result: EquipmentLabelScanResult
    ) {
        if let key = candidate.catalogSelectionKey,
           equipmentCatalogEntries.contains(where: {
               $0.selectionKey == key
           })
        {
            selectedCatalogKey = key
        }
        if let manufacturer = candidate.manufacturer {
            self.manufacturer = manufacturer
        }
        if let model = candidate.model {
            self.model = model
        }
        if let serial = candidate.serialOrAssetTag {
            serialNumber = serial
        }
        if userLabel.isEmpty {
            userLabel = [
                candidate.manufacturer, candidate.model,
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        }
        if !scanEvidenceRefs.contains(result.evidenceRef) {
            scanEvidenceRefs.append(result.evidenceRef)
        }
    }

    private func buildItem() throws -> SystemInventoryItem {
        try SystemInventoryItem(
            itemID: editing?.itemID ?? AuthorityRecordID(),
            equipmentClass: equipmentClass,
            manufacturer: manufacturer.isEmpty ? nil : manufacturer,
            model: model.isEmpty ? nil : model,
            userLabel: userLabel,
            equipmentRef: try selectedEntry?.equipmentReference(
                authorityVersion: HTDTEquipmentCatalogSnapshot
                    .expectedAuthorityVersion
            ),
            serialNumber: serialNumber.isEmpty ? nil : serialNumber,
            hostRackEntityID: hostRackSelection,
            coordinateSpaceID: editing?.coordinateSpaceID,
            worldFromItem: editing?.worldFromItem,
            evidenceRefs: editing?.evidenceRefs ?? []
        )
    }

    private func buildPlacement(
        for item: SystemInventoryItem
    ) throws -> RackPlacementObservation? {
        guard let rack = hostRackSelection else { return nil }
        let unit = rackUnitText.isEmpty
            ? nil : Int(rackUnitText)
        if !rackUnitText.isEmpty && unit == nil {
            throw TheaterAuthorityError.nonPositiveDimension
        }
        let evidence = Array(
            Set(editingPlacementEvidence + scanEvidenceRefs)
        ).sorted()
        let placement = try RackPlacementObservation(
            placementID: editingPlacementID ?? AuthorityRecordID(),
            itemID: item.itemID,
            hostRackEntityID: rack,
            rackUnitPosition: unit,
            shelfSlotLabel: shelfSlotLabel.isEmpty
                ? nil : shelfSlotLabel,
            facing: facing,
            coordinateSpaceID: evidence.isEmpty
                ? nil : coordinateSpaceID,
            evidenceRefs: evidence
        )
        return placement
    }

    private func save(_ mode: SaveMode) {
        do {
            let item = try buildItem()
            let placement = try buildPlacement(for: item)
            if !duplicateAcknowledged {
                let found = authorities.inventoryDuplicateCandidates(
                    for: item
                )
                if !found.isEmpty {
                    duplicates = found
                    pendingSaveMode = mode
                    return
                }
            }
            onSave(item, placement)
            savedNotice = String(localized: "Saved")
            switch mode {
            case .done:
                dismiss()
            case .addNext:
                resetForNext()
            case .scanNext:
                resetForNext()
                if let scanEquipmentLabel {
                    scanLabel(scanEquipmentLabel)
                }
            }
        } catch {
            errorText = String(describing: error)
        }
    }

    /// Clears device-specific identity fields while keeping rack,
    /// class, and Mission context for the next unit (#402 §2).
    private func resetForNext() {
        editingPlacementID = nil
        editingPlacementEvidence = []
        userLabel = ""
        manufacturer = ""
        model = ""
        serialNumber = ""
        selectedCatalogKey = nil
        rackUnitText = ""
        shelfSlotLabel = ""
        facing = nil
        scanEvidenceRefs = []
        duplicates = []
        duplicateAcknowledged = false
        errorText = nil
    }
}
