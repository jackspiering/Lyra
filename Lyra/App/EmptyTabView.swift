import AppKit
import SwiftUI

/// Detail placeholder for an empty note tab when a vault is already open.
/// Full-window “No Vault Open” is only for `store.rootURL == nil`.
struct EmptyTabView: View {
    var onNewNote: () -> Void
    /// Open-note panel for a Markdown file in the current vault (⌘O when vault is open).
    var onGoToFile: () -> Void
    var onCloseTab: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .opacity(0.55)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                EmptyTabAction(title: "New Note", shortcut: "⌘N", action: onNewNote)
                EmptyTabAction(title: "Go to File", shortcut: "⌘O", action: onGoToFile)
                EmptyTabAction(title: "Close Tab", shortcut: "⇧⌘W", action: onCloseTab)
            }
            .frame(width: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LyraTheme.paperColor)
    }
}

private struct EmptyTabAction: View {
    let title: String
    let shortcut: String
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(LyraFonts.label)
                    .foregroundStyle(isHovering ? LyraTheme.accentColor : Color.primary)
                Spacer()
                Text(shortcut)
                    .font(LyraFonts.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(LyraTheme.hairlineColor, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? LyraTheme.fillColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityHint("Keyboard shortcut \(shortcut)")
    }
}
