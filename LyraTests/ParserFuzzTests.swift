import XCTest
@testable import Lyra

final class ParserFuzzTests: XCTestCase {
    func testRandomMarkdownDoesNotCrashParsers() {
        var rng = FuzzRNG(seed: 0x4C59_5241)
        for _ in 0..<250 {
            let markdown = randomMarkdown(&rng)
            let utf16 = (markdown as NSString).length
            let links = WikiLinkSyntax.extractLinks(in: markdown)
            for link in links {
                XCTAssertGreaterThanOrEqual(link.range.location, 0)
                XCTAssertLessThanOrEqual(NSMaxRange(link.range), utf16)
            }
            _ = MarkdownPreviewBlocks.parse(markdown)
            for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
                _ = MarkdownImagePath.parseImageLine(String(line))
            }
        }
    }

    private func randomMarkdown(_ rng: inout FuzzRNG) -> String {
        let tokens = [
            "# ", "## ", "- ", "* ", "> ", "```", "[[", "]]", "`",
            "Hello", "World", "Note.md", "/tmp/x.png", "![](", ")",
            "\n", "  ", "café", "😀", "|alias", "---",
        ]
        let count = rng.next(in: 0...80)
        var parts: [String] = []
        parts.reserveCapacity(count)
        for _ in 0..<count {
            parts.append(tokens[rng.next(in: 0...(tokens.count - 1))])
        }
        return parts.joined()
    }
}

/// Tiny deterministic RNG so fuzz input stays stable across runs.
private struct FuzzRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }
}
