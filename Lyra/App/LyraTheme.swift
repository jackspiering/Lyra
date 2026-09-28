import AppKit
import SwiftUI

/// Brand colors sampled from the lyre logo: cream gold on deep navy night sky.
///
/// Two built-in looks follow the system appearance — **Night** (dark) and
/// **Parchment** (light). There is no theme picker.
enum LyraTheme {
    static let gold = NSColor(srgbRed: 0.957, green: 0.784, blue: 0.506, alpha: 1)      // #f4c881
    static let cream = NSColor(srgbRed: 0.996, green: 0.933, blue: 0.792, alpha: 1)     // #feeeca
    static let bronze = NSColor(srgbRed: 0.533, green: 0.376, blue: 0.282, alpha: 1)    // #886048

    // MARK: - Surfaces

    /// Writing surface behind Source and Reading.
    static var paper: NSColor {
        dynamic(light: rgb(0xFDFBF6), dark: rgb(0x121530))
    }

    /// Tab strip and window toolbar.
    static var chrome: NSColor {
        dynamic(light: rgb(0xF7F2E8), dark: rgb(0x0F1226))
    }

    /// Sidebar and backlinks inspector.
    static var sidebar: NSColor {
        dynamic(light: rgb(0xEFE8DA), dark: rgb(0x0C0F22))
    }

    /// Low-contrast fill for chips, the filter field, and cards.
    static var fill: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.24, green: 0.16, blue: 0.04, alpha: 0.06),
            dark: NSColor(white: 1, alpha: 0.06)
        )
    }

    /// 1px separators.
    static var hairline: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.24, green: 0.16, blue: 0.04, alpha: 0.10),
            dark: NSColor(white: 1, alpha: 0.08)
        )
    }

    // MARK: - Ink

    /// Body text.
    static var ink: NSColor {
        dynamic(light: rgb(0x23202E), dark: rgb(0xE9E6F2))
    }

    /// Markdown syntax markers (`#`, `**`, `[[ ]]`, backticks) — present but quiet.
    static var markup: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.14, green: 0.13, blue: 0.18, alpha: 0.34),
            dark: NSColor(srgbRed: 0.91, green: 0.90, blue: 0.95, alpha: 0.32)
        )
    }

    // MARK: - Accent

    /// Gold in Night; a deeper bronze-gold in Parchment so it reads on paper.
    static var accent: NSColor {
        dynamic(light: rgb(0x93601F), dark: gold)
    }

    /// Tinted fill behind active accent controls.
    static var accentSoft: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.78, green: 0.57, blue: 0.23, alpha: 0.16),
            dark: gold.withAlphaComponent(0.14)
        )
    }

    /// Text selection in Source.
    static var selection: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.78, green: 0.57, blue: 0.23, alpha: 0.24),
            dark: gold.withAlphaComponent(0.24)
        )
    }

    // MARK: - Markdown tokens

    static var heading: NSColor {
        dynamic(light: rgb(0x3A2A14), dark: cream)
    }

    static var code: NSColor {
        dynamic(light: bronze, dark: cream.withAlphaComponent(0.9))
    }

    static var link: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.35, green: 0.28, blue: 0.63, alpha: 1),
            dark: NSColor(srgbRed: 0.75, green: 0.69, blue: 0.95, alpha: 1)
        )
    }

    static var wiki: NSColor { accent }

    static var emphasis: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.25, green: 0.22, blue: 0.40, alpha: 1),
            dark: cream
        )
    }

    static var listMarker: NSColor { accent }

    static var quote: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.14, green: 0.13, blue: 0.18, alpha: 0.66),
            dark: NSColor(srgbRed: 0.91, green: 0.90, blue: 0.95, alpha: 0.66)
        )
    }

    static var codeBackground: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.47, green: 0.35, blue: 0.12, alpha: 0.07),
            dark: NSColor(white: 1, alpha: 0.05)
        )
    }

    // MARK: - SwiftUI

    static var accentColor: Color { Color(nsColor: accent) }
    static var accentSoftColor: Color { Color(nsColor: accentSoft) }
    static var paperColor: Color { Color(nsColor: paper) }
    static var chromeColor: Color { Color(nsColor: chrome) }
    static var sidebarColor: Color { Color(nsColor: sidebar) }
    static var fillColor: Color { Color(nsColor: fill) }
    static var hairlineColor: Color { Color(nsColor: hairline) }

    // MARK: - Layout

    /// Maximum width of the writing column (title, Source, Reading).
    static let columnWidth: CGFloat = 680
    /// Minimum side margin around the column in narrow windows.
    static let columnMargin: CGFloat = 32

    /// Horizontal inset that centers a `columnWidth` column in `width`.
    static func columnInset(forWidth width: CGFloat) -> CGFloat {
        max(columnMargin, ((width - columnWidth) / 2).rounded(.down))
    }

    // MARK: - Helpers

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
