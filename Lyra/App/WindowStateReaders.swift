import AppKit
import SwiftUI

/// Reports the hosting window's number so command handlers can target the key window only.
struct WindowNumberReader: NSViewRepresentable {
    var onChange: (Int?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onChange(view.window?.windowNumber) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onChange(nsView.window?.windowNumber) }
    }
}

/// Drives the standard macOS dirty indicator on the window close button.
struct DocumentEditedReader: NSViewRepresentable {
    var isEdited: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.window?.isDocumentEdited = isEdited
    }
}