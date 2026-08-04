import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("lyra.appearance") private var appearanceRaw = AppearancePreference.system.rawValue

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    private var appearance: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(rawValue: appearanceRaw) ?? .system },
            set: {
                appearanceRaw = $0.rawValue
                AppearanceController.apply($0)
            }
        )
    }

    var body: some View {
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
        .preferredColorScheme(appearancePreference.colorScheme)
        .onAppear {
            AppearanceController.apply(rawValue: appearanceRaw)
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Picker("Appearance", selection: appearance) {
                ForEach(AppearancePreference.allCases) { pref in
                    Text(pref.label).tag(pref)
                }
            }
            .pickerStyle(.inline)
            Text("Applies to all Lyra windows. PDF export always uses print-safe light colours.")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Room for later preference toggles (confirm delete, etc.)
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 220)
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
                    Text(versionLine)
                        .foregroundStyle(.secondary)
                    Text("Native macOS Markdown vault editor.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Acknowledgments")
                    .font(.headline)
                Text("Inter font by Rasmus Andersson, licensed under the SIL Open Font License 1.1.")
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

            Link(
                "Latest release",
                destination: URL(string: "https://github.com/jackspiering/Lyra/releases/latest")!
            )
            .font(.callout)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320, alignment: .topLeading)
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }
}
