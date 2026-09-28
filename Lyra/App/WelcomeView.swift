import AppKit
import SwiftUI

/// Full-window start page when this window has no vault yet.
struct WelcomeView: View {
    var onOpenVault: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                .accessibilityHidden(true)
                .padding(.bottom, 22)
            Text("Welcome to Lyra")
                .font(LyraFonts.title)
                .foregroundStyle(LyraTheme.inkColor)
            Text("Write in plain Markdown. Every note stays a file you own.")
                .font(LyraFonts.prose)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Button(action: onOpenVault) {
                Label("Open Vault…", systemImage: "folder")
            }
            .buttonStyle(AccentButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.top, 28)
            HStack(spacing: 6) {
                Text("Choose any folder of Markdown files. Lyra reads them in place.")
                KeyHint("⌘O")
            }
            .font(LyraFonts.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 14)
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                LyraTheme.paperColor
                // A soft glow behind the icon.
                RadialGradient(
                    colors: [LyraTheme.glowColor, .clear],
                    center: UnitPoint(x: 0.5, y: 0.34),
                    startRadius: 0,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
    }
}

/// Filled accent button: bronze in Parchment, gold in Night, with text that
/// stays readable on both (the system prominent style puts white on gold).
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LyraFonts.labelEmphasized)
            .foregroundStyle(LyraTheme.onAccentColor)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(LyraTheme.accentColor)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .shadow(color: LyraTheme.accentColor.opacity(0.35), radius: configuration.isPressed ? 2 : 8, y: 3)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
