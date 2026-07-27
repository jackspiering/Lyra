import Foundation
import AppKit

enum AttachmentStore {
    static let folderName = "_attachments"

    static func uniquePNGFilename(now: Date = Date(), existing: Set<String>) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: now)
        let base = "Pasted Image \(stamp).png"
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("Pasted Image \(stamp)-\(n).png") { n += 1 }
        return "Pasted Image \(stamp)-\(n).png"
    }

    static func savePNG(data: Data, vaultRoot: URL, now: Date = Date()) throws -> String {
        let dir = vaultRoot.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        )
        let name = uniquePNGFilename(now: now, existing: existing)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return "\(folderName)/\(name)"
    }

    /// PNG bytes from pasteboard image representations.
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
