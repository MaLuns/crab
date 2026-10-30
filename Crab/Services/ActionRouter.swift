import AppKit
import CryptoKit
import OSLog

final class ActionRouter {
    private static let logger = Logger(subsystem: "dev.crab.Crab", category: "Actions")
    private let files = FileOperations()
    private let store: ConfigurationStore
    private let launchScript: (CustomScript, [URL], URL, @escaping (Error) -> Void) throws -> Void
    private let reportScriptError: (Error) -> Void
    private let airDrop: AirDropSharing
    private var windows: [NSWindowController] = []
    private var cutSession: CutSessionManager?

    init(store: ConfigurationStore = .shared,
         launchScript: @escaping (CustomScript, [URL], URL, @escaping (Error) -> Void) throws -> Void = {
             try CustomScriptRunner.shared.launch($0, selectedURLs: $1, directory: $2, onFailure: $3)
         },
         reportScriptError: @escaping (Error) -> Void = { presentError($0) },
         airDropService: @escaping () -> NSSharingService? = { NSSharingService(named: .sendViaAirDrop) },
         reportAirDropError: @escaping (Error) -> Void = { presentError($0) }) {
        self.store = store
        self.launchScript = launchScript
        self.reportScriptError = reportScriptError
        self.airDrop = AirDropSharing(makeService: airDropService, reportError: reportAirDropError)
        installExecutors()
    }

    private func clipboardSession() throws -> CutSessionManager {
        if let cutSession { return cutSession }
        let session = try CutSessionManager()
        session.onRecoveryError = { error in DispatchQueue.main.async { presentError(error) } }
        cutSession = session
        return session
    }
    func startClipboardRecovery() {
        do { _ = try clipboardSession() } catch { presentError(error) }
    }
    func shutdownClipboard() throws { try cutSession?.shutdown() }

    private var executors: [String: (OperationRecord, OperationContext) -> Void] = [:]
    func registerExecutor(kind: String, handler: @escaping (OperationRecord, OperationContext) -> Void) {
        executors[kind] = handler
    }
    func execute(_ request: ActionRequest) {
        guard request.version == 2,
              let op = store.configuration.operations.first(where: { $0.id == request.operationID }) else { return }
        let context = OperationContext(urls: request.urls, directory: request.directoryURL ?? request.urls.first?.deletingLastPathComponent())
        guard OperationResolver.canExecute(op, context: context, configuration: store.configuration, allowFileRead: true) else { return }
        Self.logger.notice("operation kind=\(op.parameters.kind, privacy: .public) count=\(context.urls.count, privacy: .public)")
        executors[op.parameters.kind]?(op, context)
    }
    private func installExecutors() {
        registerExecutor(kind: "tool") { [weak self] op, context in
            guard case .tool(let p) = op.parameters else { return }
            if p.action == .addCommon {
                let directories = context.urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                let targets = context.urls.count == 1 && directories.count == 1 ? directories : [context.directory].compactMap { $0 }
                self?.store.update { config in
                    for url in targets {
                        config.operations.append(OperationRecord(name: url.lastPathComponent, parameters: .directory(url.path)))
                    }
                }
                return
            }
            self?.execute(p.action, urls: context.urls, directory: context.directory, options: p)
        }
        registerExecutor(kind: "template") { [weak self] op, context in
            guard let self, case .template(let p) = op.parameters, let directory = context.directory else { return }
            self.perform("创建文件") { try self.files.createFile(template: p.template, in: directory) } completion: { url in
                if p.playSound { NSSound(named: "Glass")?.play() }
                if p.autoOpen { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
        registerExecutor(kind: "transfer") { [weak self] op, context in
            guard let self, case .transfer(let p) = op.parameters else { return }
            let target = p.target.map { URL(fileURLWithPath: $0) } ?? self.chooseFolder(prompt: L(p.move ? "移动到" : "复制到"))
            guard let target else { return }; self.transfer(context.urls, to: target, move: p.move)
        }
        registerExecutor(kind: "directory") { op, _ in
            guard case .directory(let path) = op.parameters else { return }; NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        registerExecutor(kind: "application") { op, context in
            guard case .application(let p) = op.parameters else { return }
            Task { @MainActor in
                do {
                    if let id = p.catalogID {
                        try await ApplicationLauncher.launch(id: id, urls: context.urls, directory: context.directory, applicationURL: p.path.map { URL(fileURLWithPath: $0) }, newTab: p.newTab)
                    } else if let path = p.path {
                        try await ApplicationLauncher.launchCustom(applicationURL: URL(fileURLWithPath: path), urls: context.urls, directory: context.directory)
                    }
                } catch { presentError(error) }
            }
        }
        registerExecutor(kind: "image") { [weak self] op, context in
            guard let self, case .image(let p) = op.parameters else { return }
            do { try self.setIcon(p.remove ? nil : OperationImages.source(op), urls: context.urls); self.store.broadcast() }
            catch { presentError(error) }
        }
        registerExecutor(kind: "script") { [weak self] op, context in
            guard let self, case .script(let path) = op.parameters, let directory = context.directory else { return }
            let script = CustomScript(name: op.displayName, path: path)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.launchScript(script, context.urls, directory) { error in DispatchQueue.main.async { self.reportScriptError(error) } }
                } catch { DispatchQueue.main.async { self.reportScriptError(error) } }
            }
        }
    }
    private func execute(_ action: ToolAction, urls: [URL], directory: URL?, options: ToolParameters) {
        Self.logger.notice("execute action=\(action.rawValue, privacy: .public) selection=\(urls.count, privacy: .public) directory=\(directory != nil, privacy: .public)")
        if let applicationID = action.applicationID {
            let selectedApp: URL? = nil
            let newTab = options.newTab
            Task { @MainActor in
                do {
                    try await ApplicationLauncher.launch(id: applicationID, urls: urls, directory: directory, applicationURL: selectedApp, newTab: newTab)
                } catch { presentError(error) }
            }
            return
        }
        switch action {
        case .copyPath, .copyName:
            do { try clipboardSession().prepareForCopy() } catch { presentError(error); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map { action == .copyPath ? $0.path : $0.lastPathComponent }.joined(separator: "\n"), forType: .string)
        case .cut:
            do {
                try clipboardSession().cut(urls, hideOriginals: options.hideOriginals)
            } catch { presentError(error) }
        case .paste:
            guard let directory else { return }
            do {
                let session = try clipboardSession()
                let plan = try session.prepareForPaste()
                guard !plan.urls.isEmpty else { return }
                perform("粘贴文件") { try self.files.transfer(urls: plan.urls, to: directory, move: plan.move) } completion: { results in
                    do { try session.completePaste(plan) } catch { presentError(error) }
                    NSWorkspace.shared.activateFileViewerSelecting(results)
                }
            } catch { presentError(error) }
        case .fileInfo: showFileInfo(urls)
        case .newFolderByName:
            perform("创建文件夹") { try self.files.createFoldersByFilename(urls: urls) } completion: { NSWorkspace.shared.activateFileViewerSelecting($0) }
        case .dissolveFolder:
            guard confirm(title: "解散所选文件夹？", message: "将内部文件移到上一级目录，再移除空文件夹。同名文件会自动编号，不会覆盖。\n\n\(summary(urls))", button: "解散", store: store) else { return }
            perform("解散文件夹") { try self.files.dissolveFolders(urls: urls) } completion: { NSWorkspace.shared.activateFileViewerSelecting($0) }
        case .hide, .unhide:
            perform("修改隐藏属性", showsProgress: false, work: { try self.files.setHidden(urls: urls, hidden: action == .hide) })
        case .showHidden, .hideHidden:
            perform("设置访达", showsProgress: false, work: {
                try Self.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", action == .showHidden ? "true" : "false"])
                try Self.run("/usr/bin/killall", ["Finder"])
            })
        case .toggleExtension:
            perform("修改扩展名显示", showsProgress: false, work: { try self.files.toggleExtensions(urls: urls) })
        case .makeWritable:
            perform("修改写入权限", showsProgress: false, work: { try self.files.makeWritable(urls: urls) })
        case .trash:
            perform("移到废纸篓", showsProgress: false, work: { try self.files.trash(urls: urls) })
        case .deletePermanently:
            if options.confirmDeletion && !confirm(title: "彻底删除所选文件？", message: "这些项目不会进入废纸篓。\n\n\(summary(urls))", button: "彻底删除", store: store) { return }
            perform("删除文件", showsProgress: false, work: { for url in urls { try FileManager.default.removeItem(at: url) } })
        case .desktopLink:
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            perform("创建快捷方式") { try self.files.desktopLinks(urls: urls, desktop: desktop) } completion: { NSWorkspace.shared.activateFileViewerSelecting($0) }
        case .airDrop:
            airDrop.share(urls)
        case .wallpaper:
            guard let url = urls.first else { return }
            do { for screen in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) } } catch { presentError(error) }
        case .png, .jpeg, .heic, .webp, .tiff, .icns, .macIconset, .iosIconset:
            perform("转换图片") { try MediaTools.convert(urls, format: action) } completion: { NSWorkspace.shared.activateFileViewerSelecting($0) }
        case .zip:
            guard let directory else { return }
            perform("压缩 ZIP") { try ArchiveTools.compress(urls, in: directory) } completion: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        case .sevenZip:
            guard let directory else { return }
            perform("压缩 7z") { try ArchiveTools.compress7z(urls, in: directory) } completion: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        case .unzip:
            guard let directory else { return }
            perform("解压归档") { try urls.map { try ArchiveTools.extractArchive($0, in: directory) } } completion: { NSWorkspace.shared.activateFileViewerSelecting($0) }
        case .repairFilename:
            let controller = FilenameRepairWindowController(urls: urls, store: store)
            windows.append(controller); controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        case .addCommon: return
        case .terminal, .vscode, .iterm2, .sublimeText, .sublimeMerge, .warp, .markText, .obsidian,
             .tabby, .visualStudio, .hyper, .emacs, .clion, .cotEditor, .hbuilderX, .phpstorm, .pycharm,
             .typora, .webstorm, .intellijIdea, .androidStudio, .appCode, .dataGrip, .goland, .rider, .rubyMine, .cursor, .ghostty:
            assertionFailure("Application catalog is missing an application action")
        }
    }
    private func transfer(_ urls: [URL], to destination: URL, move: Bool) {
        perform(move ? "移动文件" : "复制文件") { try self.files.transfer(urls: urls, to: destination, move: move) } completion: { NSWorkspace.shared.activateFileViewerSelecting($0) }
    }
    private func setIcon(_ image: NSImage?, urls: [URL]) throws {
        for url in urls where !NSWorkspace.shared.setIcon(image, forFile: url.path, options: []) { throw Self.error("无法修改图标：\(url.lastPathComponent)") }
    }
    private func showFileInfo(_ urls: [URL]) {
        perform("计算文件校验") {
            try urls.map { url -> String in
                let v = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
                var rows = [url.lastPathComponent, "路径：\(url.path)", v.isDirectory == true ? "类型：文件夹（不递归统计大小）" : "大小：\(ByteCountFormatter.string(fromByteCount: Int64(v.fileSize ?? 0), countStyle: .file))"]
                if let date = v.creationDate { rows.append("创建：\(date.formatted())") }
                if let date = v.contentModificationDate { rows.append("修改：\(date.formatted())") }
                if v.isDirectory != true {
                    let hashes = try HashTools.digests(of: url)
                    for key in ["MD5", "SHA1", "SHA256", "SHA512"] { if let value = hashes[key] { rows.append("\n\(key)：\n\(value)") } }
                }
                return rows.joined(separator: "\n")
            }.joined(separator: "\n\n────────────────────────────\n\n")
        } completion: { text in
            let window = TextWindowController(title: "文件信息与校验", text: text, store: self.store)
            self.windows.append(window); window.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        }
    }
    private func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = prompt
        WindowAppearance.bind(panel, to: store)
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func summary(_ urls: [URL]) -> String {
        urls.prefix(8).map(\.lastPathComponent).joined(separator: "\n") + (urls.count > 8 ? "\n以及其他 \(urls.count - 8) 项" : "")
    }
    private func perform<T>(_ title: String, showsProgress: Bool = true, work: @escaping () throws -> T,
                            completion: @escaping (T) -> Void = { _ in }) {
        var panel: NSPanel?
        var finished = false
        let showProgress = DispatchWorkItem {
            guard !finished else { return }
            panel = self.progressPanel(title: title)
        }
        if showsProgress { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: showProgress) }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result(catching: work)
            switch result {
            case .success: Self.logger.notice("operation completed")
            case .failure(let error): Self.logger.error("operation failed code=\((error as NSError).code, privacy: .public)")
            }
            DispatchQueue.main.async {
                finished = true
                showProgress.cancel()
                panel?.close()
                switch result { case .success(let value): completion(value); case .failure(let error): presentError(error) }
            }
        }
    }
    private func progressPanel(title: String) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 82), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        WindowAppearance.bind(panel, to: store)
        panel.title = title; panel.center(); panel.isFloatingPanel = true
        let progress = NSProgressIndicator(); progress.style = .spinning; progress.startAnimation(nil)
        let row = stack([progress, label("正在\(title)…")], vertical: false, spacing: 12)
        panel.contentView?.addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.centerXAnchor.constraint(equalTo: panel.contentView!.centerXAnchor), row.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor)])
        panel.orderFrontRegardless()
        return panel
    }
    private static func error(_ description: String) -> NSError { .init(domain: "Crab", code: 1, userInfo: [NSLocalizedDescriptionKey: description]) }
    private static func run(_ executable: String, _ args: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        let pipe = Pipe(); process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        if process.terminationStatus != 0 { throw error(String(data: data, encoding: .utf8) ?? "系统操作失败。") }
    }
}

final class AirDropSharing: NSObject, NSSharingServiceDelegate {
    private let makeService: () -> NSSharingService?
    private let reportError: (Error) -> Void
    private var services: [ObjectIdentifier: NSSharingService] = [:]

    init(makeService: @escaping () -> NSSharingService?, reportError: @escaping (Error) -> Void) {
        self.makeService = makeService
        self.reportError = reportError
        super.init()
    }

    func share(_ urls: [URL]) {
        guard let service = makeService() else {
            reportError(SharingError.unavailable)
            return
        }
        guard service.canPerform(withItems: urls) else {
            reportError(SharingError.unsupportedItems)
            return
        }
        services[ObjectIdentifier(service)] = service
        service.delegate = self
        service.perform(withItems: urls)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish(sharingService)
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard finish(sharingService) else { return }
        let failure = error as NSError
        guard failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError else { return }
        reportError(SharingError.failed(error))
    }

    @discardableResult
    private func finish(_ service: NSSharingService) -> Bool {
        guard services.removeValue(forKey: ObjectIdentifier(service)) != nil else { return false }
        service.delegate = nil
        return true
    }

    private enum SharingError: LocalizedError {
        case unavailable, unsupportedItems, failed(Error)

        var errorDescription: String? {
            switch self {
            case .unavailable: return L("隔空投送服务当前不可用，请稍后重试。")
            case .unsupportedItems: return L("无法通过隔空投送分享所选文件。")
            case .failed(let error): return LF("隔空投送失败：%@", error.localizedDescription)
            }
        }
    }
}
