import AppKit

enum ApplicationIcon {
    static func discoverApplicationURL(id: String, applicationURL: URL? = nil,
                                       workspace: NSWorkspace = .shared,
                                       lookup: ((ApplicationDescriptor) -> URL?)? = nil) -> URL? {
        guard let descriptor = ApplicationCatalog.entry(id: id) else { return nil }
        let candidate = applicationURL ?? (lookup ?? { descriptor in
            for identifier in descriptor.bundleIdentifiers {
                if let url = workspace.urlForApplication(withBundleIdentifier: identifier) { return url }
            }
            for name in descriptor.applicationNames {
                if let path = workspace.fullPath(forApplication: name) {
                    return URL(fileURLWithPath: path, isDirectory: true)
                }
            }
            return nil
        })(descriptor)
        guard let candidate, let url = validateApplicationURL(candidate) else { return nil }
        if descriptor.requiresMatchingIdentity,
           !descriptor.bundleIdentifiers.contains(Bundle(url: url)?.bundleIdentifier ?? "") { return nil }
        return url
    }

    static func validateApplicationURL(_ url: URL) -> URL? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return url
    }

    static func image(at applicationURL: URL, pointSize: CGFloat = MenuIconPreview.pointSize) -> NSImage? {
        guard let url = validateApplicationURL(applicationURL), pointSize.isFinite, pointSize > 0,
              let image = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage,
              image.isValid else { return nil }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = false
        return image
    }

    static func unavailableImage(style: AppIconStyle, size: CGFloat = 18) -> NSImage? {
        guard let outline = CrabSymbol.image(named: "app-unavailable", size: size) else { return nil }
        let image = style == .color ? CategoryIcon.applications.coloredImage(outline, size: size) : outline
        image?.accessibilityDescription = L("应用不可用")
        return image
    }
}
