import AppKit

@MainActor
final class ApplicationLauncher {
    enum LaunchError: LocalizedError {
        case unknownApplication(String)
        case missingApplication(String)
        case invalidApplication(URL)
        case incorrectApplication(String, URL)
        case missingItem(URL)
        case invalidDirectory(URL)
        case unsupportedNewTab(String)
        case terminalServiceUnavailable
        case scriptFailed(String)
        case commandFailed(String, Int32)

        var errorDescription: String? {
            switch self {
            case .unknownApplication(let id): return "未知的应用项目：\(id)"
            case .missingApplication(let name): return "未找到 \(name)。请安装该应用，或在工具设置中选择它的 .app 路径。"
            case .invalidApplication(let url): return "所选路径不是可启动的 macOS 应用：\(url.path)"
            case .incorrectApplication(let name, let url): return "此功能需要 \(name)，所选应用不匹配：\(url.path)"
            case .missingItem(let url): return "文件不存在或无法访问：\(url.path)"
            case .invalidDirectory(let url): return "目录不存在或无法访问：\(url.path)"
            case .unsupportedNewTab(let name): return "\(name) 未提供新建终端标签页功能。"
            case .terminalServiceUnavailable: return "系统的“在文件夹位置新建终端标签页”服务不可用，请在系统设置的键盘服务中启用它。"
            case .scriptFailed(let message): return "终端操作失败：\(message)"
            case .commandFailed(let name, let status): return LF("无法在 %@ 中打开所选位置（退出状态：%d）。", name, status)
            }
        }
    }

    enum Strategy: Equatable {
        case documents
        case terminal(directory: URL, newTab: Bool)
        case iTerm(directory: URL, newTab: Bool)
        case command(executable: URL, arguments: [String], directory: URL)
    }

    struct LaunchPlan: Equatable {
        let applicationURL: URL
        let documentURLs: [URL]
        let strategy: Strategy
    }

    static let shared = ApplicationLauncher()
    private let workspace: NSWorkspace
    private let lookup: (ApplicationDescriptor) -> URL?
    private let openHandler: ((URL, [URL]) async throws -> Void)?
    private var processes: [UUID: Process] = [:]

    init(workspace: NSWorkspace = .shared, lookup: ((ApplicationDescriptor) -> URL?)? = nil,
         openHandler: ((URL, [URL]) async throws -> Void)? = nil) {
        self.workspace = workspace
        self.openHandler = openHandler
        self.lookup = lookup ?? { descriptor in
            for identifier in descriptor.bundleIdentifiers {
                if let url = workspace.urlForApplication(withBundleIdentifier: identifier) { return url }
            }
            for name in descriptor.applicationNames {
                if let path = workspace.fullPath(forApplication: name) { return URL(fileURLWithPath: path, isDirectory: true) }
            }
            return nil
        }
    }

    static func discoverApplicationURL(id: String, applicationURL: URL? = nil) -> URL? {
        ApplicationIcon.discoverApplicationURL(id: id, applicationURL: applicationURL)
    }

    static func launch(id: String, urls: [URL], directory: URL?, applicationURL: URL? = nil, newTab: Bool = false) async throws {
        try await shared.performLaunch(id: id, urls: urls, directory: directory, applicationURL: applicationURL, newTab: newTab)
    }

    static func launchCustom(applicationURL: URL, urls: [URL], directory: URL?) async throws {
        try await shared.perform(shared.customLaunchPlan(applicationURL: applicationURL, urls: urls, directory: directory))
    }

    func customLaunchPlan(applicationURL: URL, urls: [URL], directory: URL?) throws -> LaunchPlan {
        if let entry = ApplicationCatalog.entry(for: applicationURL) {
            return try launchPlan(id: entry.id, urls: urls, directory: directory, applicationURL: applicationURL)
        }
        try validateApplication(applicationURL)
        try validateItems(urls, directory: directory)
        return .init(applicationURL: applicationURL, documentURLs: urls.isEmpty ? [directory].compactMap { $0 } : urls, strategy: .documents)
    }

    func launchPlan(id: String, urls: [URL], directory: URL?, applicationURL: URL? = nil, newTab: Bool = false) throws -> LaunchPlan {
        guard let descriptor = ApplicationCatalog.application(id: id) else { throw LaunchError.unknownApplication(id) }
        guard !newTab || descriptor.supportsNewTab else { throw LaunchError.unsupportedNewTab(descriptor.name) }
        guard let application = applicationURL ?? lookup(descriptor) else { throw LaunchError.missingApplication(descriptor.name) }
        try validateApplication(application)
        if descriptor.requiresMatchingIdentity,
           !descriptor.bundleIdentifiers.contains(Bundle(url: application)?.bundleIdentifier ?? "") {
            throw LaunchError.incorrectApplication(descriptor.name, application)
        }
        try validateItems(urls, directory: directory)
        let documents = urls.isEmpty ? [directory].compactMap { $0 } : urls
        switch descriptor.launchMethod {
        case .documents:
            return .init(applicationURL: application, documentURLs: documents, strategy: .documents)
        case .directory:
            let folder = try workingDirectory(urls: urls, directory: directory)
            return .init(applicationURL: application, documentURLs: [folder], strategy: .documents)
        case .terminal, .iTerm:
            let folder = try workingDirectory(urls: urls, directory: directory)
            return .init(applicationURL: application, documentURLs: [], strategy: descriptor.launchMethod == .terminal ? .terminal(directory: folder, newTab: newTab) : .iTerm(directory: folder, newTab: newTab))
        case .warp:
            let folder = try workingDirectory(urls: urls, directory: directory)
            var uri = URLComponents()
            uri.scheme = "warp"; uri.host = "action"; uri.path = "/new_window"
            uri.queryItems = [URLQueryItem(name: "path", value: folder.path)]
            uri.percentEncodedQuery = uri.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            guard let url = uri.url else { throw LaunchError.invalidDirectory(folder) }
            return .init(applicationURL: application, documentURLs: [url], strategy: .documents)
        case .tabby:
            let folder = try workingDirectory(urls: urls, directory: directory)
            guard let executable = Bundle(url: application)?.executableURL else { throw LaunchError.invalidApplication(application) }
            return .init(applicationURL: application, documentURLs: [],
                         strategy: .command(executable: executable, arguments: ["open", folder.path], directory: folder))
        }
    }

    func performLaunch(id: String, urls: [URL], directory: URL?, applicationURL: URL? = nil, newTab: Bool = false) async throws {
        let plan = try launchPlan(id: id, urls: urls, directory: directory, applicationURL: applicationURL, newTab: newTab)
        try await perform(plan)
    }

    private func perform(_ plan: LaunchPlan) async throws {
        switch plan.strategy {
        case .documents:
            try await open(plan.applicationURL, documents: plan.documentURLs)
        case .terminal(let directory, let newTab):
            if newTab {
                let board = NSPasteboard.withUniqueName()
                defer { board.releaseGlobally() }
                board.writeObjects([directory as NSURL])
                guard NSPerformService("New Terminal Tab at Folder", board) else { throw LaunchError.terminalServiceUnavailable }
            } else {
                try await open(plan.applicationURL, documents: [directory])
            }
        case .iTerm(let directory, let newTab):
            try await open(plan.applicationURL, documents: [])
            let target = Self.appleScriptString(plan.applicationURL.path)
            let command = Self.appleScriptString(Self.commandForDirectory(directory))
            let create = newTab ? """
                if (count of windows) is 0 then
                    set newSession to current session of (create window with default profile)
                else
                    tell current window
                        set newSession to current session of (create tab with default profile)
                    end tell
                end if
                """ : "set newSession to current session of (create window with default profile)"
            try runAppleScript("tell application \(target)\n\(create)\ntell newSession to write text \(command)\nactivate\nend tell")
        case .command(let executable, let arguments, let directory):
            try await runCommand(executable, arguments: arguments, directory: directory,
                                 name: ApplicationCatalog.entry(for: plan.applicationURL)?.name ?? plan.applicationURL.deletingPathExtension().lastPathComponent)
        }
    }

    private func validateItems(_ urls: [URL], directory: URL?) throws {
        let manager = FileManager.default
        for url in urls {
            guard url.isFileURL, manager.fileExists(atPath: url.path) else { throw LaunchError.missingItem(url) }
        }
        if let directory {
            var isDirectory: ObjCBool = false
            guard directory.isFileURL, manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw LaunchError.invalidDirectory(directory)
            }
        }
    }

    private func validateApplication(_ url: URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw LaunchError.invalidApplication(url)
        }
    }

    private func workingDirectory(urls: [URL], directory: URL?) throws -> URL {
        if let first = urls.first {
            return (try first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? first : first.deletingLastPathComponent()
        }
        guard let directory else { throw LaunchError.invalidDirectory(URL(fileURLWithPath: "")) }
        return directory
    }

    private func open(_ application: URL, documents: [URL]) async throws {
        if let openHandler { return try await openHandler(application, documents) }
        let configuration = NSWorkspace.OpenConfiguration()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { app, error in
                if let error { continuation.resume(throwing: error) }
                else if app != nil { continuation.resume() }
                else { continuation.resume(throwing: LaunchError.invalidApplication(application)) }
            }
            if documents.isEmpty { workspace.openApplication(at: application, configuration: configuration, completionHandler: completion) }
            else { workspace.open(documents, withApplicationAt: application, configuration: configuration, completionHandler: completion) }
        }
    }

    private func runCommand(_ executable: URL, arguments: [String], directory: URL, name: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process(), token = UUID()
            process.executableURL = executable; process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                let succeeded = process.terminationReason == .exit && process.terminationStatus == 0
                let status = process.terminationStatus
                Task { @MainActor in
                    self?.processes.removeValue(forKey: token)
                    if succeeded { continuation.resume() }
                    else { continuation.resume(throwing: LaunchError.commandFailed(name, status)) }
                }
            }
            processes[token] = process
            do { try process.run() }
            catch {
                processes.removeValue(forKey: token); process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw LaunchError.scriptFailed("无法编译终端脚本。") }
        script.executeAndReturnError(&error)
        if let error { throw LaunchError.scriptFailed(error[NSAppleScript.errorMessage] as? String ?? error.description) }
    }

    static func commandForDirectory(_ directory: URL) -> String { "cd -- " + shellQuote(directory.path) }

    static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
    private static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
