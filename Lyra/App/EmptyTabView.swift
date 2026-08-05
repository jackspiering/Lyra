import SwiftUI

/// Detail placeholder for an empty note tab when a vault is already open.
/// Full-window “No Vault Open” is only for `store.rootURL == nil`.
struct EmptyTabView: View {
    var onNewNote: () -> Void
    /// Open-note panel for a Markdown file in the current vault (⌘O when vault is open).
    var onGoToFile: () -> Void
    var onCloseTab: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            emptyLink("Create new note (⌘ N)", action: onNewNote)
            emptyLink("Go to file (⌘ O)", action: onGoToFile)
            emptyLink("Close", action: onCloseTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LyraFonts.body)
                .foregroundStyle(Color(nsColor: LyraTheme.wiki))
        }
        .buttonStyle(.plain)
    }
}
