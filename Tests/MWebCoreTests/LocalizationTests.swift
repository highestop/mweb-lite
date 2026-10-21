import Foundation
import XCTest
import CaseReporting
@testable import MWebCore

final class LocalizationTests: CaseReportingTestCase {
    func test_L10N_001_LanguagePreferenceFallbackAndCatalogCompleteness() throws {
        for (preferences, expected) in [
            (["en-GB", "zh-Hans"], "en"), (["zh-CN", "en"], "zh-Hans"),
            (["fr-FR", "zh-Hans-CN", "en"], "zh-Hans"), (["zh-TW", "en"], "zh-Hans"),
            (["ja-JP"], "en"), ([String](), "en")
        ] {
            XCTAssertEqual(Localization(preferredLanguages: preferences).language, expected)
        }
        let english = Localization(preferredLanguages: ["en"])
        let chinese = Localization(preferredLanguages: ["zh-Hans"])
        func catalog(_ localization: Localization) throws -> [String: String] {
            let url = try XCTUnwrap(localization.bundle.url(forResource: "Localizable", withExtension: "strings"))
            let data = try Data(contentsOf: url)
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let en = try catalog(english), zh = try catalog(chinese)
        XCTAssertGreaterThan(en.count, 100)
        XCTAssertEqual(Set(en.keys), Set(zh.keys))
        let placeholders = try NSRegularExpression(pattern: "%(@|ld)")
        func arguments(_ value: String) -> [String] {
            placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .map { (value as NSString).substring(with: $0.range) }
        }
        for (key, value) in en {
            XCTAssertEqual(value, key)
            XCTAssertFalse(try XCTUnwrap(zh[key]).isEmpty, key)
            XCTAssertEqual(arguments(value), arguments(zh[key]!), key)
            XCTAssertEqual(english.string(key), value)
            XCTAssertEqual(chinese.string(key), zh[key])
        }
        XCTAssertEqual(english.string("New Article"), "New Article")
        XCTAssertEqual(chinese.string("New Article"), "新建文章")
        XCTAssertEqual(chinese.string("not-in-catalog"), "not-in-catalog")
        let name = "中文 / 100% / 😀"
        XCTAssertEqual(english.format("Delete Category “%@”?", name), "Delete Category “\(name)”?")
        XCTAssertEqual(chinese.format("Delete Category “%@”?", name), "删除分类“\(name)”？")
        XCTAssertEqual(english.format("%ld articles", 12), "12 articles")
        XCTAssertEqual(chinese.format("%ld articles", 12), "12 篇文章")
        // Native standard menus use the executable bundle's declared localizations.
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let info = try Data(contentsOf: project.appendingPathComponent("Support/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleLocalizations"] as? [String], ["en", "zh-Hans"])
        XCTAssertEqual(plist["CFBundleDevelopmentRegion"] as? String, "en")
    }
}
