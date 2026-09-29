import Foundation
import UniformTypeIdentifiers

enum AttachmentStore {
    static let folderName = "_attachments"

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// `pasted-image-<timestamp>.<ext>`, with `-2`, `-3`, … when a name (in any case) is taken.
    static func uniqueFilename(fileExtension: String, now: Date = Date(), existing: Set<String>) -> String {
        let stamp = stampFormatter.string(from: now)
        // Hyphenated name: CommonMark link destinations cannot contain unescaped spaces.
        func name(_ n: Int) -> String {
            n == 1 ? "pasted-image-\(stamp).\(fileExtension)" : "pasted-image-\(stamp)-\(n).\(fileExtension)"
        }
        let occupied = Set(existing.map { $0.lowercased() })
        var n = 1
        while occupied.contains(name(n).lowercased()) { n += 1 }
        return name(n)
    }

    /// Whether a paste should become an attachment rather than text. Apps
    /// list pasteboard types richest first, and Office, Numbers, and Pages add
    /// a picture of copied text after the text itself, so text listed before
    /// any image wins. PDF is never treated as a pasted image.
    static func prefersImagePaste(types: [String]) -> Bool {
        guard let firstImage = types.firstIndex(where: isRasterImageType) else { return false }
        guard let firstText = types.firstIndex(where: isTextType) else { return true }
        return firstImage < firstText
    }

    /// Image files keep their bytes on paste. Returns `nil` for other files.
    static func imageFileExtension(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              let type = UTType(filenameExtension: ext),
              type.conforms(to: .image), !type.conforms(to: .pdf) else {
            return nil
        }
        return ext
    }

    private static func isRasterImageType(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .pdf)
    }

    private static func isTextType(_ identifier: String) -> Bool {
        UTType(identifier)?.conforms(to: .text) == true
    }

    /// Writes an image under `vaultRoot/_attachments/` (a pasted JPEG stays JPEG) and returns a
    /// path for its Markdown image link. When `noteURL` is set, the path is relative to the
    /// note's folder so other renderers resolve it; otherwise vault-root style (`_attachments/…`).
    static func save(
        data: Data,
        fileExtension: String,
        vaultRoot: URL,
        noteURL: URL? = nil,
        now: Date = Date()
    ) throws -> String {
        guard FileSystemVault.isSafeDirectory(vaultRoot, within: vaultRoot) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let dir = vaultRoot.appendingPathComponent(folderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path),
           !FileSystemVault.isSafeDirectory(dir, within: vaultRoot) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard FileSystemVault.isSafeDirectory(dir, within: vaultRoot) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let existing = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        )
        var fileURL = dir.appendingPathComponent(uniqueFilename(fileExtension: fileExtension, now: now, existing: existing))
        for _ in 0..<100 {
            // Final vault-boundary check: _attachments may have been swapped for a symlink
            // between the directory validations and the write.
            guard FileSystemVault.isSafePath(fileURL, within: vaultRoot) else {
                throw CocoaError(.fileWriteNoPermission)
            }
            if FileSystemVault.exclusivelyCreateEmptyFile(at: fileURL) {
                break
            }
            let names = Set(
                (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            )
            fileURL = dir.appendingPathComponent(uniqueFilename(fileExtension: fileExtension, now: now, existing: names))
        }
        guard FileSystemVault.isSafePath(fileURL, within: vaultRoot),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try data.write(to: fileURL, options: .atomic)
        // Verify the write landed inside the vault. Only clean up when the
        // resolved path is still inside the vault.
        guard FileSystemVault.isSafePath(fileURL, within: vaultRoot) else {
            if FileSystemVault.isWithin(fileURL, root: vaultRoot) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            throw CocoaError(.fileWriteNoPermission)
        }
        if let noteURL {
            let noteDir = noteURL.deletingLastPathComponent()
            return relativePath(from: noteDir, to: fileURL)
        }
        return "\(folderName)/\(fileURL.lastPathComponent)"
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
}
