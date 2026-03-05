import Foundation

/// Holds app-wide configuration loaded from the `.env` file in the app bundle.
struct AppConfig {
    let assemblyAIKey: String

    static func load() throws -> AppConfig {
        guard let envURL = Bundle.main.url(forResource: ".env", withExtension: nil) else {
            throw ConfigError.envFileNotFound
        }
        let contents = try String(contentsOf: envURL, encoding: .utf8)
        var keyValues: [String: String] = [:]

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            // Split on first `=` only, to allow `=` in values
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            keyValues[key] = value
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
            return ".env file not found in app bundle. Add it to Copy Bundle Resources."
        case .missingKey(let key):
            return "'\(key)' is missing or empty in .env."
        }
    }
}
