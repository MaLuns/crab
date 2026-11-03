import AppKit
import ImageIO
import UniformTypeIdentifiers
import CWebP

/// Coordinates refer to the oriented image, with the origin at its top-left corner.
struct IconCrop: Equatable {
    var center: CGPoint
    var fraction: CGFloat
    static let centered = IconCrop(center: CGPoint(x: 0.5, y: 0.5), fraction: 1)

    func pixelRect(in size: CGSize) -> CGRect {
        let width = floor(size.width), height = floor(size.height)
        guard width >= 1, height >= 1 else { return .zero }
        let side = max(1, (min(width, height) * min(1, max(0, fraction))).rounded())
        let x = min(width - side, max(0, (center.x * width - side / 2).rounded()))
        let y = min(height - side, max(0, (center.y * height - side / 2).rounded()))
        return CGRect(x: x, y: y, width: side, height: side)
    }
}

struct IconExportOptions {
    var crop: IconCrop?
    var backgroundColor: CGColor?

    static func defaultBackground(for format: ToolAction) -> CGColor? {
        format == .iosIconset ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) : nil
    }
}

enum MediaTools {
    private static func failure(_ message: String) -> Error {
        NSError(domain: "Crab.Media", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func convert(_ urls: [URL], format: ToolAction, iconOptions: [URL: IconExportOptions] = [:]) throws -> [URL] {
        guard !urls.isEmpty else { throw failure("请先选择图片。") }
        var results: [URL] = []
        do {
            for url in urls {
                let image = try loadImage(url)
                let directory = url.deletingLastPathComponent()
                let name = url.deletingPathExtension().lastPathComponent
                switch format {
                case .png, .jpeg, .heic, .tiff:
                    let type: UTType = format == .png ? .png : format == .jpeg ? .jpeg : format == .heic ? .heic : .tiff
                    let suffix = format == .jpeg ? "jpg" : type.preferredFilenameExtension ?? format.rawValue
                    let target = try FileOperations().uniqueURL(in: directory, preferredName: name + "." + suffix)
                    let temp = directory.appendingPathComponent(".crab-" + UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: temp) }
                    let output = format == .jpeg ? try resized(image, width: image.width, height: image.height,
                        backgroundColor: NSColor.white.cgColor, colorSpace: CGColorSpaceCreateDeviceRGB()) : image
                    try write(output, to: temp, type: type)
                    try FileManager.default.moveItem(at: temp, to: target)
                    results.append(target)
                case .webp:
                    let target = try FileOperations().uniqueURL(in: directory, preferredName: name + ".webp")
                    let temp = directory.appendingPathComponent(".crab-" + UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: temp) }
                    try writeWebP(image, to: temp)
                    try FileManager.default.moveItem(at: temp, to: target)
                    results.append(target)
                case .macIconset, .iosIconset, .icns:
                    let options = iconOptions[url]
                    let iconImage: CGImage
                    if let crop = options?.crop {
                        let rect = crop.pixelRect(in: CGSize(width: image.width, height: image.height))
                        guard let cropped = image.cropping(to: rect) else { throw failure(L("无法裁剪图片。")) }
                        iconImage = cropped
                    } else {
                        iconImage = image
                    }
                    let background = options?.backgroundColor ?? IconExportOptions.defaultBackground(for: format)
                    results.append(try createIcons(iconImage, name: name, directory: directory, format: format, backgroundColor: background))
                default: throw failure("该操作不是图片转换格式。")
                }
            }
            return results
        } catch {
            for result in results { try? FileManager.default.removeItem(at: result) }
            throw error
        }
    }

    static func iconPreview(_ url: URL) throws -> CGImage {
        try loadImage(url, maximumPixelSize: 1400)
    }

    private static func loadImage(_ url: URL, maximumPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw failure(LF("无法读取图片：%@", url.lastPathComponent)) }
        let w = width.int64Value, h = height.int64Value
        guard w > 0, h > 0, w <= 32_768, h <= 32_768, w <= 100_000_000 / h else { throw failure(L("图片尺寸过大，最多支持一亿像素，单边不超过 32768 像素。")) }
        let maximum = max(width.intValue, height.intValue)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: min(maximumPixelSize ?? maximum, maximum)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw failure(LF("无法解码图片：%@", url.lastPathComponent)) }
        return image
    }

    private static func resized(_ image: CGImage, width: Int, height: Int,
                                backgroundColor: CGColor?, colorSpace: CGColorSpace) throws -> CGImage {
        let alphaInfo: CGImageAlphaInfo = backgroundColor == nil ? .premultipliedLast : .noneSkipLast
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: alphaInfo.rawValue) else { throw failure("无法创建图片画布。") }
        if let backgroundColor {
            context.setFillColor(backgroundColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let scale = min(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h))
        guard let result = context.makeImage() else { throw failure("无法生成图片。") }
        return result
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType) throws {
        guard (CGImageDestinationCopyTypeIdentifiers() as NSArray).contains(type.identifier),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { throw failure("当前系统不支持输出 \(type.identifier)。") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw failure("写入图片失败。") }
    }

    private static func writeWebP(_ image: CGImage, to url: URL) throws {
        guard image.width <= WEBP_MAX_DIMENSION, image.height <= WEBP_MAX_DIMENSION else {
            throw failure("WebP 单边尺寸不能超过 16383 像素。")
        }
        let stride = image.width * 4
        var rgba = [UInt8](repeating: 0, count: stride * image.height)
        try rgba.withUnsafeMutableBytes { pixels in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: pixels.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: stride, space: space,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw failure("无法创建 WebP 编码画布。")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        for offset in Swift.stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Int(rgba[offset + 3])
            if alpha > 0 && alpha < 255 {
                for component in 0..<3 {
                    rgba[offset + component] = UInt8(min(255, (Int(rgba[offset + component]) * 255 + alpha / 2) / alpha))
                }
            }
        }
        var encoded: UnsafeMutablePointer<UInt8>?
        let count = rgba.withUnsafeBufferPointer {
            WebPEncodeLosslessRGBA($0.baseAddress, Int32(image.width), Int32(image.height), Int32(stride), &encoded)
        }
        guard count > 0, let encoded = encoded else { throw failure("WebP 编码失败。") }
        defer { WebPFree(encoded) }
        try Data(bytes: encoded, count: count).write(to: url, options: .withoutOverwriting)
    }

    private static func createIcons(_ image: CGImage, name: String, directory: URL, format: ToolAction,
                                    backgroundColor: CGColor?) throws -> URL {
        let fm = FileManager.default
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw failure("无法创建图片画布。") }
        func writeIcon(pixels: Int, to url: URL) throws {
            let icon = try resized(image, width: pixels, height: pixels, backgroundColor: backgroundColor, colorSpace: colorSpace)
            try write(icon, to: url, type: .png)
        }
        let workspace = directory.appendingPathComponent(".crab-icons-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workspace) }
        let iconset = workspace.appendingPathComponent(format == .iosIconset ? "Icon.appiconset" : "Icon.iconset", isDirectory: true)
        try fm.createDirectory(at: iconset, withIntermediateDirectories: false)
        if format == .iosIconset {
            var entries: [[String: String]] = []
            let specs: [(String, [Double], [Int])] = [("iphone", [20, 29, 40, 60], [2, 3]), ("ipad", [20, 29, 40, 76], [1, 2])]
            for (idiom, sizes, scales) in specs {
                for side in sizes {
                    for scale in scales {
                        let label = String(format: "%g", side)
                        let filename = "Icon-\(label)@\(scale)x.png"
                        let target = iconset.appendingPathComponent(filename)
                        if !fm.fileExists(atPath: target.path) {
                            try writeIcon(pixels: Int(side * Double(scale)), to: target)
                        }
                        entries.append(["idiom": idiom, "size": "\(label)x\(label)", "scale": "\(scale)x", "filename": filename])
                    }
                }
            }
            for (idiom, side, scale) in [("ipad", 83.5, 2), ("ios-marketing", 1024.0, 1)] {
                let label = String(format: "%g", side), filename = "Icon-\(String(format: "%g", side))@\(scale)x.png"
                try writeIcon(pixels: Int(side * Double(scale)), to: iconset.appendingPathComponent(filename))
                entries.append(["idiom": idiom, "size": "\(label)x\(label)", "scale": "\(scale)x", "filename": filename])
            }
            let json: [String: Any] = ["images": entries, "info": ["author": "Crab", "version": 1]]
            try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: iconset.appendingPathComponent("Contents.json"))
        } else {
            for side in [16, 32, 128, 256, 512] {
                for scale in [1, 2] {
                    let suffix = scale == 1 ? "" : "@2x"
                    try writeIcon(pixels: side * scale, to: iconset.appendingPathComponent("icon_\(side)x\(side)\(suffix).png"))
                }
            }
        }
        let artifact: URL, suffix: String
        if format == .icns {
            artifact = workspace.appendingPathComponent("Icon.icns")
            suffix = "icns"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
            process.arguments = ["-c", "icns", "-o", artifact.path, iconset.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw failure("系统 iconutil 生成 ICNS 失败。") }
        } else {
            artifact = iconset
            suffix = format == .iosIconset ? "appiconset" : "iconset"
        }
        let target = try FileOperations().uniqueURL(in: directory, preferredName: name + "." + suffix)
        try fm.moveItem(at: artifact, to: target)
        return target
    }
}
