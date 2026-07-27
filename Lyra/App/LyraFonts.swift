import AppKit
import CoreText
import SwiftUI

/// Bundled [Inter](https://rsms.me/inter/) (SIL Open Font License 1.1) — clear UI and note text.
enum LyraFonts {
    private static let family = "Inter"
    private static var didRegister = false

    /// Call once at launch before any UI that needs custom fonts.
    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        let names = [
            "Inter-Regular",
            "Inter-Medium",
            "Inter-SemiBold",
            "Inter-Bold",
        ]
        for name in names {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            guard let url else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    // MARK: - AppKit

    static func ui(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        nsFont(size: size, weight: weight) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func editor(size: CGFloat = 14) -> NSFont {
        ui(size: size, weight: .regular)
    }

    static func editorBold(size: CGFloat = 14) -> NSFont {
        ui(size: size, weight: .bold)
    }

    static func code(size: CGFloat = 12) -> NSFont {
        // Keep code monospaced for alignment; system mono pairs well with Inter.
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - SwiftUI

    static func swiftUI(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = postScriptName(for: weight)
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        if NSFont(name: family, size: size) != nil {
            return .custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    static var body: Font { swiftUI(size: 14, weight: .regular) }
    static var callout: Font { swiftUI(size: 13, weight: .regular) }
    static var caption: Font { swiftUI(size: 11, weight: .regular) }
    static var headline: Font { swiftUI(size: 15, weight: .semibold) }

    static func heading(level: Int) -> Font {
        switch level {
        case 1: return swiftUI(size: 28, weight: .bold)
        case 2: return swiftUI(size: 22, weight: .semibold)
        case 3: return swiftUI(size: 18, weight: .semibold)
        case 4: return swiftUI(size: 16, weight: .semibold)
        default: return swiftUI(size: 15, weight: .semibold)
        }
    }

    // MARK: - Private

    private static func nsFont(size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let ps = postScriptName(for: weight)
        if let font = NSFont(name: ps, size: size) { return font }
        // Fallback: family name + traits
        let base = NSFont(name: family, size: size) ?? NSFont(name: "Inter-Regular", size: size)
        guard let base else { return nil }
        let traits: NSFontTraitMask
        switch weight {
        case .bold, .heavy, .black: traits = .boldFontMask
        default: traits = []
        }
        return NSFontManager.shared.convert(base, toHaveTrait: traits)
    }

    private static func postScriptName(for weight: NSFont.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }
}
