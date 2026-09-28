import AppKit
import SwiftUI

/// Detail placeholder for an empty note tab when a vault is already open.
/// The full-window welcome is only for `store.rootURL == nil`.
struct EmptyTabView: View {
    var onNewNote: () -> Void
    /// Go to File palette (⌘O).
    var onGoToFile: () -> Void
    /// Search Vault palette (⇧⌘F).
    var onSearchVault: () -> Void
    var onCloseTab: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .opacity(0.8)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                EmptyTabAction(title: "New Note", systemImage: "square.and.pencil", shortcut: "⌘N", action: onNewNote)
                EmptyTabAction(title: "Go to File", systemImage: "doc.text.magnifyingglass", shortcut: "⌘O", action: onGoToFile)
                EmptyTabAction(title: "Search Vault", systemImage: "magnifyingglass", shortcut: "⇧⌘F", action: onSearchVault)
                Rectangle()
                    .fill(LyraTheme.hairlineColor)
                    .frame(height: 1)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                EmptyTabAction(title: "Close Tab", systemImage: "xmark", shortcut: "⇧⌘W", action: onCloseTab)
            }
            .padding(6)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LyraTheme.fillColor.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LyraTheme.hairlineColor, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LyraTheme.paperColor)
    }
}

private struct EmptyTabAction: View {
    let title: String
    let systemImage: String
    let shortcut: String
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovering ? LyraTheme.accentColor : Color.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(LyraFonts.label)
                    .foregroundStyle(isHovering ? LyraTheme.accentColor : Color.primary)
                Spacer()
                KeyHint(shortcut)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? LyraTheme.accentSoftColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityHint("Keyboard shortcut \(shortcut)")
    }
}
