import Foundation

// MARK: - Provider enum

/// All supported AI summary providers. Add new cases here to extend support.
enum AIProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case openAI = "OpenAI"

    var id: String { rawValue }

    var apiKeyDefaultsKey: String {
        switch self {
        case .claude: return "claudeAPIKey"
        case .openAI: return "openAIAPIKey"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-…"
        case .openAI: return "sk-…"
        }
    }
}

// MARK: - Shared prompt

private let summaryPrompt = """
Please provide a structured summary of the following conversation transcript. Include:
• **Overview** – a 2–3 sentence description of what the conversation was about.
• **Key topics** – the main subjects discussed.
• **Decisions & action items** – any conclusions reached or next steps mentioned.
• **Speaker highlights** – a brief note on each speaker's main contributions, if identifiable.

Transcript:
"""

// MARK: - Summarizer

/// Routes summarisation requests to the selected AI provider.
struct Summarizer {

    func summarize(
        transcript: String,
        provider: AIProvider,
        apiKey: String
    ) async throws -> String {
        switch provider {
        case .claude:  return try await claude(transcript: transcript, apiKey: apiKey)
        case .openAI:  return try await openAI(transcript: transcript, apiKey: apiKey)
        }
    }

    // MARK: - Claude (Anthropic)

    private func claude(transcript: String, apiKey: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey,      forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1024,
            "messages": [["role": "user", "content": summaryPrompt + "\n\n" + transcript]]
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw SummaryError.providerError(extractError(from: data, http: status))
        }

        struct Resp: Decodable { struct Block: Decodable { let text: String }; let content: [Block] }
        return try JSONDecoder().decode(Resp.self, from: data).content.first?.text ?? ""
    }

    // MARK: - OpenAI

    private func openAI(transcript: String, apiKey: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o",
            "messages": [["role": "user", "content": summaryPrompt + "\n\n" + transcript]]
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw SummaryError.providerError(extractError(from: data, http: status))
        }

        struct Resp: Decodable {
            struct Choice: Decodable { struct Msg: Decodable { let content: String }; let message: Msg }
            let choices: [Choice]
        }
        return try JSONDecoder().decode(Resp.self, from: data).choices.first?.message.content ?? ""
    }

    // MARK: - Helpers

    private func extractError(from data: Data, http status: Int) -> String {
        // Both Claude and OpenAI use {"error": {"message": "..."}} shape.
        struct Wrapper: Decodable { struct Err: Decodable { let message: String }; let error: Err }
        if let w = try? JSONDecoder().decode(Wrapper.self, from: data) { return w.error.message }
        return String(data: data, encoding: .utf8) ?? "HTTP \(status)"
    }
}

// MARK: - Errors

enum SummaryError: LocalizedError {
    case missingKey
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:          return "An API key is required to generate a summary."
        case .providerError(let m): return m
        }
    }
}
