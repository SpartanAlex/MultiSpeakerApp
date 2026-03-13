import SwiftUI

/// Bottom toolbar with record/stop, streaming status, diarization state, and rename button.
struct ControlBar: View {
    let isRecording: Bool
    let streamingState: StreamingClient.State
    let chunkCount: Int
    let utteranceCount: Int
    let diarizationStatus: DiarizationStatus
    let configError: String?
    let onToggleRecording: () -> Void
    let onRename: () -> Void

    private var canRename: Bool {
        if case .complete = diarizationStatus { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 16) {
            // Streaming status indicator
            streamingBadge

            Spacer()

            // Turn count
            if utteranceCount > 0 {
                Text("\(utteranceCount) turns")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Rename speakers button — enabled once diarization completes
            Button(action: onRename) {
                Label("Rename", systemImage: "person.text.rectangle")
                    .font(.body)
            }
            .disabled(!canRename)
            .help(canRename ? "Rename speakers" : "Available after diarization completes")

            // Record / Stop button
            Button(action: onToggleRecording) {
                Label(
                    isRecording ? "Stop" : "Record",
                    systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .accentColor)
            .disabled(configError != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var streamingBadge: some View {
        switch streamingState {
        case .disconnected:
            Label("Ready", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .connecting:
            Label("Connecting…", systemImage: "circle.dotted")
                .foregroundStyle(.orange)
                .font(.caption)
        case .connected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .fill(.green.opacity(0.3))
                            .frame(width: 14, height: 14)
                    )
                Text("Live")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }
}
