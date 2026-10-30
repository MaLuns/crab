import AppKit

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let view = NSTextField(labelWithString: L(text))
    view.font = .systemFont(ofSize: size, weight: weight); view.textColor = color
    return view
}

final class ClosureButton: NSButton {
    var onClick: (() -> Void)?
    convenience init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title; self.bezelStyle = .rounded; onClick = action
        if let symbol { image = CrabSymbol.image(forLegacySymbol: symbol); imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
        target = self; self.action = #selector(clicked)
    }
    @objc private func clicked() { onClick?() }
}

final class ClosureCheck: NSButton {
    var changed: ((Bool) -> Void)?
    convenience init(_ title: String, value: Bool, changed: @escaping (Bool) -> Void) {
        self.init(frame: .zero); self.title = title; setButtonType(.switch)
        state = value ? .on : .off; self.changed = changed; target = self; action = #selector(toggled)
    }
    @objc private func toggled() { changed?(state == .on) }
}

func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 12) -> NSStackView {
    let result = NSStackView(views: views); result.orientation = vertical ? .vertical : .horizontal
    result.spacing = spacing; result.alignment = vertical ? .leading : .centerY; result.distribution = .fill
    return result
}

func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 0) {
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
}

enum WindowDialogs {
    static func present(_ alert: NSAlert, for parent: NSWindow, store: ConfigurationStore,
                        completion: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        WindowAppearance.bind(alert.window, to: store)
        alert.beginSheetModal(for: parent, completionHandler: completion)
    }

    static func present(_ panel: NSSavePanel, for parent: NSWindow, store: ConfigurationStore,
                        completion: @escaping (NSApplication.ModalResponse) -> Void) {
        WindowAppearance.bind(panel, to: store)
        panel.beginSheetModal(for: parent) { response in
            panel.orderOut(nil)
            completion(response)
        }
    }

    static func confirm(title: String, message: String, button: String, for parent: NSWindow,
                        store: ConfigurationStore, completion: @escaping (Bool) -> Void) {
        let alert = confirmationAlert(title: title, message: message, button: button)
        present(alert, for: parent, store: store) { completion($0 == .alertFirstButtonReturn) }
    }
}

private func confirmationAlert(title: String, message: String, button: String) -> NSAlert {
    let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = L(title); alert.informativeText = L(message)
    alert.addButton(withTitle: L(button)); alert.addButton(withTitle: L("取消"))
    return alert
}

func confirm(title: String, message: String, button: String = "继续", store: ConfigurationStore = .shared) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = confirmationAlert(title: title, message: message, button: button)
    WindowAppearance.bind(alert.window, to: store)
    return alert.runModal() == .alertFirstButtonReturn
}

final class TextWindowController: NSWindowController {
    init(title: String, text: String, store: ConfigurationStore = .shared) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 460), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title; window.center(); window.isReleasedWhenClosed = false
        super.init(window: window)
        WindowAppearance.bind(window, to: store)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        let editor = NSTextView(); editor.isEditable = false; editor.isSelectable = true
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular); editor.string = text
        editor.textContainerInset = NSSize(width: 20, height: 20); editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]; editor.frame = NSRect(x: 0, y: 0, width: 660, height: 440)
        editor.textContainer?.widthTracksTextView = true; scroll.documentView = editor
        window.contentView?.addSubview(scroll); pin(scroll, to: window.contentView!)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
