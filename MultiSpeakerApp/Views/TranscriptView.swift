import SwiftUI

/// Scrolling transcript view. Auto-scrolls to the bottom as new turns arrive.
struct TranscriptView: View {
    let utterances: [Utterance]
    let partialText: String
    let speakerMap: SpeakerMap

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(utterances) { utterance in
                        UtteranceRow(utterance: utterance, speakerMap: speakerMap)
                            .id(utterance.id)
                    }

                    // In-progress partial turn
                    if !partialText.isEmpty {
                        let partial = Utterance(
                            turnIndex: utterances.count,
                            text: partialText
                        )
                        UtteranceRow(
                            utterance: partial,
                            speakerMap: speakerMap,
                            isPartial: true
                        )
                        .id("partial")
                    }

                    // Invisible anchor at the bottom for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .onChange(of: utterances.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: partialText) { _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if utterances.isEmpty && partialText.isEmpty {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.and.mic")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Press Start Recording to begin")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
