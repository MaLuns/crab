import AppKit

guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: swift Scripts/GenerateAdaptiveIcon.swift SOURCE.png ARTWORK.imageset APPICON.icon")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let imageSet = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let icon = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
guard imageSet.pathExtension == "imageset", imageSet.deletingLastPathComponent().pathExtension == "xcassets",
      icon.pathExtension == "icon" else { fatalError("Expected .xcassets/.imageset and .icon output paths") }
let data = try Data(contentsOf: sourceURL)
guard let light = NSBitmapImageRep(data: data), let dark = NSBitmapImageRep(data: data),
      let pixels = dark.bitmapData, light.pixelsWide == light.pixelsHigh,
      dark.bitsPerSample == 8, dark.samplesPerPixel == 4, !dark.isPlanar,
      dark.bitmapFormat.contains(.alphaNonpremultiplied), !dark.bitmapFormat.contains(.alphaFirst) else {
    fatalError("Expected a square, nonpremultiplied RGBA8 source")
}
var minX = dark.pixelsWide, minY = dark.pixelsHigh, maxX = -1, maxY = -1
for y in 0..<dark.pixelsHigh {
    for x in 0..<dark.pixelsWide {
        let offset = y * dark.bytesPerRow + x * 4
        if pixels[offset + 3] > 128 {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
        for channel in 0..<3 { pixels[offset + channel] = 255 - pixels[offset + channel] }
    }
}
guard maxX >= minX, maxY >= minY else { fatalError("The source has no opaque artwork") }
let side = max(maxX - minX + 1, maxY - minY + 1)
let crop = CGRect(x: (minX + maxX + 1 - side) / 2, y: (minY + maxY + 1 - side) / 2,
                  width: side, height: side)
let manager = FileManager.default
try manager.createDirectory(at: imageSet, withIntermediateDirectories: true)
try manager.createDirectory(at: icon.appendingPathComponent("Assets"), withIntermediateDirectories: true)
func writeJSON(_ value: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        .write(to: url, options: .atomic)
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try writeJSON(["info": info], to: imageSet.deletingLastPathComponent().appendingPathComponent("Contents.json"))
try writeJSON(["info": info, "images": [
    ["idiom": "universal", "filename": "Light.png"],
    ["idiom": "universal", "filename": "Dark.png",
     "appearances": [["appearance": "luminosity", "value": "dark"]]]
]], to: imageSet.appendingPathComponent("Contents.json"))
try data.write(to: imageSet.appendingPathComponent("Light.png"), options: .atomic)
try dark.representation(using: .png, properties: [:])!.write(to: imageSet.appendingPathComponent("Dark.png"), options: .atomic)
for (name, source) in [("Light", light), ("Dark", dark)] {
    guard let cropped = source.cgImage?.cropping(to: crop),
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot render icon layer") }
    graphics.cgContext.interpolationQuality = .high
    graphics.cgContext.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    graphics.cgContext.draw(cropped, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: icon.appendingPathComponent("Assets/" + name + ".png"), options: .atomic)
}
try writeJSON([
    "fill": ["solid": "extended-gray:1.00000,1.00000"],
    "fill-specializations": [["appearance": "dark", "value": ["solid": "extended-gray:0.00000,1.00000"]]],
    "groups": [[
        "layers": [["name": "Crab", "glass": false, "image-name-specializations": [
            ["value": "Light.png"], ["appearance": "dark", "value": "Dark.png"]
        ]]],
        "shadow": ["kind": "none", "opacity": 0], "specular": false,
        "translucency": ["enabled": false, "value": 0]
    ]],
    "supported-platforms": ["squares": "shared"]
], to: icon.appendingPathComponent("icon.json"))
print("Appearance artwork: \(imageSet.path)")
print("System app icon: \(icon.path)")
