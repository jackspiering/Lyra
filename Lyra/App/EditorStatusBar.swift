import SwiftUI

/// Bottom strip under the note detail: word/character counts and file dates.
struct EditorStatusBar: View {
    let wordCount: Int
    let characterCount: Int
    let created: Date?
    let lastSaved: Date?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            Text("Words \(wordCount)")
            sep
            Text("Characters \(characterCount)")
            if let created {
                sep
                Text("Created \(Self.dateFormatter.string(from: created))")
            }
            if let lastSaved {
                sep
                Text("Saved \(Self.dateFormatter.string(from: lastSaved))")
            }
            Spacer(minLength: 0)
        }
        .font(LyraFonts.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var sep: some View {
        Text("  |  ").foregroundStyle(.tertiary)
    }
}
