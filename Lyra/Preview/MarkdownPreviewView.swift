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
                    let blocks = MarkdownPreviewBlocks.parse(text)
                    ForEach(blocks.indices, id: \.self) { index in
                        let block = blocks[index]
                        MarkdownBlockRow(
                            block: block,
                            noteDirectory: noteDirectory,
                            vaultRoot: vaultRoot
                        )
                        // Stable per-block identity: inserting or deleting a block
                        // above must not reuse image loading state for another block.
                        .id("\(index)-\(String(describing: block))")
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
            guard let scheme = url.scheme?.lowercased() else { return .handled }
            if ["http", "https", "mailto"].contains(scheme) {
                return .systemAction
            }
            // Local files open only when they remain inside the vault.
            if scheme == "file", let vaultRoot,
               FileSystemVault.isSafePath(url, within: vaultRoot) {
                return .systemAction
            }
            return .handled
        })
    }
}
