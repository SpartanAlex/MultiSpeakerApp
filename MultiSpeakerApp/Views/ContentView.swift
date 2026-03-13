import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showRenameSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Config error banner
            if let error = appState.configError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error).font(.footnote)
                    Spacer()
                }
                .padding(10)
                .background(.red.opacity(0.12))
            }

            // Diarization status banner
            diarizationBanner

            // Scrolling transcript
            TranscriptView(
                utterances:  appState.utterances,
                partialText: appState.partialText,
                speakerMap:  appState.speakerMap
            )
            .padding(12)

            Divider()

            // Bottom control bar
            ControlBar(
                isRecording:        appState.isRecording,
                streamingState:     appState.streamingState,
                chunkCount:         appState.chunkCount,
                utteranceCount:     appState.utterances.count,
                diarizationStatus:  appState.diarizationStatus,
                configError:        appState.configError,
                onToggleRecording: {
                    if appState.isRecording {
                        appState.stopRecording()
                    } else {
                        appState.startRecording()
                    }
                },
                onRename: { showRenameSheet = true }
            )
        }
        .frame(minWidth: 500, minHeight: 500)
        .sheet(isPresented: $showRenameSheet) {
            SpeakerRenameSheet(
                speakerLabels: appState.speakerLabels,
                suggestions:   appState.lemurSuggestions,
                speakerMap:    appState.speakerMap
            )
        }
    }

    // MARK: - Diarization banner

    @ViewBuilder
    private var diarizationBanner: some View {
        switch appState.diarizationStatus {
        case .idle, .complete:
            EmptyView()

        case .uploading:
            statusBanner("Uploading audio…", color: .blue)

        case .processing(let msg):
            statusBanner(msg, color: .blue)

        case .failed(let msg):
            statusBanner("Diarization failed: \(msg)", color: .red)
        }
    }

    private func statusBanner(_ message: String, color: Color) -> some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text(message).font(.footnote)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
