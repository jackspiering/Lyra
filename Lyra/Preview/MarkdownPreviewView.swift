import Foundation
import SwiftUI

struct MarkdownPreviewView: View {
    let text: String
    var onWikiLink: ((String) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing to preview").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(MarkdownPreviewBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                    wikiLinks
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownPreviewBlocks.Block) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(inline(content))
                .font(headingFont(level))
                .foregroundStyle(Color(nsColor: LyraTheme.heading))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(let content):
            Text(inline(content))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .listItem(let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(Color(nsColor: LyraTheme.listMarker))
                Text(inline(content))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .quote(let content):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(LyraTheme.accentColor)
                    .frame(width: 3)
                Text(inline(content))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .code(let code):
            Text(code.isEmpty ? " " : code)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color(nsColor: LyraTheme.code))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: LyraTheme.codeBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)

        case .image(let alt, let path):
            Text(alt.isEmpty ? "Image: \(path)" : "\(alt) (\(path))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .largeTitle.weight(.bold)
        case 2: return .title.weight(.semibold)
        case 3: return .title2.weight(.semibold)
        case 4: return .title3.weight(.semibold)
        default: return .headline
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

    @ViewBuilder
    private var wikiLinks: some View {
        let links = linkNames(in: text)
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
