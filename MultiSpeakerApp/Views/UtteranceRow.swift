import SwiftUI

/// A single speaker turn row in the transcript.
struct UtteranceRow: View {
    let utterance: Utterance
    let speakerMap: SpeakerMap
    /// When true the row is dimmed — used for the in-progress partial turn.
    var isPartial: Bool = false

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
        // Before diarization: cycle through palette by turn index.
        let palette: [Color] = [.blue, .teal, .orange, .purple, .pink]
        return palette[utterance.turnIndex % palette.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Colour chip + label
            VStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)

                Text(utterance.text)
                    .font(.body)
                    .foregroundStyle(isPartial ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .opacity(isPartial ? 0.6 : 1.0)
    }
}
