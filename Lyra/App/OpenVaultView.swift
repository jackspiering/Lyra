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
                if let url = VaultFolderPicker.pick(
                    message: "Choose a folder to use as a Lyra vault"
                ) {
                    onOpen(url)
                }
            }
            .keyboardShortcut("o", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
