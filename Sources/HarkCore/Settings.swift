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

    /// One of `Transcriber.languages`, or nil to auto-detect.
    public var language: String? {
        get { defaults.string(forKey: "language").flatMap { Transcriber.languages.contains($0) ? $0 : nil } }
        set { defaults.set(newValue, forKey: "language") }
    }

    /// Whether to show the floating indicator near the bottom of the screen.
    public var showsIndicator: Bool {
        get { defaults.object(forKey: "showsIndicator") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showsIndicator") }
    }

    /// Words or phrases to bias recognition towards (names, jargon).
    public var keywords: [String] {
        get { defaults.stringArray(forKey: "keywords") ?? [] }
        set { defaults.set(newValue, forKey: "keywords") }
    }
}
