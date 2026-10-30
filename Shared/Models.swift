import AppKit

enum AppConstants {
    static let scheme = "crab-native"
    static let configChanged = Notification.Name("dev.crab.operations.v1.configurationChanged")
    static let configRequest = Notification.Name("dev.crab.operations.v1.configurationRequest")
    static let localConfigChanged = Notification.Name("Crab.localConfigChanged")
    static let fallbackStatusChanged = Notification.Name("Crab.fallbackStatusChanged")
    static var appGroup: String { Bundle.main.object(forInfoDictionaryKey: "CrabAppGroupIdentifier") as? String ?? "group.dev.crab" }
}

struct FileTemplate: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var suffix: String
    var symbol: String = "doc"
    var contents = ""
    var importedPath: String? = nil
    var resourceName: String? = nil
    static let defaults: [FileTemplate] = [
        .init(id: "custom", name: "自定义创建新文件", suffix: "", symbol: "file-plus"),
        .init(id: "txt", name: "TXT 文本", suffix: "txt", symbol: "doc.text"),
        .init(id: "rtf", name: "RTF 文稿", suffix: "rtf", symbol: "doc.richtext", contents: "{\\rtf1\\ansi\\deff0\\uc1 }"),
        .init(id: "xml", name: "XML", suffix: "xml", symbol: "chevron.left.forwardslash.chevron.right", contents: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root></root>\n"),
        .init(id: "word", name: "Word 文档", suffix: "docx", symbol: "doc.richtext", resourceName: "Blank.docx"),
        .init(id: "excel", name: "Excel 工作簿", suffix: "xlsx", symbol: "tablecells", resourceName: "Blank.xlsx"),
        .init(id: "ppt", name: "PPT", suffix: "pptx", symbol: "presentation", resourceName: "Blank.pptx"),
        .init(id: "wps", name: "WPS 文字", suffix: "wps", symbol: "file-typography", resourceName: "Blank.wps"),
        .init(id: "et", name: "WPS 表格", suffix: "et", symbol: "table", resourceName: "Blank.et"),
        .init(id: "dps", name: "WPS 演示", suffix: "dps", symbol: "presentation", resourceName: "Blank.dps"),
        .init(id: "pages", name: "Pages", suffix: "pages", symbol: "file-typography", resourceName: "Blank.pages"),
        .init(id: "numbers", name: "Numbers", suffix: "numbers", symbol: "chart-bar", resourceName: "Blank.numbers"),
        .init(id: "keynote", name: "Keynote", suffix: "key", symbol: "presentation", resourceName: "Blank.key"),
        .init(id: "ai", name: "AI", suffix: "ai", symbol: "palette", resourceName: "Blank.ai"),
        .init(id: "psd", name: "PSD", suffix: "psd", symbol: "photo", resourceName: "Blank.psd"),
        .init(id: "md", name: "Markdown", suffix: "md", symbol: "text.alignleft"),
        .init(id: "json", name: "JSON", suffix: "json", symbol: "curlybraces", contents: "{\n\n}\n"),
        .init(id: "html", name: "HTML", suffix: "html", symbol: "chevron.left.forwardslash.chevron.right", contents: "<!doctype html>\n<html lang=\"zh-CN\">\n<head><meta charset=\"UTF-8\"><title>文档</title></head>\n<body></body>\n</html>\n"),
        .init(id: "csv", name: "CSV 表格", suffix: "csv", symbol: "tablecells"),
        .init(id: "swift", name: "Swift", suffix: "swift", symbol: "swift", contents: "import Foundation\n")
    ]
}

enum ToolAction: String, Codable, CaseIterable {
    case copyPath, copyName, cut, paste, fileInfo, newFolderByName, dissolveFolder
    case hide, unhide, showHidden, hideHidden, toggleExtension, makeWritable, trash, deletePermanently
    case desktopLink, airDrop, wallpaper, terminal, vscode
    case png, jpeg, heic, tiff, icns, macIconset, iosIconset
    case zip, unzip
    case repairFilename, webp, sevenZip
    case addCommon = "add-common"
    case iterm2, sublimeText, sublimeMerge, warp, markText, obsidian, tabby, visualStudio, hyper, emacs
    case clion, cotEditor, hbuilderX, phpstorm, pycharm, typora, webstorm, intellijIdea, androidStudio
    case appCode, dataGrip, goland, rider, rubyMine
    case cursor, ghostty

    var title: String {
        switch self {
        case .copyPath: return "拷贝路径"
        case .copyName: return "拷贝文件（夹）名称"
        case .cut: return "剪切"
        case .paste: return "粘贴"
        case .fileInfo: return "文件信息与校验"
        case .newFolderByName: return "根据文件名新建文件夹"
        case .dissolveFolder: return "解散文件夹"
        case .hide: return "隐藏已选文件"
        case .unhide: return "取消隐藏已选文件"
        case .showHidden: return "显示隐藏文件"
        case .hideHidden: return "不显示隐藏文件"
        case .toggleExtension: return "隐藏 / 显示文件扩展名"
        case .makeWritable: return "授予选择的文件写入权限"
        case .trash: return "移到废纸篓"
        case .deletePermanently: return "彻底删除"
        case .desktopLink: return "发送快捷方式到桌面"
        case .airDrop: return "隔空投送"
        case .wallpaper: return "设置为墙纸"
        case .terminal: return "进入终端"
        case .vscode: return "进入 VSCode"
        case .png: return "转为 PNG 格式图片"
        case .jpeg: return "转为 JPG 格式图片"
        case .heic: return "转为 HEIC 格式图片"
        case .tiff: return "转为 TIFF 格式图片"
        case .icns: return "转为 ICNS 图标"
        case .macIconset: return "转为 Mac 图标集"
        case .iosIconset: return "转为 iOS 图标集"
        case .zip: return "压缩为 ZIP"
        case .unzip: return "解压归档到独立文件夹"
        case .repairFilename: return "修复乱码文件名"
        case .webp: return "转为 WebP 格式图片"
        case .sevenZip: return "压缩为 7z"
        case .addCommon: return "添加到常用目录"
        default: return "进入 " + (ApplicationCatalog.entry(id: rawValue)?.name ?? rawValue)
        }
    }
    var category: String {
        if applicationID != nil { return "进入 App" }
        switch self {
        case .png, .jpeg, .heic, .webp, .tiff, .icns, .macIconset, .iosIconset: return "图片转换"
        case .terminal, .vscode: return "进入 App"
        case .zip, .sevenZip, .unzip: return "压缩与解压"
        default: return "文件（夹）操作"
        }
    }
    var symbol: String {
        switch self.category {
        case "图片转换": return "photo"
        case "进入 App": return "terminal"
        case "压缩与解压": return "archivebox"
        default: return self == .copyPath ? "link" : "doc.on.doc"
        }
    }
    var applicationID: String? { ApplicationCatalog.entry(id: rawValue) == nil ? nil : rawValue }
    var needsSelection: Bool {
        if applicationID != nil { return false }
        return ![.paste, .showHidden, .hideHidden, .addCommon].contains(self)
    }
    static let displayOrder: [ToolAction] = [
        .fileInfo, .desktopLink, .airDrop, .copyName, .newFolderByName, .cut, .dissolveFolder, .wallpaper,
        .copyPath, .addCommon, .deletePermanently, .makeWritable,
        .showHidden, .hideHidden, .unhide, .hide, .toggleExtension, .repairFilename,
        .webp, .heic, .jpeg, .png, .icns, .macIconset, .iosIconset,
    ] + ApplicationCatalog.all.compactMap { ToolAction(rawValue: $0.id) } + [
        .sevenZip, .zip, .unzip, .paste, .trash, .tiff
    ]
}

enum FallbackModifier: String, Codable, CaseIterable {
    case shift = "Shift", control = "Control", option = "Option", command = "Command"
    var flags: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .command: return .maskCommand
        }
    }
}

struct CustomScript: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var path: String
}

enum MenuIconCategory: String, CaseIterable, Codable {
    case newFile, send, common, customIcons, tools, scripts
}

enum AppIconStyle: String, Codable, CaseIterable {
    case color, monochrome

    var title: String {
        switch self {
        case .color: return L("彩色")
        case .monochrome: return L("纯色")
        }
    }
}

enum WindowTheme: String, Codable, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return L("跟随系统")
        case .light: return L("亮色")
        case .dark: return L("暗色")
        }
    }
}

