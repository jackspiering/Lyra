import Foundation
import AppKit

enum AttachmentStore {
    static let folderName = "_attachments"

    static func uniquePNGFilename(now: Date = Date(), existing: Set<String>) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: now)
        // Hyphenated name: CommonMark link destinations cannot contain unescaped spaces.
        let base = "pasted-image-\(stamp).png"
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("pasted-image-\(stamp)-\(n).png") { n += 1 }
        return "pasted-image-\(stamp)-\(n).png"
    }

    /// Writes PNG under `vaultRoot/_attachments/` and returns a path suitable for Markdown
    /// image destinations. When `noteURL` is set, the path is relative to the note's directory
    /// so other renderers resolve it correctly; otherwise vault-root style (`_attachments/…`).
    static func savePNG(
        data: Data,
        vaultRoot: URL,
        noteURL: URL? = nil,
        now: Date = Date()
    ) throws -> String {
        let dir = vaultRoot.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        )
        let name = uniquePNGFilename(now: now, existing: existing)
        let fileURL = dir.appendingPathComponent(name)
        try data.write(to: fileURL, options: .atomic)

        if let noteURL {
            let noteDir = noteURL.deletingLastPathComponent()
            return relativePath(from: noteDir, to: fileURL)
        }
        return "\(folderName)/\(name)"
    }

    /// Path from `baseDirectory` to `target` using `../` segments as needed.
    static func relativePath(from baseDirectory: URL, to target: URL) -> String {
        let base = baseDirectory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let dest = target.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var i = 0
        while i < base.count && i < dest.count && base[i] == dest[i] {
            i += 1
        }
        let ups = Array(repeating: "..", count: base.count - i)
        let downs = Array(dest[i...])
        let parts = ups + downs
        return parts.isEmpty ? target.lastPathComponent : parts.joined(separator: "/")
    }

    /// PNG bytes from pasteboard image representations.
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
