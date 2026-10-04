import AppKit
import ImageIO

/// Decode only the pixels the island needs, rather than retaining a full-size cover.
enum ArtworkImage {
    static let maximumPixelSize = 256

    static func decode(_ data: Data) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        // Only the thumbnail survives this call, not the source or its encoded data.
        return NSImage(cgImage: thumbnail,
                       size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }

    /// Sample the decoded thumbnail directly into one sRGB pixel; no TIFF round-trip.
    static func representativeColor(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let rendered = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered, pixel[3] > 0 else { return nil }
        // The bitmap stores premultiplied RGB; NSColor expects straight components.
        let alpha = CGFloat(pixel[3])
        return NSColor(srgbRed: min(CGFloat(pixel[0]) / alpha, 1),
                       green: min(CGFloat(pixel[1]) / alpha, 1),
                       blue: min(CGFloat(pixel[2]) / alpha, 1),
                       alpha: alpha / 255)
    }
}
