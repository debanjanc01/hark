import Foundation
import Testing
@testable import HarkCore

@MainActor
struct SettingsTests {
    private func makeSettings() -> (Settings, UserDefaults) {
        let suite = "hark-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (Settings(defaults: defaults), defaults)
    }

    @Test func defaults() {
        let (settings, _) = makeSettings()
        #expect(settings.hotkey == .rightOption)
        #expect(settings.language == Settings.systemLanguage)
        #expect(settings.showsIndicator)
        #expect(settings.keywords.isEmpty)
    }

    @Test func customWordsAreSplitOnCommas() {
        let (settings, _) = makeSettings()
        settings.customWords = " Hark,  Whistle , ,Needle "
        #expect(settings.keywords == ["Hark", "Whistle", "Needle"])
        #expect(settings.customWords == "Hark, Whistle, Needle")
    }

    @Test func persists() {
        let (settings, defaults) = makeSettings()
        settings.hotkey = .fn
        settings.language = "de"
        settings.showsIndicator = false
        settings.keywords = ["Hark", "Whistle"]

        let reloaded = Settings(defaults: defaults)
        #expect(reloaded.hotkey == .fn)
        #expect(reloaded.language == "de")
        #expect(!reloaded.showsIndicator)
        #expect(reloaded.keywords == ["Hark", "Whistle"])
    }

    @Test func ignoresUnknownStoredValues() {
        let (settings, defaults) = makeSettings()
        defaults.set("capsLock", forKey: "hotkey")
        defaults.set("xx", forKey: "language")
        #expect(settings.hotkey == .rightOption)
        #expect(settings.language == Settings.systemLanguage)
    }

    @Test func autoDetectIsRemembered() {
        let (settings, defaults) = makeSettings()
        settings.language = nil
        #expect(Settings(defaults: defaults).language == nil)
    }
}
