import AppKit

/// Builds US Letter PDF `Data` from note markdown (native AppKit / Core Graphics).
enum NotePDFExporter {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 54
    private static let blockGap: CGFloat = 10
    private static let contentWidth: CGFloat = pageWidth - margin * 2

    // Print-safe colors (not semantic — avoid light-on-light when host is dark mode).
    private static let bodyColor = NSColor.black
    private static let secondaryColor = NSColor(calibratedWhite: 0.35, alpha: 1)
    private static let codeBackgroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
    private static let quoteBarColor = NSColor(calibratedRed: 0.85, green: 0.65, blue: 0.13, alpha: 1)
    private static let ruleColor = NSColor(calibratedWhite: 0.7, alpha: 1)

    static func pdfData(markdown: String, noteDirectory: URL, vaultRoot: URL) throws -> Data {
        try Renderer(markdown: markdown, noteDirectory: noteDirectory, vaultRoot: vaultRoot).run()
    }

    // MARK: - Renderer

    private final class Renderer {
        let markdown: String
        let noteDirectory: URL
        let vaultRoot: URL

        private var ctx: CGContext!
        private var y: CGFloat = 0
        private var pageNumber = 1
        private let contentBottom = NotePDFExporter.pageHeight - NotePDFExporter.margin

        init(markdown: String, noteDirectory: URL, vaultRoot: URL) {
            self.markdown = markdown
            self.noteDirectory = noteDirectory
            self.vaultRoot = vaultRoot
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
            for block in MarkdownPreviewBlocks.parse(markdown) {
                draw(block)
            }
            endPage()
            ctx.closePDF()
            return data as Data
        }

        // MARK: Pages

        private func beginPage() {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            y = NotePDFExporter.margin
        }

        private func endPage() {
            drawPageNumber()
            NSGraphicsContext.current = nil
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
            let pageY = NotePDFExporter.pageHeight - NotePDFExporter.margin + 18
            attr.draw(at: CGPoint(x: x, y: pageY))
        }

        /// Ensure `height` fits; start a new page if needed (unless already at top).
        private func ensureSpace(_ height: CGFloat) {
            if y + height > contentBottom, y > NotePDFExporter.margin + 0.5 {
                endPage()
                beginPage()
            }
        }

        // MARK: Blocks

        private func draw(_ block: MarkdownPreviewBlocks.Block) {
            switch block {
            case .heading(let level, let text):
                drawText(text, font: headingFont(level), color: NotePDFExporter.bodyColor)

            case .paragraph(let text):
                drawText(text, font: bodyFont, color: NotePDFExporter.bodyColor)

            case .listItem(let text):
                drawListItem(text)

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

        private func drawText(_ text: String, font: NSFont, color: NSColor, indent: CGFloat = 0) {
            let attr = makeAttributed(text, font: font, color: color)
            let width = NotePDFExporter.contentWidth - indent
            let height = measure(attr, width: width)
            ensureSpace(height)
            let rect = CGRect(
                x: NotePDFExporter.margin + indent,
                y: y,
                width: width,
                height: height
            )
            attr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += height + NotePDFExporter.blockGap
        }

        private func drawListItem(_ text: String) {
            let bulletAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: NotePDFExporter.secondaryColor,
            ]
            let bullet = NSAttributedString(string: "•", attributes: bulletAttrs)
            let body = makeAttributed(text, font: bodyFont, color: NotePDFExporter.bodyColor)
            let bulletWidth: CGFloat = 16
            let bodyWidth = NotePDFExporter.contentWidth - bulletWidth
            let height = max(measure(body, width: bodyWidth), bodyFont.ascender - bodyFont.descender)
            ensureSpace(height)
            bullet.draw(at: CGPoint(x: NotePDFExporter.margin, y: y))
            let rect = CGRect(
                x: NotePDFExporter.margin + bulletWidth,
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

        private func drawCode(_ code: String) {
            let display = code.isEmpty ? " " : code
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let attr = makeAttributed(display, font: font, color: NotePDFExporter.bodyColor)
            let padding: CGFloat = 8
            let textWidth = NotePDFExporter.contentWidth - padding * 2
            let textHeight = measure(attr, width: textWidth)
            let boxHeight = textHeight + padding * 2
            ensureSpace(boxHeight)
            let box = CGRect(
                x: NotePDFExporter.margin,
                y: y,
                width: NotePDFExporter.contentWidth,
                height: boxHeight
            )
            NotePDFExporter.codeBackgroundColor.setFill()
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            path.fill()
            let textRect = CGRect(
                x: NotePDFExporter.margin + padding,
                y: y + padding,
                width: textWidth,
                height: textHeight
            )
            attr.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += boxHeight + NotePDFExporter.blockGap
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
                let scale = min(1, NotePDFExporter.contentWidth / imgSize.width)
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
                drawText(label, font: NSFont.systemFont(ofSize: 11), color: NotePDFExporter.secondaryColor)
            }
        }

        // MARK: Typography helpers

        private var bodyFont: NSFont { NSFont.systemFont(ofSize: 12) }

        private func headingFont(_ level: Int) -> NSFont {
            let size: CGFloat
            switch level {
            case 1: size = 24
            case 2: size = 20
            default: size = 16
            }
            return NSFont.boldSystemFont(ofSize: size)
        }

        private func makeAttributed(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.alignment = .natural
            return NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ])
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
