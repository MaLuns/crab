import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
import zlib
@testable import Crab

final class ToolTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CrabToolTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root = root { try FileManager.default.removeItem(at: root) } }

    func testKnownHashVectorsAndDirectoryRejection() throws {
        let file = root.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: file)
        let hashes = try HashTools.digests(of: file)
        XCTAssertEqual(hashes["MD5"], "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(hashes["SHA1"], "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(hashes["SHA256"], "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hashes["SHA512"], "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        XCTAssertThrowsError(try HashTools.digests(of: root))
        try Data().write(to: file)
        XCTAssertEqual(try HashTools.digests(of: file)["SHA256"], "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testBuiltinOfficeTemplatesCreateOriginalValidPackages() throws {
        for (id, entryPath) in [("word", "word/document.xml"), ("excel", "xl/workbook.xml")] {
            let template = try XCTUnwrap(FileTemplate.defaults.first(where: { $0.id == id }))
            let file = try FileOperations().createFile(template: template, in: root, name: "新建-\(id)")
            XCTAssertEqual(file.pathExtension, template.suffix)
            let folder = try ArchiveTools.extract(file, in: root)
            for path in ["[Content_Types].xml", "_rels/.rels", entryPath] {
                let data = try Data(contentsOf: folder.appendingPathComponent(path))
                let parser = XMLParser(data: data)
                XCTAssertTrue(parser.parse(), "\(id): \(path): \(String(describing: parser.parserError))")
            }
        }
    }

    func testZipRoundtripPreservesBytesAndNeverOverwrites() throws {
        let folder = root.appendingPathComponent("资料", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let input = folder.appendingPathComponent("你好.bin")
        let bytes = Data((0..<150_000).map { UInt8($0 % 251) })
        try bytes.write(to: input)
        let metadata = folder.appendingPathComponent("__MACOSX", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: false)
        try Data("ordinary user data".utf8).write(to: metadata.appendingPathComponent("keep.txt"))
        let archive = try ArchiveTools.compress([folder], in: root)
        let another = try ArchiveTools.compress([folder], in: root)
        XCTAssertNotEqual(archive, another)
        let output = try ArchiveTools.extract(archive, in: root)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("资料/你好.bin")), bytes)
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("资料/__MACOSX/keep.txt")), "ordinary user data")
        let secondOutput = try ArchiveTools.extract(archive, in: root)
        XCTAssertNotEqual(output, secondOutput)
        XCTAssertEqual(try Data(contentsOf: input), bytes)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".crab-") })
    }

    func testZipRejectsTraversalSymlinksConflictsAndCorruption() throws {
        let maliciousNames = ["../escaped.txt", "/absolute.txt", "ok/../escaped.txt", "C:/escape.txt", "ok\\escape.txt"]
        for name in maliciousNames {
            let archive = root.appendingPathComponent(UUID().uuidString + ".zip")
            try makeZIP([(name, Data("bad".utf8), 0x81a4_0000)]).write(to: archive)
            XCTAssertThrowsError(try ArchiveTools.extract(archive, in: root), name)
        }
        let symlink = root.appendingPathComponent("symlink.zip")
        try makeZIP([("link", Data("../../escape".utf8), 0xa1ff_0000)]).write(to: symlink)
        XCTAssertThrowsError(try ArchiveTools.extract(symlink, in: root))
        let conflict = root.appendingPathComponent("conflict.zip")
        try makeZIP([("File", Data(), 0x81a4_0000), ("file", Data(), 0x81a4_0000)]).write(to: conflict)
        XCTAssertThrowsError(try ArchiveTools.extract(conflict, in: root))
        let corrupt = root.appendingPathComponent("corrupt.zip")
        var corruptData = makeZIP([("valid.txt", Data("abc".utf8), 0x81a4_0000)])
        corruptData[30 + "valid.txt".utf8.count] ^= 0xff
        try corruptData.write(to: corrupt)
        XCTAssertThrowsError(try ArchiveTools.extract(corrupt, in: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.txt").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".crab-") })
    }

    func testCompressionRejectsRecursiveDestinationAndLinks() throws {
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ArchiveTools.compress([folder], in: folder))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        XCTAssertThrowsError(try ArchiveTools.compress([link], in: root))
    }

    func testImageConversionsAndIconsets() throws {
        let input = try halfTransparentImage()
        for format in [ToolAction.png, .jpeg, .heic, .tiff] {
            let result = try XCTUnwrap(MediaTools.convert([input], format: format).first)
            XCTAssertNotEqual(result, input)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(result as CFURL, nil))
            let converted = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(converted.width, 64)
            XCTAssertEqual(converted.height, 32)
        }
        let mac = try XCTUnwrap(MediaTools.convert([input], format: .macIconset).first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mac.appendingPathComponent("icon_512x512@2x.png").path))
        try assertIconCanvas(try readImage(mac.appendingPathComponent("icon_32x32.png")), background: .clear)
        let ios = try XCTUnwrap(MediaTools.convert([input], format: .iosIconset).first)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: ios.appendingPathComponent("Contents.json"))) as! [String: Any]
        XCTAssertEqual((manifest["images"] as? [[String: String]])?.count, 18)
        let marketingSource = try XCTUnwrap(CGImageSourceCreateWithURL(ios.appendingPathComponent("Icon-1024@1x.png") as CFURL, nil))
        let marketingImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(marketingSource, 0, nil))
        XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(marketingImage.alphaInfo))
        try assertIconCanvas(marketingImage, background: .white)
        let icns = try XCTUnwrap(MediaTools.convert([input], format: .icns).first)
        XCTAssertEqual(try Data(contentsOf: icns).prefix(4), Data("icns".utf8))
        try assertIconCanvas(try readImage(icns), background: .clear)
    }

    func testCustomBackgroundsFillSourceTransparencyAndPaddingPerImage() throws {
        let full = try halfTransparentImage()
        let cropped = root.appendingPathComponent("cropped.png")
        try FileManager.default.copyItem(at: full, to: cropped)
        let pink = NSColor(srgbRed: 0.9, green: 0.2, blue: 0.4, alpha: 1)
        let indigo = NSColor(srgbRed: 0.2, green: 0.25, blue: 0.9, alpha: 1)
        let options = [full: IconExportOptions(crop: nil, backgroundColor: pink.cgColor),
                       cropped: IconExportOptions(crop: .centered, backgroundColor: indigo.cgColor)]
        for (format, member) in [(ToolAction.icns, ""), (.macIconset, "icon_32x32.png"), (.iosIconset, "Icon-1024@1x.png")] {
            let outputs = try MediaTools.convert([full, cropped], format: format, iconOptions: options)
            XCTAssertEqual(outputs.count, 2)
            for (index, output) in outputs.enumerated() {
                let image = try readImage(member.isEmpty ? output : output.appendingPathComponent(member))
                try assertIconCanvas(image, background: index == 0 ? pink : indigo, cropped: index == 1)
                if format == .iosIconset {
                    XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo))
                }
            }
        }
    }

    private func halfTransparentImage() throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 64, height: 32))
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 32, y: 0, width: 32, height: 32))
        let url = root.appendingPathComponent("sample.png")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return url
    }

    // Compare the transparent half, the opaque subject and the space above it in a known color space.
    private func assertIconCanvas(_ image: CGImage, background: NSColor, cropped: Bool = false,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        let sample = CGRect(x: 0, y: 0, width: 1, height: 1)
        context.setBlendMode(.copy)
        for (x, y, expected) in [(0.25, 0.5, background), (0.75, 0.5, NSColor.black), (0.75, 0.125, cropped ? .black : background)] {
            let location = sample.offsetBy(dx: floor(CGFloat(image.width) * x), dy: floor(CGFloat(image.height) * y))
            context.draw(try XCTUnwrap(image.cropping(to: location)), in: sample)
            let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let color = try XCTUnwrap(expected.usingColorSpace(.sRGB))
            let components = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            for (channel, value) in components.enumerated() {
                XCTAssertEqual(CGFloat(bytes[channel]) / 255, value, accuracy: 0.035, file: file, line: line)
            }
        }
    }

    func testIconExportsUseCropFromOrientedPreviewAtEverySize() throws {
        let input = try stripedImage(named: "rotated", orientation: .right)
        let preview = try MediaTools.iconPreview(input)
        XCTAssertLessThan(preview.height, 1800)
        XCTAssertEqual(CGFloat(preview.height) / CGFloat(preview.width), 3, accuracy: 0.02)
        let crop = IconCrop(center: CGPoint(x: 0.5, y: 11.0 / 12), fraction: 0.5)
        let selection = crop.pixelRect(in: CGSize(width: preview.width, height: preview.height))
        try assertColor(try XCTUnwrap(preview.cropping(to: selection)), blue: true)

        let options = [input: IconExportOptions(crop: crop, backgroundColor: nil)]
        for format in [ToolAction.icns, .macIconset, .iosIconset] {
            let output = try XCTUnwrap(MediaTools.convert([input], format: format, iconOptions: options).first)
            if format == .icns {
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
                XCTAssertGreaterThan(CGImageSourceGetCount(source), 0)
                for i in 0..<CGImageSourceGetCount(source) {
                    try assertColor(try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, i, nil)), blue: true)
                }
            } else {
                let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
                let images = files.filter { $0.pathExtension == "png" }
                XCTAssertFalse(images.isEmpty)
                for file in images { try assertColor(try readImage(file), blue: true) }
            }
        }
    }

    func testBatchIconCropsAreIndependentAndFailedBatchPreservesEarlierResults() throws {
        let left = try stripedImage(named: "left", orientation: .up)
        let right = root.appendingPathComponent("right.tiff")
        try FileManager.default.copyItem(at: left, to: right)
        let crops = [left: IconCrop(center: CGPoint(x: 1.0 / 12, y: 0.5), fraction: 0.5),
                     right: IconCrop(center: CGPoint(x: 11.0 / 12, y: 0.5), fraction: 0.5)]
        let options = crops.mapValues { IconExportOptions(crop: $0, backgroundColor: nil) }
        let outputs = try MediaTools.convert([left, right], format: .macIconset, iconOptions: options)
        XCTAssertEqual(outputs.count, 2)
        let first = try XCTUnwrap(outputs.first).appendingPathComponent("icon_32x32.png")
        let second = try XCTUnwrap(outputs.last).appendingPathComponent("icon_32x32.png")
        try assertColor(try readImage(first), blue: false)
        try assertColor(try readImage(second), blue: true)

        let invalid = root.appendingPathComponent("invalid.png")
        try Data("Invalid image".utf8).write(to: invalid)
        let contents = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertThrowsError(try MediaTools.convert([left, invalid], format: .macIconset, iconOptions: options))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), contents)
        try assertColor(try readImage(first), blue: false)
    }

    // The outer sixth on each side is exactly half the short edge of this landscape image.
    private func stripedImage(named name: String, orientation: CGImagePropertyOrientation) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1800, height: 600))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 600))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 1500, y: 0, width: 300, height: 600))
        let url = root.appendingPathComponent(name + ".tiff")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()),
                                   [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func readImage(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func assertColor(_ image: CGImage, blue: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        for offset in [0.15, 0.85] {
            let color = try XCTUnwrap(bitmap.colorAt(x: Int(Double(image.width) * offset),
                                                    y: Int(Double(image.height) * offset))?.usingColorSpace(.sRGB))
            let expected = blue ? color.blueComponent : color.redComponent
            let other = blue ? color.redComponent : color.blueComponent
            XCTAssertGreaterThan(expected - max(other, color.greenComponent), 0.55, file: file, line: line)
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.02, file: file, line: line)
        }
    }

    private func makeZIP(_ files: [(String, Data, UInt32)]) -> Data {
        var local = Data(), central = Data()
        for (name, contents, permissions) in files {
            let offset = UInt32(local.count), path = Data(name.utf8)
            let crc = contents.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(contents.count)) }
            local.le(UInt32(0x04034b50)); local.le(UInt16(20)); local.le(UInt16(0x800)); local.le(UInt16(0))
            local.le(UInt16(0)); local.le(UInt16(0)); local.le(UInt32(crc)); local.le(UInt32(contents.count)); local.le(UInt32(contents.count))
            local.le(UInt16(path.count)); local.le(UInt16(0)); local.append(path); local.append(contents)
            central.le(UInt32(0x02014b50)); central.le(UInt16(0x0314)); central.le(UInt16(20)); central.le(UInt16(0x800)); central.le(UInt16(0))
            central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt32(crc)); central.le(UInt32(contents.count)); central.le(UInt32(contents.count))
            central.le(UInt16(path.count)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0))
            central.le(permissions); central.le(offset); central.append(path)
        }
        let start = UInt32(local.count)
        local.append(central)
        local.le(UInt32(0x06054b50)); local.le(UInt16(0)); local.le(UInt16(0)); local.le(UInt16(files.count)); local.le(UInt16(files.count))
        local.le(UInt32(central.count)); local.le(start); local.le(UInt16(0))
        return local
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ integer: T) {
        var value = integer.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}

@MainActor
final class AirDropErrorTests: XCTestCase {
    private var directory: URL!
    private var store: ConfigurationStore!
    private var selectedURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrabAirDropTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        selectedURL = directory.appendingPathComponent("selected.txt")
        try Data("test".utf8).write(to: selectedURL)
        store = ConfigurationStore(directory: directory)
        store.update { $0.operations = [.init(id: "airdrop", parameters: .tool(.init(action: .airDrop)))] }
    }

    override func tearDownWithError() throws {
        store = nil
        try FileManager.default.removeItem(at: directory)
    }

    private var request: ActionRequest {
        .init(operationID: "airdrop", paths: [selectedURL.path], targetDirectory: directory.path)
    }

    func testUnavailableServiceReportsError() {
        var failures: [Error] = []
        let router = ActionRouter(store: store, airDropService: { nil }, reportAirDropError: {
            XCTAssertTrue(Thread.isMainThread)
            failures.append($0)
        })
        router.execute(request)
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures.first?.localizedDescription.isEmpty == false)
    }

    func testUnsupportedSelectionReportsErrorWithoutPerformingService() {
        let service = FakeAirDropService()
        service.allowed = false
        var failures: [Error] = []
        let router = ActionRouter(store: store, airDropService: { service }, reportAirDropError: { failures.append($0) })
        router.execute(request)
        XCTAssertEqual(service.checkedItems as? [URL], [selectedURL!])
        XCTAssertEqual(service.performCount, 0)
        XCTAssertNil(service.delegate)
        XCTAssertEqual(failures.count, 1)
    }

    func testFailureAfterLaunchReportsOnceAndClearsDelegate() throws {
        let service = FakeAirDropService()
        var failures: [Error] = []
        let router = ActionRouter(store: store, airDropService: { service }, reportAirDropError: {
            XCTAssertTrue(Thread.isMainThread)
            failures.append($0)
        })
        router.execute(request)
        XCTAssertEqual(service.performCount, 1)
        XCTAssertEqual(service.performedItems as? [URL], [selectedURL!])
        XCTAssertTrue(failures.isEmpty, "Starting a share must not report an error before its result arrives.")
        let delegate = try XCTUnwrap(service.delegate)
        let failure = NSError(domain: "Crab.AirDrop.Test", code: 42,
                              userInfo: [NSLocalizedDescriptionKey: "Transfer failed"])
        service.fail(failure)
        XCTAssertNil(service.delegate)
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures.first?.localizedDescription.contains("Transfer failed") == true)
        delegate.sharingService?(service, didFailToShareItems: service.performedItems, error: failure)
        XCTAssertEqual(failures.count, 1, "A repeated final callback must not present the same failure twice.")
        withExtendedLifetime(router) {}
    }

    func testSuccessAndUserCancellationRemainSilent() {
        for cancellation in [false, true] {
            let service = FakeAirDropService()
            var failures: [Error] = []
            let router = ActionRouter(store: store, airDropService: { service }, reportAirDropError: { failures.append($0) })
            router.execute(request)
            XCTAssertEqual(service.performCount, 1)
            if cancellation {
                service.fail(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            } else {
                service.succeed()
            }
            XCTAssertTrue(failures.isEmpty)
            XCTAssertNil(service.delegate)
            withExtendedLifetime(router) {}
        }
    }

    func testCancellationCodeFromAnotherDomainStillReportsFailure() {
        let service = FakeAirDropService()
        var failures: [Error] = []
        let router = ActionRouter(store: store, airDropService: { service }, reportAirDropError: { failures.append($0) })
        router.execute(request)
        service.fail(NSError(domain: "Crab.AirDrop.Test", code: NSUserCancelledError))
        XCTAssertEqual(failures.count, 1)
        XCTAssertNil(service.delegate)
        withExtendedLifetime(router) {}
    }

    func testServiceIsRetainedUntilFinalCallbackThenReleased() {
        weak var service: FakeAirDropService?
        let router = ActionRouter(store: store, airDropService: {
            let created = FakeAirDropService()
            service = created
            return created
        }, reportAirDropError: { _ in XCTFail("A successful share must remain silent.") })
        autoreleasepool { router.execute(request) }
        XCTAssertNotNil(service, "The service must outlive the menu action while awaiting its final callback.")
        XCTAssertNotNil(service?.delegate)
        autoreleasepool { service?.succeed() }
        XCTAssertNil(service, "The completed service must no longer be retained by the router.")
        withExtendedLifetime(router) {}
    }

    func testIndependentPendingServicesFinishWithoutClearingEachOther() {
        let first = FakeAirDropService(), second = FakeAirDropService()
        var pending = [first, second]
        var failures: [Error] = []
        let router = ActionRouter(store: store, airDropService: { pending.removeFirst() },
                                  reportAirDropError: { failures.append($0) })
        router.execute(request)
        router.execute(request)
        XCTAssertEqual(first.performCount, 1)
        XCTAssertEqual(second.performCount, 1)
        XCTAssertNotNil(first.delegate)
        XCTAssertNotNil(second.delegate)
        first.fail(NSError(domain: "Crab.AirDrop.Test", code: 42))
        XCTAssertNil(first.delegate)
        XCTAssertNotNil(second.delegate, "Finishing one share must preserve the other pending share.")
        XCTAssertEqual(failures.count, 1)
        second.succeed()
        XCTAssertNil(second.delegate)
        XCTAssertEqual(failures.count, 1)
        withExtendedLifetime(router) {}
    }
}

@MainActor
private final class FakeAirDropService: NSSharingService {
    var allowed = true
    private(set) var checkedItems: [Any] = []
    private(set) var performedItems: [Any] = []
    private(set) var performCount = 0

    init() {
        super.init(title: "Test AirDrop", image: NSImage(size: NSSize(width: 1, height: 1)),
                   alternateImage: nil, handler: {})
    }

    override func canPerform(withItems items: [Any]?) -> Bool {
        checkedItems = items ?? []
        return allowed
    }

    override func perform(withItems items: [Any]) {
        performedItems = items
        performCount += 1
    }

    func succeed() {
        delegate?.sharingService?(self, didShareItems: performedItems)
    }

    func fail(_ error: Error) {
        delegate?.sharingService?(self, didFailToShareItems: performedItems, error: error)
    }
}
