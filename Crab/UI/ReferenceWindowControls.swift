import AppKit

final class ReferenceTrafficButton: NSButton {
    private let closesWindow: Bool
    private let callback: () -> Void
    private let hoverGlyph: NSImage?
    private var pointerInside = false
    private var pointerTracking: NSTrackingArea?
    private var applicationObservers: [NSObjectProtocol] = []
    private var windowObservers: [NSObjectProtocol] = []

    private static let activeClose = NSColor(srgbRed: 255.0 / 255, green: 95.0 / 255, blue: 89.0 / 255, alpha: 1)
    private static let activeMinimize = NSColor(srgbRed: 255.0 / 255, green: 190.0 / 255, blue: 47.0 / 255, alpha: 1)
    private static let inactive = NSColor(srgbRed: 80.0 / 255, green: 82.0 / 255, blue: 79.0 / 255, alpha: 1)

    init(close: Bool, action: @escaping () -> Void) {
        closesWindow = close
        callback = action
        hoverGlyph = CrabSymbol.image(named: close ? "x" : "minus", size: 12, template: false)
        super.init(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        isBordered = false
        title = ""
        focusRingType = .none
        target = self
        self.action = #selector(activate)
        setAccessibilityLabel(close ? "关闭" : "最小化")

        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            applicationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshPresentation()
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        let center = NotificationCenter.default
        for observer in applicationObservers + windowObservers { center.removeObserver(observer) }
        if let area = pointerTracking { removeTrackingArea(area) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        removeWindowObservers()
        pointerInside = false
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        if let window {
            let names = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification]
            for name in names {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.refreshPresentation()
                })
            }
        }
        refreshPresentation()
    }

    override func updateTrackingAreas() {
        if let area = pointerTracking { removeTrackingArea(area) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTracking = area
        refreshPresentation()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        pointerInside = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        pointerInside = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = isEnabled && NSApp?.isActive == true && (window?.isKeyWindow == true || window?.isMainWindow == true)
        let color = active ? (closesWindow ? Self.activeClose : Self.activeMinimize) : Self.inactive
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        if active && pointerInside {
            let side = min(12, min(bounds.width, bounds.height))
            let rect = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            hoverGlyph?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.65,
                             respectFlipped: true, hints: nil)
        }
    }

    private func refreshPresentation() {
        if let window, !isHiddenOrHasHiddenAncestor {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            pointerInside = bounds.contains(point) && visibleRect.contains(point)
        } else {
            pointerInside = false
        }
        needsDisplay = true
    }

    private func removeWindowObservers() {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
    }

    @objc private func activate() { callback() }
}
