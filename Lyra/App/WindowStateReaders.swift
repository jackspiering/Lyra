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

/// Vetoes individual window closes when a dirty editor cannot be saved. The
/// application termination delegate handles quit, but AppKit does not consult
/// it for a red-button close or the window-close shortcut.
struct WindowCloseGuard: NSViewRepresentable {
    var editors: [EditorViewModel]
    var onSaveFailure: ([EditorViewModel]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(editors: editors, onSaveFailure: onSaveFailure)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(editors: editors, onSaveFailure: onSaveFailure)
        context.coordinator.install(on: view.window)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(editors: editors, onSaveFailure: onSaveFailure)
        DispatchQueue.main.async {
            context.coordinator.install(on: view.window)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private var editors: [EditorViewModel]
        private var onSaveFailure: ([EditorViewModel]) -> Void
        private weak var installedWindow: NSWindow?
        private weak var previousDelegate: NSWindowDelegate?

        init(editors: [EditorViewModel], onSaveFailure: @escaping ([EditorViewModel]) -> Void) {
            self.editors = editors
            self.onSaveFailure = onSaveFailure
        }

        func update(
            editors: [EditorViewModel],
            onSaveFailure: @escaping ([EditorViewModel]) -> Void
        ) {
            self.editors = editors
            self.onSaveFailure = onSaveFailure
        }

        func install(on window: NSWindow?) {
            guard let window else { return }
            if installedWindow !== window {
                previousDelegate = window.delegate
                installedWindow = window
            } else if window.delegate !== self {
                previousDelegate = window.delegate
            }
            if window.delegate !== self {
                window.delegate = self
            }
        }

        func uninstall() {
            guard let window = installedWindow, window.delegate === self else { return }
            window.delegate = previousDelegate
            installedWindow = nil
            previousDelegate = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            let failed = editors.filter { !$0.saveIfNeeded() }
            guard failed.isEmpty else {
                onSaveFailure(failed)
                return false
            }
            return previousDelegate?.windowShouldClose?(sender) ?? true
        }

        override func responds(to selector: Selector) -> Bool {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector) -> Any? {
            if let previousDelegate, previousDelegate.responds(to: selector) {
                return previousDelegate
            }
            return super.forwardingTarget(for: selector)
        }
    }
}
