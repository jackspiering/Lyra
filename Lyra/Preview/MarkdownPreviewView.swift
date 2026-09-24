import Foundation
import SwiftUI

struct MarkdownPreviewView: View {
    let text: String
    var noteDirectory: URL?
    var vaultRoot: URL?
    var onWikiLink: ((String) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing to read yet.")
                        .font(LyraFonts.prose)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(MarkdownPreviewBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                        MarkdownBlockRow(
                            block: block,
                            noteDirectory: noteDirectory,
                            vaultRoot: vaultRoot
                        )
                    }
                }
            }
            // Same column as the title and Source so ⌘E does not shift the text.
            .frame(maxWidth: LyraTheme.columnWidth, alignment: .leading)
            .padding(.horizontal, LyraTheme.columnMargin)
            .padding(.top, 4)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity)
            .textSelection(.enabled)
        }
        .background(LyraTheme.paperColor)
        .environment(\.openURL, OpenURLAction { url in
            if let name = MarkdownPreviewBlocks.wikiLinkName(from: url) {
                onWikiLink?(name)
                return .handled
            }
            return .systemAction
        })
    }
}
