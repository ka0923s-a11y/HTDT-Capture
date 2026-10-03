import Foundation
import SwiftUI
import HTDTCaptureCore

/// The operator's inputs for one field note (issue bolph71656-ai/HTDT-Capture#375). The host —
/// never this view — stamps the revision/session binding, timestamp,
/// and any evidence frame ref or spatial anchor the operator asked
/// for.
public struct FieldNoteDraft: Sendable {
    public var text: String
    public var category: CaptureFieldNoteCategory
    public var needsAttention: Bool
    public var attachLatestEvidence: Bool
    public var dictated: Bool
    /// Authority/evidence refs the note binds against (Review-time
    /// binding); empty for an unbound note.
    public var bindingRefs: [String]
    /// The spatial anchor the operator requested (issue bolph71656-ai/HTDT-Capture#421); the
    /// host resolves it against the live session — the sheet never
    /// fabricates a point itself.
    public var anchorRequest: CaptureFieldNoteAnchorRequest

    public init(
        text: String,
        category: CaptureFieldNoteCategory,
        needsAttention: Bool,
        attachLatestEvidence: Bool,
        dictated: Bool,
        bindingRefs: [String] = [],
        anchorRequest: CaptureFieldNoteAnchorRequest = .none
    ) {
        self.text = text
        self.category = category
        self.needsAttention = needsAttention
        self.attachLatestEvidence = attachLatestEvidence
        self.dictated = dictated
        self.bindingRefs = bindingRefs
        self.anchorRequest = anchorRequest
    }
}

/// Operator field-note composer (issue bolph71656-ai/HTDT-Capture#375, presentation rework
/// legacy bolph71656-ai/HTDT-Capture#420, spatial anchoring legacy bolph71656-ai/HTDT-Capture#421): free text, a localized extensible
/// category, a needs-attention flag, subject binding drawn from
/// committed authorities, and — during scanning — an optional
/// validated spatial anchor. The sheet only gathers inputs; the host
/// resolves anchors and stamps provenance.
public struct FieldNoteComposeSheet: View {
    public let allowsEvidenceAttachment: Bool
    /// Whether a live AR session can satisfy a spatial anchor
    /// request — scan-time only (issue bolph71656-ai/HTDT-Capture#421).
    public let allowsSpatialAnchor: Bool
    public let bindingCandidates: [FieldNoteBindingCandidate]
    /// Category + bindings preloaded when correcting/binding an
    /// existing note — supersession lineage keeps them (issue bolph71656-ai/HTDT-Capture#420).
    public let preselectedCategory: CaptureFieldNoteCategory?
    public let preselectedBindingRefs: [String]
    public let onSave: (FieldNoteDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var categoryToken =
        CaptureFieldNoteCategory.general.rawValue
    @State private var customCategory = ""
    @State private var needsAttention = false
    @State private var attachLatestEvidence = true
    @State private var dictated = false
    @State private var bindingSelection = ""
    @State private var anchorRequest: CaptureFieldNoteAnchorRequest =
        .none

    private static let customToken = "x_custom"
    private static let noBinding = "_none_"

    public init(
        allowsEvidenceAttachment: Bool = true,
        allowsSpatialAnchor: Bool = false,
        bindingCandidates: [FieldNoteBindingCandidate] = [],
        preselectedCategory: CaptureFieldNoteCategory? = nil,
        preselectedBindingRefs: [String] = [],
        onSave: @escaping (FieldNoteDraft) -> Void = { _ in }
    ) {
        self.allowsEvidenceAttachment = allowsEvidenceAttachment
        self.allowsSpatialAnchor = allowsSpatialAnchor
        self.bindingCandidates = bindingCandidates
        self.preselectedCategory = preselectedCategory
        self.preselectedBindingRefs = preselectedBindingRefs
        self.onSave = onSave
    }

    private var effectiveCategory: CaptureFieldNoteCategory? {
        if categoryToken == Self.customToken {
            let token = "x_" + customCategory
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
            return try? CaptureFieldNoteCategory(token: token)
        }
        if let pre = preselectedCategory,
           categoryToken == pre.rawValue {
            return pre
        }
        return CaptureFieldNoteCategory(rawValue: categoryToken)
    }

    /// Category options: well-known tokens plus the preselected
    /// custom token when correcting an `x_` note.
    private var categoryOptions: [CaptureFieldNoteCategory] {
        var categories = CaptureFieldNoteCategory.wellKnownTokens
            .map { CaptureFieldNoteCategory(rawValue: $0) }
        if let pre = preselectedCategory,
           pre.rawValue.hasPrefix("x_"),
           !categories.contains(pre) {
            categories.append(pre)
        }
        return categories.sorted { $0.rawValue < $1.rawValue }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier(
                            "fieldNote.text"
                        )
                    Toggle(
                        "Dictated (stores text only, no audio)",
                        isOn: $dictated
                    )
                    .font(.caption)
                } header: {
                    Text("Note")
                } footer: {
                    Text(
                        "Notes travel with the capture bundle as operator context — they never change geometry or measurements."
                    )
                    .font(.caption)
                }

                Section("Category") {
                    Picker("Category", selection: $categoryToken) {
                        ForEach(
                            categoryOptions,
                            id: \.rawValue
                        ) { token in
                            DescribedPickerOption(
                                title: FieldNoteBindingResolver
                                    .categoryName(token),
                                detail: FieldNoteBindingResolver
                                    .categoryDescription(token)
                            )
                            .tag(token.rawValue)
                        }
                        DescribedPickerOption(
                            title: String(localized: "Custom…"),
                            detail: String(localized:
                                "Type your own category — stored on the note verbatim.")
                        )
                        .tag(Self.customToken)
                    }
                    if categoryToken == Self.customToken {
                        TextField(
                            "Custom category",
                            text: $customCategory
                        )
                        .font(.callout)
                        if effectiveCategory == nil,
                           !customCategory
                               .trimmingCharacters(
                                   in: .whitespacesAndNewlines
                               ).isEmpty
                        {
                            Text(
                                "Use lowercase letters, digits and underscores."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                if allowsSpatialAnchor {
                    Section {
                        Picker(
                            "Location",
                            selection: $anchorRequest
                        ) {
                            Text("Note only")
                                .tag(
                                    CaptureFieldNoteAnchorRequest
                                        .none
                                )
                            Text("Mark location")
                                .tag(
                                    CaptureFieldNoteAnchorRequest
                                        .subjectPoint
                                )
                            Text("Record from here")
                                .tag(
                                    CaptureFieldNoteAnchorRequest
                                        .viewpoint
                                )
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(
                            anchorRequest == .viewpoint
                                ? "Saves where the device stood — not the note's subject."
                                : anchorRequest == .subjectPoint
                                    ? "Saves the point in view — used when the note is about a spot."
                                    : "No location is saved with this note."
                        )
                        .font(.caption)
                    }
                }

                Section {
                    if !bindingCandidates.isEmpty {
                        Picker(
                            "Bind to",
                            selection: $bindingSelection
                        ) {
                            DescribedPickerOption(
                                title: String(localized: "Nothing yet"),
                                detail: String(localized:
                                    "The note is not bound to a subject yet — you can bind it later.")
                            )
                            .tag(Self.noBinding)
                            ForEach(bindingCandidates) { candidate in
                                DescribedPickerOption(
                                    title: candidate.title,
                                    detail: String(localized:
                                        "Bind the note to this subject.")
                                )
                                .tag(candidate.ref)
                            }
                        }
                        .accessibilityLabel(
                            String(localized: "Bind note to subject")
                        )
                    }
                    Toggle(
                        "Needs attention before finalize",
                        isOn: $needsAttention
                    )
                    if allowsEvidenceAttachment {
                        Toggle(
                            "Attach latest saved evidence frame",
                            isOn: $attachLatestEvidence
                        )
                    }
                }
            }
            .navigationTitle("Add note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let category = effectiveCategory {
                            onSave(
                                FieldNoteDraft(
                                    text: text.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ),
                                    category: category,
                                    needsAttention: needsAttention,
                                    attachLatestEvidence:
                                        allowsEvidenceAttachment
                                            && attachLatestEvidence,
                                    dictated: dictated,
                                    bindingRefs:
                                        bindingSelection.isEmpty
                                            || bindingSelection
                                                == Self.noBinding
                                            ? preselectedBindingRefs
                                            : [bindingSelection],
                                    anchorRequest: anchorRequest
                                )
                            )
                        }
                        dismiss()
                    }
                    // `effectiveCategory` can still be nil when the
                    // custom token is non-empty but grammar-invalid —
                    // disabling is what stops a silent discard on
                    // Save (onSave is skipped and the sheet closes).
                    .disabled(
                        text.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            || effectiveCategory == nil
                    )
                }
            }
            .onAppear {
                if let pre = preselectedCategory {
                    if pre.rawValue.hasPrefix("x_") {
                        categoryToken = pre.rawValue
                    } else {
                        categoryToken = pre.rawValue
                    }
                }
                if bindingSelection.isEmpty,
                   let first = preselectedBindingRefs.first {
                    bindingSelection = first
                }
            }
        }
    }
}
