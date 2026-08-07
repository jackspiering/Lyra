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
            drawAttributedSpanning(
                full,
                x: x,
                width: width,
                minimumHeight: max(font.ascender - font.descender, 1)
            )
        }

        /// Draw an attributed block in page-sized fragments. Decorations are
        /// drawn per fragment so a quote bar or code background cannot extend
        /// below the page when a block is taller than one page.
        private func drawAttributedSpanning(
            _ full: NSAttributedString,
            x: CGFloat,
            width: CGFloat,
            minimumHeight: CGFloat,
            horizontalPadding: CGFloat = 0,
            topPadding: CGFloat = 0,
            bottomPadding: CGFloat = 0,
            decoration: ((CGRect, Bool) -> Void)? = nil
        ) {
            var offset = 0
            let total = full.length
            guard total > 0 else { return }

            while offset < total {
                let minimumFragmentHeight = minimumHeight + topPadding + bottomPadding
                ensureSpace(minimumFragmentHeight)
                let available = max(1, remainingHeight - topPadding - bottomPadding)
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
                let blockHeight = topPadding + height + bottomPadding
                if blockHeight > remainingHeight + 0.5, y > NotePDFExporter.margin + 0.5 {
                    endPage()
                    beginPage()
                    continue
                }
                let textRect = CGRect(x: x, y: y + topPadding, width: width, height: height)
                let blockRect = CGRect(
                    x: x - horizontalPadding,
                    y: y,
                    width: width + horizontalPadding * 2,
                    height: blockHeight
                )
                decoration?(blockRect, offset == 0)
                slice.draw(
                    with: textRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                y += blockHeight
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
                return composedCharacterSafeLength(
                    attr,
                    from: from,
                    proposedLength: br.location + 1
                )
            }
            if low > 20 {
                let sp = window.rangeOfCharacter(from: .whitespaces, options: .backwards)
                if sp.location != NSNotFound, sp.location > low / 2 {
                    return composedCharacterSafeLength(
                        attr,
                        from: from,
                        proposedLength: sp.location + 1
                    )
                }
            }
            return composedCharacterSafeLength(attr, from: from, proposedLength: max(1, low))
        }

        private func composedCharacterSafeLength(
            _ attr: NSAttributedString,
            from: Int,
            proposedLength: Int
        ) -> Int {
            let proposedEnd = min(attr.length, from + proposedLength)
            guard proposedEnd > from, proposedEnd < attr.length else {
                return max(1, proposedEnd - from)
            }
            let cluster = (attr.string as NSString).rangeOfComposedCharacterSequence(at: proposedEnd - 1)
            guard NSMaxRange(cluster) > proposedEnd else { return proposedEnd - from }
            if cluster.location >= from {
                return NSMaxRange(cluster) - from
            }
            return max(1, cluster.location - from)
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
            let body = makeAttributed(text.isEmpty ? " " : text, font: bodyFont, color: NotePDFExporter.bodyColor)
            let bulletWidth: CGFloat = (ordinal != nil || taskChecked != nil) ? 28 : 16
            let x = NotePDFExporter.margin + indent
            let bodyWidth = max(1, NotePDFExporter.contentWidth - indent - bulletWidth)
            drawAttributedSpanning(
                body,
                x: x + bulletWidth,
                width: bodyWidth,
                minimumHeight: max(bodyFont.ascender - bodyFont.descender, 1)
            ) { rect, isFirst in
                if isFirst {
                    bullet.draw(at: CGPoint(x: x, y: rect.minY))
                }
            }
        }

        private func drawQuote(_ text: String) {
            let barWidth: CGFloat = 3
            let pad: CGFloat = 10
            let body = makeAttributed(text.isEmpty ? " " : text, font: bodyFont, color: NotePDFExporter.secondaryColor)
            let textWidth = NotePDFExporter.contentWidth - barWidth - pad
            drawAttributedSpanning(
                body,
                x: NotePDFExporter.margin + barWidth + pad,
                width: textWidth,
                minimumHeight: max(bodyFont.ascender - bodyFont.descender, 1)
            ) { rect, _ in
                let bar = CGRect(
                    x: NotePDFExporter.margin,
                    y: rect.minY,
                    width: barWidth,
                    height: rect.height
                )
                NotePDFExporter.quoteBarColor.setFill()
                bar.fill()
            }
        }

        /// Code is a padded attributed block; the shared fragment pagination
        /// also handles a single unusually long wrapped line.
        private func drawCode(_ code: String) {
            let display = code.isEmpty ? " " : code
            let font = LyraFonts.code(size: 11)
            let padding: CGFloat = 8
            let textWidth = NotePDFExporter.contentWidth - padding * 2
            let attr = makeAttributed(
                display,
                font: font,
                color: NotePDFExporter.bodyColor,
                parseMarkdown: false
            )
            drawAttributedSpanning(
                attr,
                x: NotePDFExporter.margin + padding,
                width: textWidth,
                minimumHeight: max(font.ascender - font.descender, 1),
                horizontalPadding: padding,
                topPadding: padding,
                bottomPadding: padding
            ) { box, _ in
                NotePDFExporter.codeBackgroundColor.setFill()
                let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
                path.fill()
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
            paragraph.lineBreakMode = parseMarkdown ? .byWordWrapping : .byCharWrapping
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
