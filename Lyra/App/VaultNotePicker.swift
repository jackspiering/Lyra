import AppKit
import UniformTypeIdentifiers

/// Open-panel for a Markdown note inside an already-open vault (empty-tab “Go to file”, ⌘O).
enum VaultNotePicker {
    enum Outcome {
        case note(URL)
        /// The user picked a file that isn't a note in this vault.
        case outsideVault
        case cancelled
    }

    static func pick(vaultRoot: URL, message: String? = nil) -> Outcome {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = vaultRoot
        panel.prompt = "Open"
        panel.message = message ?? "Choose a Markdown note"
        if let md = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [md]
        } else {
            panel.allowedContentTypes = []
        }
        panel.allowsOtherFileTypes = false

        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        guard url.pathExtension.lowercased() == "md" else { return .outsideVault }

        let rootPath = vaultRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let chosenPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        // Keep sandbox-friendly: only open notes under the current vault.
        guard chosenPath == rootPath || chosenPath.hasPrefix(rootPath + "/") else {
            return .outsideVault
        }
        return .note(url)
    }
}
