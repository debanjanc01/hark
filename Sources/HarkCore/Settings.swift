import Foundation

/// User preferences, persisted in UserDefaults.
@MainActor
public final class Settings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hotkey: Hotkey {
        get { defaults.string(forKey: "hotkey").flatMap(Hotkey.init(rawValue:)) ?? .rightOption }
        set { defaults.set(newValue.rawValue, forKey: "hotkey") }
    }

    /// One of `Transcriber.languages`, or nil to auto-detect. Defaults to the Mac's
    /// language when supported: auto-detection can mistake short English phrases for
    /// another language.
    public var language: String? {
        get {
            switch defaults.string(forKey: "language") {
            case "auto": nil
            case let code? where Transcriber.languages.contains(code): code
            default: Self.systemLanguage
            }
        }
        set { defaults.set(newValue ?? "auto", forKey: "language") }
    }

    /// The first of the person's preferred languages that Whistle supports.
    public static var systemLanguage: String? {
        Locale.preferredLanguages.lazy
            .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
            .first { Transcriber.languages.contains($0) }
    }

    /// Whether to show the floating indicator near the bottom of the screen.
    public var showsIndicator: Bool {
        get { defaults.object(forKey: "showsIndicator") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showsIndicator") }
    }

    /// Whether Hark has turned on Launch at Login once, at first setup. After that, only
    /// the person changes it.
    public var offeredLaunchAtLogin: Bool {
        get { defaults.bool(forKey: "offeredLaunchAtLogin") }
        set { defaults.set(newValue, forKey: "offeredLaunchAtLogin") }
    }

    /// Words or phrases to bias recognition towards (names, jargon).
    public var keywords: [String] {
        get { defaults.stringArray(forKey: "keywords") ?? [] }
        set { defaults.set(newValue, forKey: "keywords") }
    }

    /// `keywords` as the person types them: separated by commas.
    public var customWords: String {
        get { keywords.joined(separator: ", ") }
        set {
            keywords = newValue.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    /// Whether to fix misheard developer terms. On out of the box, and easy to see and turn off.
    public var fixesDeveloperWords: Bool {
        get { defaults.object(forKey: "fixesDeveloperWords") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fixesDeveloperWords") }
    }

    /// The list as the person edits it. Saved only once it differs from the built-in one,
    /// so an untouched list picks up improvements in later versions.
    public var developerWordsList: String {
        get { defaults.string(forKey: "developerWords") ?? DeveloperWords.defaults.list }
        set {
            if DeveloperWords(list: newValue) == .defaults {
                defaults.removeObject(forKey: "developerWords")
            } else {
                defaults.set(newValue, forKey: "developerWords")
            }
        }
    }

    public var developerWords: DeveloperWords {
        DeveloperWords(list: developerWordsList)
    }

    /// The choices for `language`, with their names in the person's language.
    public static var languageChoices: [(code: String?, name: String)] {
        [(nil, "Auto-Detect")] + Transcriber.languages.map { code in
            (code, Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code)
        }
    }
}
