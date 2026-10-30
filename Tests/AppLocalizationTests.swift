import XCTest
@testable import Crab

final class AppLocalizationTests: XCTestCase {
    private var originalLanguage = ""
    override func setUpWithError() throws {
        originalLanguage = AppLocalization.languageCode
        AppLocalization.languageCode = "zh-Hans"
    }
    override func tearDownWithError() throws { AppLocalization.languageCode = originalLanguage }

    private func table(_ code: String) throws -> [String: String] {
        for bundle in [Bundle.main, Bundle(for: Self.self)] {
            if let table = AppLocalization.translations(for: code, in: bundle) { return table }
        }
        XCTFail("Missing actual bundled translation: " + code)
        throw CocoaError(.fileNoSuchFile)
    }

    func testTenLanguageOptionsAndSystemRegionResolution() {
        XCTAssertEqual(AppLocalization.supportedLanguages.map(\.code), ["", "zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "es", "pt-PT", "de"])
        for (preference, expected) in [("zh-TW", "zh-Hant"), ("zh_HK", "zh-Hant"), ("zh-Hant-MO", "zh-Hant"), ("zh-CN", "zh-Hans"), ("en-GB", "en"), ("ja-JP", "ja"), ("ko-KR", "ko"), ("fr-CA", "fr"), ("es-MX", "es"), ("pt-BR", "pt-PT"), ("de-AT", "de")] {
            XCTAssertEqual(AppLocalization.resolve(code: "", preferredLanguages: [preference]), expected)
        }
        XCTAssertEqual(AppLocalization.resolve(code: "ja", preferredLanguages: ["en-US"]), "ja")
        XCTAssertEqual(AppLocalization.resolve(code: "", preferredLanguages: ["it-IT", "fr-FR"]), "fr")
        XCTAssertEqual(AppLocalization.resolve(code: "", preferredLanguages: ["it-IT"]), "en")
        XCTAssertEqual(AppLocalization.resolve(code: "unsupported", preferredLanguages: ["zh-CN"]), "en")
    }

    func testMainBundleDeclaresSupportedLanguagesForSystemPanels() throws {
        let expected = AppLocalization.supportedLanguages.map(\.code).filter { !$0.isEmpty }
        let declared = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String])
        XCTAssertEqual(Set(declared), Set(expected))
        XCTAssertEqual(declared.count, expected.count)
        XCTAssertEqual(Set(Bundle.main.localizations), Set(expected))
        for code in expected {
            XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: [code]).first, code)
        }
        for (preference, expected) in [("zh-CN", "zh-Hans"), ("zh-TW", "zh-Hant"), ("en-GB", "en"), ("ja-JP", "ja"), ("ko-KR", "ko"), ("fr-CA", "fr"), ("es-MX", "es"), ("de-AT", "de")] {
            XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: [preference]).first, expected)
        }
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: ["it-IT", "fr-FR"]).first, "fr")
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
    }

    func testAllNineResourcesContainMatchingNonemptyKeysAndFormatArguments() throws {
        let base = try table("zh-Hans")
        let requiredKeys: Set<String> = [
            "新建文件", "通用设置", "常用目录", "工具箱", "复制到", "移动到",
            "工具操作", "文件模板", "传送目录", "快捷目录", "应用入口", "自定义图标", "自定义脚本",
            "由 APP 打开", "发送到…", "收藏目录", "使用默认编排",
            "自定义脚本“%@”执行失败（退出码：%d）。", "自定义脚本“%@”异常终止（信号：%d）。",
            "隔空投送服务当前不可用，请稍后重试。", "无法通过隔空投送分享所选文件。", "隔空投送失败：%@",
            "进入 Cursor", "进入 Ghostty", "无法在 %@ 中打开所选位置（退出状态：%d）。"
        ]
        XCTAssertTrue(requiredKeys.isSubset(of: Set(base.keys)))
        let expression = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|z|t|j|L)?([@diuoxXfFeEgGcCsSp%])"#)
        func arguments(_ string: String) -> [String] {
            expression.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap { match in
                guard let range = Range(match.range(at: 1), in: string), string[range] != "%" else { return nil }
                return String(string[range])
            }
        }
        for language in AppLocalization.supportedLanguages where !language.code.isEmpty {
            let localized = try table(language.code)
            XCTAssertEqual(Set(localized.keys), Set(base.keys), language.code)
            for (source, translated) in localized {
                XCTAssertFalse(translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, source)
                XCTAssertEqual(arguments(source), arguments(translated), language.code + ": " + source)
            }
        }
    }

    func testSwitchingLoadsActualNonChineseTranslationsImmediately() {
        let expected = [("zh-Hans", "新建文件"), ("zh-Hant", "新建檔案"), ("en", "New File"), ("ja", "新規ファイル"), ("ko", "새 파일"), ("fr", "Nouveau fichier"), ("es", "Archivo nuevo"), ("pt-PT", "Novo arquivo"), ("de", "Neue Datei")]
        for (code, title) in expected {
            AppLocalization.languageCode = code
            XCTAssertEqual(L("新建文件"), title, code)
            XCTAssertEqual(L("简体中文"), "简体中文")
            XCTAssertEqual(L("繁體中文"), "繁體中文")
            XCTAssertEqual(L("日本語"), "日本語")
        }
    }

    func testUnknownCustomDataIsNeverRewrittenAndFormatsPreserveValues() {
        let customName = "客户自定义：新建文件 ~/图片/100% 报告.txt"
        for language in AppLocalization.supportedLanguages where !language.code.isEmpty {
            AppLocalization.languageCode = language.code
            XCTAssertEqual(L(customName), customName)
            let rendered = LF("共 %d 项，已选择 %d 项改名。", 50, 7)
            XCTAssertTrue(rendered.contains("50")); XCTAssertTrue(rendered.contains("7"))
            XCTAssertTrue(LF("进入 %@", customName).contains(customName))
        }
        AppLocalization.languageCode = "en"
        XCTAssertEqual(LF("已完成 %d 项改名。", 7), "Renamed 7 items.")
        AppLocalization.languageCode = "ja"
        XCTAssertEqual(LF("进入 %@", "IntelliJ IDEA"), "IntelliJ IDEA で開く")
        AppLocalization.languageCode = "de"
        XCTAssertEqual(LF("进入 %@", "IntelliJ IDEA"), "In IntelliJ IDEA öffnen")
    }

    func testResourceReaderWorksInAnIndependentFinderExtensionBundle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LocalizationTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleURL = directory.appendingPathComponent("Finder.appex", isDirectory: true)
        let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "dev.crab.localization-test-extension", "CFBundlePackageType": "XPC!"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        for language in AppLocalization.supportedLanguages where !language.code.isEmpty {
            try JSONEncoder().encode(table(language.code)).write(to: resources.appendingPathComponent("Crab-" + language.code + ".json"))
        }
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        XCTAssertEqual(try XCTUnwrap(AppLocalization.translations(for: "en", in: bundle))["新建文件"], "New File")
        XCTAssertEqual(try XCTUnwrap(AppLocalization.translations(for: "ja", in: bundle))["新建文件"], "新規ファイル")
    }
}
