import Foundation

/// Holds app-wide configuration loaded from a `.env` file.
///
/// Search order:
///   1. App bundle resources (works if .env is added to Copy Bundle Resources)
///   2. `~/.config/multispeakerapp/.env`  — user-level, survives rebuilds
struct AppConfig {
    let assemblyAIKey: String

    static func load() throws -> AppConfig {
        let candidates: [URL] = [
            // 1. Bundle (may be excluded as a dotfile by Xcode — fallback below)
            Bundle.main.url(forResource: ".env", withExtension: nil),
            // 2. ~/.config/multispeakerapp/.env
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/multispeakerapp/.env")
        ].compactMap { $0 }

        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let config = try? parse(contentsOf: url) { return config }
        }

        throw ConfigError.envFileNotFound
    }

    private static func parse(contentsOf url: URL) throws -> AppConfig {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var keyValues: [String: String] = [:]

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            keyValues[parts[0].trimmingCharacters(in: .whitespaces)] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }

        guard let key = keyValues["ASSEMBLYAI_API_KEY"], !key.isEmpty else {
            throw ConfigError.missingKey("ASSEMBLYAI_API_KEY")
        }
        return AppConfig(assemblyAIKey: key)
    }
}

enum ConfigError: LocalizedError {
    case envFileNotFound
    case missingKey(String)

    var errorDescription: String? {
        switch self {
        case .envFileNotFound:
            return "API key not found. Create ~/.config/multispeakerapp/.env with ASSEMBLYAI_API_KEY=your_key"
        case .missingKey(let key):
            return "'\(key)' is missing or empty in .env."
        }
    }
}
