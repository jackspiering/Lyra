import AppKit
import SwiftUI

enum AppearanceController {
    static func apply(_ preference: AppearancePreference) {
        let appearance: NSAppearance?
        switch preference {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
        // Clear sticky window-level overrides when returning to System (and keep light/dark consistent).
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }

    static func apply(rawValue: String) {
        apply(AppearancePreference(rawValue: rawValue) ?? .system)
    }
}
