import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var speakerMap = SpeakerMap()

    var body: some View {
        VStack(spacing: 0) {
            // Config error banner
            if let error = appState.configError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.footnote)
                    Spacer()
                }
                .padding(10)
                .background(.red.opacity(0.12))
            }

            // Scrolling transcript
            TranscriptView(
                utterances:  appState.utterances,
                partialText: appState.partialText,
                speakerMap:  speakerMap
            )
            .padding(12)

            Divider()

            // Bottom control bar
            ControlBar(
                isRecording:       appState.isRecording,
                streamingState:    appState.streamingState,
                chunkCount:        appState.chunkCount,
                utteranceCount:    appState.utterances.count,
                configError:       appState.configError,
                onToggleRecording: {
                    if appState.isRecording {
                        appState.stopRecording()
                    } else {
                        appState.startRecording()
                    }
                }
            )
        }
        .frame(minWidth: 500, minHeight: 500)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
