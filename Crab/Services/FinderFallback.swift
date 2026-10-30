import AppKit
import ApplicationServices

struct FinderFallbackStatus: Equatable {
    var modifierActive = false
    var middleClickActive = false
    var threeFingerActive = false
    var threeFingerDeviceCount = 0
    var requiresAttention = false
    var message = L("访达快捷触发均未开启。")
}

struct FinderFallbackTriggerSettings: Equatable {
    var shortcutEnabled = false
    var modifier: FallbackModifier = .option
    var middleClickEnabled = false
    var threeFingerTapEnabled = false
    var anyEnabled: Bool { shortcutEnabled || middleClickEnabled || threeFingerTapEnabled }
    init() {}
    init(_ config: AppConfiguration) {
        shortcutEnabled = config.fallbackShortcut
        modifier = config.fallbackModifier
        middleClickEnabled = config.fallbackMiddleClick
        threeFingerTapEnabled = config.fallbackThreeFingerTap
    }
}

struct FinderFallbackTriggerState {
    enum Decision: Equatable { case passThrough, consume, trigger }
    var settings = FinderFallbackTriggerSettings()
    private var rightDownConsumed = false
    private var middleDownConsumed = false
    init(settings: FinderFallbackTriggerSettings = FinderFallbackTriggerSettings()) { self.settings = settings }
    mutating func handle(type: CGEventType, flags: CGEventFlags, button: Int64, isAllowed: Bool) -> Decision {
        if type == .rightMouseUp, rightDownConsumed { rightDownConsumed = false; return .consume }
        if type == .otherMouseUp, button == 2, middleDownConsumed { middleDownConsumed = false; return .consume }
        guard isAllowed else { return .passThrough }
        if type == .rightMouseDown, settings.shortcutEnabled, flags.contains(settings.modifier.flags) {
            rightDownConsumed = true; return .trigger
        }
        if type == .otherMouseDown, button == 2, settings.middleClickEnabled {
            middleDownConsumed = true; return .trigger
        }
        return .passThrough
    }
    mutating func reset() { rightDownConsumed = false; middleDownConsumed = false }
}

struct FinderFallbackScope {
    let homeDirectory: URL
    private let isUbiquitousItem: (URL) -> Bool

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         isUbiquitousItem: @escaping (URL) -> Bool = {
             (try? $0.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
         }) {
        self.homeDirectory = homeDirectory
        self.isUbiquitousItem = isUbiquitousItem
    }

    static func directoryURL(fromDocument value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
        return url
    }

    func contains(directory: URL) -> Bool {
        guard directory.isFileURL,
              directory.host == nil || directory.host == "" || directory.host == "localhost" else { return false }
        let resolvedDirectory = normalized(directory)
        let components = resolvedDirectory.pathComponents
        let iCloud = normalizedComponents(of: homeDirectory.appendingPathComponent("Library/Mobile Documents", isDirectory: true))
        if components.starts(with: iCloud) { return true }
        if isUbiquitousItem(resolvedDirectory) { return true }
        let cloudStorage = normalizedComponents(of: homeDirectory.appendingPathComponent("Library/CloudStorage", isDirectory: true))
        guard components.starts(with: cloudStorage), components.count > cloudStorage.count else { return false }
        let provider = components[cloudStorage.count]
        return provider == "OneDrive" || (provider.hasPrefix("OneDrive-") && provider.count > "OneDrive-".count)
    }

    private func normalizedComponents(of url: URL) -> [String] {
        normalized(url).pathComponents
    }

    private func normalized(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}

final class FinderFallback {
    private(set) var status = FinderFallbackStatus()
    var onStatusChange: ((FinderFallbackStatus) -> Void)?
    var enabled: Bool {
        get { trigger.settings.anyEnabled }
        set { trigger.settings.shortcutEnabled = newValue; update() }
    }
    private var eventTap: CFMachPort?
    private var runloopSource: CFRunLoopSource?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var trigger = FinderFallbackTriggerState()
    private let scope = FinderFallbackScope()
    private lazy var threeFinger = ThreeFingerMonitor { [weak self] in self?.handleThreeFingerTap() }
    private let handler: ([URL], URL) -> Void
    init(handler: @escaping ([URL], URL) -> Void) {
        self.handler = handler
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.enabled else { return }; self.update()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.enabled else { return }
            self.threeFinger.stop(); self.update()
        }
    }
    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        removeTap(); threeFinger.stop()
    }
    @discardableResult
    func configure(_ config: AppConfiguration) -> FinderFallbackStatus {
        if !Thread.isMainThread { return DispatchQueue.main.sync { self.configure(config) } }
        let settings = FinderFallbackTriggerSettings(config)
        if trigger.settings != settings { trigger.reset(); threeFinger.invalidateCurrentGesture() }
        trigger.settings = settings
        update()
        return status
    }
    static func hasPermission() -> Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    private func removeTap() {
        if let runloopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runloopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runloopSource = nil; eventTap = nil
        trigger.reset()
    }
    private func update() {
        guard enabled else {
            removeTap(); threeFinger.stop(); publish(FinderFallbackStatus()); return
        }
        guard AXIsProcessTrusted() else {
            removeTap(); threeFinger.stop()
            publish(FinderFallbackStatus(requiresAttention: true, message: L("快捷触发尚未启用：请先授予辅助功能权限。"))); return
        }
        if eventTap == nil { installTap() }
        guard eventTap != nil else {
            threeFinger.stop()
            publish(FinderFallbackStatus(requiresAttention: true, message: L("无法启动全局鼠标监听。请检查辅助功能与输入监控权限后重试。"))); return
        }
        var value = FinderFallbackStatus(modifierActive: trigger.settings.shortcutEnabled, middleClickActive: trigger.settings.middleClickEnabled)
        var active: [String] = []
        if value.modifierActive { active.append(LF("%@ + 右键", trigger.settings.modifier.rawValue)) }
        if value.middleClickActive { active.append(L("鼠标中键")) }
        if trigger.settings.threeFingerTapEnabled {
            do {
                try threeFinger.startOrRefresh()
                value.threeFingerActive = threeFinger.isRunning
                value.threeFingerDeviceCount = threeFinger.deviceCount
                active.append(LF("三指轻点（已连接%d个触控板）", threeFinger.deviceCount))
            } catch {
                threeFinger.stop(); value.requiresAttention = true
                value.message = (active.isEmpty ? "" : LF("已启用：%@。", joined(active))) + LF("三指轻点不可用：%@", error.localizedDescription)
                publish(value); return
            }
        } else { threeFinger.stop() }
        value.message = LF("已启用：%@；仅在访达当前窗口的 iCloud、OneDrive 文件夹内触发。", joined(active))
        publish(value)
    }
    private func joined(_ values: [String]) -> String {
        let formatter = ListFormatter(); formatter.locale = Locale(identifier: AppLocalization.resolvedCode)
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }
    private func publish(_ value: FinderFallbackStatus) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.publish(value) }
            return
        }
        guard status != value else { return }
        status = value
        onStatusChange?(value)
    }
    private func installTap() {
        let mask = [CGEventType.leftMouseDown, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let receiver = Unmanaged<FinderFallback>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                receiver.trigger.reset(); receiver.threeFinger.invalidateCurrentGesture()
                if let tap = receiver.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                receiver.threeFinger.invalidateCurrentGesture()
            }
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let matchingDown = (type == .rightMouseDown && receiver.trigger.settings.shortcutEnabled && event.flags.contains(receiver.trigger.settings.modifier.flags)) ||
                (type == .otherMouseDown && button == 2 && receiver.trigger.settings.middleClickEnabled)
            let decision = receiver.trigger.handle(type: type, flags: event.flags, button: button,
                                                   isAllowed: matchingDown && receiver.canHandle(at: event.location))
            switch decision {
            case .passThrough: return Unmanaged.passUnretained(event)
            case .consume: return nil
            case .trigger:
                let location = event.location
                DispatchQueue.main.async { [weak receiver] in
                    guard let receiver, receiver.canHandle(at: location) else { return }
                    receiver.readSelection()
                }
                return nil
            }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap else { return }
        runloopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runloopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    private func handleThreeFingerTap() {
        guard trigger.settings.threeFingerTapEnabled, status.threeFingerActive,
              NSEvent.pressedMouseButtons == 0, let location = CGEvent(source: nil)?.location,
              canHandle(at: location) else { return }
        readSelection()
    }
    private func canHandle(at point: CGPoint) -> Bool {
        guard enabled, AXIsProcessTrusted(), let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else { return false }
        return isInsideFocusedWindow(of: finder.processIdentifier, at: point)
    }
    private func isInsideFocusedWindow(of pid: pid_t, at point: CGPoint) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        var document: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXDocumentAttribute as CFString, &document) == .success,
              let directory = FinderFallbackScope.directoryURL(fromDocument: document as? String),
              scope.contains(directory: directory) else { return false }
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success,
              let element else { return false }
        if CFEqual(element, focused) { return true }
        var clickedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &clickedWindow) == .success,
              let clickedWindow else { return false }
        return CFEqual(clickedWindow, focused)
    }
    private func readSelection() {
        let source = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                set locationPath to POSIX path of (target of front Finder window as alias)
            else
                set locationPath to POSIX path of (path to desktop folder)
            end if
            set selectedPaths to {}
            repeat with chosenItem in (get selection)
                set end of selectedPaths to POSIX path of (chosenItem as alias)
            end repeat
            return {locationPath, selectedPaths}
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil,
              let path = result.atIndex(1)?.stringValue, let selection = result.atIndex(2) else {
            let description = error?[NSAppleScript.errorMessage] as? String ?? L("无法读取访达选中项。请在系统设置的隐私与安全性中允许Crab自动化访达。")
            presentError(NSError(domain: "Crab", code: 1, userInfo: [NSLocalizedDescriptionKey: description])); return
        }
        let urls = selection.numberOfItems == 0 ? [] : (1...selection.numberOfItems).compactMap { selection.atIndex($0)?.stringValue }.map { URL(fileURLWithPath: $0) }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard scope.contains(directory: directory) else { return }
        handler(urls, directory)
    }
}
