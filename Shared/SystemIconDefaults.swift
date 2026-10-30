import AppKit
import CoreServices
import UniformTypeIdentifiers

enum SystemIconDefaults {
    struct Definition {
        let id: String
        let name: String
        let symbol: String
        fileprivate let source: Source
    }

    fileprivate enum Source {
        case type(UTType)
        case iconType(OSType)
        case named(NSImage.Name)
    }

    static let catalog: [Definition] = [
        .init(id: "system.icon.folder", name: "文件夹", symbol: "folder", source: .type(.folder)),
        .init(id: "system.icon.file", name: "文件", symbol: "file", source: .type(.data)),
        .init(id: "system.icon.application", name: "应用程序", symbol: "apps", source: .iconType(OSType(kGenericApplicationIcon))),
        .init(id: "system.icon.desktop", name: "桌面", symbol: "device-desktop", source: .iconType(OSType(kToolbarDesktopFolderIcon))),
        .init(id: "system.icon.documents", name: "文稿", symbol: "file-text", source: .iconType(OSType(kDocumentsFolderIcon))),
        .init(id: "system.icon.downloads", name: "下载", symbol: "download", source: .iconType(OSType(kToolbarDownloadsFolderIcon))),
        .init(id: "system.icon.pictures", name: "图片", symbol: "photo", source: .iconType(OSType(kToolbarPicturesFolderIcon))),
        .init(id: "system.icon.music", name: "音乐", symbol: "music", source: .iconType(OSType(kToolbarMusicFolderIcon))),
        .init(id: "system.icon.movies", name: "影片", symbol: "video", source: .iconType(OSType(kToolbarMovieFolderIcon))),
        .init(id: "system.icon.computer", name: "电脑", symbol: "device-desktop", source: .named(NSImage.computerName))
    ]

    static func nativeImage(for definition: Definition) -> NSImage? {
        let image: NSImage?
        switch definition.source {
        case .type(let type): image = NSWorkspace.shared.icon(for: type)
        case .iconType(let code):
            image = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(code))
        case .named(let name): image = NSImage(named: name)
        }
        guard let image, image.isValid, image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0,
              let copy = image.copy() as? NSImage else { return nil }
        copy.isTemplate = false
        return copy
    }

}
