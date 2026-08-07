import Foundation

/// Shared macOS-safe filename rules for create and rename.
enum FilenameValidation {
    /// Outcome of validating a proposed name.
    enum Result: Equatable, Sendable {
        case ok(String)
        case invalid(String)
    }

    /// Returns `.ok(finalName)` or `.invalid(message)`.
    /// For notes (`isDirectory == false`), ensures a `.md` suffix when missing.
    static func validate(_ name: String, isDirectory: Bool) -> FilenameValidation.Result {
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
        if isDirectory, trimmed.caseInsensitiveCompare("_attachments") == .orderedSame {
            return .invalid("That name is reserved for Lyra attachments.")
        }
        if !isDirectory, !trimmed.lowercased().hasSuffix(".md") {
            trimmed += ".md"
        }
        return .ok(trimmed)
    }

    /// Sanitizes a preferred note stem (no extension) for auto-create / Settings.
    /// Strips a trailing `.md` so `"Note.md"` does not become `Note.md.md`.
    /// Illegal or empty after trim falls back to `"Untitled"`.
    static func sanitizeNoteStem(_ raw: String) -> String {
        var stem = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.lowercased().hasSuffix(".md") {
            stem = String(stem.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !stem.isEmpty else { return "Untitled" }
        if stem.contains("/") || stem.contains(":") { return "Untitled" }
        if stem.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "Untitled"
        }
        if stem.hasPrefix(".") { return "Untitled" }
        if stem == ".." || stem == "." { return "Untitled" }
        return stem
    }
}
