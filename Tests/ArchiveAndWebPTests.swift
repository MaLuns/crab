import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CArchive
import CWebP
import Darwin
import zlib
@testable import Crab

final class ArchiveAndWebPTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CrabArchiveWebP-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testSevenZipHasRealSignatureAndRoundtripsFilesDirectoriesAndUnicode() throws {
        let folder = root.appendingPathComponent("资料")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("__MACOSX"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("空文件夹"), withIntermediateDirectories: false)
        let data = Data((0..<190_000).map { UInt8($0 % 251) })
        try data.write(to: folder.appendingPathComponent("你好.bin"))
        try Data("metadata is ordinary data".utf8).write(to: folder.appendingPathComponent("__MACOSX/keep.txt"))
        let archive = try ArchiveTools.compress7z([folder], in: root)
        XCTAssertEqual(try Data(contentsOf: archive).prefix(6), Data([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]))
        let output = try ArchiveTools.extractArchive(archive, in: root)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("资料/你好.bin")), data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("资料/空文件夹").path))
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("资料/__MACOSX/keep.txt")), "metadata is ordinary data")
        XCTAssertNotEqual(try ArchiveTools.compress7z([folder], in: root), archive)
        XCTAssertNotEqual(try ArchiveTools.extractArchive(archive, in: root), output)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("你好.bin")), data)
        try assertNoStaging()
    }

    func testSevenZipRejectsTraversalLinksDuplicatesAndDamagedPayloadWithRollback() throws {
        for path in ["../escaped", "/absolute", "a/../escaped", "C:/escape", "a\\escape"] {
            let archive = try makeSevenZip([(path, Data("unsafe".utf8), false)])
            XCTAssertThrowsError(try ArchiveTools.extractArchive(archive, in: root), path)
        }
        let link = try makeSevenZip([("link", Data(), true)])
        XCTAssertThrowsError(try ArchiveTools.extractArchive(link, in: root))
        let fifo = try makeSevenZip([("fifo", Data(), false)], specialType: UInt32(S_IFIFO))
        XCTAssertThrowsError(try ArchiveTools.extractArchive(fifo, in: root)) { error in
            XCTAssertTrue(error.localizedDescription.contains("特殊文件"))
        }
        let duplicate = try makeSevenZip([("File", Data("first".utf8), false), ("file", Data("second".utf8), false)])
        XCTAssertThrowsError(try ArchiveTools.extractArchive(duplicate, in: root))
        let input = root.appendingPathComponent("payload.bin")
        try Data((0..<20_000).map { UInt8($0 % 251) }).write(to: input)
        let archive = try ArchiveTools.compress7z([input], in: root)
        var damaged = try Data(contentsOf: archive)
        XCTAssertGreaterThan(damaged.count, 64)
        damaged[32] ^= 0x5a
        let corrupt = root.appendingPathComponent("damaged.7z")
        try damaged.write(to: corrupt)
        XCTAssertThrowsError(try ArchiveTools.extractArchive(corrupt, in: root))
        try damaged.prefix(40).write(to: corrupt)
        XCTAssertThrowsError(try ArchiveTools.extractArchive(corrupt, in: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped").path))
        try assertNoStaging()
    }

    func testSevenZipRejectsRecursiveOutputAndSourceLinksAndZIPStillWorks() throws {
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ArchiveTools.compress7z([folder], in: folder))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        XCTAssertThrowsError(try ArchiveTools.compress7z([link], in: root))
        let input = root.appendingPathComponent("small.txt")
        try Data("zip contract".utf8).write(to: input)
        let zip = try ArchiveTools.compress([input], in: root)
        let output = try ArchiveTools.extractArchive(zip, in: root)
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("small.txt")), "zip contract")
        try assertNoStaging()
    }

    func testSevenZipRejectsDeclaredAndInputSizeLimitsWithoutExpanding() throws {
        let huge = root.appendingPathComponent("declared-huge.7z")
        try oversizedSevenZipHeader().write(to: huge)
        XCTAssertThrowsError(try ArchiveTools.extractArchive(huge, in: root)) { error in
            XCTAssertTrue(error.localizedDescription.contains("1 GB"))
        }
        let sparse = root.appendingPathComponent("too-large.7z")
        XCTAssertTrue(FileManager.default.createFile(atPath: sparse.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 2_147_483_649)
        try handle.close()
        XCTAssertThrowsError(try ArchiveTools.extractArchive(sparse, in: root)) { error in
            XCTAssertTrue(error.localizedDescription.contains("2 GB"))
        }
        try assertNoStaging()
    }

    func testWebPActuallyDecodesAndPreservesSizeTransparencyAndColors() throws {
        XCTAssertEqual(WebPGetEncoderVersion(), 0x010600)
        let input = root.appendingPathComponent("alpha.png")
        let rgba: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 0, 0, 0, 0, 128, 128]
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let writer = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let output = try XCTUnwrap(MediaTools.convert([input], format: .webp).first)
        let bytes = try Data(contentsOf: output)
        XCTAssertEqual(bytes.prefix(4), Data("RIFF".utf8))
        XCTAssertEqual(bytes[8..<12], Data("WEBP".utf8))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 2); XCTAssertEqual(decoded.height, 2)
        var width: Int32 = 0, height: Int32 = 0
        let pixels = bytes.withUnsafeBytes { WebPDecodeRGBA($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &width, &height) }
        let pixelPointer = try XCTUnwrap(pixels)
        defer { WebPFree(pixelPointer) }
        let actual = Array(UnsafeBufferPointer(start: pixelPointer, count: Int(width * height * 4)))
        XCTAssertEqual(actual, [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 0, 0, 0, 0, 255, 128])
        XCTAssertNotEqual(try MediaTools.convert([input], format: .webp).first, output)
        XCTAssertEqual(try Data(contentsOf: input).prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
        try assertNoStaging()
    }

    func testWebPBatchFailureRollsBackEarlierOutput() throws {
        let valid = root.appendingPathComponent("valid.png")
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: valid)
        let bad = root.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        XCTAssertThrowsError(try MediaTools.convert([valid, bad], format: .webp))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("valid.webp").path))
        try assertNoStaging()
    }

    private func assertNoStaging(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".crab-") }, file: file, line: line)
    }

    private func makeSevenZip(_ entries: [(String, Data, Bool)], specialType: UInt32? = nil) throws -> URL {
        let output = root.appendingPathComponent(UUID().uuidString + ".7z")
        let writer = try XCTUnwrap(archive_write_new())
        defer { archive_write_free(writer) }
        XCTAssertEqual(archive_write_set_format_7zip(writer), ARCHIVE_OK)
        XCTAssertEqual(archive_write_open_filename(writer, output.path), ARCHIVE_OK)
        for (name, bytes, link) in entries {
            let entry = try XCTUnwrap(archive_entry_new())
            defer { archive_entry_free(entry) }
            archive_entry_set_pathname_utf8(entry, name)
            archive_entry_set_perm(entry, 0o600)
            archive_entry_set_filetype(entry, specialType ?? UInt32(link ? S_IFLNK : S_IFREG))
            archive_entry_set_size(entry, link ? 0 : Int64(bytes.count))
            if link { archive_entry_set_symlink_utf8(entry, "../../escape") }
            XCTAssertEqual(archive_write_header(writer, entry), ARCHIVE_OK)
            if !link && !bytes.isEmpty {
                let written = bytes.withUnsafeBytes { archive_write_data(writer, $0.baseAddress, $0.count) }
                XCTAssertEqual(written, bytes.count)
            }
        }
        XCTAssertEqual(archive_write_close(writer), ARCHIVE_OK)
        return output
    }
    private func oversizedSevenZipHeader() -> Data {
        func little(_ value: UInt64, bytes: Int = 8) -> Data {
            Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
        }
        func number(_ value: UInt64) -> Data { Data([0xff]) + little(value) }
        func checksum(_ data: Data) -> UInt64 {
            UInt64(data.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) })
        }
        let filename = Data("huge\0".utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] })
        var header = Data([1, 4, 6])
        header += number(0) + number(1) + Data([9]) + number(0) + Data([0])
        header += Data([7, 11]) + number(1) + Data([0]) + number(1) + Data([1, 0])
        header += Data([12]) + number(1_073_741_825) + Data([0, 8, 0, 0])
        header += Data([5]) + number(1) + Data([17]) + number(UInt64(1 + filename.count)) + Data([0]) + filename + Data([0, 0])
        let start = little(0) + little(UInt64(header.count)) + little(checksum(header), bytes: 4)
        return Data([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0, 4]) + little(checksum(start), bytes: 4) + start + header
    }
}
