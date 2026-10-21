import Foundation

/// One catalog shared by SwiftUI, AppKit, library errors, and the WebKit shell.
/// Resolve once at launch, using macOS preferences (including per-app language).
public struct Localization {
    public let language: String
    public let locale: Locale
    let bundle: Bundle

    static let resources: Bundle = {
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("MWebLite_MWebCore.bundle")) {
            return packaged
        }
        return .module
    }()

    public init(preferredLanguages: [String] = Locale.preferredLanguages) {
        // Provide simplified Chinese for Chinese variants without another translation.
        let preferences = preferredLanguages.map { $0.lowercased().hasPrefix("zh") ? "zh-Hans" : $0 }
        language = Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferences).first ?? "en"
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: language)
        locale = Locale(components: components)
        bundle = Self.resources.url(forResource: language, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? Self.resources
    }

    public func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
}

public enum L10n {
    public static let current = Localization()

    public static func string(_ key: String) -> String { current.string(key) }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: current.locale, arguments: arguments)
    }
}
