import AppKit

enum ToolMenuIcon {
    static func image(for action: ToolAction, size: CGFloat = 18) -> NSImage? {
        let name: String
        let fallback: String
        switch action {
        case .fileInfo: name = "info.circle"; fallback = "doc"
        case .makeWritable: name = "lock.open"; fallback = "lock"
        case .trash: name = "trash"; fallback = "doc"
        case .airDrop: name = "airdrop"; fallback = "square.and.arrow.up"
        case .desktopLink: name = "arrowshape.turn.up.right"; fallback = "arrow.up.right"
        case .copyName: name = "doc.text"; fallback = "doc"
        case .newFolderByName: name = "folder.badge.plus"; fallback = "folder"
        case .cut: name = "scissors"; fallback = "doc"
        case .dissolveFolder: name = "folder.badge.minus"; fallback = "folder"
        case .copyPath: name = "link"; fallback = "doc"
        case .hide: name = "eye.slash"; fallback = "eye"
        case .unhide: name = "eye"; fallback = "doc"
        case .showHidden: name = "eye.circle"; fallback = "eye"
        case .hideHidden: name = "eye.slash.circle"; fallback = "eye.slash"
        case .toggleExtension: name = "textformat.abc"; fallback = "doc.text"
        case .repairFilename: name = "character.cursor.ibeam"; fallback = "textformat"
        case .paste: name = "doc.on.clipboard"; fallback = "clipboard"
        case .deletePermanently: name = "trash.slash"; fallback = "trash"
        case .wallpaper: name = "photo.on.rectangle"; fallback = "photo"
        case .addCommon: name = "star"; fallback = "folder"
        case .png, .jpeg, .heic, .webp, .tiff: name = "photo"; fallback = "doc"
        case .icns: name = "app.badge"; fallback = "app"
        case .macIconset: name = "square.grid.2x2"; fallback = "app"
        case .iosIconset: name = "app"; fallback = "photo"
        case .zip, .sevenZip: name = "archivebox"; fallback = "doc.zipper"
        case .unzip: name = "arrow.up.doc"; fallback = "archivebox"
        default:
            guard action.applicationID != nil else { return nil }
            name = ["terminal", "iterm2", "warp", "tabby", "hyper"].contains(action.rawValue) ? "terminal" : "app"
            fallback = "app"
        }
        return symbol(name, fallback: fallback, size: size, description: action.title)
    }

    static func applicationFallback(size: CGFloat = 18) -> NSImage? {
        symbol("app", fallback: "square", size: size, description: L("应用程序"))
    }

    static func image(for action: ToolAction, style: AppIconStyle, size: CGFloat = 18) -> NSImage? {
        guard let outline = image(for: action, size: size) else { return nil }
        guard style == .color else { return outline }
        return (CategoryIcon.toolCategory(action.category) ?? .tools).coloredImage(outline, size: size)
    }

    static func applicationFallback(style: AppIconStyle, size: CGFloat = 18) -> NSImage? {
        guard let outline = applicationFallback(size: size) else { return nil }
        return style == .color ? CategoryIcon.applications.coloredImage(outline, size: size) : outline
    }

    static func categoryImage(for category: String, size: CGFloat = 18) -> NSImage? {
        guard let image = CategoryIcon.toolCategory(category)?.image(size: size) else { return nil }
        image.accessibilityDescription = L(category)
        return image
    }

    static func categoryImage(for category: String, style: AppIconStyle, size: CGFloat = 18) -> NSImage? {
        guard let image = CategoryIcon.toolCategory(category)?.image(style: style, size: size) else { return nil }
        image.accessibilityDescription = L(category)
        return image
    }

    private static func symbol(_ name: String, fallback: String, size: CGFloat, description: String) -> NSImage? {
        guard size.isFinite, size > 0, size <= 2048,
              let source = NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(.preferringMonochrome())
        let configured = source.withSymbolConfiguration(configuration) ?? source
        guard configured.isValid, let result = configured.copy() as? NSImage,
              configured.size.width.isFinite, configured.size.height.isFinite,
              configured.size.width > 0, configured.size.height > 0 else { return nil }
        let scale = size / max(configured.size.width, configured.size.height)
        result.size = NSSize(width: configured.size.width * scale, height: configured.size.height * scale)
        result.isTemplate = true
        result.accessibilityDescription = description
        return result
    }
}
