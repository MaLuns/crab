import AppKit
import ApplicationServices
import CoreServices
import FinderSync

enum AppPermission: String, CaseIterable {
    case accessibility, inputMonitoring, finderAutomation, iTermAutomation
    case filesAndFolders, fullDiskAccess, finderExtension
}

enum AppPermissionState: Equatable {
    case authorized, notAuthorized, notDetermined, notRunning
    case requiresSystemSettings, unavailable, enabled, disabled
}

struct AppPermissionStatus: Equatable {
    let permission: AppPermission
    let state: AppPermissionState
}

enum AppPermissions {
    private static let loader = SnapshotLoader()
    struct Environment {
        var hasAccessibilityPermission: () -> Bool
        var hasInputMonitoringPermission: () -> Bool
        var isFinderExtensionEnabled: () -> Bool
        var isApplicationInstalled: (String) -> Bool
        var isApplicationRunning: (String) -> Bool
        var automationPermission: (String, AEEventClass, AEEventID) -> OSStatus
        var finderExtensionState: (() -> AppPermissionState)? = nil
    }

    static func currentStatuses(hasAccessibilityPermission: @escaping () -> Bool = FinderFallback.hasPermission) -> [AppPermissionStatus] {
        currentStatuses(environment: systemEnvironment(hasAccessibilityPermission: hasAccessibilityPermission))
    }

    static func loadStatuses(hasAccessibilityPermission: @escaping () -> Bool = FinderFallback.hasPermission,
                             completion: @escaping ([AppPermissionStatus]) -> Void) {
        loader.load(environment: systemEnvironment(hasAccessibilityPermission: hasAccessibilityPermission), completion: completion)
    }

    private static func systemEnvironment(hasAccessibilityPermission: @escaping () -> Bool) -> Environment {
        Environment(
            hasAccessibilityPermission: hasAccessibilityPermission,
            hasInputMonitoringPermission: { CGPreflightListenEventAccess() },
            isFinderExtensionEnabled: { FIFinderSyncController.isExtensionEnabled },
            isApplicationInstalled: { identifier in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil || isRunning(identifier)
            },
            isApplicationRunning: isRunning,
            automationPermission: { identifier, eventClass, eventID in
                automationPermission(for: identifier, eventClass: eventClass, eventID: eventID, askUserIfNeeded: false)
            }, finderExtensionState: {
                finderExtensionState(nativeEnabled: FIFinderSyncController.isExtensionEnabled,
                                     extensionURL: Bundle.main.builtInPlugInsURL?.appendingPathComponent("CrabFinder.appex"),
                                     registryOutput: readExtensionRegistry)
            })
    }

    final class SnapshotLoader {
        private let lock = NSLock()
        private var probes: [AppPermission: AutomationProbe] = [:]

        func load(environment: Environment, timeout: TimeInterval = 2,
                  completion: @escaping ([AppPermissionStatus]) -> Void) {
            DispatchQueue.global(qos: .utility).async {
                var immediate = environment
                immediate.automationPermission = { _, _, _ in OSStatus(errAETimeout) }
                let statuses = AppPermissions.currentStatuses(environment: immediate)
                var queries: [AppPermission: AutomationProbe] = [:]
                for status in statuses where status.state == .unavailable {
                    let permission = status.permission
                    guard permission == .finderAutomation || permission == .iTermAutomation else { continue }
                    self.lock.lock()
                    let probe: AutomationProbe
                    if let running = self.probes[permission], running.result == nil {
                        probe = running
                    } else {
                        probe = AutomationProbe {
                            let target = permission == .finderAutomation ? "com.apple.finder" : "com.googlecode.iterm2"
                            guard environment.isApplicationRunning(target) else { return OSStatus(procNotFound) }
                            let eventClass = permission == .finderAutomation ? AEEventClass(kAECoreSuite) : AEEventClass(typeWildCard)
                            let eventID = permission == .finderAutomation ? AEEventID(kAEGetData) : AEEventID(typeWildCard)
                            return environment.automationPermission(target, eventClass, eventID)
                        }
                        self.probes[permission] = probe
                    }
                    self.lock.unlock()
                    queries[permission] = probe
                }
                let deadline = DispatchTime.now() + max(0, timeout)
                for probe in queries.values { _ = probe.finished.wait(timeout: deadline) }
                let snapshot = statuses.map { status -> AppPermissionStatus in
                    guard let result = queries[status.permission]?.result else { return status }
                    return .init(permission: status.permission, state: AppPermissions.automationState(for: result))
                }
                DispatchQueue.main.async { completion(snapshot) }
            }
        }
    }

    private final class AutomationProbe {
        let finished = DispatchGroup()
        private let lock = NSLock()
        private var value: OSStatus?
        var result: OSStatus? {
            lock.lock(); defer { lock.unlock() }
            return value
        }

        init(query: @escaping () -> OSStatus) {
            finished.enter()
            DispatchQueue.global(qos: .utility).async {
                let result = query()
                self.lock.lock(); self.value = result; self.lock.unlock()
                self.finished.leave()
            }
        }
    }

    static func currentStatuses(environment: Environment) -> [AppPermissionStatus] {
        var statuses = [
            AppPermissionStatus(permission: .accessibility, state: environment.hasAccessibilityPermission() ? .authorized : .notAuthorized),
            AppPermissionStatus(permission: .inputMonitoring, state: environment.hasInputMonitoringPermission() ? .authorized : .notAuthorized),
            AppPermissionStatus(permission: .finderAutomation, state: automationState(for: "com.apple.finder", eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData), environment: environment))
        ]
        if environment.isApplicationInstalled("com.googlecode.iterm2") {
            statuses.append(.init(permission: .iTermAutomation,
                                  state: automationState(for: "com.googlecode.iterm2", eventClass: AEEventClass(typeWildCard), eventID: AEEventID(typeWildCard), environment: environment)))
        }
        statuses.append(.init(permission: .filesAndFolders, state: .requiresSystemSettings))
        statuses.append(.init(permission: .fullDiskAccess, state: .requiresSystemSettings))
        statuses.append(.init(permission: .finderExtension,
                              state: environment.finderExtensionState?() ?? (environment.isFinderExtensionEnabled() ? .enabled : .disabled)))
        return statuses
    }

    static func finderExtensionState(nativeEnabled: Bool, extensionURL: URL?,
                                     registryOutput: () -> String?) -> AppPermissionState {
        if let extensionURL, let output = registryOutput() {
            return registeredExtensionState(output, extensionURL: extensionURL)
        }
        return nativeEnabled ? .enabled : .unavailable
    }

    static func registeredExtensionState(_ output: String, extensionURL: URL,
                                         identifier: String = "dev.crab.Crab.FinderExtension") -> AppPermissionState {
        let expected = extensionURL.standardizedFileURL.resolvingSymlinksInPath()
        let matches = output.split(whereSeparator: \.isNewline).compactMap { line -> AppPermissionState? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4, let first = fields.first, let last = fields.last else { return nil }
            let header = first.trimmingCharacters(in: .whitespaces)
            guard header.dropFirst().trimmingCharacters(in: .whitespaces).hasPrefix(identifier + "(") else { return nil }
            let path = String(last).trimmingCharacters(in: .whitespaces)
            guard URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() == expected else { return nil }
            switch header.first {
            case "+": return .enabled
            case "-": return .disabled
            default: return .unavailable
            }
        }
        guard let first = matches.first, matches.allSatisfy({ $0 == first }) else { return .unavailable }
        return first
    }

    private static func readExtensionRegistry() -> String? {
        let process = Process(), output = Pipe()
        let exited = DispatchSemaphore(value: 0), drained = DispatchSemaphore(value: 0)
        let capture = RegistryCapture()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-v", "-A", "-D", "-i", "dev.crab.Crab.FinderExtension"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in exited.signal() }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
            if data.isEmpty { handle.readabilityHandler = nil; drained.signal() }
            else { capture.append(data) }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            try? output.fileHandleForReading.close()
        }
        do { try process.run() } catch { return nil }
        guard exited.wait(timeout: .now() + 1) == .success else {
            if process.isRunning { process.terminate() }
            return nil
        }
        guard process.terminationStatus == 0, drained.wait(timeout: .now() + 0.2) == .success else { return nil }
        return capture.string
    }

    private final class RegistryCapture {
        private let lock = NSLock()
        private var data = Data()
        private var truncated = false
        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            if data.count + chunk.count > 512 * 1024 { truncated = true }
            if !truncated { data.append(chunk) }
        }
        var string: String? {
            lock.lock(); defer { lock.unlock() }
            return truncated ? nil : String(data: data, encoding: .utf8)
        }
    }

    static func request(_ permission: AppPermission, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            switch permission {
            case .accessibility:
                FinderFallback.requestPermission()
            case .inputMonitoring:
                _ = CGRequestListenEventAccess()
            case .finderAutomation, .iTermAutomation:
                let identifier = permission == .finderAutomation ? "com.apple.finder" : "com.googlecode.iterm2"
                let eventClass = permission == .finderAutomation ? AEEventClass(kAECoreSuite) : AEEventClass(typeWildCard)
                let eventID = permission == .finderAutomation ? AEEventID(kAEGetData) : AEEventID(typeWildCard)
                if isRunning(identifier) {
                    _ = automationPermission(for: identifier, eventClass: eventClass, eventID: eventID, askUserIfNeeded: true)
                }
            case .filesAndFolders, .fullDiskAccess, .finderExtension:
                break
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    static func automationState(for status: OSStatus) -> AppPermissionState {
        switch status {
        case noErr: return .authorized
        case OSStatus(errAEEventNotPermitted): return .notAuthorized
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .notRunning
        default: return .unavailable
        }
    }

    private static func automationState(for identifier: String, eventClass: AEEventClass, eventID: AEEventID, environment: Environment) -> AppPermissionState {
        guard environment.isApplicationRunning(identifier) else { return .notRunning }
        return automationState(for: environment.automationPermission(identifier, eventClass, eventID))
    }

    private static func isRunning(_ identifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains { !$0.isTerminated }
    }

    private static func automationPermission(for identifier: String, eventClass: AEEventClass, eventID: AEEventID, askUserIfNeeded: Bool) -> OSStatus {
        guard isRunning(identifier) else { return OSStatus(procNotFound) }
        let target = NSAppleEventDescriptor(bundleIdentifier: identifier)
        guard let address = target.aeDesc else { return OSStatus(paramErr) }
        return AEDeterminePermissionToAutomateTarget(address, eventClass, eventID, askUserIfNeeded)
    }
}
