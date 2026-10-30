import AppKit
import UniformTypeIdentifiers

enum FileTemplateIcon {
    static func image(for template: FileTemplate, allowFileRead: Bool = true,
                      bundle: Bundle = .main) -> NSImage {
        let path = allowFileRead
            ? template.importedPath ?? template.resourceName.flatMap {
                bundle.url(forResource: $0, withExtension: nil)?.path
            } : nil
        let source = path.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: UTType(filenameExtension: template.suffix) ?? .data)
        let image = source.copy() as? NSImage ?? source
        image.isTemplate = false
        return image
    }
}
