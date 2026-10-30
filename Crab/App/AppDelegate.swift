import AppKit
import FinderSync
import Carbon
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settings: SettingsWindowController?
    private var observers: [NSObjectProtocol] = []
    let router = ActionRouter()
    private var pendingURLs: [URL] = []
    private var ready = false
    private var menuBuilder: ContextMenuBuilder?
    private static let logger = Logger(subsystem: "dev.crab.Crab", category: "ActionTransport")
    private var fallback: FinderFallback?
    var fallbackStatus: FinderFallbackStatus? { fallback?.status }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(receiveURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    @objc private func receiveURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: value) else { return }
        Self.logger.notice("URL event received ready=\(self.ready, privacy: .public)")
        if ready { handle(url) } else { pendingURLs.append(url) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        AppLocalization.languageCode = ConfigurationStore.shared.configuration.languageCode
        NSApp.setActivationPolicy(.accessory)
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("关于Crab"), action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: L("设置…"), action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("退出Crab"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: L("编辑"))
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: L(title), action: selector, keyEquivalent: key)
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = StatusBarPresentation.icon()
        statusItem?.button?.target = self; statusItem?.button?.action = #selector(statusClicked)
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        observers.append(DistributedNotificationCenter.default().addObserver(forName: AppConstants.configRequest, object: nil, queue: .main) { _ in ConfigurationStore.shared.broadcast() })
        observers.append(NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshSettings() })
        fallback = FinderFallback { [weak self] urls, directory in self?.showContextMenu(urls: urls, directory: directory, selectionNotice: true) }
        fallback?.onStatusChange = { status in
            NotificationCenter.default.post(name: AppConstants.fallbackStatusChanged, object: status)
        }
        refreshSettings()
        router.startClipboardRecovery()
        let actionLaunch = pendingURLs.contains(where: ActionLaunchPolicy.isActionURL)
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        ready = true
        pendingURLs.forEach(handle); pendingURLs.removeAll()
        if ActionLaunchPolicy.shouldShowSettingsOnLaunch(arguments: ProcessInfo.processInfo.arguments,
                hasLaunched: UserDefaults.standard.bool(forKey: "hasLaunched"), isDefaultLaunch: isDefaultLaunch,
                hasPendingActionURLs: actionLaunch, event: launchEvent) {
            showSettings(); UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
        if let page = ActionLaunchPolicy.settingsPageArgument(in: ProcessInfo.processInfo.arguments) {
            settings?.selectPage(page)
        }
        ConfigurationStore.shared.broadcast()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do { try router.shutdownClipboard(); return .terminateNow }
        catch { presentError(error); return .terminateCancel }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if ready { urls.forEach(handle) } else { pendingURLs.append(contentsOf: urls) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let show = ActionLaunchPolicy.shouldShowSettingsOnReopen(event: event, applicationIsActive: sender.isActive)
        Self.logger.notice("reopen active=\(sender.isActive, privacy: .public) eventClass=\(event?.eventClass ?? 0, privacy: .public) eventID=\(event?.eventID ?? 0, privacy: .public) showSettings=\(show, privacy: .public)")
        guard show else { return false }
        showSettings()
        return true
    }
    private func handle(_ url: URL) {
        do {
            let request = try ActionRequest.decode(url)
            Self.logger.notice("dispatch action=\("operation", privacy: .public) items=\(request.paths.count, privacy: .public)")
            router.execute(request)
        }
        catch { presentError(error) }
    }
    private func refreshSettings() {
        AppLocalization.languageCode = ConfigurationStore.shared.configuration.languageCode
        statusItem?.isVisible = ConfigurationStore.shared.configuration.showStatusItem
        fallback?.configure(ConfigurationStore.shared.configuration)
    }
    @objc func showSettings() {
        Self.logger.notice("settings requested")
        if settings == nil { settings = SettingsWindowController() }
        settings?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        ConfigurationStore.shared.broadcast()
    }
    @objc private func showAbout() {
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Crab", .applicationVersion: "1.0.0", .credits: NSAttributedString(string: "Swift 原生文件与右键菜单工具\nAppKit · FinderSync · 本地处理")])
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && !existingWindows.contains(ObjectIdentifier($0)) }) ?? NSApp.keyWindow {
            WindowAppearance.bind(window)
        }
    }
    @objc private func statusClicked() {
        let menu = StatusBarPresentation.menu(target: self, settingsAction: #selector(showSettings),
                                              quitAction: #selector(quitFromStatusMenu(_:)))
        statusItem?.menu = menu; statusItem?.button?.performClick(nil); statusItem?.menu = nil
    }
    @objc private func quitFromStatusMenu(_ sender: Any?) {
        NSApp.terminate(sender)
    }
    private func showContextMenu(urls: [URL], directory: URL, selectionNotice: Bool = false) {
        menuBuilder = ContextMenuBuilder(configuration: ConfigurationStore.shared.configuration) { [weak self] in self?.router.execute($0) }
        let menu = menuBuilder!.menu(selectedURLs: urls, directory: directory)
        if selectionNotice {
            let title = urls.isEmpty ? "当前位置：\(directory.lastPathComponent)" : "对已选中的 \(urls.count) 项操作：\(urls.prefix(2).map(\.lastPathComponent).joined(separator: "、"))"
            let notice = NSMenuItem(title: title, action: nil, keyEquivalent: ""); notice.isEnabled = false
            menu.insertItem(notice, at: 0); menu.insertItem(.separator(), at: 1)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

func presentError(_ error: Error) {
    NSApp.activate(ignoringOtherApps: true)
    WindowAppearance.errorAlert(error).runModal()
}
