import AppKit
import SwiftUI

enum AppearanceController {
    static func apply(_ preference: AppearancePreference) {
        switch preference {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func apply(rawValue: String) {
        apply(AppearancePreference(rawValue: rawValue) ?? .system)
    }
}
