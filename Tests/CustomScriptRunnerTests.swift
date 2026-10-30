import XCTest
import Darwin
@testable import Crab

final class CustomScriptRunnerTests: XCTestCase {
    private var root: URL!
    private var bin: URL!
    private var runner: CustomScriptRunner!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CustomScriptRunnerTests-" + UUID().uuidString, isDirectory: true)
        bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        runner = CustomScriptRunner(baseEnvironment: ["PATH": bin.path, "PARENT_MARKER": "preserved"])
    }

    override func tearDownWithError() throws {
        XCTAssertTrue(waitUntil { self.runner.runningProcessCount == 0 }, "Fixture processes must finish before removing their directory")
        runner = nil
        try FileManager.default.removeItem(at: root)
    }

    private func script(_ name: String = "fixture.sh", contents: String = "#!/bin/sh\nexit 0\n") throws -> CustomScript {
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return CustomScript(name: name, path: url.path)
    }

    private func installRuntime(_ name: String) throws -> URL {
        let url = bin.appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
        return url
    }

    private func waitUntil(timeout: TimeInterval = 5, _ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if predicate() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < deadline
        return predicate()
    }

    private func text(_ name: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    func testContextPreservesPathsAsJSONAndDoesNotRequireSelectedFilesToExist() throws {
        let item = try script()
        let selection = [root.appendingPathComponent("中文 'quotes' $HOME `id`;x\\line\nnext"), root.appendingPathComponent("missing.txt")]
        let plan = try runner.launchPlan(item, selectedURLs: selection, directory: root)
        XCTAssertEqual(plan.environment["PARENT_MARKER"], "preserved")
        XCTAssertEqual(plan.environment["CRAB_DIRECTORY"], root.path)
        XCTAssertEqual(plan.environment["CRAB_SELECTED_COUNT"], "2")
        let json = try XCTUnwrap(plan.environment["CRAB_SELECTED_PATHS_JSON"]?.data(using: .utf8))
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: json), selection.map(\.path))
        XCTAssertNil(plan.environment["CRAB_SCRIPT_PATH"])
        XCTAssertEqual(plan.directoryURL, root)
        XCTAssertEqual(plan.arguments, [item.path])
    }

    func testEmptySelectionAndExistingCrabVariablesAreOverriddenOnlyInChildEnvironment() throws {
        let base = ["CRAB_DIRECTORY": "old", "CRAB_SELECTED_COUNT": "9", "CRAB_SELECTED_PATHS_JSON": "old"]
        let isolated = CustomScriptRunner(baseEnvironment: base)
        let plan = try isolated.launchPlan(script(), selectedURLs: [], directory: root)
        XCTAssertEqual(plan.environment["CRAB_DIRECTORY"], root.path)
        XCTAssertEqual(plan.environment["CRAB_SELECTED_COUNT"], "0")
        XCTAssertEqual(plan.environment["CRAB_SELECTED_PATHS_JSON"], "[]")
        XCTAssertEqual(base["CRAB_SELECTED_COUNT"], "9")
    }

    func testShebangWinsOverSuffixAndPreservesDarwinArguments() throws {
        let item = try script("has-python-suffix.py", contents: "#!/bin/sh -e -u\nexit 0\n")
        let plan = try runner.launchPlan(item, selectedURLs: [], directory: root)
        XCTAssertEqual(plan.executableURL.path, "/bin/sh")
        XCTAssertEqual(plan.arguments, ["-e", "-u", item.path])
        let permissions = try FileManager.default.attributesOfItem(atPath: item.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testCommonSuffixFallbacksUseInjectedPathWithoutInstalledLanguageDependencies() throws {
        for name in ["python3", "node", "ruby", "perl"] { _ = try installRuntime(name) }
        let suffixes = ["sh": "/bin/sh", "bash": "/bin/bash", "zsh": "/bin/zsh",
                        "py": bin.appendingPathComponent("python3").path,
                        "js": bin.appendingPathComponent("node").path,
                        "mjs": bin.appendingPathComponent("node").path,
                        "cjs": bin.appendingPathComponent("node").path,
                        "rb": bin.appendingPathComponent("ruby").path,
                        "pl": bin.appendingPathComponent("perl").path]
        for (suffix, executable) in suffixes {
            let item = try script("fallback." + suffix, contents: "exit 0\n")
            let plan = try runner.launchPlan(item, selectedURLs: [], directory: root)
            XCTAssertEqual(plan.executableURL.path, executable)
            XCTAssertEqual(plan.arguments, [item.path])
        }
        XCTAssertThrowsError(try runner.launchPlan(script("unknown.data", contents: "exit 0\n"), selectedURLs: [], directory: root))
    }

    func testSimpleEnvShebangChecksRuntimeAndKeepsEnvAsExecutable() throws {
        _ = try installRuntime("crab-test-sh")
        let item = try script("env.data", contents: "#!/usr/bin/env crab-test-sh -e\nexit 0\n")
        let plan = try runner.launchPlan(item, selectedURLs: [], directory: root)
        XCTAssertEqual(plan.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(plan.arguments, ["crab-test-sh", "-e", item.path])
    }

    func testEnvSplitStringIsPassedAsOneArgumentWithoutReparsingQuotedOptions() throws {
        _ = try installRuntime("crab-test-sh")
        let splitString = "crab-test-sh -e -c 'printf \"quoted value\"'"
        let item = try script("env-split.data", contents: "#!/usr/bin/env -S " + splitString + "\n")
        let plan = try runner.launchPlan(item, selectedURLs: [], directory: root)
        XCTAssertEqual(plan.arguments, ["-S", splitString, item.path])
    }

    func testMissingEnvRuntimeFailsDuringPlanningInsteadOfStartingEnvAndIgnoringExit127() throws {
        let missing = "crab-missing-runtime-" + UUID().uuidString
        for suffix in [missing, "-S " + missing + " -e"] {
            let item = try script(contents: "#!/usr/bin/env " + suffix + "\n")
            XCTAssertThrowsError(try runner.launchPlan(item, selectedURLs: [], directory: root)) { error in
                guard let failure = error as? CustomScriptRunner.LaunchError, case .missingInterpreter(let name) = failure else {
                    return XCTFail("Expected a missing interpreter, got \(error)")
                }
                XCTAssertEqual(name, missing)
            }
        }
    }

    func testUnsupportedEnvCombinationsDoNotFallBackToShSuffix() throws {
        for suffix in ["-i sh", "PATH=/bin sh", "-S '$RUNTIME' -e", "-S \"sh\" -e", "-S ./sh -e", "-S"] {
            let item = try script(contents: "#!/usr/bin/env " + suffix + "\nexit 0\n")
            XCTAssertThrowsError(try runner.launchPlan(item, selectedURLs: [], directory: root)) { error in
                guard let failure = error as? CustomScriptRunner.LaunchError, case .unrecognizedInterpreter = failure else {
                    return XCTFail("Expected an unrecognized interpreter, got \(error)")
                }
            }
        }
    }

    func testInvalidAndMissingShebangInterpretersDoNotUseSuffixFallback() throws {
        for header in ["#!\n", "#!relative-sh\n", "#!/crab-missing/sh\n", "#!" + String(repeating: "x", count: 5000) + "\n"] {
            XCTAssertThrowsError(try runner.launchPlan(script(contents: header + "exit 0\n"), selectedURLs: [], directory: root))
        }
    }

    func testHeaderReadingIgnoresNonUTF8BodyAndAcceptsCRLF() throws {
        let item = try script("binary-body.data", contents: "#!/bin/sh -e\r\n")
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: item.path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xff, 0xfe, 0x00]))
        try handle.close()
        let plan = try runner.launchPlan(item, selectedURLs: [], directory: root)
        XCTAssertEqual(plan.executableURL.path, "/bin/sh")
        XCTAssertEqual(plan.arguments, ["-e", item.path])
    }

    func testEffectivePathPreservesInheritedOrderAndAddsCommonLocations() throws {
        let plan = try runner.launchPlan(script(), selectedURLs: [], directory: root)
        let components = try XCTUnwrap(plan.environment["PATH"]).components(separatedBy: ":")
        XCTAssertEqual(components.first, bin.path)
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            XCTAssertTrue(components.contains(path))
        }
        let localRuntime = root.appendingPathComponent("crab-local-sh")
        try FileManager.default.createSymbolicLink(at: localRuntime, withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
        let local = CustomScriptRunner(baseEnvironment: ["PATH": ""])
        let item = try script(contents: "#!/usr/bin/env crab-local-sh\n")
        XCTAssertNoThrow(try local.launchPlan(item, selectedURLs: [], directory: root))
    }

    func testOriginalScriptSymlinkIsPreservedAndInterpreterSymlinksAreAccepted() throws {
        let runtime = try installRuntime("crab-linked-sh")
        let original = try script("original.data", contents: "#!" + runtime.path + "\nexit 0\n")
        let alias = root.appendingPathComponent("linked.data")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: URL(fileURLWithPath: original.path))
        let plan = try runner.launchPlan(CustomScript(name: "alias", path: alias.path), selectedURLs: [], directory: root)
        XCTAssertEqual(plan.executableURL, runtime)
        XCTAssertEqual(plan.arguments, [alias.path])
    }

    func testMissingFilesInvalidDirectoryAndInvalidEnvironmentFailBeforeLaunch() throws {
        let item = try script()
        XCTAssertThrowsError(try runner.launchPlan(CustomScript(name: "missing", path: root.appendingPathComponent("missing.sh").path), selectedURLs: [], directory: root))
        XCTAssertThrowsError(try runner.launchPlan(CustomScript(name: "directory", path: root.path), selectedURLs: [], directory: root))
        XCTAssertThrowsError(try runner.launchPlan(item, selectedURLs: [], directory: URL(fileURLWithPath: item.path)))
        XCTAssertThrowsError(try runner.launchPlan(item, selectedURLs: [URL(string: "https://example.com/file")!], directory: root))
        for environment in [["BROKEN": "a\0b"], ["BAD=KEY": "value"]] {
            let invalid = CustomScriptRunner(baseEnvironment: environment)
            XCTAssertThrowsError(try invalid.launchPlan(item, selectedURLs: [], directory: root))
        }
        XCTAssertEqual(runner.runningProcessCount, 0)
    }

    func testOversizedContextIsRejectedWithoutTruncatingTheSelection() throws {
        let item = try script()
        let systemLimit = sysconf(_SC_ARG_MAX)
        let limit = systemLimit > 0 ? Int(systemLimit) : 262_144
        let oversized = CustomScriptRunner(baseEnvironment: ["TOO_LARGE": String(repeating: "x", count: limit + 1024)])
        XCTAssertThrowsError(try oversized.launchPlan(item, selectedURLs: [], directory: root)) { error in
            guard let failure = error as? CustomScriptRunner.LaunchError, case .oversizedEnvironment = failure else {
                return XCTFail("Expected an oversized environment, got \(error)")
            }
        }
        let selections = (0..<(limit / 1000 + 1)).map { root.appendingPathComponent(String(repeating: "x", count: 1000) + String($0)) }
        XCTAssertGreaterThan(try JSONEncoder().encode(selections.map(\.path)).count, limit)
        XCTAssertThrowsError(try runner.launchPlan(item, selectedURLs: selections, directory: root))
    }

    func testLaunchReadsNonExecutableOriginalFileWithExactContextAndEOFInput() throws {
        let item = try script("原始 'quotes' $HOME `id`;\\line\nscript.data", contents: """
        #!/bin/sh
        if IFS= read -r unexpected; then exit 20; fi
        printf '%s' "$CRAB_SELECTED_PATHS_JSON" > "$CRAB_DIRECTORY/context.json"
        printf '%s' "$PWD" > "$CRAB_DIRECTORY/working-directory"
        printf '%s' "$0" > "$CRAB_DIRECTORY/script-path"
        printf '%s' "$CRAB_SELECTED_COUNT" > "$CRAB_DIRECTORY/count"
        """)
        let selection = [root.appendingPathComponent("missing 'quoted' \"double\" $HOME `id` ;\n中文")]
        try runner.launch(item, selectedURLs: selection, directory: root)
        XCTAssertTrue(waitUntil { self.text("count") == "1" })
        let encoded = try XCTUnwrap(text("context.json")?.data(using: .utf8))
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: encoded), selection.map(\.path))
        let workingDirectory = URL(fileURLWithPath: try XCTUnwrap(text("working-directory")), isDirectory: true)
        XCTAssertEqual(workingDirectory.resolvingSymlinksInPath(), root.resolvingSymlinksInPath())
        XCTAssertEqual(text("script-path"), item.path)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: item.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testLaunchReturnsBeforeScriptFinishesAndLatestOriginalContentsAreUsed() throws {
        let item = try script(contents: """
        #!/bin/sh
        i=0
        while [ ! -f "$CRAB_DIRECTORY/release" ] && [ "$i" -lt 200 ]; do
            /bin/sleep 0.01
            i=$((i + 1))
        done
        [ -f "$CRAB_DIRECTORY/release" ] || exit 21
        printf first > "$CRAB_DIRECTORY/version"
        """)
        try runner.launch(item, selectedURLs: [], directory: root)
        XCTAssertGreaterThan(runner.runningProcessCount, 0)
        try Data().write(to: root.appendingPathComponent("release"))
        XCTAssertTrue(waitUntil { self.text("version") == "first" })
        XCTAssertTrue(waitUntil { self.runner.runningProcessCount == 0 })
        try Data("#!/bin/bash\nprintf second > \"$CRAB_DIRECTORY/version\"\nexit 7\n".utf8).write(to: URL(fileURLWithPath: item.path))
        XCTAssertEqual(try runner.launchPlan(item, selectedURLs: [], directory: root).executableURL.path, "/bin/bash")
        XCTAssertNoThrow(try runner.launch(item, selectedURLs: [], directory: root))
        XCTAssertTrue(waitUntil { self.text("version") == "second" })
    }

    func testStdoutAndStderrLargerThanPipeCapacityAreDiscardedWithoutBlocking() throws {
        let item = try script(contents: """
        #!/bin/sh
        /usr/bin/head -c 2097152 /dev/zero
        /usr/bin/head -c 2097152 /dev/zero >&2
        printf done > "$CRAB_DIRECTORY/output-finished"
        """)
        try runner.launch(item, selectedURLs: [], directory: root)
        XCTAssertTrue(waitUntil { self.text("output-finished") == "done" })
    }

    func testRepeatedClicksStartIndependentProcessesAndReleaseAllRegistryEntries() throws {
        _ = try installRuntime("crab-test-sh")
        let item = try script(contents: """
        #!/usr/bin/env -S crab-test-sh -e
        /bin/sleep 0.02
        printf '%s' "$CRAB_SELECTED_COUNT" > "$CRAB_DIRECTORY/run-$$"
        """)
        for _ in 0..<8 { try runner.launch(item, selectedURLs: [], directory: root) }
        XCTAssertTrue(waitUntil { self.runner.runningProcessCount == 0 })
        let outputs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("run-") }
        XCTAssertEqual(outputs.count, 8)
        for output in outputs { XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "0") }
    }

    func testSuccessfulExitDoesNotReportFailure() throws {
        let unexpected = expectation(description: "Successful scripts stay silent")
        unexpected.isInverted = true
        let item = try script(contents: "#!/bin/sh\nprintf output\nprintf error >&2\nexit 0\n")
        try runner.launch(item, selectedURLs: [], directory: root) { _ in unexpected.fulfill() }
        XCTAssertTrue(waitUntil { self.runner.runningProcessCount == 0 })
        wait(for: [unexpected], timeout: 0.2)
    }

    func testNonZeroExitReportsItsScriptAndExitCodeOnMainThreadAfterReleasingProcess() throws {
        let reported = expectation(description: "Nonzero exit is reported")
        reported.assertForOverFulfill = true
        let item = try script("失败 %d 'quoted'.sh", contents: "#!/bin/sh\nexit 23\n")
        try runner.launch(item, selectedURLs: [], directory: root) { error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(error as? CustomScriptRunner.ExecutionError, .nonZeroExit(scriptName: item.name, status: 23))
            XCTAssertEqual(self.runner.runningProcessCount, 0)
            reported.fulfill()
        }
        wait(for: [reported], timeout: 5)
    }

    func testSignalTerminationReportsTheSignalOnMainThread() throws {
        let reported = expectation(description: "Signal termination is reported")
        reported.assertForOverFulfill = true
        let item = try script("signal.sh", contents: "#!/bin/sh\nkill -KILL $$\n")
        try runner.launch(item, selectedURLs: [], directory: root) { error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(error as? CustomScriptRunner.ExecutionError, .terminatedBySignal(scriptName: item.name, signal: SIGKILL))
            XCTAssertEqual(self.runner.runningProcessCount, 0)
            reported.fulfill()
        }
        wait(for: [reported], timeout: 5)
    }

    func testConcurrentFailuresKeepTheirOwnCallbackAndReportEachProcessOnce() throws {
        let reported = expectation(description: "Each failed script is reported")
        reported.expectedFulfillmentCount = 8
        reported.assertForOverFulfill = true
        let duplicate = expectation(description: "A process must not report failure twice")
        duplicate.isInverted = true
        var reports: [String: Int32] = [:]
        var expected: [String: Int32] = [:]
        for index in 0..<8 {
            let status = Int32(index + 11)
            let item = try script("failure-\(index).sh", contents: "#!/bin/sh\n/bin/sleep 0.02\nexit \(status)\n")
            expected[item.name] = status
            try runner.launch(item, selectedURLs: [], directory: root) { error in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(error as? CustomScriptRunner.ExecutionError, .nonZeroExit(scriptName: item.name, status: status))
                guard reports.updateValue(status, forKey: item.name) == nil else {
                    duplicate.fulfill()
                    return
                }
                reported.fulfill()
            }
        }
        wait(for: [reported], timeout: 5)
        XCTAssertTrue(waitUntil { self.runner.runningProcessCount == 0 })
        wait(for: [duplicate], timeout: 0.2)
        XCTAssertEqual(reports, expected)
    }

    func testPlanningFailureThrowsWithoutReportingAnExecutionFailure() throws {
        let unexpected = expectation(description: "Planning errors are only thrown")
        unexpected.isInverted = true
        let item = CustomScript(name: "missing", path: root.appendingPathComponent("missing.sh").path)
        XCTAssertThrowsError(try runner.launch(item, selectedURLs: [], directory: root) { _ in unexpected.fulfill() })
        XCTAssertEqual(runner.runningProcessCount, 0)
        wait(for: [unexpected], timeout: 0.2)
    }

    func testFailedProcessStartReleasesRegistryEntry() throws {
        let runtime = bin.appendingPathComponent("broken-runtime")
        try Data("#!/crab-missing-interpreter\n".utf8).write(to: runtime)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        let item = try script(contents: "#!" + runtime.path + "\n")
        let unexpected = expectation(description: "Process startup errors are only thrown")
        unexpected.isInverted = true
        XCTAssertNoThrow(try runner.launchPlan(item, selectedURLs: [], directory: root))
        XCTAssertThrowsError(try runner.launch(item, selectedURLs: [], directory: root) { _ in unexpected.fulfill() })
        XCTAssertEqual(runner.runningProcessCount, 0)
        wait(for: [unexpected], timeout: 0.2)
    }

    func testScriptContinuesAfterAnIsolatedLauncherHostExits() throws {
        let item = try script(contents: """
        #!/bin/sh
        parent="$PPID"
        printf '%s' "$parent" > "$CRAB_DIRECTORY/child-ready"
        while kill -0 "$parent" 2>/dev/null; do /bin/sleep 0.01; done
        printf survived > "$CRAB_DIRECTORY/after-parent"
        """)
        let helper = try compileIsolatedHelper()
        let parent = Process()
        parent.executableURL = helper
        parent.arguments = [item.path, root.path]
        parent.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        parent.standardInput = FileHandle.nullDevice
        parent.standardOutput = FileHandle.nullDevice
        parent.standardError = FileHandle.nullDevice
        try parent.run()
        parent.waitUntilExit()
        XCTAssertEqual(parent.terminationStatus, 0)
        XCTAssertEqual(text("child-ready"), String(parent.processIdentifier))
        XCTAssertTrue(waitUntil { self.text("after-parent") == "survived" })
    }

    private func compileIsolatedHelper() throws -> URL {
        let directory = root.appendingPathComponent("helper", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let support = directory.appendingPathComponent("Support.swift")
        try Data(#"""
        import Foundation
        struct CustomScript { let name: String; let path: String }
        func L(_ source: String) -> String { source }
        func LF(_ source: String, _ arguments: CVarArg...) -> String { String(format: source, arguments: arguments) }
        """#.utf8).write(to: support)
        let main = directory.appendingPathComponent("main.swift")
        try Data(#"""
        import Foundation
        import Darwin
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try CustomScriptRunner.shared.launch(CustomScript(name: "fixture", path: CommandLine.arguments[1]), selectedURLs: [], directory: directory)
        let ready = directory.appendingPathComponent("child-ready")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if !FileManager.default.fileExists(atPath: ready.path) { exit(2) }
        """#.utf8).write(to: main)
        let bundled = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ScriptRunnerSource", withExtension: "txt"))
        let source = directory.appendingPathComponent("CustomScriptRunner.swift")
        try Data(contentsOf: bundled).write(to: source)
        let helper = directory.appendingPathComponent("launcher-helper")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", support.path, source.path, main.path, "-module-cache-path", directory.appendingPathComponent("ModuleCache").path, "-o", helper.path]
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for key in ["DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS"] { environment[key] = ProcessInfo.processInfo.environment[key] }
        compiler.environment = environment
        compiler.standardInput = FileHandle.nullDevice
        let output = Pipe()
        compiler.standardOutput = output
        compiler.standardError = output
        try compiler.run()
        let diagnostics = output.fileHandleForReading.readDataToEndOfFile()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
        return helper
    }
}
