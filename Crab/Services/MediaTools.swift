import AppKit
import ImageIO
import UniformTypeIdentifiers
import CWebP

enum MediaTools {
    private static func failure(_ message: String) -> Error {
        NSError(domain: "Crab.Media", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func convert(_ urls: [URL], format: ToolAction) throws -> [URL] {
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
                    let output = format == .jpeg ? try resized(image, width: image.width, height: image.height, opaque: true) : image
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
                    results.append(try createIcons(image, name: name, directory: directory, format: format))
                default: throw failure("该操作不是图片转换格式。")
                }
            }
            return results
        } catch {
            for result in results { try? FileManager.default.removeItem(at: result) }
            throw error
        }
    }

    private static func loadImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw failure("无法读取图片：\(url.lastPathComponent)") }
        let w = width.int64Value, h = height.int64Value
        guard w > 0, h > 0, w <= 32_768, h <= 32_768, w <= 100_000_000 / h else { throw failure("图片尺寸过大，最多支持一亿像素，单边不超过 32768 像素。") }
        let maximum = max(width.intValue, height.intValue)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maximum]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw failure("无法解码图片：\(url.lastPathComponent)") }
        return image
    }

    private static func resized(_ image: CGImage, width: Int, height: Int, opaque: Bool = false) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("无法创建图片画布。") }
        if opaque {
            context.setFillColor(NSColor.white.cgColor)
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

    private static func createIcons(_ image: CGImage, name: String, directory: URL, format: ToolAction) throws -> URL {
        let fm = FileManager.default
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
                            try write(resized(image, width: Int(side * Double(scale)), height: Int(side * Double(scale)), opaque: true), to: target, type: .png)
                        }
                        entries.append(["idiom": idiom, "size": "\(label)x\(label)", "scale": "\(scale)x", "filename": filename])
                    }
                }
            }
            for (idiom, side, scale) in [("ipad", 83.5, 2), ("ios-marketing", 1024.0, 1)] {
                let label = String(format: "%g", side), filename = "Icon-\(String(format: "%g", side))@\(scale)x.png"
                try write(resized(image, width: Int(side * Double(scale)), height: Int(side * Double(scale)), opaque: true), to: iconset.appendingPathComponent(filename), type: .png)
                entries.append(["idiom": idiom, "size": "\(label)x\(label)", "scale": "\(scale)x", "filename": filename])
            }
            let json: [String: Any] = ["images": entries, "info": ["author": "Crab", "version": 1]]
            try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: iconset.appendingPathComponent("Contents.json"))
        } else {
            for side in [16, 32, 128, 256, 512] {
                for scale in [1, 2] {
                    let suffix = scale == 1 ? "" : "@2x"
                    try write(resized(image, width: side * scale, height: side * scale), to: iconset.appendingPathComponent("icon_\(side)x\(side)\(suffix).png"), type: .png)
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
