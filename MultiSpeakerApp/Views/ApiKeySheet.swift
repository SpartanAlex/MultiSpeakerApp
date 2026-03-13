import SwiftUI

/// Presented when no AssemblyAI API key is configured.
/// The user pastes their key once; it is saved to UserDefaults.
struct ApiKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var keyText = ""
    @State private var showError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter AssemblyAI API Key")
                .font(.headline)

            Text("Your key is stored locally on this Mac and is never shared.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField("Paste your API key here…", text: $keyText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            if showError {
                Text("Key cannot be empty.")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        let trimmed = keyText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { showError = true; return }
        AppConfig.save(apiKey: trimmed)
        appState.reloadConfig()
        dismiss()
    }
}
