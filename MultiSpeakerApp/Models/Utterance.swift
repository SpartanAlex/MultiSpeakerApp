import Foundation

/// A single turn of speech in the transcript.
/// Created during live streaming (no speaker label yet) and enriched with
/// speaker information after async diarization completes.
struct Utterance: Identifiable {
    let id: UUID
    /// Sequential index used as placeholder label before diarization.
    let turnIndex: Int
    /// The transcribed text for this turn.
    var text: String
    /// Speaker label returned by AssemblyAI diarization (e.g. "A", "B").
    var speakerLabel: String?
    /// Custom display name set by the user or suggested by LeMUR (e.g. "Alice").
    var displayName: String?

    init(turnIndex: Int, text: String) {
        self.id = UUID()
        self.turnIndex = turnIndex
        self.text = text
    }

    /// The best available label to show in the UI.
    var effectiveLabel: String {
        if let name = displayName, !name.isEmpty { return name }
        if let label = speakerLabel { return "Speaker \(label)" }
        return "Turn \(turnIndex + 1)"
    }
}
