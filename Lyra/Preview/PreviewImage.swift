import AppKit
import ImageIO

/// Decode vault images with a pixel budget so a hostile file cannot expand
/// into an unbounded bitmap during Reading or PDF export.
enum PreviewImage {
    static let maxEncodedBytes = 32 * 1024 * 1024
    static let maxDecodedPixels = 50_000_000
    static let maxDecodedDimension = 16_384

    static func isWithinBudget(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        guard width <= maxDecodedDimension, height <= maxDecodedDimension else { return false }
        return width <= maxDecodedPixels / height
    }

    static func decode(_ data: Data) -> NSImage? {
        guard data.count <= maxEncodedBytes else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard isWithinBudget(width: width, height: height) else { return nil }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    static func decode(contentsOf url: URL) -> NSImage? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size > maxEncodedBytes { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
}
