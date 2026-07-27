import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var onEdit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        context.coordinator.textView = textView
        context.coordinator.applyHighlight(text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            context.coordinator.applyHighlight(text)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
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
