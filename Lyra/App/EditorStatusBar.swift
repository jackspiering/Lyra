import SwiftUI

/// Bottom strip under the note detail: word/letter counts and file dates.
struct EditorStatusBar: View {
    let wordCount: Int
    let letterCount: Int
    let created: Date?
    let lastSaved: Date?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 16) {
            stat("Words", value: "\(wordCount)")
            stat("Letters", value: "\(letterCount)")
            if let created {
                stat("Created", value: Self.dateFormatter.string(from: created))
            }
            if let lastSaved {
                stat("Saved", value: Self.dateFormatter.string(from: lastSaved))
            }
            Spacer(minLength: 0)
        }
        .font(LyraFonts.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func stat(_ label: String, value: String) -> some View {
        Text("\(label) \(value)")
            .lineLimit(1)
    }
}
