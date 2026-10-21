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
        self.init(preferredLanguages: preferredLanguages, resources: Self.resources)
    }

    init(preferredLanguages: [String], resources: Bundle) {
        // Use the same native matching rules and supported languages as the main
        // bundle, so application strings and AppKit menus cannot choose differently.
        language = Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferredLanguages).first ?? "en"
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: language)
        locale = Locale(components: components)
        // Native SwiftPM lowercases lproj names; Xcode preserves their spelling.
        // Resolve the actual directory instead of relying on localized resource
        // lookup, which can silently choose the development language.
        let directories = resources.resourceURL.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
        } ?? []
        let localized = directories.first {
            $0.pathExtension == "lproj" &&
                $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(language) == .orderedSame
        }
        bundle = localized.flatMap(Bundle.init(url:)) ?? resources
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
