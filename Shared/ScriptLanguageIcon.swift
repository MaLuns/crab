import AppKit
import Darwin

enum ScriptLanguage: String, CaseIterable {
    case shell, python, javascript, typescript, ruby, perl, php, lua, swift, applescript

    var title: String {
        switch self {
        case .shell: return "Shell"
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .ruby: return "Ruby"
        case .perl: return "Perl"
        case .php: return "PHP"
        case .lua: return "Lua"
        case .swift: return "Swift"
        case .applescript: return "AppleScript"
        }
    }

    var symbol: String {
        switch self {
        case .shell: return "script-shell"
        case .perl: return "script-perl"
        case .applescript: return "script-applescript"
        default: return "brand-" + rawValue
        }
    }

    var color: NSColor {
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .shell: rgb = (0.17, 0.48, 0.36)
        case .python: rgb = (0.19, 0.43, 0.67)
        case .javascript: rgb = (0.62, 0.45, 0.04)
        case .typescript: rgb = (0.16, 0.45, 0.73)
        case .ruby: rgb = (0.73, 0.18, 0.24)
        case .perl: rgb = (0.43, 0.32, 0.65)
        case .php: rgb = (0.39, 0.43, 0.67)
        case .lua: rgb = (0.20, 0.29, 0.65)
        case .swift: rgb = (0.81, 0.28, 0.10)
        case .applescript: rgb = (0.36, 0.43, 0.51)
        }
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    // Inspect a bounded header only. Nonblocking open plus fstat keeps a pipe or
    // device (including a replaced symlink target) from blocking icon preparation.
    static func detect(at path: String) -> ScriptLanguage? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let descriptor = path.withCString { Darwin.open($0, O_RDONLY | O_NONBLOCK) }
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { return nil }
        do { return detect(path: path, header: try handle.read(upToCount: 4096) ?? Data()) }
        catch { return nil }
    }

    static func detect(path: String, header: Data) -> ScriptLanguage? {
        guard header.starts(with: [0x23, 0x21]) else { return suffixLanguage(path) }
        let bytes = header.prefix(4096).prefix { $0 != 0x0a }
        guard bytes.count < 4096, let firstLine = String(data: bytes, encoding: .utf8),
              !firstLine.contains("\0") else { return nil }
        let line = firstLine.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
        var tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let executable = tokens.first, executable.hasPrefix("/") else { return nil }
        if executable == "/usr/bin/env" {
            tokens.removeFirst()
            if tokens.first == "-S" { tokens.removeFirst() }
            guard let runtime = tokens.first, !runtime.hasPrefix("-"), !runtime.hasPrefix("#"),
                  !runtime.contains(where: { "'\"\\$=\0".contains($0) }),
                  runtime.hasPrefix("/") || !runtime.contains("/") else { return nil }
        }
        guard let runtime = tokens.first else { return nil }
        let name = URL(fileURLWithPath: runtime).lastPathComponent
        switch name {
        case "sh", "bash", "zsh", "fish", "ksh", "dash": return .shell
        case "node", "nodejs", "jsc": return .javascript
        case "deno", "bun": return suffixLanguage(path) == .typescript ? .typescript : .javascript
        case "ts-node", "tsx": return .typescript
        case "swift": return .swift
        case "osascript":
            if let index = tokens.firstIndex(of: "-l"), tokens.indices.contains(index + 1) {
                switch tokens[index + 1].lowercased() {
                case "javascript": return .javascript
                case "applescript": return .applescript
                default: return nil
                }
            }
            return .applescript
        case "luajit": return .lua
        default:
            for (base, language): (String, ScriptLanguage) in [("python", .python), ("ruby", .ruby), ("perl", .perl), ("php", .php), ("lua", .lua)] {
                if name == base { return language }
                if name.hasPrefix(base) {
                    let version = name.dropFirst(base.count).split(separator: ".", omittingEmptySubsequences: false)
                    if !version.isEmpty, version.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) { return language }
                }
            }
            return nil
        }
    }

    private static func suffixLanguage(_ path: String) -> ScriptLanguage? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "sh", "bash", "zsh", "fish", "ksh", "command": return .shell
        case "py", "pyw": return .python
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "mts", "cts", "tsx": return .typescript
        case "rb": return .ruby
        case "pl", "pm": return .perl
        case "php": return .php
        case "lua": return .lua
        case "swift": return .swift
        case "applescript", "scpt": return .applescript
        default: return nil
        }
    }
}

enum ScriptLanguageIcon {
    static func isAutomatic(_ operation: OperationRecord) -> Bool {
        guard case .script = operation.parameters else { return false }
        return operation.iconID == nil || operation.iconID == "category.scripts"
    }

    static func outline(language: ScriptLanguage?, size: CGFloat = 18) -> NSImage? {
        guard let language else { return CategoryIcon.scripts.image(size: size) }
        let image = CrabSymbol.image(named: language.symbol, size: size)
        image?.accessibilityDescription = language.title
        return image
    }

    static func image(language: ScriptLanguage?, style: AppIconStyle, size: CGFloat = 18) -> NSImage? {
        guard let language else { return CategoryIcon.scripts.image(style: style, size: size) }
        guard let outline = outline(language: language, size: size) else { return nil }
        return style == .color ? CategoryIcon.scripts.coloredImage(outline, size: size, color: language.color) : outline
    }
}
