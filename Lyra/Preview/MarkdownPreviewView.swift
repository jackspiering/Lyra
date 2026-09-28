import Foundation
import SwiftUI

struct MarkdownPreviewView: View {
    let text: String
    var noteDirectory: URL?
    var vaultRoot: URL?
    var onWikiLink: ((String) -> Void)?
    /// Relative link to a Markdown note inside the vault.
    var onNoteLink: ((URL) -> Void)?

    /// Parsed blocks for the last text seen, so a window redraw that leaves
    /// the note unchanged does not parse it again.
    @State private var cache = BlockCache()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                let blocks = cache.blocks(for: text)
                if blocks.isEmpty {
                    Text("Nothing to read yet.")
                        .font(LyraFonts.prose)
                        .foregroundStyle(.secondary)
                } else {
                    // Identity is position plus content: inserting or deleting
                    // a block above must not reuse another block's image state.
                    ForEach(blocks) { item in
                        MarkdownBlockRow(
                            block: item.block,
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
            switch MarkdownPreviewBlocks.linkTarget(for: url, noteDirectory: noteDirectory, vaultRoot: vaultRoot) {
            case .wiki(let name):
                onWikiLink?(name)
                return .handled
            case .note(let note):
                onNoteLink?(note)
                return .handled
            case .external:
                return .systemAction
            case .unsupported:
                return .discarded
            }
        })
    }
}

/// One Reading block with an identity made of its position and content.
struct PreviewBlockItem: Identifiable, Hashable {
    let index: Int
    let block: MarkdownPreviewBlocks.Block
    var id: Self { self }
}

/// Memo for `MarkdownPreviewBlocks.parse`. A reference type so updating it
/// while `body` runs does not invalidate the view.
final class BlockCache {
    private var text: String?
    private var items: [PreviewBlockItem] = []

    func blocks(for text: String) -> [PreviewBlockItem] {
        if text != self.text {
            self.text = text
            items = MarkdownPreviewBlocks.parse(text).enumerated().map {
                PreviewBlockItem(index: $0.offset, block: $0.element)
            }
        }
        return items
    }
}
