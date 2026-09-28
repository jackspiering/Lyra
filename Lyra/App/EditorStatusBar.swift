import SwiftUI

/// Below this many UTF-8 bytes (an O(1) count), counting takes well under a millisecond.
private let statusBarInlineCountLimit = 20_000

/// Quiet floating pill in the corner of the note: word/character counts and last save.
/// The created date lives in the tooltip so the pill stays one short line.
struct EditorStatusBar: View {
    let text: String
    let created: Date?
    let lastSaved: Date?
    @State private var wordCount = 0
    @State private var characterCount = 0

    var body: some View {
        HStack(spacing: 0) {
            Text(wordCount == 1 ? "1 word" : "\(wordCount.formatted()) words")
            sep
            Text(characterCount == 1 ? "1 character" : "\(characterCount.formatted()) characters")
            if let lastSaved {
                sep
                Text("Saved \(Self.shortStamp(lastSaved))")
            }
        }
        .font(LyraFonts.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(LyraTheme.hairlineColor, lineWidth: 1))
        .help(created.map { "Created \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
        .accessibilityElement(children: .combine)
        .task(id: text) {
            // Short notes count at once, so switching notes never shows the
            // previous note's numbers. Long ones wait for a typing pause and
            // count off the main actor.
            if text.utf8.count <= statusBarInlineCountLimit {
                wordCount = NoteStats.wordCount(text)
                characterCount = NoteStats.characterCount(text)
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let counts = await Task.detached(priority: .utility) {
                (NoteStats.wordCount(text), NoteStats.characterCount(text))
            }.value
            guard !Task.isCancelled else { return }
            wordCount = counts.0
            characterCount = counts.1
        }
    }

    private var sep: some View {
        Text("  ·  ").foregroundStyle(.tertiary)
    }

    /// Time only for today; date and time otherwise.
    private static func shortStamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
