import AppKit

struct PlannedMenuItem {
    var node: MenuNode
    var title: String
    var operation: OperationRecord?
    var children: [PlannedMenuItem]
}
enum MenuPlanner {
    static func items(configuration: AppConfiguration, context: OperationContext, allowFileRead: Bool = Bundle.main.bundleURL.pathExtension != "appex") -> [PlannedMenuItem] {
        let operations = Dictionary(configuration.operations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func resolve(_ node: MenuNode, depth: Int) -> PlannedMenuItem? {
            guard node.visible else { return nil }
            if node.kind == .group {
                guard depth == 1 else { return nil }
                let children = node.children.compactMap { resolve($0, depth: 2) }
                guard !children.isEmpty else { return nil }
                return PlannedMenuItem(node: node, title: node.displayName(), operation: nil, children: children)
            }
            guard node.children.isEmpty, let id = node.operationID, let op = operations[id],
                  OperationResolver.canExecute(op, context: context, configuration: configuration, allowFileRead: allowFileRead) else { return nil }
            return PlannedMenuItem(node: node, title: node.displayName(operation: op), operation: op, children: [])
        }
        return configuration.menu.compactMap { resolve($0, depth: 1) }
    }
}
final class ContextMenuBuilder: NSObject {
    private let configuration: AppConfiguration
    private let handler: (ActionRequest) -> Void
    init(configuration: AppConfiguration, handler: @escaping (ActionRequest) -> Void) {
        self.configuration = configuration; self.handler = handler; super.init()
    }
    func menu(selectedURLs: [URL], directory: URL, isToolbar: Bool = false) -> NSMenu {
        AppLocalization.languageCode = configuration.languageCode
        let selection = selectedURLs.filter(\.isFileURL)
        let context = OperationContext(urls: selection, directory: directory.standardizedFileURL)
        func build(_ items: [PlannedMenuItem]) -> NSMenu {
            let menu = ContextActionMenu(); menu.actionOwner = self; menu.autoenablesItems = false
            for entry in items {
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                if let operation = entry.operation {
                    item.target = self; item.action = #selector(performAction(_:))
                    item.representedObject = ActionRequest(operationID: operation.id, paths: selection.map(\.path), targetDirectory: directory.path)
                } else { item.submenu = build(entry.children) }
                item.image = MenuNodeIcons.image(node: entry.node, operation: entry.operation, configuration: configuration)
                menu.addItem(item)
            }
            return menu
        }
        return build(MenuPlanner.items(configuration: configuration, context: context))
    }
    @objc private func performAction(_ item: NSMenuItem) {
        guard let request = item.representedObject as? ActionRequest else { return }; handler(request)
    }
}
private final class ContextActionMenu: NSMenu { var actionOwner: AnyObject? }
