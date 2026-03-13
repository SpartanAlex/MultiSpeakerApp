import Foundation

/// Holds app-wide configuration. The API key is persisted in UserDefaults,
/// which is always accessible to sandboxed macOS apps.
struct AppConfig {
    let assemblyAIKey: String

    private static let defaultsKey = "assemblyAIKey"

    // MARK: - Load

    static func load() throws -> AppConfig {
        // 1. UserDefaults (primary — sandbox-safe, persists across launches)
        if let key = UserDefaults.standard.string(forKey: defaultsKey), !key.isEmpty {
            return AppConfig(assemblyAIKey: key)
        }

        // 2. Bundle .env (dev convenience — may be present when running from Xcode)
        if let url = Bundle.main.url(forResource: ".env", withExtension: nil),
           let config = try? parse(contentsOf: url) {
            // Migrate to UserDefaults so future launches don't need the bundle file.
            save(apiKey: config.assemblyAIKey)
            return config
        }

        throw ConfigError.envFileNotFound
    }

    // MARK: - Save

    /// Persists the API key to UserDefaults. Call after the user enters the key in-app.
    static func save(apiKey: String) {
        UserDefaults.standard.set(apiKey, forKey: defaultsKey)
    }

    /// Removes the stored key (for testing / reset).
    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - .env parser

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
            return "AssemblyAI API key not configured. Enter your key in Settings."
        case .missingKey(let key):
            return "'\(key)' is missing or empty."
        }
    }
}
