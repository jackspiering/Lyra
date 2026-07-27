import AppKit
import SwiftUI

/// Shared rendered row for one Markdown block (Reading + Live Preview idle).
struct MarkdownBlockRow: View {
    let block: MarkdownPreviewBlocks.Block
    var noteDirectory: URL?
    var vaultRoot: URL?

    var body: some View {
        switch block {
        case .heading(let level, let content):
            Text(inline(content))
                .font(LyraFonts.heading(level: level))
                .foregroundStyle(Color(nsColor: LyraTheme.heading))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(let content):
            Text(inline(content))
                .font(LyraFonts.body)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .listItem(let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(Color(nsColor: LyraTheme.listMarker))
                Text(inline(content))
                    .font(LyraFonts.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .quote(let content):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(LyraTheme.accentColor)
                    .frame(width: 3)
                Text(inline(content))
                    .font(LyraFonts.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .code(let code):
            Text(code.isEmpty ? " " : code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(nsColor: LyraTheme.code))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: LyraTheme.codeBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)

        case .image(let alt, let path):
            if let noteDirectory, let vaultRoot,
               let url = MarkdownImagePath.resolve(path: path, noteDirectory: noteDirectory, vaultRoot: vaultRoot),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 480, alignment: .leading)
                    .accessibilityLabel(alt.isEmpty ? "Image" : alt)
            } else {
                Text("Missing image: \(path)")
                    .font(LyraFonts.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func inline(_ source: String) -> AttributedString {
        let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown(source)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let attributed = try? AttributedString(markdown: prepared, options: options) {
            return attributed
        }
        return AttributedString(source)
    }
}
