import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
enum ArtworkImageTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func fixture(width: Int, height: Int, alpha: CGFloat = 1,
                        orientation: Int = 1) -> Data {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!,
                                  [kCGImagePropertyOrientation: orientation] as CFDictionary)
        check(CGImageDestinationFinalize(destination), "Fixture encoding failed")
        return data as Data
    }

    static func pixels(_ image: NSImage) -> CGImage {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    static func main() {
        autoreleasepool {
            let large = ArtworkImage.decode(fixture(width: 3000, height: 3000))!
            check(pixels(large).width == 256 && pixels(large).height == 256, "Large cover not bounded")
            let wide = ArtworkImage.decode(fixture(width: 1200, height: 600))!
            check(pixels(wide).width == 256 && pixels(wide).height == 128, "Aspect ratio changed")
            let rotated = ArtworkImage.decode(fixture(width: 1200, height: 600, orientation: 6))!
            check(pixels(rotated).width == 128 && pixels(rotated).height == 256, "Orientation ignored")
            let small = ArtworkImage.decode(fixture(width: 32, height: 16))!
            check(pixels(small).width == 32 && pixels(small).height == 16, "Small cover was enlarged")
            check(ArtworkImage.decode(Data()).isNil, "Empty data accepted")
            check(ArtworkImage.decode(Data("not an image".utf8)).isNil, "Corrupt data accepted")

            let red = ArtworkImage.representativeColor(from: large)!.usingColorSpace(.sRGB)!
            check(red.redComponent > 0.98 && red.greenComponent < 0.02 && red.blueComponent < 0.02,
                  "RGB channels changed")
            let translucent = ArtworkImage.decode(fixture(width: 32, height: 32, alpha: 0.5))!
            let color = ArtworkImage.representativeColor(from: translucent)!.usingColorSpace(.sRGB)!
            check(color.redComponent > 0.98 && abs(color.alphaComponent - 0.5) < 0.02,
                  "Premultiplied alpha was not handled")
            let transparent = ArtworkImage.decode(fixture(width: 32, height: 32, alpha: 0))!
            check(ArtworkImage.representativeColor(from: transparent).isNil, "Transparent cover needs fallback")
        }
        print("Artwork image tests passed")
    }
}

private extension Optional {
    var isNil: Bool { self == nil }
}
