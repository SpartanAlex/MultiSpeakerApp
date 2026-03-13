import SwiftUI

/// Maps speaker labels (e.g. "A", "B") to display names and colours.
/// Display names persist in UserDefaults across the session.
final class SpeakerMap: ObservableObject {

    // MARK: - Published

    /// Custom display names keyed by speaker label.
    @Published private(set) var names: [String: String] = [:]

    // MARK: - Colours

    /// A deterministic palette — same label always gets the same colour,
    /// stable across renames and relaunches.
    private static let palette: [Color] = [
        Color(red: 0.20, green: 0.46, blue: 0.90), // blue
        Color(red: 0.18, green: 0.68, blue: 0.51), // teal
        Color(red: 0.83, green: 0.37, blue: 0.22), // orange
        Color(red: 0.62, green: 0.32, blue: 0.82), // purple
        Color(red: 0.82, green: 0.22, blue: 0.42), // rose
        Color(red: 0.45, green: 0.65, blue: 0.22), // green
        Color(red: 0.90, green: 0.65, blue: 0.10), // amber
        Color(red: 0.25, green: 0.60, blue: 0.75), // cyan
    ]

    // MARK: - Public API

    /// Display name for a speaker label, falling back to "Speaker X".
    func displayName(for label: String) -> String {
        names[label] ?? "Speaker \(label)"
    }

    /// Colour assigned to a speaker label — deterministic by label string.
    func color(for label: String) -> Color {
        let index = label.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palette[index % Self.palette.count]
    }

    /// Set a custom display name for a speaker.
    func setName(_ name: String, for label: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        names[label] = trimmed.isEmpty ? nil : trimmed
        objectWillChange.send()
    }

    /// Resets all custom names.
    func reset() {
        names.removeAll()
    }
}
