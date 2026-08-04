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
            }
            .formStyle(.grouped)
            .padding()
            .frame(width: 420, height: 180)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
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
                .padding(.vertical, 4)

                Text("Notes stay as plain UTF-8 `.md` files on disk. No cloud account, no proprietary store.")
                    .font(.callout)

                Text("MIT License")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .padding()
            .frame(width: 420, height: 240)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .preferredColorScheme(appearancePreference.colorScheme)
        .onAppear {
            AppearanceController.apply(rawValue: appearanceRaw)
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }
}
