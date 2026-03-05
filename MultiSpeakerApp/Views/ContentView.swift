import SwiftUI

/// Phase (a) — minimal UI to verify the audio pipeline.
/// Will be replaced with the full transcript view in Phase (c).
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {

            // Config error banner
            if let error = appState.configError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.footnote)
                }
                .padding(12)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Record / Stop button
            Button {
                if appState.isRecording {
                    appState.stopRecording()
                } else {
                    appState.startRecording()
                }
            } label: {
                Label(
                    appState.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .font(.title3.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isRecording ? .red : .accentColor)
            .disabled(appState.configError != nil)

            // Live diagnostics
            if appState.isRecording || appState.chunkCount > 0 {
                VStack(spacing: 4) {
                    Label("Recording…", systemImage: "waveform")
                        .foregroundStyle(.red)
                        .opacity(appState.isRecording ? 1 : 0)

                    Text("\(appState.chunkCount) chunks received")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(40)
        .frame(minWidth: 340, minHeight: 220)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
