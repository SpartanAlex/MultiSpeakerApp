import Foundation
import Combine

// MARK: - Diarization status

enum DiarizationStatus: Equatable {
    case idle
    case uploading
    case processing(String)   // status message
    case complete
    case failed(String)
}

// MARK: - AppState

/// Root application state. Owns the full audio → streaming → diarization pipeline.
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isRecording         = false
    @Published private(set) var configError: String?
    @Published private(set) var chunkCount           = 0
    @Published private(set) var streamingState       = StreamingClient.State.disconnected
    @Published private(set) var utterances: [Utterance] = []
    @Published private(set) var partialText: String  = ""
    @Published private(set) var diarizationStatus    = DiarizationStatus.idle
    /// LeMUR-suggested names keyed by speaker label. Shown in the rename sheet.
    @Published private(set) var lemurSuggestions: [String: String?] = [:]

    // MARK: - Sub-systems

    private(set) var config: AppConfig?
    let speakerMap          = SpeakerMap()
    let audioEngine         = AudioCaptureEngine()
    let fileWriter          = AudioFileWriter()
    let streamingClient     = StreamingClient()
    let diarizationClient   = DiarizationClient()

    // MARK: - Computed helpers

    /// Unique speaker labels present in the current transcript, in order of appearance.
    var speakerLabels: [String] {
        var seen = Set<String>()
        return utterances.compactMap { $0.speakerLabel }.filter { seen.insert($0).inserted }
    }

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
            configError = nil
            print("[AppState] API key loaded ✓")
        } catch {
            configError = error.localizedDescription
            print("[AppState] Config error: \(error.localizedDescription)")
        }
    }

    /// Re-reads the API key (e.g. after the user saves it via ApiKeySheet).
    func reloadConfig() {
        loadConfig()
    }

    // MARK: - Wiring

    private func wireAudioEngine() {
        audioEngine.onAudioChunk = { [weak self] data in
            guard let self else { return }
            self.fileWriter.append(data)
            self.streamingClient.send(audioChunk: data)
            DispatchQueue.main.async { self.chunkCount += 1 }
        }
    }

    private func wireStreamingClient() {
        streamingClient.onStateChange = { [weak self] state in
            self?.streamingState = state
        }
        streamingClient.onTurn = { [weak self] transcript, isEndOfTurn in
            guard let self else { return }
            if isEndOfTurn {
                if !transcript.isEmpty {
                    let turn = Utterance(turnIndex: self.utterances.count, text: transcript)
                    self.utterances.append(turn)
                }
                self.partialText = ""
            } else {
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
        lemurSuggestions = [:]
        speakerMap.reset()
        diarizationStatus = .idle

        streamingClient.connect(apiKey: key)
        do {
            try audioEngine.start()
            isRecording = true
            print("[AppState] Recording started")
        } catch {
            streamingClient.disconnect()
            print("[AppState] Failed to start audio: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        streamingClient.disconnect()
        isRecording = false
        print("[AppState] Recording stopped — \(utterances.count) turns, " +
              "\(String(format: "%.1f", fileWriter.duration))s")
        triggerDiarization()
    }

    // MARK: - Diarization

    private func triggerDiarization() {
        guard let key = config?.assemblyAIKey else { return }
        guard fileWriter.byteCount > 0 else {
            print("[AppState] No audio to diarize")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        do {
            try fileWriter.writeWAV(to: tempURL)
        } catch {
            diarizationStatus = .failed("Could not write audio file: \(error.localizedDescription)")
            return
        }

        diarizationStatus = .uploading

        Task {
            do {
                let result = try await diarizationClient.transcribe(
                    audioURL: tempURL,
                    apiKey: key,
                    onStatus: { msg in
                        DispatchQueue.main.async {
                            self.diarizationStatus = .processing(msg)
                        }
                    }
                )
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run { self.mergeResults(result) }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run {
                    self.diarizationStatus = .failed(error.localizedDescription)
                    print("[AppState] Diarization failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - File import

    /// Imports an audio file picked by the user (m4a, mp3, wav, etc.) and runs
    /// the full diarization + LeMUR pipeline on it.
    /// Security-scoped resource access is handled here before any file reads.
    func importAndTranscribe(url: URL) {
        guard let key = config?.assemblyAIKey else { return }

        utterances.removeAll()
        partialText = ""
        lemurSuggestions = [:]
        speakerMap.reset()
        diarizationStatus = .uploading

        Task {
            // macOS sandbox: must access security-scoped bookmark, copy to temp, then release.
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)

            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
            } catch {
                await MainActor.run {
                    self.diarizationStatus = .failed("Could not read file: \(error.localizedDescription)")
                }
                return
            }

            do {
                let result = try await diarizationClient.transcribe(
                    audioURL: tempURL,
                    apiKey: key,
                    onStatus: { msg in
                        DispatchQueue.main.async { self.diarizationStatus = .processing(msg) }
                    }
                )
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run { self.mergeResults(result) }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run {
                    self.diarizationStatus = .failed(error.localizedDescription)
                    print("[AppState] Import failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func mergeResults(_ result: DiarizationClient.TranscriptResult) {
        // Replace streaming placeholder turns with diarized utterances.
        utterances = result.utterances.enumerated().map { index, d in
            var u = Utterance(turnIndex: index, text: d.text)
            u.speakerLabel = d.speaker
            return u
        }

        // Store LeMUR suggestions for the rename sheet.
        lemurSuggestions = result.suggestedNames

        // Pre-apply suggestions that have a confident name.
        for (label, name) in result.suggestedNames {
            if let name { speakerMap.setName(name, for: label) }
        }

        diarizationStatus = .complete
        print("[AppState] Diarization merged — \(utterances.count) utterances, " +
              "\(result.suggestedNames.filter { $0.value != nil }.count) names suggested")
    }

    // MARK: - Utterance editing

    func updateUtteranceText(id: UUID, text: String) {
        guard let i = utterances.firstIndex(where: { $0.id == id }) else { return }
        utterances[i].text = text
    }

    // MARK: - Speaker renaming

    func renameSpeaker(label: String, name: String) {
        speakerMap.setName(name, for: label)
    }

    // MARK: - Export

    /// Generates a plain-text transcript with speaker labels and timestamps stripped,
    /// ready to be written via TranscriptDocument / .fileExporter.
    var exportText: String {
        var lines: [String] = []

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        lines.append("MultiSpeakerApp Transcript")
        lines.append("Generated: \(formatter.string(from: Date()))")
        lines.append(String(repeating: "-", count: 40))
        lines.append("")

        for utterance in utterances {
            let label: String
            if let speakerLabel = utterance.speakerLabel {
                label = speakerMap.displayName(for: speakerLabel)
            } else {
                label = utterance.effectiveLabel
            }
            lines.append("\(label): \(utterance.text)")
        }

        return lines.joined(separator: "\n")
    }
}
