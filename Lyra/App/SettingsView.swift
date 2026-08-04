import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("lyra.appearance") private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(GeneralPreferences.promptForNewNoteNameKey) private var promptForNewNoteName = true
    @AppStorage(GeneralPreferences.defaultNoteStemKey) private var defaultNoteStem = "Untitled"
    @AppStorage(GeneralPreferences.confirmDeleteNoteKey) private var confirmDeleteNote = true
    @AppStorage(GeneralPreferences.confirmDeleteFolderKey) private var confirmDeleteFolder = true

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    private var appearance: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(rawValue: appearanceRaw) ?? .system },
            set: {
                appearanceRaw = $0.rawValue
                // Apply after storage write so System clears window-level sticky light/dark.
                AppearanceController.apply($0)
            }
        )
    }

    var body: some View {
        // Group so preferredColorScheme(nil) for System can clear a prior forced scheme.
        Group {
            TabView {
                generalTab
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }

                aboutTab
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
        }
        .preferredColorScheme(appearancePreference.colorScheme)
        // Belt-and-suspenders: force resizable + min size if the Settings scene is sticky.
        .background(SettingsWindowConfigurer())
        .onAppear {
            GeneralPreferences.migrateConfirmDeleteIfNeeded()
            AppearanceController.apply(rawValue: appearanceRaw)
        }
        .onChange(of: appearanceRaw) { _, new in
            AppearanceController.apply(rawValue: new)
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Picker(selection: appearance) {
                ForEach(AppearancePreference.allCases) { pref in
                    Text(pref.label).tag(pref)
                }
            } label: {
                settingsLabel(
                    "Appearance",
                    help: "Changes every Lyra window. PDF export always uses light colours for printing."
                )
            }
            .pickerStyle(.inline)

            Toggle(isOn: $promptForNewNoteName) {
                settingsLabel(
                    "Ask for name when creating a note",
                    help: "Shows a name field before the file is created. Turn off to create Untitled notes immediately."
                )
            }

            LabeledContent {
                TextField("Default note name", text: $defaultNoteStem)
                    .onSubmit { commitDefaultNoteStem() }
            } label: {
                settingsLabel(
                    "Default note name",
                    help: "Base name when Lyra auto-names a note. The `.md` extension is added for you."
                )
            }

            Toggle(isOn: $confirmDeleteNote) {
                settingsLabel(
                    "Confirm before moving notes to Trash",
                    help: "Asks once per note delete. You can turn this off after “Don’t ask again.”"
                )
            }

            Toggle(isOn: $confirmDeleteFolder) {
                settingsLabel(
                    "Confirm before moving folders to Trash",
                    help: "Same idea for folders. Separate from notes so you can confirm folders only."
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 300)
        .onDisappear { commitDefaultNoteStem() }
    }

    private func settingsLabel(_ title: String, help: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            SettingsInfoButton(help: help)
        }
    }

    /// Reject illegal chars, strip trailing `.md`, empty → `"Untitled"`.
    private func commitDefaultNoteStem() {
        defaultNoteStem = FilenameValidation.sanitizeNoteStem(defaultNoteStem)
    }

    // MARK: - About

    /// Static legal/about page — not a Form, so default content does not scroll.
    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lyra")
                        .font(.title2.weight(.semibold))
                    versionAndReleaseLinks
                    Text("A native Markdown vault editor for Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Acknowledgments")
                    .font(.headline)
                Text("Inter by Rasmus Andersson (SIL Open Font License 1.1).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("rsms.me/inter", destination: URL(string: "https://rsms.me/inter/")!)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("License")
                    .font(.headline)
                Text("MIT License")
                    .font(.callout)
                Text("Copyright (c) 2026 Jack Spiering")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link(
                    "MIT License on GitHub",
                    destination: URL(string: "https://github.com/jackspiering/Lyra/blob/main/LICENSE")!
                )
                .font(.callout)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320, alignment: .topLeading)
    }

    private var versionAndReleaseLinks: some View {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let releaseURL = URL(string: "https://github.com/jackspiering/Lyra/releases/tag/v\(short)")!
        let latestURL = URL(string: "https://github.com/jackspiering/Lyra/releases/latest")!
        return HStack(spacing: 8) {
            Link("Version \(short) (\(build))", destination: releaseURL)
            Text("·")
                .foregroundStyle(.secondary)
            Link("Latest release", destination: latestURL)
        }
        .font(.callout)
    }
}

// MARK: - Info popover

/// Compact (i) control that shows multi-line help in a popover.
private struct SettingsInfoButton: View {
    let help: String
    @State private var showingHelp = false

    var body: some View {
        Button {
            showingHelp.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .imageScale(.small)
        }
        .buttonStyle(.plain)
        .help(help)
        .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
            Text(help)
                .font(.callout)
                .padding(12)
                .frame(maxWidth: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel("More info")
        .accessibilityHint(help)
    }
}

// MARK: - Settings window resize (AppKit)

/// Settings scenes on macOS 15 can ignore content min size alone. Ensure the
/// hosting window is resizable and has a sensible minimum.
private struct SettingsWindowConfigurer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.configure(window: nsView.window)
        }
    }

    private static func configure(window: NSWindow?) {
        guard let window else { return }
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        let min = NSSize(width: 420, height: 300)
        if window.minSize.width < min.width || window.minSize.height < min.height {
            window.minSize = min
        }
    }
}
