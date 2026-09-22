import SwiftUI

/// A selectable option rendered as a title line plus a detailed
/// caption: every user-facing choice explains what the option means,
/// not just a label. Menu-style pickers render the caption inside
/// each option row; segmented controls pair the picker with a
/// caption describing the current selection instead.
struct DescribedPickerOption: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
