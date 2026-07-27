import AppKit
import SwiftUI

struct OpenVaultView: View {
    var onOpen: (URL) -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Vault Open", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Open a folder of Markdown files to begin.")
        } actions: {
            Button("Open Vault…") {
                pickFolder()
            }
            .keyboardShortcut("o", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open Vault"
        panel.message = "Choose a folder to use as a Lyra vault"
        if panel.runModal() == .OK, let url = panel.url {
            onOpen(url)
        }
    }
}
