import SwiftUI

/// Quiet floating pill in the corner of the note: word/character counts and last save.
/// The created date lives in the tooltip so the pill stays one short line.
struct EditorStatusBar: View {
    let wordCount: Int
    let characterCount: Int
    let created: Date?
    let lastSaved: Date?

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
