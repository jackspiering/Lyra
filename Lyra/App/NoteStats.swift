import Foundation

/// Pure text statistics for the editor status bar.
enum NoteStats {
    /// Counts whitespace-separated tokens (Unicode whitespace).
    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }

    /// Counts Unicode letters only (`Character.isLetter`); ignores spaces and punctuation.
    static func letterCount(_ text: String) -> Int {
        text.reduce(0) { count, ch in
            count + (ch.isLetter ? 1 : 0)
        }
    }
}
