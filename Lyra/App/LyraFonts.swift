import AppKit
import CoreText
import SwiftUI

/// Bundled [Inter](https://rsms.me/inter/) (SIL Open Font License 1.1).
enum LyraFonts {
    private static var didRegister = false

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        for name in ["Inter-Regular", "Inter-SemiBold", "Inter-Bold"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func ui(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: face(weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func code(size: CGFloat = 12) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static var body: Font { font(14) }
    static var caption: Font { font(11) }
    static var headline: Font { font(15, weight: .semibold) }

    static func heading(level: Int) -> Font {
        switch level {
        case 1: return font(28, weight: .bold)
        case 2: return font(22, weight: .semibold)
        case 3: return font(18, weight: .semibold)
        case 4: return font(16, weight: .semibold)
        default: return font(15, weight: .semibold)
        }
    }

    private static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(face(weight), size: size)
    }

    private static func face(_ weight: NSFont.Weight) -> String {
        if weight >= .bold { return "Inter-Bold" }
        if weight >= .semibold { return "Inter-SemiBold" }
        return "Inter-Regular"
    }

    private static func face(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold, .medium: return "Inter-SemiBold"
        default: return "Inter-Regular"
        }
    }
}
