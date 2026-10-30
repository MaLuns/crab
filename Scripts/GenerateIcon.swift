import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4 else {
    fatalError("Usage: swift Scripts/GenerateIcon.swift SOURCE.png OUTPUT.iconset [OUTPUT.icns]")
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
guard directory.pathExtension == "iconset" else {
    fatalError("The output directory must have the .iconset extension")
}
guard let source = NSBitmapImageRep(data: try Data(contentsOf: sourceURL)),
      let image = source.cgImage,
      source.pixelsWide > 0, source.pixelsWide == source.pixelsHigh else {
    fatalError("The source must be a readable square image")
}
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Cannot allocate \(pixels)px icon bitmap")
        }
        bitmap.size = NSSize(width: pixels, height: pixels)
        let context = graphics.cgContext
        let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        context.clear(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        guard let png = bitmap.representation(using: .png, properties: [:]),
              let verified = NSBitmapImageRep(data: png),
              verified.pixelsWide == pixels, verified.pixelsHigh == pixels else {
            fatalError("Unexpected output pixel size for \(pixels)px icon")
        }
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: directory.appendingPathComponent(filename), options: .atomic)
        print("\(filename): \(pixels)×\(pixels)")
    }
}
if arguments.count == 4 {
    let destination = URL(fileURLWithPath: arguments[3])
    guard destination.pathExtension == "icns" else {
        fatalError("The ICNS output must have the .icns extension")
    }
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".crab-icon-" + UUID().uuidString + ".icns")
    defer { try? FileManager.default.removeItem(at: temporary) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["--convert", "icns", "--output", temporary.path, directory.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("iconutil failed with status \(process.terminationStatus)") }
    try Data(contentsOf: temporary).write(to: destination, options: .atomic)
    print("ICNS: \(destination.path)")
}
print("Artwork source: \(sourceURL.path)")
