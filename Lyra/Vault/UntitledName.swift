import Foundation

enum UntitledName {
    /// Unique filename in `directory`, e.g. `Untitled.md`, `Untitled 2.md`.
    static func next(base: String = "Untitled", ext: String? = "md", in directory: URL, fileManager: FileManager = .default) -> String {
        let candidate: (Int) -> String = { n in
            let stem = n == 1 ? base : "\(base) \(n)"
            if let ext, !ext.isEmpty { return "\(stem).\(ext)" }
            return stem
        }
        var n = 1
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate(n)).path) {
            n += 1
        }
        return candidate(n)
    }
}
