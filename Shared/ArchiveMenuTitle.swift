import Foundation

enum ArchiveOutputNaming {
    static func compressionFilename(for urls: [URL], suffix: String) -> String {
        let name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "归档"
        return name + "." + suffix
    }

    static func extractionDirectoryName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "解压文件" : name
    }
}
