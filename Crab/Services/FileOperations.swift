import Foundation
import Darwin

final class FileOperations {
    enum OperationError: LocalizedError {
        case invalidName(String)
        case missingItem(URL)
        case notDirectory(URL)
        case unsafeTransfer(URL, URL)
        case overlappingSources
        case symbolicFolder(URL)
        case failed(String, URL, Error)
        case incompleteMove([URL], [URL])
        case folderNotEmpty(URL)

        var errorDescription: String? {
            switch self {
            case .invalidName(let name): return "文件名无效：\(name)。请勿使用空名称、路径分隔符、控制字符或超过 255 字节的名称。"
            case .missingItem(let url): return "文件不存在或无法访问：\(url.path)"
            case .notDirectory(let url): return "目标不是可用的文件夹：\(url.path)"
            case .unsafeTransfer(let source, let destination): return "不能将文件夹“\(source.lastPathComponent)”放入自身或其子文件夹：\(destination.path)"
            case .overlappingSources: return "选择中包含互相嵌套的文件夹或文件，请分开操作。"
            case .symbolicFolder(let url): return "不能解散符号链接或对链接修改权限：\(url.path)"
            case .failed(let operation, let url, let error): return "\(operation)失败：\(url.path)\n\(error.localizedDescription)"
            case .incompleteMove(let destinations, let sources):
                return "文件已完整保存到目标位置，但部分原文件未能删除。请检查后再处理原文件。\n目标：\(destinations.map(\.path).joined(separator: "、"))\n保留的原文件：\(sources.map(\.path).joined(separator: "、"))"
            case .folderNotEmpty(let url): return "文件夹中仍有文件，已保留该文件夹：\(url.path)"
            }
        }
    }

    private let manager: FileManager
    init(fileManager: FileManager = .default) { manager = fileManager }

    func uniqueURL(in directory: URL, preferredName: String) throws -> URL {
        try validateName(preferredName)
        try requireDirectory(directory)
        return try availableURL(in: directory, name: preferredName, reserved: [])
    }

    @discardableResult
    func createFile(template: FileTemplate, in directory: URL, name: String = "未命名") throws -> URL {
        try validateName(name)
        if !template.suffix.isEmpty { try validateName(template.suffix) }
        let suffix = template.suffix.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let filename = suffix.isEmpty || name.lowercased().hasSuffix("." + suffix.lowercased()) ? name : name + "." + suffix
        let destination = try uniqueURL(in: directory, preferredName: filename)
        let stage = temporaryURL(in: directory)
        defer { try? manager.removeItem(at: stage) }
        do {
            if template.importedPath != nil || template.resourceName != nil {
                let source: URL
                if let importedPath = template.importedPath { source = URL(fileURLWithPath: importedPath) }
                else if let name = template.resourceName, let resource = Bundle.main.url(forResource: name, withExtension: nil) { source = resource }
                else { throw OperationError.missingItem(URL(fileURLWithPath: template.resourceName ?? "模板")) }
                let kind = try itemKind(source)
                guard kind != .typeSymbolicLink else { throw OperationError.symbolicFolder(source) }
                if kind == .typeDirectory { try validateTransfer(source: source, destination: directory) }
                try manager.copyItem(at: source, to: stage)
            } else {
                try Data(template.contents.utf8).write(to: stage, options: .withoutOverwriting)
            }
            try manager.moveItem(at: stage, to: destination)
            return destination
        } catch let error as OperationError { throw error }
        catch { throw OperationError.failed("新建文件", destination, error) }
    }

    @discardableResult
    func transfer(urls: [URL], to directory: URL, move: Bool) throws -> [URL] {
        try requireDirectory(directory)
        let sources = try validatedSources(urls)
        try rejectNestedSources(sources)
        var reserved = Set<String>()
        var plans: [(source: URL, destination: URL, stage: URL?)] = []
        for source in sources {
            try validateTransfer(source: source, destination: directory)
            if move && normalized(source.deletingLastPathComponent()) == normalized(directory) {
                plans.append((source, source, nil))
                continue
            }
            let destination = try availableURL(in: directory, name: source.lastPathComponent, reserved: reserved)
            reserved.insert(destination.lastPathComponent.lowercased())
            plans.append((source, destination, temporaryURL(in: directory)))
        }
        var committed: [URL] = []
        do {
            for plan in plans {
                if let stage = plan.stage { try manager.copyItem(at: plan.source, to: stage) }
            }
            for plan in plans {
                if let stage = plan.stage {
                    try manager.moveItem(at: stage, to: plan.destination)
                    committed.append(plan.destination)
                }
            }
        } catch {
            for plan in plans { if let stage = plan.stage { try? manager.removeItem(at: stage) } }
            for destination in committed { try? manager.removeItem(at: destination) }
            throw OperationError.failed(move ? "移动前复制" : "复制", directory, error)
        }
        if move {
            var remaining: [URL] = []
            for plan in plans where plan.stage != nil {
                do { try manager.removeItem(at: plan.source) }
                catch { remaining.append(plan.source) }
            }
            if !remaining.isEmpty {
                throw OperationError.incompleteMove(plans.map(\.destination), remaining)
            }
        }
        return plans.map(\.destination)
    }

    @discardableResult
    func createFoldersByFilename(urls: [URL]) throws -> [URL] {
        let sources = try validatedSources(urls)
        let names = try sources.map { url -> String in
            let name = url.deletingPathExtension().lastPathComponent
            try validateName(name)
            return name
        }
        var result: [URL] = []
        do {
            for (source, name) in zip(sources, names) {
                let destination = try uniqueURL(in: source.deletingLastPathComponent(), preferredName: name)
                try manager.createDirectory(at: destination, withIntermediateDirectories: false)
                result.append(destination)
            }
            return result
        } catch {
            for directory in result { _ = directory.withUnsafeFileSystemRepresentation { $0.map { Darwin.rmdir($0) } ?? -1 } }
            throw OperationError.failed("根据文件名新建文件夹", sources.first ?? URL(fileURLWithPath: "/"), error)
        }
    }

    @discardableResult
    func dissolveFolders(urls: [URL]) throws -> [URL] {
        let folders = try validatedSources(urls)
        try rejectNestedSources(folders)
        for folder in folders {
            let kind = try itemKind(folder)
            guard kind != .typeSymbolicLink else { throw OperationError.symbolicFolder(folder) }
            guard kind == .typeDirectory else { throw OperationError.notDirectory(folder) }
            guard folder.path != "/" else { throw OperationError.notDirectory(folder) }
        }
        var result: [URL] = []
        for folder in folders {
            let children: [URL]
            do { children = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: []) }
            catch { throw OperationError.failed("读取待解散文件夹", folder, error) }
            result += try transfer(urls: children, to: folder.deletingLastPathComponent(), move: true)
            let removed = folder.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { errno = EINVAL; return -1 }
                return Darwin.rmdir(path)
            }
            if removed != 0 {
                if errno == ENOTEMPTY || errno == EEXIST { throw OperationError.folderNotEmpty(folder) }
                throw OperationError.failed("移除已解散的空文件夹", folder, POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
            }
        }
        return result
    }

    func setHidden(urls: [URL], hidden: Bool) throws {
        for var url in try validatedSources(urls) {
            var values = URLResourceValues()
            values.isHidden = hidden
            do { try url.setResourceValues(values) }
            catch { throw OperationError.failed(hidden ? "隐藏文件" : "取消隐藏文件", url, error) }
        }
    }

    func toggleExtensions(urls: [URL]) throws {
        for var url in try validatedSources(urls) {
            do {
                var values = URLResourceValues()
                values.hasHiddenExtension = !(try url.resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension ?? false)
                try url.setResourceValues(values)
            } catch { throw OperationError.failed("切换扩展名显示", url, error) }
        }
    }

    func makeWritable(urls: [URL]) throws {
        let sources = try validatedSources(urls)
        for url in sources where try itemKind(url) == .typeSymbolicLink { throw OperationError.symbolicFolder(url) }
        for url in sources {
            var info = stat()
            guard url.withUnsafeFileSystemRepresentation({ $0.map { Darwin.lstat($0, &info) } ?? -1 }) == 0 else {
                throw OperationError.missingItem(url)
            }
            let result = url.withUnsafeFileSystemRepresentation { $0.map { Darwin.chmod($0, info.st_mode | mode_t(S_IWUSR)) } ?? -1 }
            if result != 0 { throw OperationError.failed("添加所有者写权限", url, POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)) }
        }
    }

    @discardableResult
    func desktopLinks(urls: [URL], desktop: URL) throws -> [URL] {
        try requireDirectory(desktop)
        let sources = try validatedSources(urls)
        var links: [URL] = []
        do {
            for source in sources {
                let link = try uniqueURL(in: desktop, preferredName: source.lastPathComponent)
                try manager.createSymbolicLink(at: link, withDestinationURL: source)
                links.append(link)
            }
            return links
        } catch {
            for link in links { try? manager.removeItem(at: link) }
            throw OperationError.failed("创建桌面快捷方式", desktop, error)
        }
    }

    func trash(urls: [URL]) throws {
        let sources = try validatedSources(urls)
        try rejectNestedSources(sources)
        for url in sources {
            do { try manager.trashItem(at: url, resultingItemURL: nil) }
            catch { throw OperationError.failed("移到废纸篓", url, error) }
        }
    }

    private func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", name.utf8.count <= 255,
              !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else { throw OperationError.invalidName(name) }
    }

    private func availableURL(in directory: URL, name: String, reserved: Set<String>) throws -> URL {
        try validateName(name)
        let original = directory.appendingPathComponent(name)
        if !exists(original) && !reserved.contains(name.lowercased()) { return original }
        let nsName = name as NSString
        let suffix = nsName.pathExtension
        let stem = suffix.isEmpty ? name : nsName.deletingPathExtension
        var index = 2
        while true {
            let numbered = stem + " \(index)" + (suffix.isEmpty ? "" : "." + suffix)
            try validateName(numbered)
            let candidate = directory.appendingPathComponent(numbered)
            if !exists(candidate) && !reserved.contains(numbered.lowercased()) { return candidate }
            index += 1
        }
    }

    private func temporaryURL(in directory: URL) -> URL {
        var url = directory.appendingPathComponent(".crab-" + UUID().uuidString)
        while exists(url) { url = directory.appendingPathComponent(".crab-" + UUID().uuidString) }
        return url
    }

    private func exists(_ url: URL) -> Bool {
        var info = stat()
        return url.withUnsafeFileSystemRepresentation { $0.map { Darwin.lstat($0, &info) == 0 } ?? false }
    }

    private func itemKind(_ url: URL) throws -> FileAttributeType {
        guard url.isFileURL, exists(url) else { throw OperationError.missingItem(url) }
        do { return try manager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType ?? .typeUnknown }
        catch { throw OperationError.failed("读取文件属性", url, error) }
    }

    private func requireDirectory(_ url: URL) throws {
        guard url.isFileURL,
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw OperationError.notDirectory(url) }
    }

    private func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func itemLocation(_ url: URL) -> URL {
        normalized(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent).standardizedFileURL
    }

    private func validatedSources(_ urls: [URL]) throws -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            _ = try itemKind(url)
            let location = itemLocation(url)
            if seen.insert(location.path).inserted { result.append(location) }
        }
        return result
    }

    private func contains(_ directory: URL, _ candidate: URL) -> Bool {
        let parent = directory.pathComponents
        let child = candidate.pathComponents
        return child.count >= parent.count && Array(child.prefix(parent.count)) == parent
    }

    private func validateTransfer(source: URL, destination: URL) throws {
        if try itemKind(source) == .typeDirectory && contains(normalized(source), normalized(destination)) {
            throw OperationError.unsafeTransfer(source, destination)
        }
    }

    private func rejectNestedSources(_ sources: [URL]) throws {
        for source in sources where try itemKind(source) == .typeDirectory {
            for other in sources where source != other {
                if contains(normalized(source), itemLocation(other)) { throw OperationError.overlappingSources }
            }
        }
    }
}
