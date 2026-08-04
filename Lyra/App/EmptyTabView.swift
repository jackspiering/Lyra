import SwiftUI

/// Detail placeholder for an empty note tab when a vault is already open.
/// Full-window “No Vault Open” is only for `store.rootURL == nil`.
struct EmptyTabView: View {
    var onNewNote: () -> Void
    /// Focus vault search (vault is open when this view is shown).
    var onGoToFile: () -> Void
    var onCloseTab: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No note open")
                .font(LyraFonts.headline)

            Text("Create a note, jump to a file in the sidebar, or close this tab.")
                .font(LyraFonts.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            VStack(spacing: 10) {
                Button(action: onNewNote) {
                    emptyActionLabel("Create new note", shortcut: "⌘N")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)

                Button(action: onGoToFile) {
                    emptyActionLabel("Go to File", shortcut: "⌘F")
                }
                .buttonStyle(.bordered)
                // Focus search; ⌘F is also Find in Vault on the menu.

                Button(action: onCloseTab) {
                    emptyActionLabel("Close", shortcut: nil)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func emptyActionLabel(_ title: String, shortcut: String?) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            if let shortcut {
                Text(shortcut)
                    .foregroundStyle(.secondary)
                    .font(LyraFonts.caption)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
