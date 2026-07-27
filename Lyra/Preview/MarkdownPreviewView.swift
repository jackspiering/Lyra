import Foundation
import SwiftUI

struct MarkdownPreviewView: View {
    let text: String
    var onWikiLink: ((String) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if text.isEmpty {
                    Text("Nothing to preview")
                        .foregroundStyle(.secondary)
                } else {
                    markdownBody
                    wikiLinksSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var markdownBody: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            ) {
                Text(attributed)
            } else {
                Text(text).font(.body)
            }
        }
    }

    @ViewBuilder
    private var wikiLinksSection: some View {
        let links = Self.linkNames(in: text)
        if !links.isEmpty {
            Divider()
            Text("Wiki links")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(links, id: \.self) { name in
                Button {
                    onWikiLink?(name)
                } label: {
                    Text("[[\(name)]]")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func linkNames(in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else {
            return []
        }
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)
        var names: [String] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: source, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let name = ns.substring(with: match.range(at: 1))
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }
}
