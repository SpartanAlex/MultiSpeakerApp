import SwiftUI

/// A single speaker turn row in the transcript.
/// Text is selectable by default. Double-click the body text to edit it inline.
struct UtteranceRow: View {
    let utterance: Utterance
    let speakerMap: SpeakerMap
    var isPartial: Bool = false
    /// Called when the user commits an inline text edit.
    var onTextChange: ((String) -> Void)?

    @State private var isEditing = false
    @State private var draft    = ""

    private var label: String {
        if let speakerLabel = utterance.speakerLabel {
            return speakerMap.displayName(for: speakerLabel)
        }
        return utterance.effectiveLabel
    }

    private var color: Color {
        if let speakerLabel = utterance.speakerLabel {
            return speakerMap.color(for: speakerLabel)
        }
        let palette: [Color] = [.blue, .teal, .orange, .purple, .pink]
        return palette[utterance.turnIndex % palette.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Colour chip
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .textSelection(.enabled)

                if isEditing && !isPartial {
                    TextField("", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1...)
                        .onSubmit { commitEdit() }
                        .onExitCommand { isEditing = false }
                        .onAppear { draft = utterance.text }
                } else {
                    Text(utterance.text)
                        .font(.body)
                        .foregroundStyle(isPartial ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .onTapGesture(count: 2) {
                            guard !isPartial else { return }
                            draft = utterance.text
                            isEditing = true
                        }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isPartial ? 0.6 : 1.0)
        // When a new diarization result replaces text externally, exit edit mode.
        .onChange(of: utterance.text) { _ in
            if isEditing { isEditing = false }
        }
    }

    private func commitEdit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        guard !trimmed.isEmpty, trimmed != utterance.text else { return }
        onTextChange?(trimmed)
    }
}
