import AppKit
import Carbon

enum ActionLaunchPolicy {
    static func backgroundOpenConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false
        return configuration
    }

    static func isActionURL(_ url: URL) -> Bool {
        url.scheme == AppConstants.scheme && url.host == "execute"
    }

    static func settingsPageArgument(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--page"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func shouldShowSettingsOnLaunch(arguments: [String], hasLaunched: Bool,
                                          isDefaultLaunch: Bool, hasPendingActionURLs: Bool,
                                          event: NSAppleEventDescriptor?) -> Bool {
        if arguments.contains("--settings") || settingsPageArgument(in: arguments) != nil { return true }
        return !hasLaunched && isDefaultLaunch && !hasPendingActionURLs && !isActionEvent(event)
    }

    static func shouldShowSettingsOnReopen(event: NSAppleEventDescriptor?, applicationIsActive: Bool) -> Bool {
        guard !isActionEvent(event) else { return false }
        if let expected = event?.paramDescriptor(forKeyword: AEKeyword(kAEApplicationActivationExpected)) {
            return expected.booleanValue
        }
        return applicationIsActive
    }

    private static func isActionEvent(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == AEEventClass(kInternetEventClass),
              event.eventID == AEEventID(kAEGetURL),
              let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: value) else { return false }
        return isActionURL(url)
    }
}
