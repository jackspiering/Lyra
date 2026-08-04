import Foundation

/// Pure text statistics for the editor status bar.
enum NoteStats {
    /// Counts whitespace-separated tokens (Unicode whitespace).
    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }

    /// Unicode extended grapheme clusters (`String.count`), including spaces and punctuation.
    static func characterCount(_ text: String) -> Int {
        text.count
    }
}
