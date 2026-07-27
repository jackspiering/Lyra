import AppKit
import SwiftUI

/// Hybrid Live Preview: rendered blocks; click a block to edit its raw Markdown.
struct LivePreviewView: View {
    @Binding var text: String
    var noteDirectory: URL?
    var vaultRoot: URL?
    var onWikiLink: ((String) -> Void)?
    var onEdit: () -> Void
    var onPasteError: ((String) -> Void)?
    /// Bump from the parent to force-commit an open block edit (mode/note switch).
    var commitToken: Int = 0

    @State private var focusedIndex: Int?
    @State private var draft = ""
    @State private var editRange = NSRange(location: 0, length: 0)
    @State private var frozenBlocks: [MarkdownPreviewBlocks.RangedBlock] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if isEffectivelyEmpty && focusedIndex == nil {
                    emptyEditor
                } else if let focusedIndex {
                    focusedContent(focusedIndex)
                } else {
                    idleContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: commitToken) { _, _ in
            commitFocus()
        }
        .onDisappear {
            commitFocus()
        }
        .onChange(of: text) { _, newValue in
            // External note switch / reload: drop focus if document replaced.
            if focusedIndex != nil {
                let ns = newValue as NSString
                if editRange.location + editRange.length > ns.length {
                    focusedIndex = nil
                    frozenBlocks = []
                }
            }
        }
        .onExitCommand {
            commitFocus()
        }
    }

    private var isEffectivelyEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyEditor: some View {
        MarkdownTextView(
            text: $text,
            vaultRoot: vaultRoot,
            onEdit: onEdit,
            onPasteError: onPasteError
        )
        .frame(minHeight: 200)
    }

    private var idleContent: some View {
        let blocks = MarkdownPreviewBlocks.parseRanged(text)
        return Group {
            if blocks.isEmpty {
                emptyEditor
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, ranged in
                    MarkdownBlockRow(
                        block: ranged.block,
                        noteDirectory: noteDirectory,
                        vaultRoot: vaultRoot
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginEdit(index: index, blocks: blocks)
                    }
                }
                wikiLinks(in: text)
            }
        }
    }

    @ViewBuilder
    private func focusedContent(_ index: Int) -> some View {
        ForEach(Array(frozenBlocks.enumerated()), id: \.offset) { i, ranged in
            if i == index {
                VStack(alignment: .leading, spacing: 6) {
                    MarkdownTextView(
                        text: $draft,
                        vaultRoot: vaultRoot,
                        onEdit: {},
                        onPasteError: onPasteError
                    )
                    .frame(minHeight: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(LyraTheme.accentColor.opacity(0.5), lineWidth: 1)
                    )
                    HStack {
                        Button("Done") { commitFocus() }
                            .keyboardShortcut(.defaultAction)
                        Button("Cancel") { cancelFocus() }
                        Spacer()
                    }
                    .font(.caption)
                }
            } else {
                MarkdownBlockRow(
                    block: ranged.block,
                    noteDirectory: noteDirectory,
                    vaultRoot: vaultRoot
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    commitFocus()
                    let blocks = MarkdownPreviewBlocks.parseRanged(text)
                    if i < blocks.count {
                        beginEdit(index: i, blocks: blocks)
                    }
                }
            }
        }
    }

    private func beginEdit(index: Int, blocks: [MarkdownPreviewBlocks.RangedBlock]) {
        guard index >= 0, index < blocks.count else { return }
        let ranged = blocks[index]
        frozenBlocks = blocks
        focusedIndex = index
        editRange = ranged.range
        let ns = text as NSString
        if ranged.range.location + ranged.range.length <= ns.length {
            draft = ns.substring(with: ranged.range)
        } else {
            draft = ""
        }
    }

    private func commitFocus() {
        guard focusedIndex != nil else { return }
        let next = MarkdownPreviewBlocks.replacing(in: text, range: editRange, with: draft)
        if next != text {
            text = next
            onEdit()
        }
        focusedIndex = nil
        frozenBlocks = []
        draft = ""
    }

    private func cancelFocus() {
        focusedIndex = nil
        frozenBlocks = []
        draft = ""
    }

    @ViewBuilder
    private func wikiLinks(in source: String) -> some View {
        let links = linkNames(in: source)
        if !links.isEmpty {
            Divider().padding(.top, 8)
            Text("Wiki links")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(links, id: \.self) { name in
                Button {
                    onWikiLink?(name)
                } label: {
                    Text("[[\(name)]]")
                        .foregroundStyle(LyraTheme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func linkNames(in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return [] }
        let ns = source as NSString
        var names: [String] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: source, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let name = ns.substring(with: match.range(at: 1))
            if seen.insert(name).inserted { names.append(name) }
        }
        return names
    }
}
