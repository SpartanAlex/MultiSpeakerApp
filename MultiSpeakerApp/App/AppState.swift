import Foundation
import Combine

/// Root application state. Owns the audio pipeline and will own the
/// networking and transcript store in later phases.
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isRecording = false
    @Published private(set) var configError: String?
    @Published private(set) var chunkCount  = 0   // Phase (a) diagnostic

    // MARK: - Sub-systems (internal — views use AppState as interface)

    private(set) var config: AppConfig?
    let audioEngine = AudioCaptureEngine()
    let fileWriter  = AudioFileWriter()

    // MARK: - Init

    init() {
        loadConfig()
        wireAudioEngine()
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

    // MARK: - Audio wiring

    private func wireAudioEngine() {
        audioEngine.onAudioChunk = { [weak self] data in
            guard let self else { return }
            // Called on audio background thread — fileWriter is thread-safe.
            self.fileWriter.append(data)

            // Update diagnostic counter on main thread.
            DispatchQueue.main.async {
                self.chunkCount += 1
                print("[Audio] chunk \(self.chunkCount) — \(data.count) bytes " +
                      "(\(data.count / 2) samples) | " +
                      "total: \(String(format: "%.1f", self.fileWriter.duration))s")
            }
        }
    }

    // MARK: - Recording control

    func startRecording() {
        guard !isRecording else { return }
        fileWriter.reset()
        chunkCount = 0
        do {
            try audioEngine.start()
            isRecording = true
            print("[AppState] Recording started")
        } catch {
            print("[AppState] Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        isRecording = false
        print("[AppState] Recording stopped — " +
              "\(chunkCount) chunks, " +
              "\(String(format: "%.1f", fileWriter.duration))s of audio")
    }
}
