import AppKit

final class HoverHelpButton: NSButton, NSPopoverDelegate {
    private let popover = NSPopover()
    private var hoverTracking: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []
    private var hover: HelpHoverCoordinator!

    init(title: String, message: String) {
        super.init(frame: .zero)
        hover = HelpHoverCoordinator(
            show: { [weak self] in self?.presentHelp() ?? false },
            hide: { [weak self] in self?.popover.close() })
        self.title = ""; isBordered = false; imagePosition = .imageOnly
        image = CrabSymbol.image(named: "help-circle", size: 18)
        contentTintColor = ReferenceStyle.secondary
        target = self; action = #selector(openHelp(_:))
        setAccessibilityLabel(L("帮助") + ": " + L(title))
        setAccessibilityHelp(L(message))
        popover.behavior = .transient; popover.animates = false
        popover.delegate = self
        let controller = HoverHelpContentController(title: title, message: message)
        controller.onHoverChanged = { [weak self] inside in
            if inside { self?.hover.enterContent() } else { self?.hover.exitContent() }
        }
        popover.contentViewController = controller
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        hover?.dismiss()
        popover.close()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); hoverTracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hover.enterButton() }
    override func mouseExited(with event: NSEvent) { hover.exitButton() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { hover.dismiss() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        guard let window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.hover.dismiss() })
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.hover.dismiss() })
    }
    @objc private func openHelp(_ sender: Any?) { hover.openImmediately() }
    private func presentHelp() -> Bool {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return false }
        if !popover.isShown { popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY) }
        return popover.isShown
    }
    func popoverDidClose(_ notification: Notification) { hover.presentationClosed() }
}

final class HelpHoverCoordinator {
    private let show: () -> Bool
    private let hide: () -> Void
    private let showDelay: TimeInterval
    private let hideDelay: TimeInterval
    private var buttonInside = false
    private var contentInside = false
    private var shown = false
    private var pendingShow: DispatchWorkItem?
    private var pendingHide: DispatchWorkItem?

    init(showDelay: TimeInterval = 0.15, hideDelay: TimeInterval = 0.12,
         show: @escaping () -> Bool, hide: @escaping () -> Void) {
        self.showDelay = showDelay; self.hideDelay = hideDelay
        self.show = show; self.hide = hide
    }
    deinit { pendingShow?.cancel(); pendingHide?.cancel() }
    func enterButton() {
        buttonInside = true; pendingHide?.cancel(); pendingHide = nil
        guard !shown else { return }
        pendingShow?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.buttonInside else { return }
            self.pendingShow = nil; self.shown = self.show()
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
    }
    func exitButton() {
        buttonInside = false; pendingShow?.cancel(); pendingShow = nil
        scheduleDismissal()
    }
    func enterContent() { contentInside = true; pendingHide?.cancel(); pendingHide = nil }
    func exitContent() { contentInside = false; scheduleDismissal() }
    func openImmediately() {
        pendingShow?.cancel(); pendingShow = nil
        pendingHide?.cancel(); pendingHide = nil
        if !shown { shown = show() }
    }
    func dismiss() {
        pendingShow?.cancel(); pendingShow = nil
        pendingHide?.cancel(); pendingHide = nil
        buttonInside = false; contentInside = false
        let wasShown = shown; shown = false
        if wasShown { hide() }
    }
    func presentationClosed() {
        shown = false; contentInside = false
        pendingHide?.cancel(); pendingHide = nil
    }
    private func scheduleDismissal() {
        guard !buttonInside, !contentInside, shown else { return }
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.buttonInside, !self.contentInside else { return }
            self.pendingHide = nil; self.shown = false; self.hide()
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: work)
    }
}

final class HoverHelpContentController: NSViewController {
    var onHoverChanged: ((Bool) -> Void)?
    private let heading: String
    private let message: String
    init(title: String, message: String) {
        heading = L(title); self.message = L(message)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        let contentWidth: CGFloat = 300
        let title = NSTextField(wrappingLabelWithString: heading)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        let body = NSTextField(wrappingLabelWithString: message)
        body.font = .systemFont(ofSize: 13); body.textColor = .labelColor
        for label in [title, body] {
            label.maximumNumberOfLines = 0; label.lineBreakMode = .byWordWrapping
            label.preferredMaxLayoutWidth = contentWidth
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        }
        let stack = NSStackView(views: [title, body])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let size = NSSize(width: contentWidth + 32, height: max(72, ceil(stack.fittingSize.height) + 32))
        let root = HoverHelpContentView(frame: NSRect(origin: .zero, size: size))
        root.onHoverChanged = { [weak self] inside in self?.onHoverChanged?(inside) }
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        view = root; preferredContentSize = size
    }
}

private final class HoverHelpContentView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); hoverTracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}
