import SwiftUI

/// Phase (b) — verifies the full audio → WebSocket → transcript pipeline.
/// Will be replaced with the full scrolling transcript UI in Phase (c).
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {

            // Config error banner
            if let error = appState.configError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.footnote)
                }
                .padding(12)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Connection status
            streamingStatusBadge

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

            // Diagnostics
            Text("\(appState.chunkCount) chunks · \(appState.utterances.count) turns")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            Divider()

            // Live transcript preview (Phase b verification)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.utterances) { turn in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(turn.effectiveLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(turn.text)
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Partial / in-progress turn
                    if !appState.partialText.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Turn \(appState.utterances.count + 1) …")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(appState.partialText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var streamingStatusBadge: some View {
        switch appState.streamingState {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .connecting:
            Label("Connecting…", systemImage: "circle.dotted")
                .foregroundStyle(.orange)
                .font(.caption)
        case .connected:
            Label("Streaming", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
