import AppKit
import ObjectiveC

enum WindowAppearance {
    private static var bindingKey: UInt8 = 0

    static func apply(to window: NSWindow, theme: WindowTheme) {
        switch theme {
        case .system: window.appearance = nil
        case .light: window.appearance = NSAppearance(named: .aqua)
        case .dark: window.appearance = NSAppearance(named: .darkAqua)
        }
        window.contentView?.needsDisplay = true
    }

    static func bind(_ window: NSWindow, to store: ConfigurationStore = .shared) {
        apply(to: window, theme: store.configuration.windowTheme)
        let binding = WindowAppearanceBinding(window: window, store: store)
        objc_setAssociatedObject(window, &bindingKey, binding, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func errorAlert(_ error: Error, store: ConfigurationStore = .shared) -> NSAlert {
        let alert = NSAlert(error: error)
        bind(alert.window, to: store)
        return alert
    }
}

private final class WindowAppearanceBinding {
    private weak var window: NSWindow?
    private let store: ConfigurationStore
    private var observer: NSObjectProtocol?

    init(window: NSWindow, store: ConfigurationStore) {
        self.window = window
        self.store = store
        observer = NotificationCenter.default.addObserver(forName: AppConstants.localConfigChanged, object: nil, queue: .main) { [weak self] note in
            guard let self, (note.object as? ConfigurationStore) === self.store, let window = self.window else { return }
            WindowAppearance.apply(to: window, theme: self.store.configuration.windowTheme)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
