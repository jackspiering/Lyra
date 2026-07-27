import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var vaultRoot: URL?
    var onEdit: () -> Void
    var onPasteError: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = LyraTextView()
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.vaultRoot = vaultRoot
        let coordinator = context.coordinator
        textView.onPasteError = { message in
            coordinator.parent.onPasteError?(message)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.applyHighlight(text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? LyraTextView else { return }
        textView.vaultRoot = vaultRoot
        let coordinator = context.coordinator
        textView.onPasteError = { message in
            coordinator.parent.onPasteError?(message)
        }
        if textView.string != text {
            context.coordinator.applyHighlight(text)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: LyraTextView?
        private var isApplying = false

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func applyHighlight(_ string: String) {
            guard let textView else { return }
            isApplying = true
            let selected = textView.selectedRanges
            textView.textStorage?.setAttributedString(MarkdownHighlighter.attributedString(from: string))
            textView.selectedRanges = selected
            isApplying = false
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView else { return }
            parent.text = textView.string
            parent.onEdit()
            applyHighlight(textView.string)
        }
    }
}

/// `NSTextView` that pastes clipboard images into the vault `_attachments` folder.
final class LyraTextView: NSTextView {
    var vaultRoot: URL?
    var onPasteError: ((String) -> Void)?

    override func paste(_ sender: Any?) {
        if pasteImageIfPossible() { return }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if pasteImageIfPossible() { return }
        super.pasteAsPlainText(sender)
    }

    /// Returns `true` if the pasteboard was handled as an image (success or surfaced error).
    @discardableResult
    func pasteImageIfPossible() -> Bool {
        guard let root = vaultRoot else { return false }
        guard let data = Self.pngDataFromPasteboard(NSPasteboard.general) else { return false }
        do {
            let rel = try AttachmentStore.savePNG(data: data, vaultRoot: root)
            let insertion = "![](\(rel))"
            let range = selectedRange()
            if shouldChangeText(in: range, replacementString: insertion) {
                insertText(insertion, replacementRange: range)
                didChangeText()
            }
            return true
        } catch {
            onPasteError?(error.localizedDescription)
            return true
        }
    }

    /// Best-effort PNG bytes from common pasteboard image representations.
    static func pngDataFromPasteboard(_ pb: NSPasteboard) -> Data? {
        if let img = NSImage(pasteboard: pb), let data = AttachmentStore.pngData(from: img) {
            return data
        }
        if let data = pb.data(forType: .png) { return data }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        let typeNames = pb.types?.map(\.rawValue) ?? []
        for name in typeNames {
            if name.contains("png") || name == UTType.png.identifier {
                if let data = pb.data(forType: NSPasteboard.PasteboardType(name)) { return data }
            }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                guard let img = NSImage(contentsOf: url),
                      let data = AttachmentStore.pngData(from: img) else { continue }
                return data
            }
        }
        return nil
    }
}
