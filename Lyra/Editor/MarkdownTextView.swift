import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var vaultRoot: URL?
    var onEdit: () -> Void

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
        textView.onImagePasted = { [weak coordinator = context.coordinator] in
            coordinator?.handleImagePasted()
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
        textView.onImagePasted = { [weak coordinator = context.coordinator] in
            coordinator?.handleImagePasted()
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

        func handleImagePasted() {
            guard !isApplying, let textView else { return }
            parent.text = textView.string
            parent.onEdit()
            applyHighlight(textView.string)
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
    var onImagePasted: (() -> Void)?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let img = NSImage(pasteboard: pb),
           let root = vaultRoot,
           let data = AttachmentStore.pngData(from: img),
           let rel = try? AttachmentStore.savePNG(data: data, vaultRoot: root) {
            let snippet = "![](\(rel))"
            insertText(snippet, replacementRange: selectedRange())
            onImagePasted?()
            return
        }
        super.paste(sender)
    }
}
