import AppKit
import HarkCore
import ServiceManagement

/// The menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    enum Icon {
        case loading, idle, needsAttention
        case listening(level: Float)
        case transcribing(phase: Double)
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: Settings
    private let menu = NSMenu()

    /// Set by the controller to describe the current state at the top of the menu.
    var status = "Loading speech model…"
    var onSettingsChanged: () -> Void = {}

    init(settings: Settings) {
        self.settings = settings
        super.init()
        menu.delegate = self
        item.menu = menu
        item.button?.toolTip = "Hark"
        setIcon(.loading)
    }

    func setIcon(_ icon: Icon) {
        guard let button = item.button else { return }
        // Template images only, so macOS colors the icon like the rest of the menu bar
        // (white or black depending on the wallpaper and appearance).
        let (symbol, value): (String, Double?) = switch icon {
        case .loading: ("waveform", 0.3)
        case .idle: ("waveform", nil)
        case .needsAttention: ("waveform.slash", nil)
        case .listening(let level): ("waveform", 0.15 + 0.85 * Double(level))
        case .transcribing(let phase): ("waveform", phase)
        }
        let image = value.map { NSImage(systemSymbolName: symbol, variableValue: $0, accessibilityDescription: "Hark") }
            ?? NSImage(systemSymbolName: symbol, accessibilityDescription: "Hark")
        image?.isTemplate = true
        button.image = image
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled(status))
        menu.addItem(disabled("Hold \(settings.hotkey.displayName) to dictate"))

        let missing = Permission.allCases.filter { !$0.isGranted }
        if !missing.isEmpty {
            menu.addItem(.separator())
            for permission in missing {
                let item = action("Grant \(permission.displayName) Access…") {
                    Task { await permission.request() }
                }
                item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(submenu("Hotkey", Hotkey.allCases.map { hotkey in
            checked(hotkey.displayName, settings.hotkey == hotkey) { [self] in
                settings.hotkey = hotkey
                onSettingsChanged()
            }
        }))
        let languageNames = Locale.current
        menu.addItem(submenu("Language", [checked("Auto-Detect", settings.language == nil) { [self] in
            settings.language = nil
        }] + Transcriber.languages.map { code in
            checked(languageNames.localizedString(forLanguageCode: code)?.capitalized ?? code,
                    settings.language == code) { [self] in settings.language = code }
        }))
        menu.addItem(checked("Show On-Screen Indicator", settings.showsIndicator) { [self] in
            settings.showsIndicator.toggle()
        })
        menu.addItem(checked("Launch at Login", SMAppService.mainApp.status == .enabled) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        })

        menu.addItem(.separator())
        menu.addItem(action("About Hark") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
        })
        let quit = action("Quit Hark") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private static let credits = NSAttributedString(
        string: "Local, private dictation.\nSpeech recognition by Whistle and the Needle engine from Cactus Compute (Apache-2.0).",
        attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor])

    // MARK: Menu item helpers

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ClosureTarget.invoke), keyEquivalent: "")
        let target = ClosureTarget(handler)
        item.target = target
        item.representedObject = target  // NSMenuItem.target is weak; keep the target alive
        return item
    }

    private func checked(_ title: String, _ isOn: Bool, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = action(title, handler)
        item.state = isOn ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }
}

@MainActor
private final class ClosureTarget: NSObject {
    private let handler: @MainActor () -> Void
    init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}
