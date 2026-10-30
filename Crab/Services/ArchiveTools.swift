import Foundation
import Darwin
import zlib
import CArchive

enum ArchiveTools {
    private struct Entry {
        let name: String
        let isDirectory: Bool
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let dataOffset: Int
    }
    private static let maximumArchiveSize: UInt64 = 2_147_483_648
    private static let maximumFileSize = 1_073_741_824
    private static let maximumExpandedSize: UInt64 = 2_147_483_648
    private static func failure(_ message: String) -> Error {
        NSError(domain: "Crab.Archive", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func compress(_ urls: [URL], in directory: URL) throws -> URL {
        guard !urls.isEmpty, urls.count <= 10_000 else { throw failure("请选择 1–10000 个要压缩的文件。") }
        let fm = FileManager.default
        let outputPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        for url in urls where try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            let sourcePath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard outputPath != sourcePath, !outputPath.hasPrefix(sourcePath + "/") else {
                throw failure("压缩输出目录不能位于所选文件夹内部。")
            }
        }
        let workspace = directory.appendingPathComponent(".crab-zip-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workspace) }
        let payload = workspace.appendingPathComponent("Payload", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: false)
        for url in urls {
            guard url.standardizedFileURL.path != "/" else { throw failure("不支持压缩整个根目录。") }
            try rejectLinksAndSpecialFiles(url)
            let target = try FileOperations().uniqueURL(in: payload, preferredName: url.lastPathComponent)
            try fm.copyItem(at: url, to: target)
        }
        try rejectLinksAndSpecialFiles(payload)
        let archive = workspace.appendingPathComponent("Archive.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", payload.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure("系统 ZIP 压缩失败，请检查磁盘空间和读取权限。") }
        _ = try validatedEntries(in: try archiveData(archive))
        let target = try FileOperations().uniqueURL(in: directory,
            preferredName: ArchiveOutputNaming.compressionFilename(for: urls, suffix: "zip"))
        try fm.moveItem(at: archive, to: target)
        return target
    }

    static func extract(_ url: URL, in directory: URL) throws -> URL {
        let fm = FileManager.default
        let workspace = directory.appendingPathComponent(".crab-unzip-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workspace) }
        let snapshot = workspace.appendingPathComponent("Source.zip")
        try fm.copyItem(at: url, to: snapshot)
        let data = try archiveData(snapshot)
        let entries = try validatedEntries(in: data)
        let payload = workspace.appendingPathComponent("Payload", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for entry in entries {
            let target = payload.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
            if entry.isDirectory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try extractFile(entry, archive: data, to: target)
            }
        }
        let target = try FileOperations().uniqueURL(in: directory,
            preferredName: ArchiveOutputNaming.extractionDirectoryName(for: url))
        try fm.moveItem(at: payload, to: target)
        return target
    }

    private static func rejectLinksAndSpecialFiles(_ url: URL) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
        func check(_ item: URL) throws {
            let values = try item.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else {
                throw failure("为确保安全，暂不压缩符号链接或特殊文件：\(item.lastPathComponent)")
            }
        }
        try check(url)
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { return }
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, error in
            traversalError = error
            return false
        }) else { throw failure("无法读取所选文件夹。") }
        for case let item as URL in enumerator { try check(item) }
        if let error = traversalError { throw error }
    }

    private static func archiveData(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0, UInt64(size) <= maximumArchiveSize else {
            throw failure("请选择不超过 2 GB 的普通压缩文件。")
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func validatedEntries(in data: Data) throws -> [Entry] {
        func word(_ offset: Int) throws -> UInt16 {
            guard offset >= 0, offset <= data.count - 2 else { throw failure("ZIP 文件已损坏。") }
            return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }
        func dword(_ offset: Int) throws -> UInt32 {
            UInt32(try word(offset)) | UInt32(try word(offset + 2)) << 16
        }
        guard data.count >= 22 else { throw failure("这不是有效的 ZIP 文件。") }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try dword(offset) == 0x06054b50,
               offset + 22 + Int(try word(offset + 20)) == data.count { end = offset; break }
        }
        guard let eocd = end else { throw failure("找不到 ZIP 中央目录。") }
        let count = Int(try word(eocd + 10))
        let centralSize = Int(try dword(eocd + 12)), centralStart = Int(try dword(eocd + 16))
        guard count != 0xffff, centralSize != 0xffffffff, centralStart != 0xffffffff else { throw failure("暂不支持 ZIP64 压缩包。") }
        guard try word(eocd + 4) == 0, try word(eocd + 6) == 0, Int(try word(eocd + 8)) == count else { throw failure("暂不支持分卷 ZIP 压缩包。") }
        guard count <= 10_000, centralStart <= eocd, centralSize == eocd - centralStart else { throw failure("ZIP 目录异常或文件数量超过 10000。") }
        var cursor = centralStart, entries: [Entry] = [], total: UInt64 = 0
        var names: [String: Bool] = [:], ranges: [Range<Int>] = []
        for _ in 0..<count {
            guard cursor <= eocd - 46, try dword(cursor) == 0x02014b50 else { throw failure("ZIP 中央目录已损坏。") }
            let flags = try word(cursor + 8), method = try word(cursor + 10)
            guard flags & 0x2041 == 0 else { throw failure("暂不支持加密 ZIP，请先在其他工具中解密。") }
            guard flags & ~UInt16(0x080e) == 0, method == 0 || method == 8 else { throw failure("该 ZIP 使用了暂不支持的压缩方式。") }
            let crc = try dword(cursor + 16), compressed = Int(try dword(cursor + 20)), expanded = Int(try dword(cursor + 24))
            let nameLength = Int(try word(cursor + 28)), extraLength = Int(try word(cursor + 30)), commentLength = Int(try word(cursor + 32))
            let local = Int(try dword(cursor + 42)), external = try dword(cursor + 38)
            guard compressed != 0xffffffff, expanded != 0xffffffff, local != 0xffffffff else { throw failure("暂不支持 ZIP64 压缩包。") }
            guard try word(cursor + 34) == 0, nameLength > 0,
                  cursor + 46 + nameLength + extraLength + commentLength <= eocd else { throw failure("ZIP 条目已损坏。") }
            let rawName = data.subdata(in: cursor + 46..<cursor + 46 + nameLength)
            guard let name = String(data: rawName, encoding: .utf8) else { throw failure("ZIP 文件名不是 UTF-8 编码，暂不能安全解压。") }
            let directory = name.hasSuffix("/")
            let cleanName = directory ? String(name.dropLast()) : name
            let parts = cleanName.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"),
                  !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  !(parts.first.map { $0.count >= 2 && $0[$0.index(after: $0.startIndex)] == ":" } ?? false) else {
                throw failure("已拒绝包含绝对路径或路径穿越的 ZIP 条目。")
            }
            let mode = (external >> 16) & 0xf000
            guard mode == 0 || mode == 0x8000 || mode == 0x4000,
                  mode != 0x4000 || directory, mode != 0x8000 || !directory else { throw failure("已拒绝 ZIP 中的符号链接或特殊文件。") }
            guard expanded <= maximumFileSize else { throw failure("ZIP 中的单个文件超过 1 GB 限制。") }
            total += UInt64(expanded)
            guard total <= maximumExpandedSize else { throw failure("ZIP 解压后总大小超过 2 GB 限制。") }
            if directory && (expanded != 0 || compressed != 0) { throw failure("ZIP 文件夹条目异常。") }
            let key = cleanName.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard names[key] == nil else { throw failure("ZIP 包含重复或大小写冲突的文件名。") }
            names[key] = directory
            guard local >= 0, local <= centralStart - 30, try dword(local) == 0x04034b50,
                  try word(local + 6) == flags, try word(local + 8) == method else { throw failure("ZIP 本地文件头与目录不一致。") }
            let localNameLength = Int(try word(local + 26)), localExtraLength = Int(try word(local + 28))
            let start = local + 30 + localNameLength + localExtraLength
            guard localNameLength == nameLength, start <= centralStart, compressed <= centralStart - start,
                  data.subdata(in: local + 30..<local + 30 + localNameLength) == rawName else { throw failure("ZIP 本地路径或数据范围异常。") }
            if flags & 8 == 0 {
                guard try dword(local + 14) == crc, Int(try dword(local + 18)) == compressed,
                      Int(try dword(local + 22)) == expanded else { throw failure("ZIP 文件大小或校验信息不一致。") }
            }
            ranges.append(local..<start + compressed)
            entries.append(Entry(name: cleanName, isDirectory: directory, method: method, crc: crc, compressedSize: compressed, size: expanded, dataOffset: start))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        guard cursor == eocd else { throw failure("ZIP 目录长度不一致。") }
        let sortedRanges = ranges.sorted { $0.lowerBound < $1.lowerBound }
        for index in sortedRanges.indices.dropFirst() {
            guard sortedRanges[index - 1].upperBound <= sortedRanges[index].lowerBound else { throw failure("ZIP 条目数据相互重叠。") }
        }
        for (name, _) in names {
            var ancestor = (name as NSString).deletingLastPathComponent
            while !ancestor.isEmpty {
                guard names[ancestor] != false else { throw failure("ZIP 文件与文件夹路径冲突。") }
                ancestor = (ancestor as NSString).deletingLastPathComponent
            }
        }
        return entries
    }

    private static func extractFile(_ entry: Entry, archive: Data, to target: URL) throws {
        let descriptor = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw failure("无法创建解压文件，或目标已存在。") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var checksum = crc32(0, nil, 0), written = 0
        func write(_ buffer: UnsafeRawBufferPointer) throws {
            guard buffer.count <= entry.size - written else { throw failure("ZIP 展开大小超过声明值，已停止解压。") }
            checksum = crc32(checksum, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count))
            try handle.write(contentsOf: Data(buffer))
            written += buffer.count
        }
        try archive.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else { throw failure("ZIP 数据为空。") }
            let input = base.advanced(by: entry.dataOffset)
            if entry.method == 0 {
                var offset = 0
                while offset < entry.compressedSize {
                    let size = min(65_536, entry.compressedSize - offset)
                    try write(UnsafeRawBufferPointer(start: input.advanced(by: offset), count: size))
                    offset += size
                }
            } else {
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw failure("无法初始化 ZIP 解压器。") }
                defer { inflateEnd(&stream) }
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(entry.compressedSize)
                var buffer = [UInt8](repeating: 0, count: 65_536)
                try buffer.withUnsafeMutableBytes { output in
                    while true {
                        stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(output.count)
                        let status = inflate(&stream, Z_NO_FLUSH)
                        let produced = output.count - Int(stream.avail_out)
                        if produced > 0 { try write(UnsafeRawBufferPointer(start: output.baseAddress, count: produced)) }
                        if status == Z_STREAM_END {
                            guard stream.avail_in == 0 else { throw failure("ZIP 压缩数据包含多余字节。") }
                            break
                        }
                        guard status == Z_OK, produced > 0 || stream.avail_in > 0 else { throw failure("ZIP 压缩数据已损坏。") }
                    }
                }
            }
        }
        guard written == entry.size, UInt32(checksum & 0xffffffff) == entry.crc else { throw failure("ZIP 文件长度或 CRC 校验失败。") }
    }
}

extension ArchiveTools {
    static func compress7z(_ urls: [URL], in directory: URL) throws -> URL {
        guard !urls.isEmpty, urls.count <= 10_000 else { throw failure("请选择 1–10000 个要压缩的文件。") }
        let fm = FileManager.default
        let outputPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        for url in urls {
            guard url.standardizedFileURL.path != "/" else { throw failure("不支持压缩整个根目录。") }
            try rejectLinksAndSpecialFiles(url)
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                let sourcePath = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard outputPath != sourcePath, !outputPath.hasPrefix(sourcePath + "/") else {
                    throw failure("压缩输出目录不能位于所选文件夹内部。")
                }
            }
        }
        let workspace = directory.appendingPathComponent(".crab-7z-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workspace) }
        let payload = workspace.appendingPathComponent("Payload", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for url in urls {
            let target = try FileOperations().uniqueURL(in: payload, preferredName: url.lastPathComponent)
            try fm.copyItem(at: url, to: target)
        }
        try rejectLinksAndSpecialFiles(payload)
        var count = 0, total: UInt64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        var traversalError: Error?
        guard let enumerator = fm.enumerator(at: payload, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, error in
            traversalError = error
            return false
        }) else { throw failure("无法读取待压缩文件。") }
        for case let item as URL in enumerator {
            count += 1
            guard count <= 10_000 else { throw failure("压缩文件数量超过 10000。") }
            let values = try item.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                guard let size = values.fileSize, size >= 0, size <= maximumFileSize else { throw failure("单个文件超过 1 GB 限制。") }
                total += UInt64(size)
                guard total <= maximumExpandedSize else { throw failure("待压缩文件总大小超过 2 GB 限制。") }
            }
        }
        if let error = traversalError { throw error }
        let archive = workspace.appendingPathComponent("Archive.7z")
        let names = try fm.contentsOfDirectory(atPath: payload.path).sorted()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["--format=7zip", "-cf", archive.path, "-C", payload.path, "--"] + names
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure("系统 7z 压缩失败，请检查磁盘空间和读取权限。") }
        let data = try archiveData(archive)
        guard data.starts(with: [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) else { throw failure("系统未生成有效的 7z 压缩包。") }
        let target = try FileOperations().uniqueURL(in: directory,
            preferredName: ArchiveOutputNaming.compressionFilename(for: urls, suffix: "7z"))
        try fm.moveItem(at: archive, to: target)
        return target
    }

    static func extractArchive(_ url: URL, in directory: URL) throws -> URL {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0, UInt64(size) <= maximumArchiveSize else {
            throw failure("请选择不超过 2 GB 的普通 ZIP 或 7z 文件。")
        }
        let fm = FileManager.default
        let workspace = directory.appendingPathComponent(".crab-extract-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workspace) }
        let snapshot = workspace.appendingPathComponent("Source.archive")
        try fm.copyItem(at: url, to: snapshot)
        let copied = try snapshot.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard copied.isRegularFile == true, copied.isSymbolicLink != true,
              let copiedSize = copied.fileSize, copiedSize >= 0, UInt64(copiedSize) <= maximumArchiveSize else {
            throw failure("压缩文件在读取时发生变化，或已超过 2 GB。")
        }
        let handle = try FileHandle(forReadingFrom: snapshot)
        let signature = try handle.read(upToCount: 6) ?? Data()
        try handle.close()
        if signature.starts(with: [0x50, 0x4b]) {
            let extracted = try extract(snapshot, in: workspace)
            let target = try FileOperations().uniqueURL(in: directory,
                preferredName: ArchiveOutputNaming.extractionDirectoryName(for: url))
            try fm.moveItem(at: extracted, to: target)
            return target
        }
        guard signature == Data([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) else {
            throw failure("目前支持解压 ZIP 与 7z；该文件格式不受支持或文件已损坏。")
        }
        let payload = workspace.appendingPathComponent("Payload", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try extractSevenZip(snapshot, to: payload)
        let target = try FileOperations().uniqueURL(in: directory,
            preferredName: ArchiveOutputNaming.extractionDirectoryName(for: url))
        try fm.moveItem(at: payload, to: target)
        return target
    }

    private static func extractSevenZip(_ snapshot: URL, to payload: URL) throws {
        guard let reader = archive_read_new() else { throw failure("无法初始化 7z 解压器。") }
        defer { archive_read_free(reader) }
        func check(_ status: Int32) throws {
            guard status == ARCHIVE_OK else {
                let detail = archive_error_string(reader).map { String(cString: $0) } ?? "未知错误"
                if detail.lowercased().contains("encrypt") || detail.lowercased().contains("passphrase") {
                    throw failure("暂不支持加密 7z，请先解密后重试。")
                }
                throw failure("7z 解压失败或校验失败：\(detail)")
            }
        }
        try check(archive_read_support_format_7zip(reader))
        try check(archive_read_support_filter_none(reader))
        try check(archive_read_open_filename(reader, snapshot.path, 65_536))
        var entry: OpaquePointer?, names: Set<String> = [], count = 0, total: UInt64 = 0
        while true {
            let status = archive_read_next_header(reader, &entry)
            if status == ARCHIVE_EOF { break }
            try check(status)
            guard let entry = entry, let path = archive_entry_pathname_utf8(entry) else { throw failure("7z 文件名不是有效 UTF-8。") }
            count += 1
            guard count <= 10_000 else { throw failure("压缩包文件数量超过 10000。") }
            guard archive_entry_is_encrypted(entry) == 0 else { throw failure("暂不支持加密 7z，请先解密后重试。") }
            let type = archive_entry_filetype(entry)
            let isDirectory = type == mode_t(S_IFDIR)
            guard isDirectory || type == mode_t(S_IFREG),
                  archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil,
                  archive_entry_sparse_count(entry) == 0 else { throw failure("已拒绝压缩包中的符号链接、硬链接或特殊文件。") }
            let rawName = String(cString: path)
            let name = isDirectory && rawName.hasSuffix("/") ? String(rawName.dropLast()) : rawName
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"),
                  !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  !(parts.first.map { $0.count >= 2 && $0[$0.index(after: $0.startIndex)] == ":" } ?? false) else {
                throw failure("已拒绝包含绝对路径或路径穿越的压缩包条目。")
            }
            let key = name.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard names.insert(key).inserted else { throw failure("压缩包包含重复或大小写冲突的文件名。") }
            let declared = archive_entry_size(entry)
            guard archive_entry_size_is_set(entry) != 0, declared >= 0, declared <= maximumFileSize,
                  !isDirectory || declared == 0 else { throw failure("压缩包文件大小异常，或单个文件超过 1 GB。") }
            total += UInt64(declared)
            guard total <= maximumExpandedSize else { throw failure("解压后总大小超过 2 GB 限制。") }
            let target = payload.appendingPathComponent(name, isDirectory: isDirectory)
            if isDirectory {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var byte: UInt8 = 0
                guard archive_read_data(reader, &byte, 1) == 0 else { throw failure("7z 文件夹条目包含异常数据。") }
            } else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let fd = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
                guard fd >= 0 else { throw failure("无法创建解压文件，或目标已经存在。") }
                let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? output.close() }
                var buffer = [UInt8](repeating: 0, count: 65_536), written: Int64 = 0
                while true {
                    let amount = buffer.withUnsafeMutableBytes { archive_read_data(reader, $0.baseAddress, $0.count) }
                    guard amount >= 0 else { try check(ARCHIVE_FATAL); return }
                    if amount == 0 { break }
                    guard Int64(amount) <= declared - written else { throw failure("7z 展开大小超过声明值，已停止解压。") }
                    try output.write(contentsOf: Data(buffer.prefix(amount)))
                    written += Int64(amount)
                }
                guard written == declared else { throw failure("7z 文件长度校验失败。") }
            }
        }
        try check(archive_read_close(reader))
    }
}
