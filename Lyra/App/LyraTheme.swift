import AppKit
import SwiftUI

/// Brand colors sampled from the lyre logo: cream gold on deep navy night sky.
enum LyraTheme {
    static let gold = NSColor(srgbRed: 0.957, green: 0.784, blue: 0.506, alpha: 1)      // #f4c881
    static let cream = NSColor(srgbRed: 0.996, green: 0.933, blue: 0.792, alpha: 1)     // #feeeca
    static let navy = NSColor(srgbRed: 0.039, green: 0.055, blue: 0.153, alpha: 1)      // #0a0e27
    static let bronze = NSColor(srgbRed: 0.533, green: 0.376, blue: 0.282, alpha: 1)    // #886048
    static let dusk = NSColor(srgbRed: 0.118, green: 0.078, blue: 0.196, alpha: 1)      // #1e1432

    static var accent: NSColor { gold }

    static var heading: NSColor {
        dynamic(light: NSColor(srgbRed: 0.55, green: 0.38, blue: 0.12, alpha: 1), dark: gold)
    }

    static var code: NSColor {
        dynamic(light: bronze, dark: cream.withAlphaComponent(0.9))
    }

    static var link: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.35, green: 0.28, blue: 0.55, alpha: 1),
            dark: NSColor(srgbRed: 0.75, green: 0.68, blue: 0.95, alpha: 1)
        )
    }

    static var wiki: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.62, green: 0.45, blue: 0.18, alpha: 1),
            dark: gold
        )
    }

    static var emphasis: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.25, green: 0.22, blue: 0.40, alpha: 1),
            dark: cream
        )
    }

    static var listMarker: NSColor {
        dynamic(light: bronze, dark: gold.withAlphaComponent(0.85))
    }

    static var codeBackground: NSColor {
        dynamic(
            light: NSColor(srgbRed: 0.97, green: 0.95, blue: 0.90, alpha: 1),
            dark: dusk.withAlphaComponent(0.85)
        )
    }

    static var accentColor: Color { Color(nsColor: accent) }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
