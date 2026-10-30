import AppKit

struct OperationUIAdapter {
    let kind: String
    let makeDraft: () -> OperationRecord
    let summary: (OperationRecord) -> String
    let fields: (OperationEditor) -> Void
    var cardHeight: CGFloat = 56
    var makeCardContent: ((OperationRecord, NSRect) -> NSView)? = nil
}
final class OperationUIRegistry {
    static let shared = OperationUIRegistry()
    private let lock = NSLock()
    private var entries: [OperationUIAdapter] = []
    var adapters: [OperationUIAdapter] { lock.lock(); defer { lock.unlock() }; return entries }
    func register(_ adapter: OperationUIAdapter) {
        let entry = OperationUIAdapter(kind: adapter.kind, makeDraft: {
            var draft = adapter.makeDraft()
            if draft.iconID == nil { draft.iconID = OperationImages.defaultIconID(for: draft.parameters.kind) }
            return draft
        }, summary: adapter.summary, fields: adapter.fields, cardHeight: adapter.cardHeight, makeCardContent: adapter.makeCardContent)
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.kind == adapter.kind }; entries.append(entry)
    }
    func adapter(_ kind: String) -> OperationUIAdapter? { adapters.first { $0.kind == kind } }
    init() {
        register(.init(kind: "tool", makeDraft: { .init(parameters: .tool(.init(action: .copyPath))) }, summary: { op in
            guard case .tool(let p) = op.parameters else { return "" }
            if p.action == .cut { return L(p.hideOriginals ? "剪切时隐藏选中的文件" : "剪切时不隐藏选中的文件") }
            if p.action == .deletePermanently { return L(p.confirmDeletion ? "需要再次确认" : "不需要再次确认") }
            return L(p.action.category)
        }, fields: { $0.toolFields() }))
        register(.init(kind: "template", makeDraft: { .init(parameters: .template(.init(template: .init(name: "", suffix: "txt")))) }, summary: {
            guard case .template(let p) = $0.parameters else { return "" }
            return (p.template.suffix.isEmpty ? L("自定义文件格式") : p.template.suffix.uppercased()) + " · " + (p.template.importedPath ?? p.template.resourceName ?? L("内置内容"))
        }, fields: { $0.templateFields() }))
        register(.init(kind: "transfer", makeDraft: { .init(parameters: .transfer(.init())) }, summary: {
            guard case .transfer(let p) = $0.parameters else { return "" }; return L(p.move ? "移动到" : "复制到") + " · " + (p.target ?? L("每次选择目标目录"))
        }, fields: { $0.transferFields() }))
        register(.init(kind: "directory", makeDraft: { .init(parameters: .directory("")) }, summary: {
            guard case .directory(let path) = $0.parameters else { return "" }; return path
        }, fields: { $0.directoryFields() }))
        register(.init(kind: "application", makeDraft: { .init(parameters: .application(.init())) }, summary: {
            guard case .application(let p) = $0.parameters else { return "" }; return (p.path ?? p.catalogID ?? L("请选择应用")) + " · " + L(p.newTab ? "在新标签页里打开" : "在新窗口里打开")
        }, fields: { $0.applicationFields() }))
        register(.init(kind: "image", makeDraft: { .init(parameters: .image(.init())) }, summary: {
            guard case .image(let p) = $0.parameters else { return "" }
            if p.remove { return L("移除自定义图标") }
            if let id = p.systemID { return L(SystemIconDefaults.catalog.first { $0.id == id }?.name ?? "图标不可用") }
            if let path = p.path, let size = MenuIconPreview.dimensions(at: path) { return path + " · \(Int(size.width)) × \(Int(size.height))" }
            return p.path ?? L("请选择图片")
        }, fields: { $0.imageFields() }))
        register(.init(kind: "script", makeDraft: { .init(parameters: .script("")) }, summary: {
            guard case .script(let path) = $0.parameters else { return "" }
            let interpreter = (try? CustomScriptRunner.shared.launchPlan(CustomScript(name: "", path: path), selectedURLs: [], directory: URL(fileURLWithPath: path).deletingLastPathComponent()))
            return path + (interpreter.map { " · " + $0.executableURL.path } ?? "")
        }, fields: { $0.scriptFields() }))
    }
}

struct PreparedOperationImport {
    let records: [OperationRecord]
    let assets: [URL]
    func commit(to store: ConfigurationStore) throws {
        guard store.update({ $0.operations += records }) else {
            discard()
            throw NSError(domain: "Crab", code: 1, userInfo: [NSLocalizedDescriptionKey: store.lastError ?? L("保存失败")])
        }
    }
    func discard() { for url in assets { try? FileManager.default.removeItem(at: url) } }
}
enum OperationFileImport {
    static let kinds = ["template", "transfer", "directory", "application", "image", "script"]
    static func prepare(kind: String, urls: [URL], store: ConfigurationStore) throws -> PreparedOperationImport {
        var assets: [URL] = [], records: [OperationRecord] = []
        do {
            for url in urls {
                guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
                let name = url.deletingPathExtension().lastPathComponent
                let parameters: OperationParameters
                switch kind {
                case "template": parameters = .template(.init(template: .init(name: name, suffix: url.pathExtension, importedPath: url.path)))
                case "transfer": parameters = .transfer(.init(target: url.path))
                case "directory": parameters = .directory(url.path)
                case "application": parameters = .application(.init(path: url.path))
                case "image": parameters = .image(.init(path: url.path))
                case "script": parameters = .script(url.path)
                default: throw CocoaError(.coderInvalidValue)
                }
                let displayName: String
                if kind == "application" {
                    let appName = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? name
                    displayName = LF("进入 %@", appName)
                } else { displayName = ["directory", "transfer"].contains(kind) ? url.lastPathComponent : name }
                var record = OperationRecord(name: displayName, iconID: OperationImages.defaultIconID(for: kind), parameters: parameters)
                if let reason = OperationRegistry.shared.definition(for: record)?.validation(record) {
                    throw NSError(domain: "Crab", code: 1, userInfo: [NSLocalizedDescriptionKey: L(reason)])
                }
                if kind == "template" || kind == "image" {
                    let asset = try store.importAsset(url); assets.append(asset)
                    if case .template(var p) = record.parameters { p.template.importedPath = asset.path; record.parameters = .template(p) }
                    if case .image(var p) = record.parameters { p.path = asset.path; record.parameters = .image(p) }
                }
                records.append(record)
            }
            return PreparedOperationImport(records: records, assets: assets)
        } catch { for asset in assets { try? FileManager.default.removeItem(at: asset) }; throw error }
    }
}
