import AppKit
import Darwin

final class CutSessionManager {
    struct PastePlan {
        let urls: [URL]
        let move: Bool
        fileprivate let sessionID: UUID?
        fileprivate let changeCount: Int
    }

    private struct Record: Codable {
        let url: URL
        let bookmark: Data?
        let device: UInt64
        let inode: UInt64
        let fileSystemID0: Int32?
        let fileSystemID1: Int32?
        let birthSeconds: Int64?
        let birthNanoseconds: Int64?
        let originalHidden: Bool
        var restorePending: Bool
    }
    private struct Journal: Codable {
        let version: Int
        let id: UUID
        var records: [Record]
    }
    private struct Session {
        let id: UUID
        let urls: [URL]
        var records: [Record]
        var changeCount: Int
    }
    private static let marker = NSPasteboard.PasteboardType("dev.crab.cut-session")
    private let pasteboard: NSPasteboard
    private let journalURL: URL
    private let notificationCenter: NotificationCenter
    private let lock = NSRecursiveLock()
    private var session: Session?
    private var monitor: DispatchSourceTimer?
    private var terminationObserver: NSObjectProtocol?
    private var stopped = false
    private var reportedError: String?
    var onRecoveryError: ((Error) -> Void)?

    static var defaultJournalURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return directory.appendingPathComponent("Crab", isDirectory: true).appendingPathComponent("CutSession.json")
    }

    init(pasteboard: NSPasteboard = .general,
         journalURL: URL = CutSessionManager.defaultJournalURL,
         pollInterval: TimeInterval = 0.5,
         notificationCenter: NotificationCenter = .default) throws {
        self.pasteboard = pasteboard
        self.journalURL = journalURL
        self.notificationCenter = notificationCenter
        try recoverJournal()
        if pollInterval.isFinite && pollInterval > 0 {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                do { try self.pollPasteboard() }
                catch { self.report(error) }
            }
            monitor = timer
            timer.resume()
        }
        terminationObserver = notificationCenter.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            do { try self.shutdown() }
            catch { self.report(error) }
        }
    }

    deinit {
        monitor?.cancel()
        if let observer = terminationObserver { notificationCenter.removeObserver(observer) }
        try? restoreAndEndSession()
    }

    func cut(_ urls: [URL], hideOriginals: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw Self.failure("剪切会话已经退出。") }
        try restoreAndEndSession()
        guard !urls.isEmpty, urls.count <= 10_000 else { throw Self.failure("请选择 1–10000 个要剪切的文件。") }
        var seenPaths: Set<String> = [], seenFiles: Set<String> = [], records: [Record] = [], selected: [URL] = []
        for input in urls {
            guard input.isFileURL else { throw Self.failure("只能剪切本机文件。") }
            let url = input.standardizedFileURL
            guard url.path != "/" else { throw Self.failure("不能剪切根目录。") }
            guard seenPaths.insert(url.path).inserted else { continue }
            let value = try Self.info(url)
            let type = value.st_mode & mode_t(S_IFMT)
            if hideOriginals && type != mode_t(S_IFREG) && type != mode_t(S_IFDIR) {
                throw Self.failure("启用剪切隐藏时，仅支持普通文件和文件夹；不会隐藏符号链接或特殊文件。")
            }
            selected.append(url)
            let identity = "\(UInt64(UInt32(bitPattern: value.st_dev))):\(value.st_ino)"
            guard seenFiles.insert(identity).inserted else { continue }
            let hidden = value.st_flags & UInt32(UF_HIDDEN) != 0
            let fileSystemID = Self.fileSystemID(url)
            records.append(Record(url: url,
                                  bookmark: try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil),
                                  device: UInt64(UInt32(bitPattern: value.st_dev)), inode: UInt64(value.st_ino),
                                  fileSystemID0: fileSystemID?.0, fileSystemID1: fileSystemID?.1,
                                  birthSeconds: Int64(value.st_birthtimespec.tv_sec), birthNanoseconds: Int64(value.st_birthtimespec.tv_nsec),
                                  originalHidden: hidden, restorePending: hideOriginals && !hidden))
        }
        let id = UUID()
        if records.contains(where: \.restorePending) { try save(Journal(version: 1, id: id, records: records)) }
        session = Session(id: id, urls: selected, records: records, changeCount: -1)
        do {
            for record in records where record.restorePending {
                guard try Self.setHidden(true, record: record) else { throw Self.failure("剪切文件在操作前发生变化，请重新选择。") }
            }
            pasteboard.clearContents()
            guard pasteboard.writeObjects(selected as [NSURL]), pasteboard.setString(id.uuidString, forType: Self.marker) else {
                throw Self.failure("无法将剪切文件写入剪贴板。")
            }
            session?.changeCount = pasteboard.changeCount
            reportedError = nil
        } catch {
            let original = error
            do { try restoreAndEndSession() }
            catch { throw Self.failure("剪切未完成，部分隐藏状态暂未恢复；已保留恢复记录。\n\(error.localizedDescription)") }
            throw original
        }
    }

    func prepareForCopy() throws {
        lock.lock(); defer { lock.unlock() }
        try restoreAndEndSession()
    }

    func prepareForPaste() throws -> PastePlan {
        lock.lock(); defer { lock.unlock() }
        try pollPasteboard()
        if var current = session, ownsPasteboard(current) {
            do { try restore(records: &current.records, id: current.id) }
            catch { session = current; throw error }
            session = current
            return PastePlan(urls: current.urls, move: true, sessionID: current.id, changeCount: current.changeCount)
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return PastePlan(urls: urls, move: false, sessionID: nil, changeCount: pasteboard.changeCount)
    }

    func completePaste(_ plan: PastePlan) throws {
        lock.lock(); defer { lock.unlock() }
        guard plan.move, let current = session, current.id == plan.sessionID,
              current.changeCount == plan.changeCount else { return }
        let stillOwned = ownsPasteboard(current)
        try restoreAndEndSession()
        if stillOwned { pasteboard.clearContents() }
    }

    func pollPasteboard() throws {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, let current = session, !ownsPasteboard(current) else { return }
        try restoreAndEndSession()
    }

    func cancel() throws { try prepareForCopy() }

    func shutdown() throws {
        lock.lock(); defer { lock.unlock() }
        try restoreAndEndSession()
        stopped = true
        monitor?.cancel(); monitor = nil
        if let observer = terminationObserver { notificationCenter.removeObserver(observer); terminationObserver = nil }
    }

    private func ownsPasteboard(_ current: Session) -> Bool {
        current.changeCount == pasteboard.changeCount && pasteboard.string(forType: Self.marker) == current.id.uuidString
    }

    private func restoreAndEndSession() throws {
        guard var current = session else { return }
        do {
            try restore(records: &current.records, id: current.id)
            session = nil
            reportedError = nil
        } catch {
            session = current
            throw error
        }
    }

    private func restore(records: inout [Record], id: UUID) throws {
        var failures: [String] = []
        for index in records.indices where records[index].restorePending {
            do {
                _ = try Self.setHidden(records[index].originalHidden, record: records[index])
                records[index].restorePending = false
            } catch { failures.append("\(records[index].url.lastPathComponent)：\(error.localizedDescription)") }
        }
        if records.contains(where: \.restorePending) {
            try save(Journal(version: 1, id: id, records: records))
            throw Self.failure("无法恢复部分剪切文件的隐藏状态，恢复记录已保留：\n" + failures.joined(separator: "\n"))
        }
        try removeJournal()
    }

    private func recoverJournal() throws {
        var metadata = stat()
        let result = journalURL.withUnsafeFileSystemRepresentation { path in path.map { Darwin.lstat($0, &metadata) } ?? -1 }
        if result != 0 {
            if errno == ENOENT { return }
            throw Self.posixFailure("无法读取剪切恢复记录")
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), metadata.st_size >= 0, metadata.st_size <= 16_777_216 else {
            throw Self.failure("剪切恢复记录不是有效的普通文件。")
        }
        let data = try Data(contentsOf: journalURL)
        var journal = try JSONDecoder().decode(Journal.self, from: data)
        guard journal.version == 1, journal.records.count <= 10_000,
              journal.records.allSatisfy({ $0.url.isFileURL && $0.url.path.hasPrefix("/") && $0.url.path != "/" && $0.inode != 0 }) else {
            throw Self.failure("剪切恢复记录格式无效；未覆盖原记录。")
        }
        try restore(records: &journal.records, id: journal.id)
    }

    private func save(_ journal: Journal) throws {
        let data = try JSONEncoder().encode(journal)
        guard data.count <= 16_777_216 else { throw Self.failure("剪切恢复记录过大，请减少所选文件数量。") }
        let parent = journalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stage = parent.appendingPathComponent(".cut-journal-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        let descriptor = stage.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600)) } ?? -1
        }
        guard descriptor >= 0 else { throw Self.posixFailure("无法创建剪切恢复记录") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        let result = stage.withUnsafeFileSystemRepresentation { from in
            journalURL.withUnsafeFileSystemRepresentation { to in
                guard let from = from, let to = to else { return Int32(-1) }
                return Darwin.rename(from, to)
            }
        }
        guard result == 0 else { throw Self.posixFailure("无法保存剪切恢复记录") }
        Self.syncDirectory(parent)
    }

    private func removeJournal() throws {
        let result = journalURL.withUnsafeFileSystemRepresentation { path in path.map { Darwin.unlink($0) } ?? -1 }
        if result != 0 && errno != ENOENT { throw Self.posixFailure("无法清理剪切恢复记录") }
        Self.syncDirectory(journalURL.deletingLastPathComponent())
    }

    private static func syncDirectory(_ url: URL) {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in path.map { Darwin.open($0, O_RDONLY | O_CLOEXEC) } ?? -1 }
        if descriptor >= 0 { _ = Darwin.fsync(descriptor); Darwin.close(descriptor) }
    }

    private static func originalURL(_ record: Record) throws -> URL? {
        func matches(_ url: URL) throws -> Bool {
            let info: stat
            do { info = try Self.info(url) }
            catch let error as NSError {
                if error.domain == "Crab.CutSession" && (error.code == Int(ENOENT) || error.code == Int(ENOTDIR)) { return false }
                throw error
            }
            return Self.hasIdentity(info, record: record)
        }
        if try matches(record.url) { return record.url }
        if let first = record.fileSystemID0, let second = record.fileSystemID1 {
            var identifier = fsid_t()
            identifier.val = (first, second)
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fsgetpath(&path, path.count, &identifier, record.inode) > 0 {
                let located = path.withUnsafeBufferPointer { URL(fileURLWithFileSystemRepresentation: $0.baseAddress!, isDirectory: false, relativeTo: nil) }
                if try matches(located) { return located }
            }
        }
        if let bookmark = record.bookmark {
            var stale = false
            if let moved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
               moved.isFileURL, try matches(moved) { return moved }
        }
        return nil
    }

    @discardableResult
    private static func setHidden(_ hidden: Bool, record: Record) throws -> Bool {
        guard let url = try originalURL(record) else { return false }
        let value = try info(url)
        if (value.st_flags & UInt32(UF_HIDDEN) != 0) == hidden { return true }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else { throw posixFailure("无法修改隐藏属性") }
        defer { Darwin.close(descriptor) }
        var actual = stat()
        guard Darwin.fstat(descriptor, &actual) == 0 else { throw posixFailure("无法读取隐藏属性") }
        guard hasIdentity(actual, record: record) else { throw failure("文件在恢复时发生变化，已保留恢复记录。") }
        let flags = hidden ? actual.st_flags | UInt32(UF_HIDDEN) : actual.st_flags & ~UInt32(UF_HIDDEN)
        guard Darwin.fchflags(descriptor, flags) == 0 else { throw posixFailure("无法修改隐藏属性") }
        _ = Darwin.fsync(descriptor)
        return true
    }

    private static func hasIdentity(_ value: stat, record: Record) -> Bool {
        guard UInt64(UInt32(bitPattern: value.st_dev)) == record.device, UInt64(value.st_ino) == record.inode else { return false }
        if let seconds = record.birthSeconds, let nanoseconds = record.birthNanoseconds {
            return Int64(value.st_birthtimespec.tv_sec) == seconds && Int64(value.st_birthtimespec.tv_nsec) == nanoseconds
        }
        return true
    }

    private static func fileSystemID(_ url: URL) -> (Int32, Int32)? {
        var value = statfs()
        let result = url.withUnsafeFileSystemRepresentation { path in path.map { statfs($0, &value) } ?? -1 }
        return result == 0 ? value.f_fsid.val : nil
    }

    private static func info(_ url: URL) throws -> stat {
        var value = stat()
        let status = url.withUnsafeFileSystemRepresentation { path in path.map { Darwin.lstat($0, &value) } ?? -1 }
        guard status == 0 else { throw posixFailure("文件不存在或无法访问：\(url.lastPathComponent)") }
        return value
    }

    private func report(_ error: Error) {
        lock.lock()
        let description = error.localizedDescription
        let notify = reportedError != description
        reportedError = description
        let callback = onRecoveryError
        lock.unlock()
        if notify { callback?(error) }
    }
    private static func failure(_ text: String) -> NSError {
        NSError(domain: "Crab.CutSession", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private static func posixFailure(_ text: String) -> NSError {
        let code = errno
        return NSError(domain: "Crab.CutSession", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "\(text)：\(String(cString: strerror(code)))"])
    }
}
