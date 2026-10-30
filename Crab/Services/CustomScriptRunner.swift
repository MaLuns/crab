import Foundation
import Darwin

final class CustomScriptRunner {
    enum LaunchError: LocalizedError {
        case unreadableScript(String)
        case invalidDirectory(String)
        case unrecognizedInterpreter
        case missingInterpreter(String)
        case invalidEnvironment
        case oversizedEnvironment
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadableScript(let path): return LF("脚本文件不存在或无法读取：%@", path)
            case .invalidDirectory(let path): return LF("脚本工作目录不存在或无法访问：%@", path)
            case .unrecognizedInterpreter: return L("无法识别脚本解释器，请在脚本首行添加有效的 shebang。")
            case .missingInterpreter(let name): return LF("找不到脚本解释器：%@", name)
            case .invalidEnvironment: return L("脚本上下文包含无法传递的环境变量。")
            case .oversizedEnvironment: return L("脚本上下文超出系统进程启动限制，无法执行。")
            case .launchFailed(let message): return LF("无法启动自定义脚本：%@", message)
            }
        }
    }

    enum ExecutionError: LocalizedError, Equatable {
        case nonZeroExit(scriptName: String, status: Int32)
        case terminatedBySignal(scriptName: String, signal: Int32)

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let name, let status):
                return LF("自定义脚本“%@”执行失败（退出码：%d）。", name, status)
            case .terminatedBySignal(let name, let signal):
                return LF("自定义脚本“%@”异常终止（信号：%d）。", name, signal)
            }
        }
    }

    struct LaunchPlan: Equatable {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
        let directoryURL: URL
    }

    static let shared = CustomScriptRunner()
    private let baseEnvironment: [String: String]
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]

    init(baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.baseEnvironment = baseEnvironment
    }

    var runningProcessCount: Int {
        lock.lock(); defer { lock.unlock() }
        return processes.count
    }

    func launch(_ script: CustomScript, selectedURLs: [URL], directory: URL,
                onFailure: @escaping (Error) -> Void = { _ in }) throws {
        let plan = try launchPlan(script, selectedURLs: selectedURLs, directory: directory)
        let process = Process()
        process.executableURL = plan.executableURL
        process.arguments = plan.arguments
        process.environment = plan.environment
        process.currentDirectoryURL = plan.directoryURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let token = UUID()
        process.terminationHandler = { [weak self] process in
            self?.releaseProcess(token)
            let failure: ExecutionError
            switch process.terminationReason {
            case .exit:
                guard process.terminationStatus != 0 else { return }
                failure = .nonZeroExit(scriptName: script.name, status: process.terminationStatus)
            case .uncaughtSignal:
                failure = .terminatedBySignal(scriptName: script.name, signal: process.terminationStatus)
            @unknown default:
                return
            }
            DispatchQueue.main.async { onFailure(failure) }
        }
        lock.lock()
        processes[token] = process
        lock.unlock()
        do {
            try process.run()
        } catch {
            releaseProcess(token)
            process.terminationHandler = nil
            let failure = error as NSError
            if failure.domain == NSPOSIXErrorDomain && failure.code == Int(E2BIG) {
                throw LaunchError.oversizedEnvironment
            }
            throw LaunchError.launchFailed(error.localizedDescription)
        }
    }

    func launchPlan(_ script: CustomScript, selectedURLs: [URL], directory: URL) throws -> LaunchPlan {
        let manager = FileManager.default
        guard script.path.hasPrefix("/"), !script.path.contains("\0") else {
            throw LaunchError.unreadableScript(script.path)
        }
        let scriptURL = URL(fileURLWithPath: script.path)
        guard (try? scriptURL.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              manager.isReadableFile(atPath: scriptURL.path) else {
            throw LaunchError.unreadableScript(script.path)
        }
        var isDirectory: ObjCBool = false
        guard directory.isFileURL, !directory.path.contains("\0"),
              manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LaunchError.invalidDirectory(directory.path)
        }
        guard selectedURLs.allSatisfy({ $0.isFileURL && !$0.path.contains("\0") }) else {
            throw LaunchError.invalidEnvironment
        }
        var environment = baseEnvironment
        environment["PATH"] = effectivePath()
        environment["CRAB_DIRECTORY"] = directory.path
        environment["CRAB_SELECTED_PATHS_JSON"] = String(decoding: try JSONEncoder().encode(selectedURLs.map(\.path)), as: UTF8.self)
        environment["CRAB_SELECTED_COUNT"] = String(selectedURLs.count)
        guard environment.allSatisfy({ !$0.key.isEmpty && !$0.key.contains("=") && !$0.key.contains("\0") && !$0.value.contains("\0") }) else {
            throw LaunchError.invalidEnvironment
        }
        let invocation = try interpreter(for: scriptURL, path: environment["PATH"]!, directory: directory)
        let arguments = invocation.arguments + [scriptURL.path]
        try validateSize(executable: invocation.executableURL.path, arguments: arguments, environment: environment)
        return LaunchPlan(executableURL: invocation.executableURL, arguments: arguments,
                          environment: environment, directoryURL: directory)
    }

    private func releaseProcess(_ token: UUID) {
        lock.lock(); defer { lock.unlock() }
        processes.removeValue(forKey: token)
    }

    private func effectivePath() -> String {
        var components = baseEnvironment["PATH"].map { $0.components(separatedBy: ":") } ?? []
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !components.contains(directory) {
            components.append(directory)
        }
        return components.joined(separator: ":")
    }

    private func interpreter(for script: URL, path: String, directory: URL) throws -> (executableURL: URL, arguments: [String]) {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: script)
            defer { try? handle.close() }
            data = try handle.read(upToCount: 4096) ?? Data()
        } catch {
            throw LaunchError.unreadableScript(script.path)
        }
        if data.starts(with: [0x23, 0x21]) {
            let bytes = data.prefix { $0 != 0x0a }
            guard bytes.count < 4096, let firstLine = String(data: bytes, encoding: .utf8), !firstLine.contains("\0") else {
                throw LaunchError.unrecognizedInterpreter
            }
            let line = firstLine.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let executable = tokens.first, executable.hasPrefix("/"), !executable.contains("\0") else {
                throw LaunchError.unrecognizedInterpreter
            }
            if executable == "/usr/bin/env" {
                let remainder = String(line.dropFirst(executable.count)).trimmingCharacters(in: .whitespaces)
                return try environmentInterpreter(remainder, path: path, directory: directory)
            }
            return (try executableURL(executable), Array(tokens.dropFirst()))
        }
        let executable: String
        switch script.pathExtension.lowercased() {
        case "sh": executable = "/bin/sh"
        case "bash": executable = "/bin/bash"
        case "zsh": executable = "/bin/zsh"
        case "py": executable = "python3"
        case "js", "mjs", "cjs": executable = "node"
        case "rb": executable = "ruby"
        case "pl": executable = "perl"
        default: throw LaunchError.unrecognizedInterpreter
        }
        return (try findExecutable(executable, path: path, directory: directory), [])
    }

    private func environmentInterpreter(_ remainder: String, path: String, directory: URL) throws -> (executableURL: URL, arguments: [String]) {
        let tokens = remainder.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let splitString: String?
        let runtime: String
        if tokens.first == "-S" {
            let value = String(remainder.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard let first = value.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else {
                throw LaunchError.unrecognizedInterpreter
            }
            runtime = String(first)
            splitString = value
        } else {
            guard let first = tokens.first else { throw LaunchError.unrecognizedInterpreter }
            runtime = first
            splitString = nil
        }
        guard !runtime.hasPrefix("-"), !runtime.hasPrefix("#"),
              !runtime.contains(where: { "'\"\\$=\0".contains($0) }),
              runtime.hasPrefix("/") || !runtime.contains("/") else {
            throw LaunchError.unrecognizedInterpreter
        }
        _ = try findExecutable(runtime, path: path, directory: directory)
        let env = try executableURL("/usr/bin/env")
        return (env, splitString.map { ["-S", $0] } ?? tokens)
    }

    private func findExecutable(_ name: String, path: String, directory: URL) throws -> URL {
        if name.hasPrefix("/") { return try executableURL(name) }
        for entry in path.components(separatedBy: ":") {
            let folder = entry.hasPrefix("/") ? URL(fileURLWithPath: entry, isDirectory: true) : directory.appendingPathComponent(entry, isDirectory: true)
            let candidate = folder.appendingPathComponent(name)
            if isExecutableFile(candidate) { return candidate }
        }
        throw LaunchError.missingInterpreter(name)
    }

    private func executableURL(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        guard isExecutableFile(url) else { throw LaunchError.missingInterpreter(path) }
        return url
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && FileManager.default.isExecutableFile(atPath: url.path)
    }

    private func validateSize(executable: String, arguments: [String], environment: [String: String]) throws {
        let strings = executable.utf8.count + 1
            + arguments.reduce(0) { $0 + $1.utf8.count + 1 }
            + environment.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count + 2 }
        let pointers = (arguments.count + environment.count + 3) * MemoryLayout<UnsafeRawPointer?>.size
        let systemLimit = sysconf(_SC_ARG_MAX)
        let limit = systemLimit > 0 ? Int(systemLimit) : 262_144
        guard strings + pointers <= limit else { throw LaunchError.oversizedEnvironment }
    }
}
