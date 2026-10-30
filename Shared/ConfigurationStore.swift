import AppKit

final class ConfigurationStore {
    static let shared = ConfigurationStore()
    private let fileURL: URL
    private var observer: NSObjectProtocol?
    private let notificationName: Notification.Name?
    private let cacheReceivedConfiguration: Bool
    private var unreadable = false
    private var generation = 0
    private(set) var configuration: AppConfiguration
    var lastError: String?

    init(directory: URL? = nil, notificationName: Notification.Name? = nil,
         cacheReceivedConfiguration: Bool? = nil) {
        self.cacheReceivedConfiguration = cacheReceivedConfiguration ?? (Bundle.main.bundleURL.pathExtension == "appex")
        self.notificationName = notificationName ?? (directory == nil ? AppConstants.configChanged : nil)
        let manager = FileManager.default
        let group = directory == nil && !AppConstants.appGroup.isEmpty ? manager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup) : nil
        let base = directory ?? group?.appendingPathComponent("Library/Application Support/Crab", isDirectory: true)
            ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Crab", isDirectory: true)
        fileURL = base.appendingPathComponent(self.cacheReceivedConfiguration ? "finder-operations-v1.json" : "operations-v1.json")
        configuration = AppConfiguration()
        if manager.fileExists(atPath: fileURL.path) {
            do { configuration = try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: fileURL)) }
            catch {
                configuration.menu = []
                unreadable = true; lastError = error.localizedDescription
            }
        }
        if !self.cacheReceivedConfiguration { configuration.previews = [:] }
        if let channel = self.notificationName {
            observer = DistributedNotificationCenter.default().addObserver(forName: channel, object: nil, queue: .main) { [weak self] note in
                guard let self, self.cacheReceivedConfiguration, let json = note.object as? String, let data = json.data(using: .utf8),
                      let value = try? JSONDecoder().decode(AppConfiguration.self, from: data) else { return }
                do {
                    try self.persist(value); self.configuration = value; self.lastError = nil
                    NotificationCenter.default.post(name: AppConstants.localConfigChanged, object: self)
                } catch { self.lastError = error.localizedDescription }
            }
        }
    }
    deinit { if let observer { DistributedNotificationCenter.default().removeObserver(observer) } }
    @discardableResult func update(_ change: (inout AppConfiguration) -> Void) -> Bool {
        guard !unreadable else { return false }
        var next = configuration; change(&next)
        do {
            try next.validate(); try persist(next)
            configuration = next; lastError = nil
            broadcast(); NotificationCenter.default.post(name: AppConstants.localConfigChanged, object: self)
            return true
        } catch { lastError = error.localizedDescription; return false }
    }
    @discardableResult func replace(_ config: AppConfiguration) -> Bool { update { $0 = config } }
    func broadcast() {
        guard let notificationName, !cacheReceivedConfiguration, !unreadable else { return }
        generation += 1
        let expected = generation, snapshot = configuration
        Self.prepareAsync(snapshot) { [weak self] prepared in
            guard let self, self.generation == expected,
                  let data = try? JSONEncoder().encode(prepared), let json = String(data: data, encoding: .utf8) else { return }
            DistributedNotificationCenter.default().postNotificationName(notificationName, object: json, userInfo: nil, deliverImmediately: true)
        }
    }
    static func prepareAsync(_ config: AppConfiguration, isCancelled: @escaping () -> Bool = { false }, completion: @escaping (AppConfiguration) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var statuses: [String: OperationPreview] = [:]
            for op in config.operations {
                let definition = OperationRegistry.shared.definition(for: op)
                let reason = definition?.validation(op) ?? (definition == nil ? L("不受当前版本支持") : nil)
                var data: Data?
                if case .image(let p) = op.parameters, let path = p.path { data = MenuIconPreview.thumbnail(at: path) }
                let language: ScriptLanguage?
                if ScriptLanguageIcon.isAutomatic(op), case .script(let path) = op.parameters { language = ScriptLanguage.detect(at: path) }
                else { language = nil }
                statuses[op.id] = OperationPreview(data: data, available: reason == nil, reason: reason, scriptLanguageID: language?.rawValue)
            }
            DispatchQueue.main.async {
                var result = config; result.previews = statuses
                func batch(_ start: Int) {
                    guard !isCancelled() else { return }
                    let end = min(start + 6, config.operations.count)
                    if start < end {
                        for op in config.operations[start..<end] {
                            let preview = result.previews[op.id]
                            if preview?.data == nil {
                                let data = OperationImages.source(op, preview: preview).flatMap { MenuIconPreview.pngData(from: $0) }
                                result.previews[op.id]?.data = data
                            }
                        }
                    }
                    if end == config.operations.count { completion(result) }
                    else { DispatchQueue.main.async { batch(end) } }
                }
                batch(0)
            }
        }
    }
    static func prepare(_ config: AppConfiguration) -> AppConfiguration {
        var result = config; result.previews = [:]
        for operation in config.operations {
            let reason = OperationRegistry.shared.definition(for: operation)?.validation(operation) ?? (OperationRegistry.shared.definition(for: operation) == nil ? L("不受当前版本支持") : nil)
            let language: ScriptLanguage?
            if ScriptLanguageIcon.isAutomatic(operation), case .script(let path) = operation.parameters { language = ScriptLanguage.detect(at: path) }
            else { language = nil }
            var preview = OperationPreview(available: reason == nil, reason: reason, scriptLanguageID: language?.rawValue)
            preview.data = OperationImages.source(operation, preview: preview).flatMap { MenuIconPreview.pngData(from: $0) }
            result.previews[operation.id] = preview
        }
        return result
    }
    private func persist(_ next: AppConfiguration) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var output = next
        if !cacheReceivedConfiguration { output.previews = [:] }
        try JSONEncoder().encode(output).write(to: fileURL, options: .atomic)
    }
    var assetsDirectory: URL { fileURL.deletingLastPathComponent().appendingPathComponent("OperationAssets-v1", isDirectory: true) }
    func importAsset(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        let destination = assetsDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination); return destination
    }
}
