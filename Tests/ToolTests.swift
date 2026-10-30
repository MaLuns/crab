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
        let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let image = context.makeImage()!
        let input = root.appendingPathComponent("sample.png")
        let destination = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
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
        let ios = try XCTUnwrap(MediaTools.convert([input], format: .iosIconset).first)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: ios.appendingPathComponent("Contents.json"))) as! [String: Any]
        XCTAssertEqual((manifest["images"] as? [[String: String]])?.count, 18)
        let marketingSource = try XCTUnwrap(CGImageSourceCreateWithURL(ios.appendingPathComponent("Icon-1024@1x.png") as CFURL, nil))
        let marketingImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(marketingSource, 0, nil))
        XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(marketingImage.alphaInfo))
        let icns = try XCTUnwrap(MediaTools.convert([input], format: .icns).first)
        XCTAssertEqual(try Data(contentsOf: icns).prefix(4), Data("icns".utf8))
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
