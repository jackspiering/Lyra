import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var vaultRoot: URL?
    /// Current note URL (for note-relative attachment links on paste).
    var noteURL: URL?
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
        textView.textStorage?.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = LyraFonts.ui(size: 14)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.vaultRoot = vaultRoot
        textView.noteURL = noteURL
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
        context.coordinator.loadDocument(text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? LyraTextView else { return }
        textView.vaultRoot = vaultRoot
        textView.noteURL = noteURL
        textView.textStorage?.delegate = context.coordinator
        let coordinator = context.coordinator
        textView.onPasteError = { message in
            coordinator.parent.onPasteError?(message)
        }
        if textView.string != text {
            context.coordinator.loadDocument(text)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownTextView
        weak var textView: LyraTextView?
        private var isApplying = false

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        /// Replace document contents (note switch / external binding). Not used on keystrokes.
        func loadDocument(_ string: String) {
            guard let textView, let storage = textView.textStorage else { return }
            isApplying = true
            let selected = textView.selectedRanges
            textView.string = string
            MarkdownHighlighter.applyHighlighting(to: storage)
            let newLength = (string as NSString).length
            textView.selectedRanges = selected.map { value -> NSValue in
                let r = value.rangeValue
                let loc = min(r.location, newLength)
                return NSValue(range: NSRange(location: loc, length: min(r.length, newLength - loc)))
            }
            textView.undoManager?.removeAllActions()
            isApplying = false
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView else { return }
            parent.text = textView.string
            parent.onEdit()
        }

        /// NSTextStorage reports the post-edit range, including replacements
        /// and deletions. The caret alone cannot identify a multi-character
        /// paste or a replacement made through undo/IME.
        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard !isApplying, editedMask.contains(.editedCharacters) else { return }
            isApplying = true
            MarkdownHighlighter.applyHighlighting(to: textStorage, range: editedRange)
            isApplying = false
        }
    }
}

/// `NSTextView` that pastes clipboard images into the vault `_attachments` folder.
final class LyraTextView: NSTextView {
    var vaultRoot: URL?
    var noteURL: URL?
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
            let rel = try AttachmentStore.savePNG(data: data, vaultRoot: root, noteURL: noteURL)
            let encoded = rel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rel
            let insertion = "![](\(encoded))"
            let range = selectedRange()
            if shouldChangeText(in: range, replacementString: insertion) {
                insertText(insertion, replacementRange: range)
                didChangeText()
            }
            return true
        } catch {
            onPasteError?(UserFacingError.message(for: error, context: .pasteImage))
            return true
        }
    }

    /// Best-effort PNG bytes from common pasteboard image representations.
    /// Never loads remote URLs — a copied https link must paste as text, not trigger a fetch.
    static func pngDataFromPasteboard(_ pb: NSPasteboard) -> Data? {
        if let data = pb.data(forType: .png) { return data }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        if let img = NSImage(pasteboard: pb), let data = AttachmentStore.pngData(from: img) {
            return data
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                guard url.isFileURL else { continue }
                if let img = NSImage(contentsOf: url), let data = AttachmentStore.pngData(from: img) {
                    return data
                }
            }
        }
        return nil
    }
}
