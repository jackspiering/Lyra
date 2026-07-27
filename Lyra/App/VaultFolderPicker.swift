import AppKit

enum VaultFolderPicker {
    static func pick(message: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open Vault"
        if let message {
            panel.message = message
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
