import Foundation
import SwiftUI
import HTDTCaptureCore

/// The operator's inputs for one field note (issue #375). The host —
/// never this view — stamps the revision/session binding, timestamp,
/// and any evidence frame ref.
public struct FieldNoteDraft: Sendable {
    public var text: String
    public var category: CaptureFieldNoteCategory
    public var needsAttention: Bool
    public var attachLatestEvidence: Bool
    public var dictated: Bool
    /// Authority/evidence refs the note binds against (Review-time
    /// binding); empty for an unbound note.
    public var bindingRefs: [String]

    public init(
        text: String,
        category: CaptureFieldNoteCategory,
        needsAttention: Bool,
        attachLatestEvidence: Bool,
        dictated: Bool,
        bindingRefs: [String] = []
    ) {
        self.text = text
        self.category = category
        self.needsAttention = needsAttention
        self.attachLatestEvidence = attachLatestEvidence
        self.dictated = dictated
        self.bindingRefs = bindingRefs
    }
}

/// Operator field-note composer (issue #375): free text, an
/// extensible category, an optional needs-attention flag, and —
/// when a live scan context offers one — binding of the latest
/// committed evidence frame. Review passes `bindingCandidates` so an
/// unbound note can be authored already bound; the host keeps notes
/// as an append-only supplemental document — this sheet only gathers
/// inputs.
public struct FieldNoteComposeSheet: View {
    public let allowsEvidenceAttachment: Bool
    public let bindingCandidates: [String]
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

    private static let customToken = "x_custom"
    private static let noBinding = "_none_"

    public init(
        allowsEvidenceAttachment: Bool = true,
        bindingCandidates: [String] = [],
        onSave: @escaping (FieldNoteDraft) -> Void = { _ in }
    ) {
        self.allowsEvidenceAttachment = allowsEvidenceAttachment
        self.bindingCandidates = bindingCandidates
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
        return CaptureFieldNoteCategory(rawValue: categoryToken)
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
                            CaptureFieldNoteCategory
                                .wellKnownTokens
                                .sorted(),
                            id: \.self
                        ) { token in
                            Text(
                                token.replacingOccurrences(
                                    of: "_",
                                    with: " "
                                ).capitalized
                            )
                            .tag(token)
                        }
                        Text("Custom…").tag(Self.customToken)
                    }
                    if categoryToken == Self.customToken {
                        TextField(
                            "custom_category",
                            text: $customCategory
                        )
                        .font(.callout.monospaced())
                    }
                }

                Section {
                    if !bindingCandidates.isEmpty {
                        Picker(
                            "Bind to",
                            selection: $bindingSelection
                        ) {
                            Text("Nothing yet").tag(Self.noBinding)
                            ForEach(
                                bindingCandidates,
                                id: \.self
                            ) { ref in
                                Text(ref)
                                    .font(.caption.monospaced())
                                    .tag(ref)
                            }
                        }
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
                                            ? []
                                            : [bindingSelection]
                                )
                            )
                        }
                        dismiss()
                    }
                    .disabled(
                        text.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            || (categoryToken == Self.customToken
                                && customCategory
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty)
                    )
                }
            }
        }
    }
}
