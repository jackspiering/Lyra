import Foundation

/// Shared macOS-safe filename rules for create and rename.
enum FilenameValidation {
    /// Returns `.ok(finalName)` or `.invalid(message)`.
    /// For notes (`isDirectory == false`), ensures a `.md` suffix when missing.
    static func validate(_ name: String, isDirectory: Bool) -> VaultStore.ValidatedRename {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .invalid("Name can't be empty.")
        }
        if trimmed.contains("/") || trimmed.contains(":") {
            return .invalid("Names can't contain / or :.")
        }
        if trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return .invalid("Names can't contain control characters.")
        }
        if trimmed.hasPrefix(".") {
            return .invalid("Names can't start with a period (they'd be hidden).")
        }
        if trimmed == ".." || trimmed == "." {
            return .invalid("That name isn't valid.")
        }
        if !isDirectory, !trimmed.lowercased().hasSuffix(".md") {
            trimmed += ".md"
        }
        return .ok(trimmed)
    }
}
