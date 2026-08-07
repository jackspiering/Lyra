import Foundation
import SwiftUI

struct MarkdownPreviewView: View {
    let text: String
    var noteDirectory: URL?
    var vaultRoot: URL?
    var onWikiLink: ((String) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .environment(\.openURL, OpenURLAction { url in
            if let name = MarkdownPreviewBlocks.wikiLinkName(from: url) {
                onWikiLink?(name)
                return .handled
            }
            return .systemAction
        })
    }
}
