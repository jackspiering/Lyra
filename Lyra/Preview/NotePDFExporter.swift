import AppKit

/// Builds US Letter PDF `Data` from note markdown (native AppKit / Core Graphics).
enum NotePDFExporter {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 54
    private static let blockGap: CGFloat = 10
    private static let contentWidth: CGFloat = pageWidth - margin * 2
    private static let contentHeight: CGFloat = pageHeight - margin * 2

    // Print-safe colors (not semantic — avoid light-on-light when host is dark mode).
    private static let bodyColor = NSColor.black
    private static let secondaryColor = NSColor(calibratedWhite: 0.35, alpha: 1)
    private static let codeBackgroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
    private static let quoteBarColor = NSColor(calibratedRed: 0.85, green: 0.65, blue: 0.13, alpha: 1)
    private static let ruleColor = NSColor(calibratedWhite: 0.7, alpha: 1)
    /// Print-safe link colour (wiki + http) so PDF matches Reading intent.
    private static let linkColor = NSColor(calibratedRed: 0.15, green: 0.25, blue: 0.65, alpha: 1)

    /// One note (or section) to place into a PDF.
    struct NoteSource: Equatable {
        var title: String
        var markdown: String
        var noteDirectory: URL
    }

    static func pdfData(markdown: String, noteDirectory: URL, vaultRoot: URL) throws -> Data {
        try pdfData(
            notes: [NoteSource(title: "", markdown: markdown, noteDirectory: noteDirectory)],
            vaultRoot: vaultRoot
        )
    }

    /// Multiple notes in one PDF (each optional title as H1; page break between notes).
    static func pdfData(notes: [NoteSource], vaultRoot: URL) throws -> Data {
        try Renderer(notes: notes, vaultRoot: vaultRoot).run()
    }

    // MARK: - Renderer

    private final class Renderer {
        let notes: [NoteSource]
        let vaultRoot: URL

        private var ctx: CGContext!
        private var y: CGFloat = 0
        private var pageNumber = 1
        private var noteDirectory: URL
        private let contentBottom = NotePDFExporter.pageHeight - NotePDFExporter.margin

        init(notes: [NoteSource], vaultRoot: URL) {
            self.notes = notes
            self.vaultRoot = vaultRoot
            self.noteDirectory = notes.first?.noteDirectory ?? vaultRoot
        }

        func run() throws -> Data {
            let pageRect = CGRect(
                x: 0, y: 0,
                width: NotePDFExporter.pageWidth,
                height: NotePDFExporter.pageHeight
            )
            let data = NSMutableData()
            guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
                throw CocoaError(.fileWriteUnknown)
            }
            var mediaBox = pageRect
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            ctx = context

            beginPage()
            for (index, note) in notes.enumerated() {
                if index > 0 {
                    endPage()
                    beginPage()
                }
                noteDirectory = note.noteDirectory
                if !note.title.isEmpty {
                    drawTextSpanning(note.title, font: headingFont(1), color: NotePDFExporter.bodyColor)
                }
                for block in MarkdownPreviewBlocks.parse(note.markdown) {
                    draw(block)
                }
            }
            endPage()
            ctx.closePDF()
            return data as Data
        }

        // MARK: Pages

        private func beginPage() {
            ctx.beginPDFPage(nil)
            // PDF media box is bottom-up. Map layout coords (origin top-left, y down) onto it
            // so AppKit text/images are upright in Preview.app.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: NotePDFExporter.pageHeight)
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            y = NotePDFExporter.margin
        }

        private func endPage() {
            drawPageNumber()
            NSGraphicsContext.current = nil
            ctx.restoreGState()
            ctx.endPDFPage()
            pageNumber += 1
        }

        private func drawPageNumber() {
            let text = "\(pageNumber)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NotePDFExporter.secondaryColor,
            ]
            let attr = NSAttributedString(string: text, attributes: attrs)
            let size = attr.size()
            let x = (NotePDFExporter.pageWidth - size.width) / 2
            // Footer just above the bottom margin (top-down layout coords).
            let pageY = NotePDFExporter.pageHeight - 36
            attr.draw(at: CGPoint(x: x, y: pageY))
        }

        private var remainingHeight: CGFloat { contentBottom - y }

        /// Start a new page when the next fragment needs more room (unless already at top).
        private func ensureSpace(_ height: CGFloat) {
            if height > remainingHeight, y > NotePDFExporter.margin + 0.5 {
                endPage()
                beginPage()
            }
        }

        // MARK: Blocks

        private func draw(_ block: MarkdownPreviewBlocks.Block) {
            switch block {
            case .heading(let level, let text):
                drawTextSpanning(text, font: headingFont(level), color: NotePDFExporter.bodyColor)

            case .paragraph(let text):
                drawTextSpanning(text, font: bodyFont, color: NotePDFExporter.bodyColor)

            case .listItem(let text, let ordinal, let depth, let taskChecked):
                drawListItem(text, ordinal: ordinal, depth: depth, taskChecked: taskChecked)

            case .quote(let text):
                drawQuote(text)

            case .code(let code):
                drawCode(code)

            case .thematicBreak:
                drawThematicBreak()

            case .image(let alt, let path):
                drawImage(alt: alt, path: path)
            }
        }

        /// Draw attributed text, splitting across pages when taller than the remaining space.
        private func drawTextSpanning(
            _ text: String,
            font: NSFont,
            color: NSColor,
            x: CGFloat = NotePDFExporter.margin,
            width: CGFloat = NotePDFExporter.contentWidth
        ) {
            let full = makeAttributed(text, font: font, color: color)
            var offset = 0
            let ns = full.string as NSString
            let total = ns.length
            guard total > 0 else { return }

            while offset < total {
                ensureSpace(min(20, remainingHeight))
                let available = remainingHeight
                let fit = charactersFitting(
                    full,
                    from: offset,
                    width: width,
                    maxHeight: available
                )
                let length = max(1, fit)
                let range = NSRange(location: offset, length: min(length, total - offset))
                let slice = full.attributedSubstring(from: range)
                let height = measure(slice, width: width)
                let rect = CGRect(x: x, y: y, width: width, height: height)
                slice.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += height
                offset += range.length
                if offset < total {
                    endPage()
                    beginPage()
                }
            }
            y += NotePDFExporter.blockGap
        }

        /// Binary search for the longest prefix (from `from`) that fits in `maxHeight`.
        private func charactersFitting(
            _ attr: NSAttributedString,
            from: Int,
            width: CGFloat,
            maxHeight: CGFloat
        ) -> Int {
            let total = attr.length - from
            guard total > 0 else { return 0 }
            if measure(attr.attributedSubstring(from: NSRange(location: from, length: total)), width: width) <= maxHeight {
                return total
            }
            var low = 1
            var high = total
            while low < high {
                let mid = (low + high + 1) / 2
                let sub = attr.attributedSubstring(from: NSRange(location: from, length: mid))
                if measure(sub, width: width) <= maxHeight {
                    low = mid
                } else {
                    high = mid - 1
                }
            }
            // Prefer breaking near a line boundary when possible.
            let ns = attr.string as NSString
            let window = ns.substring(with: NSRange(location: from, length: low)) as NSString
            let br = window.rangeOfCharacter(from: .newlines, options: .backwards)
            if br.location != NSNotFound, br.location > 0 {
                return br.location + 1
            }
            if low > 20 {
                let sp = window.rangeOfCharacter(from: .whitespaces, options: .backwards)
                if sp.location != NSNotFound, sp.location > low / 2 {
                    return sp.location + 1
                }
            }
            return max(1, low)
        }

        private func drawListItem(_ text: String, ordinal: Int?, depth: Int, taskChecked: Bool?) {
            let indent = CGFloat(depth) * 16
            let marker: String
            if let taskChecked {
                marker = taskChecked ? "☑" : "☐"
            } else {
                marker = ordinal.map { "\($0)." } ?? "•"
            }
            let bulletAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: NotePDFExporter.secondaryColor,
            ]
            let bullet = NSAttributedString(string: marker, attributes: bulletAttrs)
            let body = makeAttributed(text, font: bodyFont, color: NotePDFExporter.bodyColor)
            let bulletWidth: CGFloat = (ordinal != nil || taskChecked != nil) ? 28 : 16
            let x = NotePDFExporter.margin + indent
            let bodyWidth = NotePDFExporter.contentWidth - indent - bulletWidth
            let height = max(measure(body, width: bodyWidth), bodyFont.ascender - bodyFont.descender)
            ensureSpace(height)
            bullet.draw(at: CGPoint(x: x, y: y))
            let rect = CGRect(
                x: x + bulletWidth,
                y: y,
                width: bodyWidth,
                height: height
            )
            body.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += height + NotePDFExporter.blockGap
        }

        private func drawQuote(_ text: String) {
            let barWidth: CGFloat = 3
            let pad: CGFloat = 10
            let body = makeAttributed(text, font: bodyFont, color: NotePDFExporter.secondaryColor)
            let textWidth = NotePDFExporter.contentWidth - barWidth - pad
            let height = max(measure(body, width: textWidth), 16)
            ensureSpace(height)
            let bar = CGRect(
                x: NotePDFExporter.margin,
                y: y,
                width: barWidth,
                height: height
            )
            NotePDFExporter.quoteBarColor.setFill()
            bar.fill()
            let rect = CGRect(
                x: NotePDFExporter.margin + barWidth + pad,
                y: y,
                width: textWidth,
                height: height
            )
            body.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += height + NotePDFExporter.blockGap
        }

        /// Code is uniform line-height text — split by lines that fit each page.
        private func drawCode(_ code: String) {
            let display = code.isEmpty ? " " : code
            let font = LyraFonts.code(size: 11)
            let padding: CGFloat = 8
            let textWidth = NotePDFExporter.contentWidth - padding * 2
            let lines = display.components(separatedBy: "\n")
            var index = 0
            while index < lines.count {
                ensureSpace(min(40, remainingHeight))
                let available = remainingHeight - padding * 2
                var chunk: [String] = []
                var chunkHeight: CGFloat = 0
                while index < lines.count {
                    let candidate = chunk + [lines[index]]
                    let attr = makeAttributed(
                        candidate.joined(separator: "\n"),
                        font: font,
                        color: NotePDFExporter.bodyColor,
                        parseMarkdown: false
                    )
                    let h = measure(attr, width: textWidth)
                    if !chunk.isEmpty, h > available { break }
                    chunk = candidate
                    chunkHeight = h
                    index += 1
                    // Single oversize line: still emit one line so we make progress.
                    if chunk.count == 1, h > available { break }
                }
                let boxHeight = chunkHeight + padding * 2
                let box = CGRect(
                    x: NotePDFExporter.margin,
                    y: y,
                    width: NotePDFExporter.contentWidth,
                    height: boxHeight
                )
                NotePDFExporter.codeBackgroundColor.setFill()
                let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
                path.fill()
                let attr = makeAttributed(
                    chunk.joined(separator: "\n"),
                    font: font,
                    color: NotePDFExporter.bodyColor,
                    parseMarkdown: false
                )
                let textRect = CGRect(
                    x: NotePDFExporter.margin + padding,
                    y: y + padding,
                    width: textWidth,
                    height: chunkHeight
                )
                attr.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += boxHeight + NotePDFExporter.blockGap
                if index < lines.count {
                    endPage()
                    beginPage()
                }
            }
        }

        private func drawThematicBreak() {
            let lineHeight: CGFloat = 12
            ensureSpace(lineHeight)
            let midY = y + lineHeight / 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: NotePDFExporter.margin, y: midY))
            path.line(to: NSPoint(x: NotePDFExporter.pageWidth - NotePDFExporter.margin, y: midY))
            NotePDFExporter.ruleColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            y += lineHeight + NotePDFExporter.blockGap
        }

        private func drawImage(alt: String, path: String) {
            if let url = MarkdownImagePath.resolve(
                path: path,
                noteDirectory: noteDirectory,
                vaultRoot: vaultRoot
            ), let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 {
                let imgSize = image.size
                let maxH = NotePDFExporter.contentHeight
                let scale = min(1, NotePDFExporter.contentWidth / imgSize.width, maxH / imgSize.height)
                let drawW = imgSize.width * scale
                let drawH = imgSize.height * scale
                ensureSpace(drawH)
                let rect = CGRect(x: NotePDFExporter.margin, y: y, width: drawW, height: drawH)
                image.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0,
                    respectFlipped: true,
                    hints: nil
                )
                y += drawH + NotePDFExporter.blockGap
            } else {
                let label = alt.isEmpty ? "Missing image: \(path)" : "Missing image: \(path) (\(alt))"
                drawTextSpanning(label, font: LyraFonts.ui(size: 11), color: NotePDFExporter.secondaryColor)
            }
        }

        // MARK: Typography helpers

        private var bodyFont: NSFont { LyraFonts.ui(size: 12) }

        private func headingFont(_ level: Int) -> NSFont {
            let size: CGFloat
            switch level {
            case 1: size = 24
            case 2: size = 20
            default: size = 16
            }
            return LyraFonts.ui(size: size, weight: .bold)
        }

        /// Render inline Markdown (bold/italic/code/links) the way Reading does, with AppKit fonts.
        private func makeAttributed(
            _ text: String,
            font: NSFont,
            color: NSColor,
            parseMarkdown: Bool = true
        ) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.alignment = .natural

            guard parseMarkdown else {
                return NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ])
            }

            let prepared = MarkdownPreviewBlocks.prepareInlineMarkdown(text)
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            options.failurePolicy = .returnPartiallyParsedIfPossible

            let bridged: NSAttributedString
            if let attributed = try? AttributedString(markdown: prepared, options: options) {
                bridged = NSAttributedString(attributed)
            } else {
                bridged = NSAttributedString(string: text)
            }

            let mutable = NSMutableAttributedString(attributedString: bridged)
            let full = NSRange(location: 0, length: mutable.length)
            // Base face/colour first (erases presentation styling), then re-apply intents.
            mutable.addAttributes([
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ], range: full)

            mutable.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
                guard let intent = value as? InlinePresentationIntent else { return }
                var face = font
                if intent.contains(.stronglyEmphasized) {
                    face = LyraFonts.ui(size: font.pointSize, weight: .bold)
                } else if intent.contains(.emphasized) {
                    // NSFontDescriptor.withSymbolicTraits is non-optional on macOS (unlike UIKit).
                    let italic = font.fontDescriptor.withSymbolicTraits(.italic)
                    face = NSFont(descriptor: italic, size: font.pointSize) ?? font
                }
                if intent.contains(.code) {
                    face = LyraFonts.code(size: font.pointSize)
                }
                mutable.addAttribute(.font, value: face, range: range)
            }

            // Style link runs (wiki + http) with a print-safe blue; labels only (not raw URLs).
            mutable.enumerateAttribute(.link, in: full) { value, range, _ in
                guard value != nil else { return }
                mutable.addAttributes([
                    .foregroundColor: NotePDFExporter.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: range)
            }
            return mutable
        }

        private func measure(_ attr: NSAttributedString, width: CGFloat) -> CGFloat {
            let bounds = attr.boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return max(ceil(bounds.height), 1)
        }
    }
}
