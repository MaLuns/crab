import XCTest
@testable import Crab

@MainActor
final class ApplicationLauncherTests: XCTestCase {
    private var root: URL!
    private var application: URL!

    private func fakeApplication(_ name: String, identifier: String) throws -> URL {
        let app = root.appendingPathComponent(name + ".app", isDirectory: true)
        let executable = app.appendingPathComponent("Contents/MacOS/TestEditor")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": identifier, "CFBundleExecutable": "TestEditor"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return app
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ApplicationLauncherTests-" + UUID().uuidString, isDirectory: true)
        application = try fakeApplication("Test Editor", identifier: "dev.crab.launcher-test")
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testCatalogContainsSupportedApplicationsAndNoDuplicateIDs() throws {
        let ids = ["terminal", "iterm2", "vscode", "cursor", "sublimeText", "sublimeMerge", "warp", "ghostty", "markText", "obsidian", "tabby", "visualStudio", "hyper", "emacs", "clion", "cotEditor", "hbuilderX", "phpstorm", "pycharm", "typora", "webstorm", "intellijIdea", "androidStudio", "appCode", "dataGrip", "goland", "rider", "rubyMine"]
        XCTAssertEqual(ApplicationCatalog.all.map(\.id), ids)
        XCTAssertEqual(Set(ApplicationCatalog.all.map(\.id)).count, ids.count)
        XCTAssertNil(ApplicationCatalog.entry(id: "missing"))
        XCTAssertEqual(ApplicationCatalog.all.filter(\.supportsNewTab).map(\.id), ["terminal", "iterm2"])
    }

    func testEveryEditorHasARealOpenDocumentPlanAndExplicitPathWins() throws {
        let file = root.appendingPathComponent("a file 中文.txt")
        try Data("test".utf8).write(to: file)
        let launcher = ApplicationLauncher(lookup: { _ in nil })
        for entry in ApplicationCatalog.all where entry.launchMethod == .documents {
            let plan = try launcher.launchPlan(id: entry.id, urls: [file], directory: root, applicationURL: application)
            XCTAssertEqual(plan.applicationURL, application)
            XCTAssertEqual(plan.documentURLs, [file])
            XCTAssertEqual(plan.strategy, .documents)
            let background = try launcher.launchPlan(id: entry.id, urls: [], directory: root, applicationURL: application)
            XCTAssertEqual(background.documentURLs, [root!])
        }
    }

    func testMissingApplicationAndInvalidConfiguredPathAreExplicitErrors() throws {
        let launcher = ApplicationLauncher(lookup: { _ in nil })
        XCTAssertThrowsError(try launcher.launchPlan(id: "vscode", urls: [], directory: root)) { error in
            XCTAssertTrue(error.localizedDescription.contains("选择"))
        }
        XCTAssertThrowsError(try launcher.launchPlan(id: "vscode", urls: [], directory: root, applicationURL: root))
        XCTAssertThrowsError(try launcher.launchPlan(id: "unknown", urls: [], directory: root, applicationURL: application))
    }

    func testTerminalPlansPreserveNewTabAndUseSelectedFolderOrFileParent() throws {
        let child = root.appendingPathComponent("folder with 'quotes' 和中文", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let file = child.appendingPathComponent("hello.txt")
        try Data().write(to: file)
        let terminal = try fakeApplication("Terminal", identifier: "com.apple.Terminal")
        let iTerm = try fakeApplication("iTerm", identifier: "com.googlecode.iterm2")
        let launcher = ApplicationLauncher(lookup: { $0.id == "terminal" ? terminal : iTerm })
        XCTAssertEqual(try launcher.launchPlan(id: "terminal", urls: [file], directory: root, newTab: true).strategy, .terminal(directory: child, newTab: true))
        XCTAssertEqual(try launcher.launchPlan(id: "iterm2", urls: [child], directory: root, newTab: false).strategy, .iTerm(directory: child, newTab: false))
        XCTAssertThrowsError(try launcher.launchPlan(id: "vscode", urls: [], directory: root, newTab: true))
    }

    func testDirectoryTerminalsReceiveTheSelectedFolderOrFilesParentOnEveryLaunch() async throws {
        let child = root.appendingPathComponent("中文 'quotes' & + # folder", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let file = child.appendingPathComponent("do-not-execute.sh")
        try Data("exit 99".utf8).write(to: file)
        var received: [[URL]] = []
        let launcher = ApplicationLauncher(openHandler: { _, documents in received.append(documents) })
        for id in ["hyper", "ghostty"] {
            for selection in [[child], [file], []] {
                try await launcher.performLaunch(id: id, urls: selection, directory: child, applicationURL: application)
                XCTAssertEqual(received.last, [child], id)
            }
        }
        XCTAssertEqual(received.count, 6, "A running terminal must receive a fresh directory request on every click.")
    }

    func testWarpUsesAnEncodedDirectoryURIAndPreservesTheChosenApplication() async throws {
        let child = root.appendingPathComponent("中文 &+?#%= 'quotes'\nnext", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let warp = try fakeApplication("Warp", identifier: "dev.warp.Warp-Stable")
        var opened: [URL] = []
        let launcher = ApplicationLauncher(openHandler: { app, documents in
            XCTAssertEqual(app, warp)
            opened += documents
        })
        for _ in 0..<2 {
            try await launcher.performLaunch(id: "warp", urls: [child], directory: root, applicationURL: warp)
        }
        XCTAssertEqual(opened.count, 2)
        for url in opened {
            let uri = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(uri.scheme, "warp"); XCTAssertEqual(uri.host, "action"); XCTAssertEqual(uri.path, "/new_window")
            XCTAssertEqual(uri.queryItems, [URLQueryItem(name: "path", value: child.path)])
            XCTAssertFalse(url.absoluteString.contains("+"))
        }
        XCTAssertThrowsError(try launcher.launchPlan(id: "warp", urls: [child], directory: root, applicationURL: application))
    }

    func testTabbyActuallyReceivesOpenAndTheExactSelectedDirectoryWithoutAShell() async throws {
        let child = root.appendingPathComponent("中文 'quotes' $HOME `id`;x\\line\nnext", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let tabby = try fakeApplication("Tabby", identifier: "org.tabby")
        let executable = try XCTUnwrap(Bundle(url: tabby)?.executableURL)
        let script = """
        #!/bin/sh
        printf '%s' "$1" > "$2/received-command"
        printf '%s' "$2" > "$2/received-directory"
        printf '%s' "$PWD" > "$2/received-cwd"
        """
        try Data(script.utf8).write(to: executable)
        let launcher = ApplicationLauncher(openHandler: { _, _ in XCTFail("Tabby requires its bundled command entry.") })
        try await launcher.performLaunch(id: "tabby", urls: [child], directory: root, applicationURL: tabby)
        XCTAssertEqual(try String(contentsOf: child.appendingPathComponent("received-command")), "open")
        XCTAssertEqual(try String(contentsOf: child.appendingPathComponent("received-directory")), child.path)
        let actualCWD = URL(fileURLWithPath: try String(contentsOf: child.appendingPathComponent("received-cwd")))
        XCTAssertEqual(actualCWD.resolvingSymlinksInPath().path, child.resolvingSymlinksInPath().path)
        try Data("#!/bin/sh\nexit 7\n".utf8).write(to: executable)
        do {
            try await launcher.performLaunch(id: "tabby", urls: [child], directory: root, applicationURL: tabby)
            XCTFail("A failed app command must propagate an error.")
        } catch {
            guard let failure = error as? ApplicationLauncher.LaunchError, case .commandFailed("Tabby", 7) = failure else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testManuallyAddedKnownTerminalsUseTheirDirectoryAdapter() throws {
        let ghostty = try fakeApplication("Ghostty", identifier: "com.mitchellh.ghostty")
        let file = root.appendingPathComponent("selected.txt")
        try Data().write(to: file)
        let launcher = ApplicationLauncher()
        let plan = try launcher.customLaunchPlan(applicationURL: ghostty, urls: [file], directory: root)
        XCTAssertEqual(plan.documentURLs, [root!])
        let unknown = try launcher.customLaunchPlan(applicationURL: application, urls: [file], directory: root)
        XCTAssertEqual(unknown.documentURLs, [file])
    }

    func testUnknownApplicationsAreRejectedBeforeLookupOrLaunch() throws {
        var lookedUp = false
        let launcher = ApplicationLauncher(lookup: { _ in lookedUp = true; return self.application })
        for id in ["unknown.application", ""] {
            XCTAssertNil(ApplicationCatalog.entry(id: id))
            XCTAssertNil(ApplicationLauncher.discoverApplicationURL(id: id, applicationURL: application))
            XCTAssertThrowsError(try launcher.launchPlan(id: id, urls: [], directory: root, applicationURL: application)) { error in
                guard let launchError = error as? ApplicationLauncher.LaunchError,
                      case .unknownApplication(let actualID) = launchError else {
                    return XCTFail("Expected unknown application, got \(error)")
                }
                XCTAssertEqual(actualID, id)
            }
        }
        XCTAssertFalse(lookedUp)
    }

    func testMissingSelectedFileFailsBeforeOpeningAnything() throws {
        let launcher = ApplicationLauncher(lookup: { _ in self.application })
        XCTAssertThrowsError(try launcher.launchPlan(id: "vscode", urls: [root.appendingPathComponent("missing")], directory: root))
    }

    func testTerminalCommandAndAppleScriptEscapesPreserveActualUntrustedPath() throws {
        let folder = root.appendingPathComponent("中文 'single' \"double\" $HOME `id`;x\\line\nnext", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let command = ApplicationLauncher.commandForDirectory(folder)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command + "\nexec /bin/pwd -P"]
        let output = Pipe(); process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let actualPath = String(String(decoding: data, as: UTF8.self).dropLast())
        let expectedAttributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        let actualAttributes = try FileManager.default.attributesOfItem(atPath: actualPath)
        XCTAssertEqual(actualAttributes[.systemFileNumber] as? NSNumber, expectedAttributes[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(actualAttributes[.systemNumber] as? NSNumber, expectedAttributes[.systemNumber] as? NSNumber)
        var error: NSDictionary?
        let script = try XCTUnwrap(NSAppleScript(source: "return " + ApplicationLauncher.appleScriptString(command)))
        XCTAssertEqual(script.executeAndReturnError(&error).stringValue, command)
        XCTAssertNil(error)
    }
}
