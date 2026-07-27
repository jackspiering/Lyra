import Foundation

enum UntitledName {
    /// Returns a unique `Untitled.md` / `Untitled N.md` filename in `directory`.
    static func next(in directory: URL, fileManager: FileManager = .default) -> String {
        let base = "Untitled"
        let ext = "md"
        var candidate = "\(base).\(ext)"
        var n = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(n).\(ext)"
            n += 1
        }
        return candidate
    }
}
