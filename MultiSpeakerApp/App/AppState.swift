import Foundation
import Combine

/// Root application state. Owns the audio pipeline and streaming client.
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isRecording       = false
    @Published private(set) var configError: String?
    @Published private(set) var chunkCount        = 0
    @Published private(set) var streamingState    = StreamingClient.State.disconnected
    /// Live transcript turns — grows during recording, enriched with speaker
    /// labels after diarization in Phase (d).
    @Published private(set) var utterances: [Utterance] = []
    /// The in-progress partial turn being updated in real time.
    @Published private(set) var partialText: String = ""

    // MARK: - Sub-systems

    private(set) var config: AppConfig?
    let audioEngine    = AudioCaptureEngine()
    let fileWriter     = AudioFileWriter()
    let streamingClient = StreamingClient()

    // MARK: - Init

    init() {
        loadConfig()
        wireAudioEngine()
        wireStreamingClient()
    }

    // MARK: - Config

    private func loadConfig() {
        do {
            config = try AppConfig.load()
            print("[AppState] API key loaded ✓")
        } catch {
            configError = error.localizedDescription
            print("[AppState] Config error: \(error.localizedDescription)")
        }
    }

    // MARK: - Wiring

    private func wireAudioEngine() {
        audioEngine.onAudioChunk = { [weak self] data in
            guard let self else { return }
            // Called on audio thread — both calls below are thread-safe.
            self.fileWriter.append(data)
            self.streamingClient.send(audioChunk: data)

            DispatchQueue.main.async {
                self.chunkCount += 1
            }
        }
    }

    private func wireStreamingClient() {
        streamingClient.onStateChange = { [weak self] state in
            // Already dispatched to main by StreamingClient.
            self?.streamingState = state
        }

        streamingClient.onTurn = { [weak self] transcript, isEndOfTurn in
            guard let self else { return }
            // Already on main thread.
            if isEndOfTurn {
                // Finalise the partial turn and append it.
                if !transcript.isEmpty {
                    let turn = Utterance(turnIndex: self.utterances.count, text: transcript)
                    self.utterances.append(turn)
                }
                self.partialText = ""
            } else {
                // Update the rolling partial display.
                self.partialText = transcript
            }
        }

        streamingClient.onError = { error in
            print("[AppState] Streaming error: \(error.localizedDescription)")
        }
    }

    // MARK: - Recording control

    func startRecording() {
        guard !isRecording, let key = config?.assemblyAIKey else { return }
        fileWriter.reset()
        utterances.removeAll()
        partialText = ""
        chunkCount  = 0

        streamingClient.connect(apiKey: key)

        do {
            try audioEngine.start()
            isRecording = true
            print("[AppState] Recording started")
        } catch {
            streamingClient.disconnect()
            print("[AppState] Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        streamingClient.disconnect()
        isRecording = false
        print("[AppState] Recording stopped — " +
              "\(utterances.count) turns, " +
              "\(String(format: "%.1f", fileWriter.duration))s of audio")
    }
}
