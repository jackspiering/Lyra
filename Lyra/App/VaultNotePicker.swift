import AppKit
import UniformTypeIdentifiers

/// Open-panel for a Markdown note inside an already-open vault (empty-tab “Go to file”, ⌘O).
enum VaultNotePicker {
    static func pick(vaultRoot: URL, message: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = vaultRoot
        panel.prompt = "Open"
        panel.message = message ?? "Choose a Markdown note"
        panel.allowedContentTypes = [.text, .plainText]
        if let md = UTType(filenameExtension: "md") {
            panel.allowedContentTypes.append(md)
        }
        // Prefer showing .md; still allow other text the vault may hold.
        panel.allowsOtherFileTypes = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let rootPath = vaultRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let chosenPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        // Keep sandbox-friendly: only open notes under the current vault.
        guard chosenPath == rootPath || chosenPath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return url
    }
}
