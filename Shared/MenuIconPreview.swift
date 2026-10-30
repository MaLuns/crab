import AppKit
import ImageIO
import UniformTypeIdentifiers

enum MenuIconPreview {
    static let pointSize: CGFloat = 18
    static let pixelSize = 64
    private static let maximumEncodedSize = 128 * 1024
    static func dimensions(at path: String) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber, let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }
    static func thumbnail(at path: String) -> Data? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixelSize] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), data.length <= maximumEncodedSize else { return nil }
        return data as Data
    }
    static func pngData(from original: NSImage) -> Data? {
        guard let source = original.copy() as? NSImage, source.isValid,
              source.size.width.isFinite, source.size.height.isFinite,
              source.size.width > 0, source.size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: pixelSize, pixelsHigh: pixelSize,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let scale = min(CGFloat(pixelSize) / source.size.width, CGFloat(pixelSize) / source.size.height)
        let drawSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let destination = NSRect(x: (CGFloat(pixelSize) - drawSize.width) / 2,
                                 y: (CGFloat(pixelSize) - drawSize.height) / 2,
                                 width: drawSize.width, height: drawSize.height)
        source.isTemplate = false
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        source.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]), data.count <= maximumEncodedSize else { return nil }
        return data
    }

}
