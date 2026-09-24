import AppKit
import SwiftUI

/// Shared rendered row for one Markdown block in Reading view.
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
                .padding(.top, level <= 2 ? 12 : 6)

        case .paragraph(let content):
            Text(inline(content))
                .font(LyraFonts.prose)
                .lineSpacing(LyraFonts.proseLineSpacing)
                .foregroundStyle(Color(nsColor: LyraTheme.ink))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .listItem(let content, let ordinal, let depth, let taskChecked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let taskChecked {
                    Image(systemName: taskChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(Color(nsColor: LyraTheme.listMarker))
                        .font(.system(size: 14))
                        .frame(minWidth: 16, alignment: .center)
                        .accessibilityLabel(taskChecked ? "Checked" : "Unchecked")
                } else {
                    Text(ordinal.map { "\($0)." } ?? "•")
                        .foregroundStyle(Color(nsColor: LyraTheme.listMarker))
                        .font(LyraFonts.prose)
                        .frame(minWidth: 16, alignment: .trailing)
                }
                Text(inline(content))
                    .font(LyraFonts.prose)
                    .lineSpacing(LyraFonts.proseLineSpacing)
                    .foregroundStyle(Color(nsColor: LyraTheme.ink))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(depth) * 20)

        case .quote(let content):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(LyraTheme.accentColor.opacity(0.7))
                    .frame(width: 3)
                Text(inline(content))
                    .font(LyraFonts.prose)
                    .lineSpacing(LyraFonts.proseLineSpacing)
                    .foregroundStyle(Color(nsColor: LyraTheme.quote))
                    .padding(.leading, 16)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .code(let code):
            Text(code.isEmpty ? " " : code)
                .font(.system(size: 13, design: .monospaced))
                .lineSpacing(3)
                .foregroundStyle(Color(nsColor: LyraTheme.code))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(nsColor: LyraTheme.codeBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(LyraTheme.hairlineColor, lineWidth: 1)
                )

        case .thematicBreak:
            Rectangle()
                .fill(LyraTheme.hairlineColor)
                .frame(height: 1)
                .padding(.vertical, 10)

        case .image(let alt, let path):
            if let noteDirectory, let vaultRoot,
               let url = MarkdownImagePath.resolve(path: path, noteDirectory: noteDirectory, vaultRoot: vaultRoot) {
                MarkdownPreviewImage(url: url, alt: alt, path: path)
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
        guard var attributed = try? AttributedString(markdown: prepared, options: options) else {
            return AttributedString(source)
        }
        // Style wiki + http links with the brand wiki colour.
        for run in attributed.runs {
            guard run.link != nil else { continue }
            let range = run.range
            attributed[range].foregroundColor = Color(nsColor: LyraTheme.wiki)
            attributed[range].underlineStyle = .single
        }
        return attributed
    }
}

private struct MarkdownPreviewImage: View {
    let url: URL
    let alt: String
    let path: String

    @State private var image: NSImage?
    @State private var finishedLoading = false

    var body: some View {
        Group {
            if let image, image.size.width > 0, image.size.height > 0 {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 480, alignment: .leading)
                    .accessibilityLabel(alt.isEmpty ? "Image" : alt)
            } else if finishedLoading {
                Text("Missing image: \(path)")
                    .font(LyraFonts.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading image")
            }
        }
        .task(id: url) {
            image = nil
            finishedLoading = false
            // Load bytes off the main actor. `NSImage` is not Sendable, so
            // decode on this actor after the Data hop (same pattern as before).
            let data = await Task.detached(priority: .utility) {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if size > PreviewImage.maxEncodedBytes { return Data?.none }
                return try? Data(contentsOf: url)
            }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap { PreviewImage.decode($0) }
            finishedLoading = true
        }
    }
}
