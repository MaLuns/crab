import AppKit

final class PermissionWindowReturnCoordinator {
    private weak var window: NSWindow?
    private let applicationCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let restoreWindow: (NSWindow) -> Void
    private var applicationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pending = false
    private var visitedSettings = false
    private var leftApplication = false

    init(window: NSWindow, applicationCenter: NotificationCenter = .default,
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         settingsBundleIdentifier: String = "com.apple.systempreferences",
         restoreWindow: @escaping (NSWindow) -> Void = { window in
             if NSApp.isActive { window.makeKeyAndOrderFront(nil) }
             else { window.orderFront(nil) }
         }) {
        self.window = window
        self.applicationCenter = applicationCenter
        self.workspaceCenter = workspaceCenter
        self.restoreWindow = restoreWindow
        applicationObservers.append(applicationCenter.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard self?.leftApplication == true else { return }
            self?.restore()
        })
        applicationObservers.append(applicationCenter.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.pending else { return }
            self.leftApplication = true
        })
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            applicationObservers.append(applicationCenter.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.cancel()
            })
        }
        applicationObservers.append(applicationCenter.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancel()
        })
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.pending,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == settingsBundleIdentifier else { return }
            self.visitedSettings = true
            self.leftApplication = true
        })
        for name in [NSWorkspace.didDeactivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, self.visitedSettings,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == settingsBundleIdentifier else { return }
                self.restore()
            })
        }
    }

    deinit {
        applicationObservers.forEach(applicationCenter.removeObserver)
        workspaceObservers.forEach(workspaceCenter.removeObserver)
    }

    func begin(windowIsVisible: Bool) {
        guard windowIsVisible, window?.isMiniaturized == false else { cancel(); return }
        guard !pending else { return }
        pending = true
        visitedSettings = false
        leftApplication = false
    }

    private func cancel() {
        pending = false
        visitedSettings = false
        leftApplication = false
    }

    private func restore() {
        guard pending, let window, !window.isMiniaturized else { return }
        cancel()
        restoreWindow(window)
    }
}

extension AppPermission {
    var title: String {
        switch self {
        case .accessibility: return L("辅助功能")
        case .inputMonitoring: return L("输入监控")
        case .finderAutomation: return L("访达自动化")
        case .iTermAutomation: return L("iTerm2 自动化")
        case .filesAndFolders: return L("文件与文件夹")
        case .fullDiskAccess: return L("完全磁盘访问")
        case .finderExtension: return L("访达扩展")
        }
    }

    var explanation: String {
        switch self {
        case .accessibility: return L("用于识别访达当前窗口，并通过修饰键右键、鼠标中键或三指轻点打开快捷菜单；未使用快捷触发时无需授权。")
        case .inputMonitoring: return L("快捷触发监听受限时，可按系统提示授予此权限。三指轻点还依赖兼容的触控板和系统接口，授权不代表手势一定可用。")
        case .finderAutomation: return L("用于快捷触发时读取访达当前目录和选中的文件。普通访达扩展菜单不需要此权限；访达运行后才能检测。")
        case .iTermAutomation: return L("用于在 iTerm2 中创建窗口或标签页并切换到目标目录；仅使用此功能时需要，iTerm2 运行后才能检测。")
        case .filesAndFolders: return L("用于操作桌面、文稿、下载、外接磁盘等受保护位置中的文件，按实际访问位置授权。macOS 不提供统一的授权状态查询，请在系统设置中确认。")
        case .fullDiskAccess: return L("仅在需要访问系统额外保护的文件且普通文件夹授权不足时使用；常规文件操作无需开启。macOS 不提供公开的直接查询接口，请在系统设置中确认。")
        case .finderExtension: return L("用于在访达右键菜单中显示 Crab 功能。此项表示扩展是否启用，不代表已授予文件访问权限。")
        }
    }

    var settingsURL: String? {
        let pane: String
        switch self {
        case .accessibility: pane = "Privacy_Accessibility"
        case .inputMonitoring: pane = "Privacy_ListenEvent"
        case .finderAutomation, .iTermAutomation: pane = "Privacy_Automation"
        case .filesAndFolders: pane = "Privacy_FilesAndFolders"
        case .fullDiskAccess: pane = "Privacy_AllFiles"
        case .finderExtension: return nil
        }
        return "x-apple.systempreferences:com.apple.preference.security?" + pane
    }
}

extension AppPermissionState {
    var title: String {
        switch self {
        case .authorized: return L("已授权")
        case .notAuthorized: return L("未授权")
        case .notDetermined: return L("待授权")
        case .notRunning: return L("需启动后检测")
        case .requiresSystemSettings: return L("需在系统设置中确认")
        case .unavailable: return L("无法确认")
        case .enabled: return L("已启用")
        case .disabled: return L("未启用")
        }
    }

    var color: NSColor {
        switch self {
        case .authorized, .enabled: return .systemGreen
        case .notAuthorized, .disabled: return .systemOrange
        default: return .secondaryLabelColor
        }
    }
}

final class SettingsPermissionsView: ReferenceCanvas {
    private let introduction = referenceLabel("按使用到的功能授权；将鼠标移到问号可查看用途。", size: 11, color: .secondaryLabelColor)
    private let refresh: NSButton
    private let refreshFeedback = referenceLabel("", size: 11, color: .secondaryLabelColor)
    private let action: (AppPermission) -> Void
    private var rows: [SettingsPermissionRow] = []

    init(refresh: @escaping () -> Void, action: @escaping (AppPermission) -> Void) {
        self.refresh = referenceLink("刷新状态", size: 11, action: refresh)
        self.action = action
        super.init(frame: .zero)
        identifier = .init("permission-list")
        self.refresh.identifier = .init("permission-refresh")
        refreshFeedback.identifier = .init("permission-refresh-feedback")
        setStatuses(AppPermission.allCases.filter { $0 != .iTermAutomation }.map { ($0, nil) })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ statuses: [AppPermissionStatus]) {
        setStatuses(statuses.map { ($0.permission, $0.state) })
        refresh.isEnabled = true
        refreshFeedback.stringValue = L("已完成")
    }

    func beginRefresh() {
        refresh.isEnabled = false
        refreshFeedback.stringValue = L("检测中…")
    }

    private func setStatuses(_ statuses: [(AppPermission, AppPermissionState?)]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = statuses.map { permission, state in
            SettingsPermissionRow(permission: permission, state: state) { [action] in action(permission) }
        }
    }

    @discardableResult
    func layoutRows(width: CGFloat) -> CGFloat {
        var y = referenceFlowRow([introduction, refreshFeedback, refresh], x: 0, y: 0, width: width, in: self, trailingLast: true) + 8
        let actionWidth = rows.map { referenceFittingSize($0.action).width }.max() ?? 80
        for row in rows {
            let height = row.layoutRow(width: width, actionWidth: actionWidth)
            referencePlace(row, 0, y, width, height, in: self)
            y += height + 6
        }
        frame.size = NSSize(width: width, height: max(0, y - 6))
        return frame.height
    }
}

private final class SettingsPermissionRow: ReferenceCanvas {
    let action: NSButton
    private let name: NSTextField
    private let help: NSButton
    private let status: NSTextField

    init(permission: AppPermission, state: AppPermissionState?, activate: @escaping () -> Void) {
        name = referenceLabel(permission.title)
        help = HoverHelpButton(title: permission.title, message: permission.explanation)
        status = referenceLabel(state?.title ?? L("检测中…"), size: 12, color: state?.color ?? .secondaryLabelColor)
        let canRequest = state == .notDetermined || (state == .notAuthorized && [.accessibility, .inputMonitoring].contains(permission))
        action = referenceLink(permission == .finderExtension ? "扩展管理" : canRequest ? "授权" : "打开设置", size: 12, action: activate)
        super.init(frame: .zero)
        identifier = .init("permission-row-" + permission.rawValue)
        name.identifier = .init("permission-name-" + permission.rawValue)
        help.identifier = .init("permission-help-" + permission.rawValue)
        status.identifier = .init("permission-status-" + permission.rawValue)
        status.setAccessibilityLabel(permission.title + ": " + status.stringValue)
        if state == .unavailable { status.toolTip = L("无法确认权限状态，请在系统设置中检查。") }
        action.identifier = .init("permission-action-" + permission.rawValue)
        action.setAccessibilityLabel(action.title + ": " + permission.title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func layoutRow(width: CGFloat, actionWidth: CGFloat) -> CGFloat {
        let titleColumn = min(216, (width - actionWidth - 40) * 0.52)
        let naturalNameWidth = ceil((name.stringValue as NSString).size(withAttributes: [.font: name.font!]).width) + 4
        let nameSize = referenceWrapLabel(name, width: min(titleColumn - 26, naturalNameWidth))
        let statusSize = referenceWrapLabel(status, width: width - titleColumn - actionWidth - 24)
        let actionSize = referenceFittingSize(action)
        let height = max(26, nameSize.height, statusSize.height, actionSize.height)
        referencePlace(name, 0, (height - nameSize.height) / 2, nameSize.width, nameSize.height, in: self)
        let helpX = nameSize.width + 4
        referencePlace(help, helpX, (height - 20) / 2, 20, 20, in: self)
        referencePlace(status, titleColumn + 8, (height - statusSize.height) / 2, statusSize.width, statusSize.height, in: self)
        referencePlace(action, width - actionWidth, (height - actionSize.height) / 2, actionWidth, actionSize.height, in: self)
        return height
    }
}
