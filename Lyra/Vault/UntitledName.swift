import Foundation

enum UntitledName {
    /// Unique name in `directory` — e.g. `Untitled.md`, `Untitled 2.md`, or `New Folder` / `New Folder 2`.
    static func next(
        base: String = "Untitled",
        ext: String? = "md",
        in directory: URL,
        fileManager: FileManager = .default
    ) -> String {
        func name(_ n: Int) -> String {
            let stem = n == 1 ? base : "\(base) \(n)"
            return ext.map { "\(stem).\($0)" } ?? stem
        }
        var n = 1
        while fileManager.fileExists(atPath: directory.appendingPathComponent(name(n)).path) {
            n += 1
        }
        return name(n)
    }
}
