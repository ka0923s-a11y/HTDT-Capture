import Foundation
import SwiftUI
import HTDTCaptureCore

/// Session-level recents for the equipment picker (#265): the last
/// catalog `selectionKey`s the operator chose, most-recent first. Held
/// by the host/workspace so recents survive sheet dismissal.
public final class EquipmentRecents: ObservableObject {
    @Published public private(set) var keys: [String] = []

    public init(keys: [String] = []) {
        self.keys = keys
    }

    public func record(_ selectionKey: String) {
        keys.removeAll { $0 == selectionKey }
        keys.insert(selectionKey, at: 0)
        if keys.count > 8 {
            keys.removeLast(keys.count - 8)
        }
    }
}

/// Searchable equipment-definition sheet (#265). Selection is always
/// the exact catalog `selectionKey` — the deterministic
/// ID/version/SHA-256 tuple — so search and filtering can never change
/// an already-chosen binding.
public struct EquipmentCatalogPickerSheet: View {
    public let entries: [HTDTEquipmentCatalogEntry]
    /// Equipment classes relevant to the annotation being authored;
    /// entries outside the set are still shown but marked incompatible
    /// rather than silently hidden (#237 policy stays advisory here).
    public let compatibleIdentityKinds: Set<HTDTEquipmentIdentityKind>?
    /// Currently bound selection (shown pinned, never mutated by
    /// filtering).
    public let currentSelectionKey: String?
    public let recents: EquipmentRecents
    public let onSelect: (HTDTEquipmentCatalogEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var manufacturerFilter = ""
    /// Detail-sheet target; the entry type is not Identifiable so the
    /// sheet keys off its `selectionKey`.
    private struct DetailTarget: Identifiable {
        let entry: HTDTEquipmentCatalogEntry
        var id: String { entry.selectionKey }
    }
    @State private var detailTarget: DetailTarget?

    public init(
        entries: [HTDTEquipmentCatalogEntry],
        compatibleIdentityKinds:
            Set<HTDTEquipmentIdentityKind>? = nil,
        currentSelectionKey: String? = nil,
        recents: EquipmentRecents = EquipmentRecents(),
        onSelect: @escaping (HTDTEquipmentCatalogEntry) -> Void
    ) {
        self.entries = entries
        self.compatibleIdentityKinds = compatibleIdentityKinds
        self.currentSelectionKey = currentSelectionKey
        self.recents = recents
        self.onSelect = onSelect
    }

    private var manufacturers: [String] {
        Array(
            Set(entries.compactMap(\.manufacturer))
        ).sorted()
    }

    private var filtered: [HTDTEquipmentCatalogEntry] {
        entries.filter { entry in
            if !manufacturerFilter.isEmpty,
               entry.manufacturer != manufacturerFilter
            {
                return false
            }
            guard !query.isEmpty else {
                return true
            }
            let haystack = [
                entry.definitionID,
                entry.manufacturer ?? "",
                entry.model ?? "",
                entry.userLabel ?? "",
                entry.displayName,
                entry.version,
            ]
            .joined(separator: " ")
            .lowercased()
            return haystack.contains(query.lowercased())
        }
    }

    private var recentEntries: [HTDTEquipmentCatalogEntry] {
        recents.keys.compactMap { key in
            entries.first { $0.selectionKey == key }
        }
    }

    public var body: some View {
        List {
            if let currentSelectionKey,
               let current = entries.first(where: {
                   $0.selectionKey == currentSelectionKey
               })
            {
                Section(String(localized: "Current selection")) {
                    row(for: current, pinned: true)
                }
            }

            if !recentEntries.isEmpty {
                Section(String(localized: "Recently used")) {
                    ForEach(recentEntries, id: \.selectionKey) { entry in
                        row(for: entry)
                    }
                }
            }

            Section {
                if !manufacturers.isEmpty {
                    Picker(
                        String(localized: "Manufacturer"),
                        selection: $manufacturerFilter
                    ) {
                        DescribedPickerOption(
                            title: String(localized: "All"),
                            detail: String(localized:
                                "Show definitions from every manufacturer.")
                        )
                        .tag("")
                        ForEach(manufacturers, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }
            }

            Section(String(localized: "Definitions")) {
                if filtered.isEmpty {
                    Text(String(localized: "No definitions match."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered, id: \.selectionKey) { entry in
                        row(for: entry)
                    }
                }
            }
        }
        .searchable(
            text: $query,
            prompt: String(localized: "Manufacturer or model")
        )
        .navigationTitle(String(localized: "Choose equipment"))
        .inlineNavigationBarTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) { dismiss() }
            }
        }
        .sheet(item: $detailTarget) { target in
            let entry = target.entry
            NavigationStack {
                List {
                    LabeledContent(
                        String(localized: "Definition ID"),
                        value: entry.definitionID
                    )
                    LabeledContent(
                        String(localized: "Version"),
                        value: entry.version
                    )
                    LabeledContent(
                        String(localized: "Kind"),
                        value: equipmentIdentityKindName(
                            entry.identityKind
                        )
                    )
                    LabeledContent(
                        String(localized: "SHA-256"),
                        value: entry.semanticSHA256.description
                    )
                    .font(.caption.monospaced())
                }
                .navigationTitle(entry.displayName)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) {
                            detailTarget = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(
        for entry: HTDTEquipmentCatalogEntry,
        pinned: Bool = false
    ) -> some View {
        let compatible =
            compatibleIdentityKinds == nil
                || compatibleIdentityKinds!
                    .contains(entry.identityKind)
        // identityKind is the HTDTEquipmentIdentityKind enum

        Button {
            guard compatible else { return }
            recents.record(entry.selectionKey)
            onSelect(entry)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .foregroundStyle(
                            compatible
                                ? Color.primary
                                : Color.secondary
                        )
                    Text(
                        [
                            entry.manufacturer,
                            entry.model,
                            entry.version,
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if pinned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
                if !compatible {
                    Text(String(localized: "Incompatible"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    detailTarget = DetailTarget(entry: entry)
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    String(localized: "Equipment details")
                )
            }
        }
        .disabled(!compatible)
    }
}
