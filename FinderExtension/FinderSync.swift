import AppKit
import Darwin
import FinderSync
import OSLog

final class FinderSync: FIFinderSync {
    private let store = ConfigurationStore.shared
    private var localObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private static let logger = Logger(subsystem: "dev.crab.Crab.FinderExtension", category: "FinderMenu")
    private struct MenuSnapshot {
        let builder: ContextMenuBuilder
        let menu: NSMenu
        let requests: [Int: ActionRequest]
    }
    private var menuSnapshots: [MenuSnapshot] = []
    private var nextActionTag = 1

    override init() {
        super.init()
        localObserver = NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged,
                                                               object: nil, queue: .main) { [weak self] _ in
            self?.rebuildMonitoring()
        }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name,
                                                                                         object: nil, queue: .main) { [weak self] _ in
                self?.rebuildMonitoring()
            })
        }
        rebuildMonitoring()
        DistributedNotificationCenter.default().postNotificationName(AppConstants.configRequest,
                                                                     object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
    }

    deinit {
        if let localObserver { NotificationCenter.default.removeObserver(localObserver) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    override var toolbarItemName: String { "Crab" }
    override var toolbarItemToolTip: String { "Crab 文件菜单" }
    override var toolbarItemImage: NSImage {
        CrabIcon.image(size: 20) ?? NSImage(size: NSSize(width: 20, height: 20))
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let selection: [URL]
        switch menuKind {
        case .contextualMenuForContainer: selection = []
        default: selection = controller.selectedItemURLs() ?? []
        }
        guard let targeted = controller.targetedURL() ?? selection.first else { return nil }
        if !store.configuration.monitorExternalDisks,
           (try? targeted.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) == false {
            return nil
        }
        let isDirectory = (try? targeted.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? targeted.hasDirectoryPath
        let directory = isDirectory ? targeted : targeted.deletingLastPathComponent()
        let builder = ContextMenuBuilder(configuration: store.configuration) { [weak self] request in
            self?.sendToApplication(request)
        }
        let menu = builder.menu(selectedURLs: selection, directory: directory, isToolbar: menuKind == .toolbarItemMenu)
        FinderMenuPresentation.prepare(menu, appearance: NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!)
        var requests: [Int: ActionRequest] = [:]
        bindFinderActions(in: menu, requests: &requests)
        menuSnapshots.insert(MenuSnapshot(builder: builder, menu: menu, requests: requests), at: 0)
        if menuSnapshots.count > 3 { menuSnapshots.removeLast(menuSnapshots.count - 3) }
        Self.logger.notice("menu prepared kind=\(menuKind.rawValue, privacy: .public) actions=\(requests.count, privacy: .public)")
        return menu
    }

    private func bindFinderActions(in menu: NSMenu, requests: inout [Int: ActionRequest]) {
        for item in menu.items {
            if let submenu = item.submenu { bindFinderActions(in: submenu, requests: &requests) }
            guard let request = item.representedObject as? ActionRequest else { continue }
            let tag = nextActionTag
            nextActionTag &+= 1
            if nextActionTag <= 0 { nextActionTag = 1 }
            requests[tag] = request
            item.tag = tag
            item.target = self
            item.action = #selector(performFinderAction(_:))
            item.representedObject = nil
        }
    }

    @objc private func performFinderAction(_ sender: NSMenuItem) {
        Self.logger.notice("callback tag=\(sender.tag, privacy: .public) representedObject=\(sender.representedObject != nil, privacy: .public)")
        guard let request = menuSnapshots.lazy.compactMap({ $0.requests[sender.tag] }).first else {
            Self.logger.error("callback request not found tag=\(sender.tag, privacy: .public)")
            return
        }
        sendToApplication(request)
    }

    private func sendToApplication(_ request: ActionRequest) {
        do {
            let url = try request.encodedURL()
            let action = "operation"
            NSWorkspace.shared.open(url, configuration: ActionLaunchPolicy.backgroundOpenConfiguration()) { application, error in
                let opened = application != nil && error == nil
                Self.logger.notice("action=\(action, privacy: .public) URLopen=\(opened, privacy: .public) code=\((error as NSError?)?.code ?? 0, privacy: .public)")
            }
        } catch {
            Self.logger.error("action=\("operation", privacy: .public) encodingFailed code=\((error as NSError).code, privacy: .public)")
        }
    }

    private func rebuildMonitoring() {
        var roots = Set<URL>()
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            roots.insert(URL(fileURLWithPath: String(cString: home), isDirectory: true))
        } else {
            roots.insert(FileManager.default.homeDirectoryForCurrentUser)
        }
        let config = store.configuration
        let paths = config.operations.compactMap { op -> String? in
            guard op.enabled else { return nil }
            switch op.parameters {
            case .directory(let path): return path
            case .transfer(let p): return p.target
            default: return nil
            }
        }
        for path in paths {
            roots.insert(URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL)
        }
        if config.monitorExternalDisks {
            let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey], options: []) ?? []
            for volume in volumes where (try? volume.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) == false {
                roots.insert(volume)
            }
        }
        FIFinderSyncController.default().directoryURLs = roots
    }
}
