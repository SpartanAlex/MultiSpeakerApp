import SwiftUI

struct SummarySheet: View {
    /// The full transcript text to summarise.
    let transcript: String

    @Environment(\.dismiss) private var dismiss

    // Provider selection
    @AppStorage("selectedSummaryProvider") private var selectedProvider = AIProvider.claude.rawValue
    private var provider: AIProvider { AIProvider(rawValue: selectedProvider) ?? .claude }

    // Per-provider API keys
    @AppStorage("claudeAPIKey") private var claudeKey  = ""
    @AppStorage("openAIAPIKey") private var openAIKey  = ""

    private var currentKey: String {
        get { provider == .claude ? claudeKey : openAIKey }
    }
    private func setCurrentKey(_ v: String) {
        if provider == .claude { claudeKey = v } else { openAIKey = v }
    }

    // Generation state
    @State private var summary       = ""
    @State private var isGenerating  = false
    @State private var errorMessage: String?
    @State private var keyEntry      = ""

    private let summarizer = Summarizer()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack {
                Text("Summarise Conversation")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            // Provider picker
            Picker("Provider", selection: $selectedProvider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.rawValue).tag(p.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedProvider) { _ in
                errorMessage = nil
                keyEntry = currentKey
            }

            // API key field
            HStack {
                SecureField(provider.keyPlaceholder, text: $keyEntry)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onAppear { keyEntry = currentKey }

                Button("Save") {
                    setCurrentKey(keyEntry.trimmingCharacters(in: .whitespaces))
                }
                .disabled(keyEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Generate button
            Button(action: generate) {
                if isGenerating {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("Generating…")
                    }
                } else {
                    Label("Generate Summary", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || currentKey.isEmpty)

            // Error
            if let err = errorMessage {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            // Summary output
            if !summary.isEmpty {
                Divider()

                HStack {
                    Text("Summary").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }

                ScrollView {
                    Text(summary)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(minHeight: 200)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 340)
    }

    private func generate() {
        let key = currentKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { errorMessage = SummaryError.missingKey.localizedDescription; return }
        errorMessage = nil
        summary = ""
        isGenerating = true

        Task {
            do {
                let result = try await summarizer.summarize(
                    transcript: transcript,
                    provider: provider,
                    apiKey: key
                )
                await MainActor.run { summary = result; isGenerating = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isGenerating = false }
            }
        }
    }
}
