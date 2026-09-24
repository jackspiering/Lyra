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

private struct ImageVersion: Hashable {
    let path: String
    let modificationDate: Date?
    let fileSize: Int?

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        path = url.path
        modificationDate = values?.contentModificationDate
        fileSize = values?.fileSize
    }
}

private struct MarkdownPreviewImage: View {
    let url: URL
    let alt: String
    let path: String

    @State private var image: NSImage?
    @State private var finishedLoading = false
    @State private var failure: String?

    var body: some View {
        Group {
            if let image, image.size.width > 0, image.size.height > 0 {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 480, alignment: .leading)
                    .accessibilityLabel(alt.isEmpty ? "Image" : alt)
            } else if finishedLoading {
                Text(failure ?? "Missing image: \(path)")
                    .font(LyraFonts.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading image")
            }
        }
        .task(id: ImageVersion(url: url)) {
            image = nil
            failure = nil
            finishedLoading = false
            // Bytes load off the main actor with a no-follow, bounded read.
            // Decoding stays on this actor: `NSImage` is not Sendable, so it
            // cannot cross back from a detached task.
            let data = await Task.detached(priority: .utility) {
                FileSystemVault.safeBoundedData(at: url, maxBytes: PreviewImage.maxEncodedBytes)
            }.value
            guard !Task.isCancelled else { return }
            guard let data else {
                failure = "Couldn't read image: \(url.lastPathComponent)"
                finishedLoading = true
                return
            }
            guard let decoded = PreviewImage.decode(data) else {
                failure = "Image is too large or couldn't be decoded: \(url.lastPathComponent)"
                finishedLoading = true
                return
            }
            image = decoded
            finishedLoading = true
        }
    }
}
