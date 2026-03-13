import Foundation

/// Handles the full AssemblyAI async diarization pipeline:
///   1. Upload audio file (any format: WAV, M4A, MP3…) → get upload URL
///   2. Request transcription with speaker_labels
///   3. Poll until complete
///   4. Ask LeMUR to infer real speaker names from context
final class DiarizationClient {

    // MARK: - Result types

    struct TranscriptResult {
        let transcriptID: String
        let utterances: [DiarizedUtterance]
        /// LeMUR-suggested names keyed by speaker label ("A", "B"…).
        /// Value is nil when no name could be inferred.
        let suggestedNames: [String: String?]
    }

    struct DiarizedUtterance {
        let speaker: String   // "A", "B", etc.
        let text: String
        let startMs: Int
        let endMs: Int
    }

    // MARK: - Endpoints

    private let base = "https://api.assemblyai.com"

    // MARK: - Public API

    /// Uploads `audioURL` (WAV, M4A, MP3, MP4 — AssemblyAI accepts all),
    /// transcribes with speaker labels, then runs LeMUR.
    /// Progress stages are reported via `onStatus`.
    func transcribe(
        audioURL: URL,
        apiKey: String,
        onStatus: @escaping (String) -> Void
    ) async throws -> TranscriptResult {

        onStatus("Uploading audio…")
        let uploadURL = try await upload(fileURL: audioURL, apiKey: apiKey)

        onStatus("Requesting transcription…")
        let transcriptID = try await requestTranscription(audioURL: uploadURL, apiKey: apiKey)

        onStatus("Processing…")
        let utterances = try await pollUntilComplete(transcriptID: transcriptID, apiKey: apiKey)

        onStatus("Identifying speakers…")
        let suggestedNames = (try? await guessNames(transcriptID: transcriptID, apiKey: apiKey)) ?? [:]

        return TranscriptResult(
            transcriptID: transcriptID,
            utterances: utterances,
            suggestedNames: suggestedNames
        )
    }

    // MARK: - Step 1: Upload

    private func upload(fileURL: URL, apiKey: String) async throws -> String {
        // Guard against iCloud placeholder files that haven't been downloaded locally.
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs?[.size] as? Int) ?? 0
        guard fileSize > 1024 else {
            throw DiarizationError.uploadFailed(
                "Audio file is empty or not downloaded (size: \(fileSize) bytes). " +
                "If this is a Voice Memo stored in iCloud, open Voice Memos and wait for it to download first."
            )
        }

        let audioData = try Data(contentsOf: fileURL)
        var req = URLRequest(url: try endpoint("/v2/upload"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = audioData

        let (data, response) = try await URLSession.shared.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let msg = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error
                ?? String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw DiarizationError.uploadFailed(msg)
        }
        let json = try JSONDecoder().decode([String: String].self, from: data)
        guard let url = json["upload_url"] else {
            throw DiarizationError.uploadFailed("No upload_url in response")
        }
        print("[DiarizationClient] Uploaded — \(audioData.count / 1024) KB")
        return url
    }

    // MARK: - Step 2: Request transcription

    private func requestTranscription(audioURL: String, apiKey: String) async throws -> String {
        var req = URLRequest(url: try endpoint("/v2/transcript"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "audio_url": audioURL,
            "speaker_labels": true,
            "speech_models": ["universal-2"]
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let msg = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error
                ?? String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw DiarizationError.transcriptionFailed("Request failed: \(msg)")
        }
        let transcriptResponse = try JSONDecoder().decode(TranscriptStatusResponse.self, from: data)
        print("[DiarizationClient] Transcript requested — id: \(transcriptResponse.id)")
        return transcriptResponse.id
    }

    // MARK: - Step 3: Poll

    private func pollUntilComplete(
        transcriptID: String,
        apiKey: String
    ) async throws -> [DiarizedUtterance] {
        var req = URLRequest(url: try endpoint("/v2/transcript/\(transcriptID)"))
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")

        // Poll with capped backoff: 2s → 4s → 4s → … (up to ~4 min total)
        var delayNs: UInt64 = 2_000_000_000
        for attempt in 1...60 {
            try await Task.sleep(nanoseconds: delayNs)
            delayNs = min(delayNs * 2, 4_000_000_000)

            let (data, response) = try await URLSession.shared.data(for: req)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode == 200 else {
                let msg = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error
                    ?? "HTTP \(statusCode)"
                throw DiarizationError.transcriptionFailed("Poll failed: \(msg)")
            }
            let pollResponse = try JSONDecoder().decode(TranscriptStatusResponse.self, from: data)
            print("[DiarizationClient] Poll \(attempt) — status: \(pollResponse.status)")

            switch pollResponse.status {
            case "completed":
                return pollResponse.utterances?.map {
                    DiarizedUtterance(
                        speaker: $0.speaker,
                        text: $0.text,
                        startMs: $0.start,
                        endMs: $0.end
                    )
                } ?? []
            case "error":
                throw DiarizationError.transcriptionFailed(pollResponse.error ?? "Unknown error")
            default:
                continue
            }
        }
        throw DiarizationError.timeout
    }

    // MARK: - Step 4: LeMUR name guessing

    private func guessNames(
        transcriptID: String,
        apiKey: String
    ) async throws -> [String: String?] {
        var req = URLRequest(url: try endpoint("/lemur/v3/task"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Analyse this conversation transcript and determine the real name of each \
        speaker, but only if it can be clearly inferred from the conversation itself \
        — for example from direct address ("Thanks Alice"), self-introduction \
        ("I'm Bob"), or an unambiguous reference by another speaker. \
        Return ONLY a valid JSON object mapping each speaker label to their name \
        string, or null if unknown. No explanation, no markdown, just JSON. \
        Example: {"A": "Alice", "B": null, "C": "Bob"}
        """

        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "transcript_ids": [transcriptID],
            "prompt": prompt,
            "final_model": "anthropic/claude-3-5-sonnet"
        ])

        let (data, _) = try await URLSession.shared.data(for: req)
        let lemurResponse = try JSONDecoder().decode(LeMURResponse.self, from: data)
        print("[DiarizationClient] LeMUR raw: \(lemurResponse.response)")

        // Extract the JSON object from LeMUR's response text.
        // LeMUR occasionally wraps output in prose so we scan for {...}.
        let text = lemurResponse.response
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            print("[DiarizationClient] LeMUR returned no JSON object — skipping names")
            return [:]
        }
        let jsonString = String(text[start...end])
        guard let jsonData = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return [:]
        }

        var result: [String: String?] = [:]
        for (key, value) in raw {
            result[key] = value as? String  // NSNull → nil automatically
        }
        return result
    }

    // MARK: - Helpers

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: base + path) else {
            throw DiarizationError.uploadFailed("Invalid URL: \(path)")
        }
        return url
    }
}

// MARK: - Decodable response types

private struct APIErrorResponse: Decodable {
    let error: String
}

private struct TranscriptStatusResponse: Decodable {
    let id: String
    let status: String
    let error: String?
    let utterances: [UtteranceResponse]?
}

private struct UtteranceResponse: Decodable {
    let speaker: String
    let text: String
    let start: Int
    let end: Int
}

private struct LeMURResponse: Decodable {
    let request_id: String
    let response: String
}

// MARK: - Errors

enum DiarizationError: LocalizedError {
    case uploadFailed(String)
    case transcriptionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let msg):        return "Upload failed: \(msg)"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .timeout:                      return "Diarization timed out after 4 minutes."
        }
    }
}
