import Foundation
import SwiftUI

struct MarkdownPreviewView: View {
    let text: String
    var noteDirectory: URL?
    var vaultRoot: URL?
    var onWikiLink: ((String) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing to preview")
                        .font(LyraFonts.body)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(MarkdownPreviewBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                        MarkdownBlockRow(
                            block: block,
                            noteDirectory: noteDirectory,
                            vaultRoot: vaultRoot
                        )
                    }
                    WikiLinksSection(text: text, onWikiLink: onWikiLink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
