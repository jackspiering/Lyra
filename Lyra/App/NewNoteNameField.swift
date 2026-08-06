import AppKit
import SwiftUI

/// New-note name field: selects the stem before `.md` on first focus.
struct NewNoteNameField: NSViewRepresentable {
    @Binding var text: String
    /// Called on Return while the field is focused (Create default action may not fire then).
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "Name"
        field.delegate = context.coordinator
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        DispatchQueue.main.async {
            selectStem(in: field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    private func selectStem(in field: NSTextField) {
        field.window?.makeFirstResponder(field)
        let value = field.stringValue as NSString
        let length = value.length
        if (value as String).lowercased().hasSuffix(".md"), length > 3 {
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: length - 3)
        } else {
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: length)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NewNoteNameField

        init(_ parent: NewNoteNameField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// Return while focused → Create (SwiftUI `.defaultAction` often does not fire for NSTextField).
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}