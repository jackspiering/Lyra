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
                    Text("Nothing to preview").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(MarkdownPreviewBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                        MarkdownBlockRow(
                            block: block,
                            noteDirectory: noteDirectory,
                            vaultRoot: vaultRoot
                        )
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
