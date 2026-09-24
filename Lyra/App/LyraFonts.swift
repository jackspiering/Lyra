import AppKit
import CoreText
import SwiftUI

/// Bundled [Inter](https://rsms.me/inter/) (SIL Open Font License 1.1).
enum LyraFonts {
    private static var didRegister = false

    @discardableResult
    static func registerBundledFonts() -> [String] {
        guard !didRegister else { return [] }
        var failed: [String] = []
        for name in ["Inter-Regular", "Inter-SemiBold", "Inter-Bold"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            guard let url else {
                failed.append(name)
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                failed.append(name)
            }
        }
        didRegister = failed.isEmpty
        return failed
    }

    static func ui(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: face(weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func code(size: CGFloat = 12) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Prose size in the writing column (Source and Reading).
    static let proseSize: CGFloat = 16
    /// Extra space between prose lines, in points.
    static let proseLineSpacing: CGFloat = 7

    static var body: Font { font(14) }
    static var prose: Font { font(proseSize) }
    static var caption: Font { font(11) }
    static var captionEmphasized: Font { font(11, weight: .semibold) }
    /// Sidebar rows, tab chips, and card titles.
    static var label: Font { font(13) }
    static var labelEmphasized: Font { font(13, weight: .semibold) }
    static var headline: Font { font(15, weight: .semibold) }
    /// Note title above the column.
    static var title: Font { font(32, weight: .bold) }

    /// Point size for a Markdown heading level (shared by Source and Reading).
    static func headingSize(level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 22
        case 3: return 19
        default: return 17
        }
    }

    static func heading(level: Int) -> Font {
        font(headingSize(level: level), weight: level <= 2 ? .bold : .semibold)
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
