import AppKit
import UniformTypeIdentifiers

struct OperationContext {
    var urls: [URL]
    var directory: URL?
    func supports(_ action: ToolAction) -> Bool {
        if action.needsSelection && urls.isEmpty { return false }
        let allImages = !urls.isEmpty && urls.allSatisfy { url in
            let value = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
            return value?.isDirectory != true && !url.hasDirectoryPath && (value?.contentType ?? UTType(filenameExtension: url.pathExtension))?.conforms(to: .image) == true
        }
        switch action {
        case .png, .jpeg, .heic, .webp, .tiff, .icns, .macIconset, .iosIconset: return allImages
        case .wallpaper: return urls.count == 1 && allImages
        case .unzip: return !urls.isEmpty && urls.allSatisfy { ["zip", "7z"].contains($0.pathExtension.lowercased()) && !$0.hasDirectoryPath }
        case .dissolveFolder: return !urls.isEmpty && urls.allSatisfy { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? $0.hasDirectoryPath }
        default: return true
        }
    }
}
struct OperationDefinition {
    let kind: String
    let title: String
    let category: MenuIconCategory
    let symbol: String
    let defaultName: (OperationRecord) -> String
    let validation: (OperationRecord) -> String?
    let supports: (OperationRecord, OperationContext) -> Bool
}
final class OperationRegistry {
    static let shared = OperationRegistry()
    static let builtInIDs = Set(defaults().map(\.id))
    private let lock = NSLock()
    private var entries: [OperationDefinition] = []
    var definitions: [OperationDefinition] { lock.lock(); defer { lock.unlock() }; return entries }
    func definition(for operation: OperationRecord) -> OperationDefinition? { definitions.first { $0.kind == operation.parameters.kind } }
    func register(_ definition: OperationDefinition) { lock.lock(); defer { lock.unlock() }; entries.removeAll { $0.kind == definition.kind }; entries.append(definition) }
    init() {
        register(.init(kind: "tool", title: "工具操作", category: .tools, symbol: "tools", defaultName: {
            if case .tool(let p) = $0.parameters { return L(p.action.title) }; return L("工具操作")
        }, validation: { if case .tool = $0.parameters { return nil }; return "不受当前版本支持" }, supports: { op, context in
            guard case .tool(let p) = op.parameters else { return false }; return context.supports(p.action)
        }))
        register(.init(kind: "template", title: "文件模板", category: .newFile, symbol: "file-plus", defaultName: {
            if case .template(let p) = $0.parameters { return L(p.template.name) }; return L("文件模板")
        }, validation: { op in
            guard case .template(let p) = op.parameters else { return "配置无效" }
            if let path = p.template.importedPath { return Self.fileError(path) }
            if let resource = p.template.resourceName, Bundle.main.url(forResource: resource, withExtension: nil) == nil { return "找不到模板文件" }
            return nil
        }, supports: { _, context in context.directory != nil }))
        register(.init(kind: "transfer", title: "传送目录", category: .send, symbol: "folder-symlink", defaultName: {
            if case .transfer(let p) = $0.parameters { return L(p.move ? "移动到" : "复制到") }; return L("传送目录")
        }, validation: { op in
            guard case .transfer(let p) = op.parameters else { return "配置无效" }
            return p.target.flatMap(Self.directoryError)
        }, supports: { _, context in !context.urls.isEmpty }))
        register(.init(kind: "directory", title: "快捷目录", category: .common, symbol: "folder", defaultName: { _ in L("快捷目录") }, validation: {
            if case .directory(let path) = $0.parameters { return Self.directoryError(path) }; return "配置无效"
        }, supports: { _, _ in true }))
        register(.init(kind: "application", title: "应用入口", category: .tools, symbol: "app-window", defaultName: {
            if case .application(let p) = $0.parameters {
                if let id = p.catalogID, let entry = ApplicationCatalog.entry(id: id) { return LF("进入 %@", entry.name) }
                if let path = p.path { return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
            }; return L("应用入口")
        }, validation: {
            guard case .application(let p) = $0.parameters else { return "配置无效" }
            return Self.applicationURL(p) == nil ? "应用不可用" : nil
        }, supports: { _, context in context.directory != nil || !context.urls.isEmpty }))
        register(.init(kind: "image", title: "自定义图标", category: .customIcons, symbol: "palette", defaultName: {
            if case .image(let p) = $0.parameters {
                if p.remove { return L("移除自定义图标") }
                if let id = p.systemID, let d = SystemIconDefaults.catalog.first(where: { $0.id == id }) { return L(d.name) }
            }; return L("自定义图标")
        }, validation: {
            guard case .image(let p) = $0.parameters else { return "配置无效" }
            if p.remove { return nil }
            if let id = p.systemID { return SystemIconDefaults.catalog.contains { $0.id == id } ? nil : "图标不可用" }
            guard let path = p.path else { return "请选择图片" }
            if let error = Self.fileError(path) { return error }
            return NSImage(contentsOfFile: path) == nil ? "图标不可用" : nil
        }, supports: { _, context in !context.urls.isEmpty }))
        register(.init(kind: "script", title: "自定义脚本", category: .scripts, symbol: "terminal", defaultName: {
            if case .script(let path) = $0.parameters { return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }; return L("自定义脚本")
        }, validation: { if case .script(let path) = $0.parameters { return Self.fileError(path) }; return "配置无效" }, supports: { _, context in context.directory != nil }))
    }
    private static func fileError(_ path: String) -> String? {
        var directory: ObjCBool = false
        guard path.hasPrefix("/"), !path.contains("\0"), FileManager.default.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue,
              FileManager.default.isReadableFile(atPath: path) else { return "文件不存在或无法读取" }
        return nil
    }
    private static func directoryError(_ path: String) -> String? {
        var directory: ObjCBool = false
        guard path.hasPrefix("/"), !path.contains("\0"), FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { return "目录不存在或无法访问" }
        return nil
    }
    static func applicationURL(_ p: ApplicationParameters) -> URL? {
        if let id = p.catalogID { return ApplicationIcon.discoverApplicationURL(id: id, applicationURL: p.path.map { URL(fileURLWithPath: $0) }) }
        return p.path.flatMap { ApplicationIcon.validateApplicationURL(URL(fileURLWithPath: $0)) }
    }
    static func defaults() -> [OperationRecord] {
        var result = ToolAction.displayOrder.map { action -> OperationRecord in
            if let id = action.applicationID { return OperationRecord(id: "builtin.app." + id, parameters: .application(.init(catalogID: id))) }
            return OperationRecord(id: "builtin.tool." + action.rawValue, parameters: .tool(.init(action: action)))
        }
        result += FileTemplate.defaults.map { OperationRecord(id: "builtin.template." + $0.id, parameters: .template(.init(template: $0))) }
        result += SystemIconDefaults.catalog.map { OperationRecord(id: $0.id, parameters: .image(.init(systemID: $0.id))) }
        result += [OperationRecord(id: "builtin.image.remove", parameters: .image(.init(remove: true))),
                   OperationRecord(id: "builtin.transfer.copy", parameters: .transfer(.init())),
                   OperationRecord(id: "builtin.transfer.move", parameters: .transfer(.init(move: true)))]
        return result
    }
}

enum DefaultMenuLayout {
    static func nodes(for operations: [OperationRecord]) -> [MenuNode] {
        let groups: [(CategoryIcon, String)] = [
            (.newFile, "新建文件"), (.tools, "文件（夹）操作"),
            (.applications, "由 APP 打开"), (.send, "发送到…"),
            (.common, "收藏目录"), (.customIcons, "自定义图标"),
            (.images, "图片转换"), (.archives, "压缩与解压")
        ]
        let existingIDs = Set(operations.map(\.id))
        let builtIns = OperationRegistry.defaults().filter { existingIDs.contains($0.id) }
        return groups.map { category, title in
            let children = builtIns.filter { self.category(for: $0) == category }.map {
                MenuNode(id: "default.reference." + $0.id, kind: .operation, operationID: $0.id)
            }
            return MenuNode(id: "default.group." + category.rawValue, kind: .group,
                            defaultNameKey: title, iconID: "category." + category.rawValue, children: children)
        }
    }

    private static func category(for operation: OperationRecord) -> CategoryIcon? {
        switch operation.parameters {
        case .template: return .newFile
        case .application: return .applications
        case .transfer: return .send
        case .directory: return .common
        case .image: return .customIcons
        case .tool(let parameters):
            switch parameters.action {
            case .addCommon: return .common
            case .desktopLink, .airDrop: return .send
            default: return CategoryIcon.toolCategory(parameters.action.category)
            }
        case .script, .unknown: return nil
        }
    }
}

enum OperationResolver {
    static func reason(_ op: OperationRecord, configuration: AppConfiguration, allowFileRead: Bool = Bundle.main.bundleURL.pathExtension != "appex") -> String? {
        guard let definition = OperationRegistry.shared.definition(for: op) else { return L("不受当前版本支持") }
        if !allowFileRead {
            guard let preview = configuration.previews[op.id] else { return L("等待操作信息") }
            return preview.available ? nil : preview.reason.map(L) ?? L("操作不可用")
        }
        return definition.validation(op).map(L)
    }
    static func canExecute(_ op: OperationRecord, context: OperationContext, configuration: AppConfiguration, allowFileRead: Bool = Bundle.main.bundleURL.pathExtension != "appex") -> Bool {
        op.enabled && reason(op, configuration: configuration, allowFileRead: allowFileRead) == nil && (OperationRegistry.shared.definition(for: op)?.supports(op, context) ?? false)
    }
}

enum OperationImages {
    static func defaultIconID(for kind: String) -> String? {
        switch kind {
        case "tool": return "category.tools"
        case "template": return "category.newFile"
        case "transfer": return "category.send"
        case "directory": return "category.common"
        case "application": return "category.applications"
        case "image": return "category.customIcons"
        case "script": return "category.scripts"
        default: return nil
        }
    }
    static func source(_ op: OperationRecord, preview: OperationPreview? = nil) -> NSImage? {
        if op.iconID == MenuNodeIcons.hiddenID { return nil }
        if ScriptLanguageIcon.isAutomatic(op), case .script(let path) = op.parameters {
            let language: ScriptLanguage?
            if let preview { language = preview.scriptLanguageID.flatMap(ScriptLanguage.init(rawValue:)) }
            else { language = ScriptLanguage.detect(at: path) }
            return ScriptLanguageIcon.outline(language: language)
        }
        if let id = op.iconID, let image = MenuNodeIcons.catalogImage(id, style: .color) { return image }
        switch op.parameters {
        case .tool(let p): return ToolMenuIcon.image(for: p.action)
        case .template(let p): return FileTemplateIcon.image(for: p.template)
        case .directory(let p): return NSWorkspace.shared.icon(forFile: p)
        case .transfer(let p): return p.target.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .folder)
        case .application(let p): return OperationRegistry.applicationURL(p).flatMap { ApplicationIcon.image(at: $0) }
        case .image(let p):
            if p.remove { return CrabSymbol.image(named: "arrow-back-up") }
            if let id = p.systemID, let definition = SystemIconDefaults.catalog.first(where: { $0.id == id }) { return SystemIconDefaults.nativeImage(for: definition) }
            return p.path.flatMap { NSImage(contentsOfFile: $0) }
        case .script: return CrabSymbol.image(named: "terminal")
        case .unknown: return CrabSymbol.image(named: "help-circle")
        }
    }
    static func image(_ op: OperationRecord, configuration: AppConfiguration, size: CGFloat = 18, allowFileRead: Bool = Bundle.main.bundleURL.pathExtension != "appex") -> NSImage? {
        if op.iconID == MenuNodeIcons.hiddenID { return nil }
        if ScriptLanguageIcon.isAutomatic(op), case .script(let path) = op.parameters {
            let language: ScriptLanguage?
            if let preview = configuration.previews[op.id] { language = preview.scriptLanguageID.flatMap(ScriptLanguage.init(rawValue:)) }
            else { language = allowFileRead ? ScriptLanguage.detect(at: path) : nil }
            return ScriptLanguageIcon.image(language: language, style: configuration.iconStyle, size: size)
        }
        if let id = op.iconID, let image = MenuNodeIcons.catalogImage(id, style: configuration.iconStyle, size: size) { return image }
        let source: NSImage?
        let template: Bool
        switch op.parameters { case .tool, .script: template = true; case .image(let p): template = p.remove; default: template = false }
        if allowFileRead { source = self.source(op) }
        else { source = configuration.previews[op.id]?.data.flatMap { NSImage(data: $0) } }
        // Keep the placeholder separate from native artwork and availability:
        // cached clients only show it after the app is confirmed unavailable.
        if source == nil, case .application = op.parameters,
           allowFileRead || configuration.previews[op.id]?.available == false {
            return ApplicationIcon.unavailableImage(style: configuration.iconStyle, size: size)
        }
        guard let image = source?.copy() as? NSImage else { return nil }
        let scale = size / max(image.size.width, image.size.height)
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale); image.isTemplate = template
        if template && configuration.iconStyle == .color {
            let role: CategoryIcon = op.parameters.kind == "script" ? .scripts : op.parameters.kind == "image" ? .customIcons : .tools
            return role.coloredImage(image, size: size)
        }
        return image
    }
}

enum MenuNodeIcons {
    struct Entry {
        let id: String
        let title: String
    }
    static let hiddenID = "none"
    static var catalog: [Entry] {
        CategoryIcon.allCases.map { Entry(id: "category." + $0.rawValue, title: categoryTitle($0)) }
        + SystemIconDefaults.catalog.map { Entry(id: $0.id, title: L($0.name)) }
        + CrabSymbol.names.map { Entry(id: "crab." + $0, title: L("内置图标") + " · " + $0) }
    }
    static func catalogImage(_ id: String, style: AppIconStyle, size: CGFloat = 18) -> NSImage? {
        if id.hasPrefix("category."), let category = CategoryIcon(rawValue: String(id.dropFirst(9))) {
            return category.image(style: style, size: size)
        }
        if let native = SystemIconDefaults.catalog.first(where: { $0.id == id }), let image = SystemIconDefaults.nativeImage(for: native) {
            image.size = NSSize(width: size, height: size); return image
        }
        guard id.hasPrefix("crab."), let glyph = CrabSymbol.image(named: String(id.dropFirst(5)), size: size) else { return nil }
        return style == .color ? CategoryIcon.general.coloredImage(glyph, size: size) : glyph
    }
    static func image(node: MenuNode, operation: OperationRecord?, configuration: AppConfiguration, size: CGFloat = 18,
                      allowFileRead: Bool = Bundle.main.bundleURL.pathExtension != "appex") -> NSImage? {
        if node.iconID == hiddenID { return nil }
        if let id = node.iconID, let image = catalogImage(id, style: configuration.iconStyle, size: size) { return image }
        if let operation {
            return OperationImages.image(operation, configuration: configuration, size: size, allowFileRead: allowFileRead)
        }
        guard let glyph = CrabSymbol.image(named: "folder", size: size) else { return nil }
        return configuration.iconStyle == .color ? CategoryIcon.general.coloredImage(glyph, size: size) : glyph
    }

    private static func categoryTitle(_ category: CategoryIcon) -> String {
        switch category {
        case .general: return L("通用设置")
        case .newFile: return L("新建文件")
        case .send: return L("发送到")
        case .move: return L("移动到")
        case .common: return L("常用目录")
        case .customIcons: return L("自定义图标")
        case .tools: return L("工具箱")
        case .scripts: return L("自定义脚本")
        case .images: return L("图片转换")
        case .applications: return L("进入 App")
        case .archives: return L("压缩与解压")
        }
    }
}
