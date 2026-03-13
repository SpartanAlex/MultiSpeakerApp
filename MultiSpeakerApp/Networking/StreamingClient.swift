import Foundation

/// Manages the WebSocket connection to AssemblyAI's Universal-3 Pro real-time
/// streaming endpoint. Sends binary PCM Int16 audio frames and receives
/// Turn transcript events.
///
/// All callbacks are dispatched on the main thread.
final class StreamingClient {

    // MARK: - State

    enum State: Equatable {
        case disconnected
        case connecting
        case connected(sessionID: String)
    }

    // MARK: - Callbacks

    /// Called whenever a transcript turn is received.
    /// `transcript` is the current text; `isEndOfTurn` signals a finalised turn.
    var onTurn: ((String, Bool) -> Void)?
    var onStateChange: ((State) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)
    private(set) var state: State = .disconnected

    // MARK: - Connection

    func connect(apiKey: String) {
        guard case .disconnected = state else { return }

        var components = URLComponents()
        components.scheme = "wss"
        components.host = "streaming.assemblyai.com"
        components.path = "/v3/ws"
        components.queryItems = [
            URLQueryItem(name: "sample_rate",   value: "16000"),
            URLQueryItem(name: "speech_model",  value: "u3-rt-pro")
        ]

        guard let url = components.url else {
            print("[StreamingClient] Failed to build WebSocket URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let task = urlSession.webSocketTask(with: request)
        webSocketTask = task
        setState(.connecting)
        task.resume()
        receiveNextMessage()
    }

    /// Sends a Terminate message and closes the connection cleanly.
    func disconnect() {
        let terminateJSON = #"{"type":"Terminate"}"#
        let msg = URLSessionWebSocketTask.Message.string(terminateJSON)

        webSocketTask?.send(msg) { [weak self] _ in
            self?.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self?.webSocketTask = nil
            self?.setState(.disconnected)
        }
    }

    /// Sends a raw PCM Int16 audio chunk as a binary WebSocket frame.
    /// Safe to call from any thread.
    func send(audioChunk: Data) {
        guard case .connected = state else { return }
        webSocketTask?.send(.data(audioChunk)) { error in
            if let error {
                print("[StreamingClient] Audio send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Receiving

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handle(message: message)
                self.receiveNextMessage()   // recurse to keep reading
            case .failure(let error):
                print("[StreamingClient] Receive error: \(error.localizedDescription)")
                self.setState(.disconnected)
                DispatchQueue.main.async { self.onError?(error) }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return }

        do {
            let event = try JSONDecoder().decode(ServerEvent.self, from: data)

            switch event.type {
            case "Begin":
                let id = event.id ?? "unknown"
                print("[StreamingClient] Session began — id: \(id)")
                setState(.connected(sessionID: id))

            case "Turn":
                let transcript  = event.transcript ?? ""
                let isEndOfTurn = event.end_of_turn ?? false
                let marker = isEndOfTurn ? "✓" : "…"
                print("[StreamingClient] Turn \(marker): \(transcript)")
                DispatchQueue.main.async {
                    self.onTurn?(transcript, isEndOfTurn)
                }

            case "Termination":
                let duration = event.audio_duration_seconds ?? 0
                print("[StreamingClient] Session terminated — " +
                      "audio duration: \(String(format: "%.2f", duration))s")
                setState(.disconnected)

            default:
                print("[StreamingClient] Unknown event type: '\(event.type)'")
            }
        } catch {
            print("[StreamingClient] JSON decode error: \(error) — raw: \(text)")
        }
    }

    // MARK: - Helpers

    private func setState(_ newState: State) {
        state = newState
        DispatchQueue.main.async {
            self.onStateChange?(newState)
        }
    }
}

// MARK: - Server event schema

/// All possible fields across every server event type.
/// `type` is the discriminator; other fields are optional per event.
private struct ServerEvent: Decodable {
    let type: String
    // Begin
    let id: String?
    // Turn
    let transcript: String?
    let end_of_turn: Bool?
    // Termination
    let audio_duration_seconds: Double?
}
