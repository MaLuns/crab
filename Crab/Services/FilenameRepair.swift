import Foundation
import CoreFoundation
import Darwin

struct FilenameRepairCandidate: Hashable {
    let name: String
    let explanation: String
}

struct FilenameRepair {
    private let move: (URL, URL) throws -> Void

    init() { move = Self.exclusiveMove }

    init(move: @escaping (URL, URL) throws -> Void) { self.move = move }

    func candidates(for name: String) -> [FilenameRepairCandidate] {
        guard name.unicodeScalars.contains(where: { $0.value > 127 }), !name.contains("\u{FFFD}") else { return [] }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let western: [(String.Encoding, String)] = [(.isoLatin1, "ISO-8859-1"), (.windowsCP1252, "Windows-1252"), (.macOSRoman, "Mac Roman")]
        var pairs: [(String.Encoding, String, String.Encoding, String)] = []
        for (encoding, label) in western {
            pairs.append((encoding, label, .utf8, "UTF-8"))
            pairs.append((encoding, label, gb, "GB18030"))
            pairs.append((encoding, label, big5, "Big5"))
        }
        pairs += [(gb, "GB18030", .utf8, "UTF-8"), (big5, "Big5", .utf8, "UTF-8"),
                  (.utf8, "UTF-8", gb, "GB18030"), (.utf8, "UTF-8", big5, "Big5")]
        var seen = Set<String>()
        var result: [FilenameRepairCandidate] = []
        for (wrong, wrongName, intended, intendedName) in pairs {
            guard let bytes = name.data(using: wrong, allowLossyConversion: false),
                  let inputRoundtrip = String(data: bytes, encoding: wrong),
                  inputRoundtrip.utf8.elementsEqual(name.utf8),
                  let candidate = String(data: bytes, encoding: intended),
                  candidate.data(using: intended, allowLossyConversion: false) == bytes,
                  candidate != name, !candidate.contains("\u{FFFD}"), Self.isSafeName(candidate),
                  seen.insert(candidate).inserted else { continue }
            result.append(FilenameRepairCandidate(name: candidate, explanation: LF("%@ 字节 → %@（可逆）", wrongName, intendedName)))
        }
        return result
    }

    func apply(mapping: [URL: String]) throws -> [URL] {
        let plans = try makePlans(mapping)
        let changed = plans.indices.filter { plans[$0].source.lastPathComponent != plans[$0].destination.lastPathComponent }
        var staged = Set<Int>()
        var committed = Set<Int>()
        do {
            for index in changed {
                try Self.checkIdentity(at: plans[index].source, expected: plans[index].identity)
                try move(plans[index].source, plans[index].stage)
                staged.insert(index)
            }
            for index in changed {
                try Self.checkIdentity(at: plans[index].stage, expected: plans[index].identity)
                try move(plans[index].stage, plans[index].destination)
                staged.remove(index); committed.insert(index)
            }
            return plans.map(\.destination)
        } catch {
            let originalError = error.localizedDescription
            var recovery: [URL] = []
            for index in changed.reversed() where committed.contains(index) {
                do {
                    try Self.checkIdentity(at: plans[index].destination, expected: plans[index].identity)
                    try move(plans[index].destination, plans[index].stage)
                    committed.remove(index); staged.insert(index)
                } catch { recovery.append(plans[index].destination) }
            }
            for index in changed.reversed() where staged.contains(index) {
                do {
                    try Self.checkIdentity(at: plans[index].stage, expected: plans[index].identity)
                    try move(plans[index].stage, plans[index].source)
                    staged.remove(index)
                } catch { recovery.append(plans[index].stage) }
            }
            throw RepairError.operationFailed(originalError, recovery)
        }
    }

    enum RepairError: LocalizedError {
        case invalidName(String)
        case invalidSource(URL)
        case conflict(String)
        case nestedSelection
        case changed(URL)
        case operationFailed(String, [URL])
        var errorDescription: String? {
            switch self {
            case let .invalidName(name): return "“\(name)”不是有效文件名：不能包含路径分隔符、控制字符或超过255字节。"
            case let .invalidSource(url): return "无法读取“\(url.path)”，文件可能已被移动或删除。"
            case let .conflict(name): return "目标名称“\(name)”已存在或在本次改名中重复，未修改任何文件。"
            case .nestedSelection: return "所选项目包含互相嵌套的文件夹，请分开处理文件夹和其中的文件。"
            case let .changed(url): return "“\(url.path)”在操作期间发生变化，已停止改名。"
            case let .operationFailed(reason, recovery):
                if recovery.isEmpty { return "改名失败，已恢复原名：\(reason)" }
                return "改名失败，部分原名无法恢复；文件仍保留在以下位置，请勿删除：\n" + recovery.map(\.path).joined(separator: "\n") + "\n原因：" + reason
            }
        }
    }

    private struct Identity: Equatable { let device: dev_t; let inode: ino_t }
    private struct Plan { let source: URL; let destination: URL; let stage: URL; let identity: Identity }

    private func makePlans(_ mapping: [URL: String]) throws -> [Plan] {
        var sources = Set<String>()
        var targets = Set<String>()
        var plans: [Plan] = []
        for (input, name) in mapping.sorted(by: { $0.key.path < $1.key.path }) {
            guard Self.isSafeName(name) else { throw RepairError.invalidName(name) }
            guard input.isFileURL, input.path != "/" else { throw RepairError.invalidSource(input) }
            let source = input.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(input.lastPathComponent).standardizedFileURL
            guard let identity = Self.identity(at: source) else { throw RepairError.invalidSource(source) }
            let destination = source.deletingLastPathComponent().appendingPathComponent(name)
            guard sources.insert(Self.comparisonKey(source)).inserted else { throw RepairError.conflict(source.lastPathComponent) }
            guard targets.insert(Self.comparisonKey(destination)).inserted else { throw RepairError.conflict(name) }
            let stage = source.deletingLastPathComponent().appendingPathComponent(".crab-rename-" + UUID().uuidString)
            plans.append(Plan(source: source, destination: destination, stage: stage, identity: identity))
        }
        for (index, plan) in plans.enumerated() {
            for other in plans.dropFirst(index + 1) {
                if plan.source.path.hasPrefix(other.source.path + "/") || other.source.path.hasPrefix(plan.source.path + "/") {
                    throw RepairError.nestedSelection
                }
            }
            if let existing = Self.identity(at: plan.destination) {
                guard let occupied = plans.first(where: { Self.comparisonKey($0.source) == Self.comparisonKey(plan.destination) }),
                      occupied.identity == existing else { throw RepairError.conflict(plan.destination.lastPathComponent) }
            }
        }
        return plans
    }

    private static func comparisonKey(_ url: URL) -> String {
        url.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func isSafeName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name != "." && name != ".." &&
        name.utf8.count <= 255 && !name.contains(where: { $0 == "/" || $0 == "\\" || $0 == ":" }) &&
        !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func identity(at url: URL) -> Identity? {
        var info = stat()
        let code = url.withUnsafeFileSystemRepresentation { $0.map { Darwin.lstat($0, &info) } ?? -1 }
        return code == 0 ? Identity(device: info.st_dev, inode: info.st_ino) : nil
    }

    private static func checkIdentity(at url: URL, expected: Identity) throws {
        guard identity(at: url) == expected else { throw RepairError.changed(url) }
    }

    static func exclusiveMove(_ source: URL, _ destination: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { targetPath in
                guard let sourcePath, let targetPath else { errno = EINVAL; return Int32(-1) }
                return renamex_np(sourcePath, targetPath, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "无法将“\(source.lastPathComponent)”改为“\(destination.lastPathComponent)”：" + String(cString: strerror(errno))])
        }
    }
}
