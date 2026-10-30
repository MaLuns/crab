import Foundation

enum AppLocalization {
    static let supportedLanguages: [(code: String, name: String)] = [
        ("", "跟随系统"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
        ("en", "English"), ("ja", "日本語"), ("ko", "한국어"),
        ("fr", "Français"), ("es", "Español"), ("pt-PT", "Português"), ("de", "Deutsch")
    ]

    private static let lock = NSLock()
    private static var selectedCode = ""
    static var languageCode: String {
        get { lock.lock(); defer { lock.unlock() }; return selectedCode }
        set { lock.lock(); selectedCode = newValue; lock.unlock() }
    }
    static var resolvedCode: String { resolve(code: languageCode, preferredLanguages: Locale.preferredLanguages) }

    private static let tables: [String: [String: String]] = {
        let bundles = [Bundle(for: LocalizationBundleMarker.self), Bundle.main]
        var result: [String: [String: String]] = [:]
        for language in supportedLanguages where !language.code.isEmpty {
            for bundle in bundles {
                if let table = translations(for: language.code, in: bundle) {
                    result[language.code] = table
                    break
                }
            }
        }
        return result
    }()

    static func string(_ source: String) -> String {
        let code = resolvedCode
        guard code != "zh-Hans" else { return source }
        return tables[code]?[source] ?? tables["en"]?[source] ?? source
    }

    static func format(_ source: String, _ arguments: CVarArg...) -> String {
        format(source, arguments: arguments)
    }

    static func format(_ source: String, arguments: [CVarArg]) -> String {
        String(format: string(source), locale: Locale(identifier: resolvedCode), arguments: arguments)
    }

    static func resolve(code: String, preferredLanguages: [String]) -> String {
        func available(_ value: String) -> String? {
            let normalized = value.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("zh") {
                return normalized.contains("hant") || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo") ? "zh-Hant" : "zh-Hans"
            }
            for language in ["en", "ja", "ko", "fr", "es", "de"] {
                if normalized == language || normalized.hasPrefix(language + "-") { return language }
            }
            if normalized == "pt" || normalized.hasPrefix("pt-") { return "pt-PT" }
            return nil
        }
        if !code.isEmpty { return available(code) ?? "en" }
        return preferredLanguages.compactMap(available).first ?? "en"
    }

    static func translations(for code: String, in bundle: Bundle) -> [String: String]? {
        for directory in [nil, "Localization", "Resources", "Resources/Localization"] as [String?] {
            guard let url = bundle.url(forResource: "Crab-" + code, withExtension: "json", subdirectory: directory),
                  let data = try? Data(contentsOf: url),
                  let table = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            return table
        }
        return nil
    }
}

private final class LocalizationBundleMarker: NSObject {}

func L(_ source: String) -> String { AppLocalization.string(source) }
func LF(_ source: String, _ arguments: CVarArg...) -> String { AppLocalization.format(source, arguments: arguments) }
