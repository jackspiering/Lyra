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
        guard let size = imageSizeIfWithinBudget(data) else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        // Apply EXIF orientation so phone/scanner photos are upright and the
        // returned size matches the displayed pixels.
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: size.width, height: size.height))
    }

    /// Image dimensions when encoded bytes and decoded pixels are budgeted.
    /// Orientation-aware: quarter-turn EXIF orientations swap width/height.
    static func imageSizeIfWithinBudget(_ data: Data) -> (width: Int, height: Int)? {
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
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let displayWidth = (orientation >= 5 && orientation <= 8) ? height : width
        let displayHeight = (orientation >= 5 && orientation <= 8) ? width : height
        guard isWithinBudget(width: displayWidth, height: displayHeight) else { return nil }
        return (displayWidth, displayHeight)
    }

    static func decode(contentsOf url: URL) -> NSImage? {
        guard let data = FileSystemVault.safeBoundedData(at: url, maxBytes: maxEncodedBytes) else {
            return nil
        }
        return decode(data)
    }
}
