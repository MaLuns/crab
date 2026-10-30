import Foundation

struct ApplicationDescriptor: Identifiable, Equatable {
    enum LaunchMethod: Equatable {
        case documents, directory, terminal, iTerm, warp, tabby
    }

    let id: String
    let name: String
    let bundleIdentifiers: [String]
    let applicationNames: [String]
    var launchMethod: LaunchMethod = .documents
    var supportsNewTab: Bool { launchMethod == .terminal || launchMethod == .iTerm }
    var requiresMatchingIdentity: Bool { [.terminal, .iTerm, .warp, .tabby].contains(launchMethod) }
}

enum ApplicationCatalog {
    typealias Entry = ApplicationDescriptor
    static let all: [ApplicationDescriptor] = [
        .init(id: "terminal", name: "Terminal", bundleIdentifiers: ["com.apple.Terminal"], applicationNames: ["Terminal"], launchMethod: .terminal),
        .init(id: "iterm2", name: "iTerm2", bundleIdentifiers: ["com.googlecode.iterm2"], applicationNames: ["iTerm", "iTerm2"], launchMethod: .iTerm),
        .init(id: "vscode", name: "Visual Studio Code", bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], applicationNames: ["Visual Studio Code", "Visual Studio Code - Insiders"]),
        .init(id: "cursor", name: "Cursor", bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"], applicationNames: ["Cursor"]),
        .init(id: "sublimeText", name: "Sublime Text", bundleIdentifiers: [], applicationNames: ["Sublime Text"]),
        .init(id: "sublimeMerge", name: "Sublime Merge", bundleIdentifiers: [], applicationNames: ["Sublime Merge"]),
        .init(id: "warp", name: "Warp", bundleIdentifiers: ["dev.warp.Warp-Stable"], applicationNames: ["Warp"], launchMethod: .warp),
        .init(id: "ghostty", name: "Ghostty", bundleIdentifiers: ["com.mitchellh.ghostty"], applicationNames: ["Ghostty"], launchMethod: .directory),
        .init(id: "markText", name: "MarkText", bundleIdentifiers: [], applicationNames: ["MarkText"]),
        .init(id: "obsidian", name: "Obsidian", bundleIdentifiers: [], applicationNames: ["Obsidian"]),
        .init(id: "tabby", name: "Tabby", bundleIdentifiers: ["org.tabby"], applicationNames: ["Tabby"], launchMethod: .tabby),
        .init(id: "visualStudio", name: "Visual Studio", bundleIdentifiers: ["com.microsoft.visual-studio"], applicationNames: ["Visual Studio"]),
        .init(id: "hyper", name: "Hyper", bundleIdentifiers: ["co.zeit.hyper"], applicationNames: ["Hyper"], launchMethod: .directory),
        .init(id: "emacs", name: "Emacs", bundleIdentifiers: [], applicationNames: ["Emacs"]),
        .init(id: "clion", name: "CLion", bundleIdentifiers: [], applicationNames: ["CLion"]),
        .init(id: "cotEditor", name: "CotEditor", bundleIdentifiers: [], applicationNames: ["CotEditor"]),
        .init(id: "hbuilderX", name: "HBuilderX", bundleIdentifiers: ["io.dcloud.HBuilderX"], applicationNames: ["HBuilderX"]),
        .init(id: "phpstorm", name: "PhpStorm", bundleIdentifiers: [], applicationNames: ["PhpStorm"]),
        .init(id: "pycharm", name: "PyCharm", bundleIdentifiers: [], applicationNames: ["PyCharm", "PyCharm CE", "PyCharm Community Edition"]),
        .init(id: "typora", name: "Typora", bundleIdentifiers: [], applicationNames: ["Typora"]),
        .init(id: "webstorm", name: "WebStorm", bundleIdentifiers: [], applicationNames: ["WebStorm"]),
        .init(id: "intellijIdea", name: "IntelliJ IDEA", bundleIdentifiers: ["com.jetbrains.intellij"], applicationNames: ["IntelliJ IDEA", "IntelliJ IDEA CE", "IntelliJ IDEA Community Edition"]),
        .init(id: "androidStudio", name: "Android Studio", bundleIdentifiers: ["com.google.android.studio"], applicationNames: ["Android Studio"]),
        .init(id: "appCode", name: "AppCode", bundleIdentifiers: [], applicationNames: ["AppCode"]),
        .init(id: "dataGrip", name: "DataGrip", bundleIdentifiers: [], applicationNames: ["DataGrip"]),
        .init(id: "goland", name: "GoLand", bundleIdentifiers: [], applicationNames: ["GoLand"]),
        .init(id: "rider", name: "Rider", bundleIdentifiers: [], applicationNames: ["Rider"]),
        .init(id: "rubyMine", name: "RubyMine", bundleIdentifiers: [], applicationNames: ["RubyMine"])
    ]

    static func application(id: String) -> ApplicationDescriptor? {
        all.first { $0.id == id }
    }

    static func entry(id: String) -> Entry? { application(id: id) }

    static func entry(for applicationURL: URL) -> Entry? {
        guard let identifier = Bundle(url: applicationURL)?.bundleIdentifier else { return nil }
        return all.first { $0.bundleIdentifiers.contains(identifier) }
    }
}
