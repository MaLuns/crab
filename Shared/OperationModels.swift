import AppKit

struct ToolParameters: Codable, Equatable {
    var action: ToolAction
    var hideOriginals = true
    var confirmDeletion = true
    var newTab = false
}
struct TemplateParameters: Codable, Equatable {
    var template: FileTemplate
    var autoOpen = false
    var playSound = true
}
struct TransferParameters: Codable, Equatable {
    var move = false
    var target: String? = nil
}
struct ApplicationParameters: Codable, Equatable {
    var catalogID: String? = nil
    var path: String? = nil
    var newTab = false
}
struct ImageParameters: Codable, Equatable {
    var systemID: String? = nil
    var path: String? = nil
    var remove = false
}
enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
enum OperationParameters: Equatable, Codable {
    case tool(ToolParameters), template(TemplateParameters), transfer(TransferParameters)
    case directory(String), application(ApplicationParameters), image(ImageParameters), script(String)
    case unknown(String, JSONValue)
    var kind: String {
        switch self {
        case .tool: return "tool"
        case .template: return "template"
        case .transfer: return "transfer"
        case .directory: return "directory"
        case .application: return "application"
        case .image: return "image"
        case .script: return "script"
        case .unknown(let kind, _): return kind
        }
    }
    enum CodingKeys: String, CodingKey { case type, value }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        do { switch type {
        case "tool": self = .tool(try c.decode(ToolParameters.self, forKey: .value))
        case "template": self = .template(try c.decode(TemplateParameters.self, forKey: .value))
        case "transfer": self = .transfer(try c.decode(TransferParameters.self, forKey: .value))
        case "directory": self = .directory(try c.decode(String.self, forKey: .value))
        case "application": self = .application(try c.decode(ApplicationParameters.self, forKey: .value))
        case "image": self = .image(try c.decode(ImageParameters.self, forKey: .value))
        case "script": self = .script(try c.decode(String.self, forKey: .value))
        default: self = .unknown(type, try c.decode(JSONValue.self, forKey: .value))
        } } catch { self = .unknown(type, try c.decode(JSONValue.self, forKey: .value)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(kind, forKey: .type)
        switch self {
        case .tool(let v): try c.encode(v, forKey: .value)
        case .template(let v): try c.encode(v, forKey: .value)
        case .transfer(let v): try c.encode(v, forKey: .value)
        case .directory(let v), .script(let v): try c.encode(v, forKey: .value)
        case .application(let v): try c.encode(v, forKey: .value)
        case .image(let v): try c.encode(v, forKey: .value)
        case .unknown(_, let v): try c.encode(v, forKey: .value)
        }
    }
}
struct OperationRecord: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String? = nil
    var enabled = true
    var iconID: String? = nil
    var parameters: OperationParameters
    var isBuiltIn: Bool { OperationRegistry.builtInIDs.contains(id) }
    var displayName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? OperationRegistry.shared.definition(for: self)?.defaultName(self) ?? L("不受当前版本支持") }
    func duplicated() -> OperationRecord { var result = self; result.id = UUID().uuidString; return result }
}
struct MenuNode: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case operation, group }
    var id = UUID().uuidString
    var kind: Kind
    var operationID: String? = nil
    var name: String? = nil
    var defaultNameKey: String? = nil
    var visible = true
    var iconID: String? = nil
    var children: [MenuNode] = []
    static func reference(_ operationID: String) -> MenuNode { MenuNode(kind: .operation, operationID: operationID) }
    func displayName(operation: OperationRecord? = nil) -> String {
        if let name, !name.isEmpty { return name }
        if kind == .group { return L(defaultNameKey ?? "新建分组") }
        return operation?.displayName ?? L("操作引用已失效")
    }
}
struct GeneralPreferences: Codable, Equatable {
    var iconStyle: AppIconStyle = .color
    var windowTheme: WindowTheme = .system
    var monitorExternalDisks = true
    var showStatusItem = true
    var fallbackShortcut = false
    var fallbackModifier: FallbackModifier = .option
    var fallbackMiddleClick = false
    var fallbackThreeFingerTap = false
    var languageCode = ""
}
struct OperationPreview: Codable, Equatable {
    var data: Data? = nil
    var available = true
    var reason: String? = nil
    var scriptLanguageID: String? = nil
}
struct AppConfiguration: Codable, Equatable {
    var version = 1
    var operations = OperationRegistry.defaults()
    var menu: [MenuNode] = []
    var general = GeneralPreferences()
    var previews: [String: OperationPreview] = [:]
    enum CodingKeys: String, CodingKey { case version, operations, menu, general, previews }
    init() { menu = DefaultMenuLayout.nodes(for: operations) }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == 1 else { throw CocoaError(.coderReadCorrupt) }
        operations = try c.decode([OperationRecord].self, forKey: .operations)
        menu = try c.decode([MenuNode].self, forKey: .menu)
        general = try c.decode(GeneralPreferences.self, forKey: .general)
        previews = try c.decodeIfPresent([String: OperationPreview].self, forKey: .previews) ?? [:]
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version); try c.encode(operations, forKey: .operations)
        try c.encode(menu, forKey: .menu); try c.encode(general, forKey: .general)
        if !previews.isEmpty { try c.encode(previews, forKey: .previews) }
    }
    func validate() throws {
        guard Set(operations.map(\.id)).count == operations.count, operations.allSatisfy({ !$0.id.isEmpty }) else { throw CocoaError(.coderInvalidValue) }
        var ids = Set<String>()
        func check(_ nodes: [MenuNode], depth: Int) throws {
            guard depth <= 2 else { throw CocoaError(.coderInvalidValue) }
            for node in nodes {
                guard !node.id.isEmpty, ids.insert(node.id).inserted else { throw CocoaError(.coderInvalidValue) }
                if node.kind == .group {
                    guard depth == 1, node.operationID == nil else { throw CocoaError(.coderInvalidValue) }
                    try check(node.children, depth: depth + 1)
                } else {
                    guard node.children.isEmpty, node.operationID != nil else { throw CocoaError(.coderInvalidValue) }
                }
            }
        }
        try check(menu, depth: 1)
    }
    func referenceCount(_ id: String) -> Int { menu.reduce(0) { $0 + ($1.operationID == id ? 1 : 0) + $1.children.filter { $0.operationID == id }.count } }
    mutating func removeOperations(_ ids: Set<String>) {
        let removable = Set(operations.filter { ids.contains($0.id) && !$0.isBuiltIn }.map(\.id))
        operations.removeAll { removable.contains($0.id) }
        menu.removeAll { $0.operationID.map(removable.contains) ?? false }
        for index in menu.indices { menu[index].children.removeAll { $0.operationID.map(removable.contains) ?? false } }
    }
}
struct ActionRequest: Codable {
    var operationID: String
    var paths: [String]
    var targetDirectory: String?
    var version = 2
    var urls: [URL] { paths.map { URL(fileURLWithPath: $0) } }
    var directoryURL: URL? { targetDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) } }
    func encodedURL() throws -> URL {
        var c = URLComponents(); c.scheme = AppConstants.scheme; c.host = "execute"
        c.queryItems = [URLQueryItem(name: "payload", value: try JSONEncoder().encode(self).base64EncodedString())]
        guard let url = c.url else { throw CocoaError(.coderInvalidValue) }; return url
    }
    static func decode(_ url: URL) throws -> ActionRequest {
        guard url.scheme == AppConstants.scheme, url.host == "execute",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "payload" })?.value,
              let data = Data(base64Encoded: value), data.count < 2_000_000 else { throw CocoaError(.coderReadCorrupt) }
        let request = try JSONDecoder().decode(Self.self, from: data)
        guard request.version == 2, !request.operationID.isEmpty, request.paths.count <= 10000,
              (request.paths + [request.targetDirectory].compactMap { $0 }).allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else { throw CocoaError(.coderReadCorrupt) }
        return request
    }
}

extension AppConfiguration {
    var iconStyle: AppIconStyle { get { general.iconStyle } set { general.iconStyle = newValue } }
    var windowTheme: WindowTheme { get { general.windowTheme } set { general.windowTheme = newValue } }
    var monitorExternalDisks: Bool { get { general.monitorExternalDisks } set { general.monitorExternalDisks = newValue } }
    var showStatusItem: Bool { get { general.showStatusItem } set { general.showStatusItem = newValue } }
    var fallbackShortcut: Bool { get { general.fallbackShortcut } set { general.fallbackShortcut = newValue } }
    var fallbackModifier: FallbackModifier { get { general.fallbackModifier } set { general.fallbackModifier = newValue } }
    var fallbackMiddleClick: Bool { get { general.fallbackMiddleClick } set { general.fallbackMiddleClick = newValue } }
    var fallbackThreeFingerTap: Bool { get { general.fallbackThreeFingerTap } set { general.fallbackThreeFingerTap = newValue } }
    var languageCode: String { get { general.languageCode } set { general.languageCode = newValue } }
}
