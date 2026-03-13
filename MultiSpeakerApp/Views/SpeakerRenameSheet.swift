import SwiftUI

/// Sheet for reviewing and editing speaker display names.
/// Pre-fills LeMUR suggestions; user can accept, edit, or clear each one.
struct SpeakerRenameSheet: View {
    let speakerLabels: [String]
    let suggestions: [String: String?]
    @ObservedObject var speakerMap: SpeakerMap
    @Environment(\.dismiss) private var dismiss

    /// Local editable copy — only committed to speakerMap on Apply.
    @State private var editedNames: [String: String] = [:]

    init(speakerLabels: [String], suggestions: [String: String?], speakerMap: SpeakerMap) {
        self.speakerLabels = speakerLabels
        self.suggestions   = suggestions
        self.speakerMap    = speakerMap

        // Pre-fill: existing custom name → LeMUR suggestion → empty
        var initial: [String: String] = [:]
        for label in speakerLabels {
            if let existing = speakerMap.names[label] {
                initial[label] = existing
            } else if let suggestion = suggestions[label], let name = suggestion {
                initial[label] = name
            } else {
                initial[label] = ""
            }
        }
        _editedNames = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Rename Speakers")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Speaker rows
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(speakerLabels, id: \.self) { label in
                        SpeakerEditRow(
                            label: label,
                            suggestion: suggestions[label] ?? nil,
                            color: speakerMap.color(for: label),
                            name: Binding(
                                get: { editedNames[label] ?? "" },
                                set: { editedNames[label] = $0 }
                            )
                        )
                    }
                }
                .padding()
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Apply") {
                    for label in speakerLabels {
                        speakerMap.setName(editedNames[label] ?? "", for: label)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(minWidth: 360, minHeight: 300)
    }
}

// MARK: - Single speaker row

private struct SpeakerEditRow: View {
    let label: String
    let suggestion: String?
    let color: Color
    @Binding var name: String

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Colour chip
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            // Default label
            Text("Speaker \(label)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // Editable name field
            TextField("Enter name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)

            // LeMUR suggestion badge
            if let suggestion, !suggestion.isEmpty, name != suggestion {
                Button {
                    name = suggestion
                } label: {
                    Label(suggestion, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
                .help("LeMUR suggestion — click to apply")
            }
        }
    }
}
