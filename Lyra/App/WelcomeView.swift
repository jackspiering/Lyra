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
                .tracking(LyraFonts.tracking(forSize: 32))
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
            HStack(spacing: 8) {
                WelcomeTag(title: "Plain Markdown", systemImage: "doc.plaintext")
                WelcomeTag(title: "Wiki links", systemImage: "link")
                WelcomeTag(title: "Files you own", systemImage: "folder")
            }
            .padding(.top, 36)
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

/// One of the quiet promise chips under the welcome page's button.
private struct WelcomeTag: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LyraTheme.accentColor)
                .accessibilityHidden(true)
            Text(title)
                .font(LyraFonts.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule(style: .continuous).fill(LyraTheme.fillColor))
        .overlay(Capsule(style: .continuous).strokeBorder(LyraTheme.hairlineColor, lineWidth: 1))
    }
}

/// Buttons in Lyra's own sheets. The system prominent style puts white text on
/// the gold accent at night; these keep the label readable in both looks.
struct SheetButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case destructive
    }

    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .secondary ? LyraFonts.label : LyraFonts.labelEmphasized)
            .foregroundStyle(labelColor)
            .padding(.horizontal, 14)
            .frame(minWidth: 68)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(kind == .secondary ? LyraTheme.hairlineColor : Color.clear, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private var labelColor: Color {
        switch kind {
        case .primary: return LyraTheme.onAccentColor
        case .secondary: return LyraTheme.inkColor
        case .destructive: return Color.white
        }
    }

    private var fillColor: Color {
        switch kind {
        case .primary: return LyraTheme.accentColor
        case .secondary: return LyraTheme.fillColor
        case .destructive: return Color.red
        }
    }
}
