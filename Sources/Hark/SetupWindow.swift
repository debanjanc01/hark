import AppKit
import HarkCore

/// The welcome window. While a permission is missing, it says what Hark needs and why,
/// with an Allow button per permission, so macOS's own prompts only appear once the
/// person asks for them. Once everything is allowed, it becomes a place to try Hark.
///
/// It opens on launch while a permission is missing, and whenever Hark is opened again:
/// the menu bar icon can be hidden (behind the notch when the menu bar is full), so this
/// is the one place that's always reachable.
@MainActor
final class SetupWindow: NSObject, NSTextFieldDelegate {
    private let settings: Settings
    private let loginItem = LoginItem(bundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.debanjanc01.hark")
    private let window: NSWindow
    private var shown: [Bool] = []
    private var tryField: NSTextField?
    private var customWords: NSTextField?
    private var result: NSTextField?
    /// Called when the hotkey is changed here.
    var onHotkeyChanged: () -> Void = {}

    init(settings: Settings) {
        self.settings = settings
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Hark"
        window.isReleasedWhenClosed = false
    }

    func show() {
        shown = []
        refresh()
        window.center()
        focus()
    }

    /// Redraws if a permission changed.
    func refresh() {
        let granted = Permission.allCases.map(\.isGranted)
        guard granted != shown else { return }
        let newlyGranted = zip(granted, shown).contains { now, before in now && !before }
        shown = granted

        let ready = !granted.contains(false)
        let stack = NSStackView(views: ready ? tryItViews() : permissionViews(granted))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 22, right: 24)
        stack.widthAnchor.constraint(equalToConstant: 440).isActive = true  // 392 + the insets
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        // macOS hands focus back to the previous app after its prompt or System Settings,
        // so come back here for the next step. Once the last one is granted, come back
        // even if the window was closed meanwhile: the next step is trying Hark.
        if newlyGranted, window.isVisible || ready {
            if !window.isVisible { window.center() }
            focus()
        }
    }

    /// Redraws with the current settings, e.g. after they're changed in the menu.
    func settingsChanged() {
        guard window.isVisible else { return }
        shown = []
        refresh()
    }

    /// The last dictation found no speech; say so if the person is trying Hark here.
    func noSpeechHeard() {
        guard window.isKeyWindow else { return }
        result?.stringValue = "Didn't catch that. Speak a little louder, or check the input in System Settings → Sound."
    }

    private func focus() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if let tryField { window.makeFirstResponder(tryField) }
    }

    // MARK: Permissions

    private func permissionViews(_ granted: [Bool]) -> [NSView] {
        tryField = nil
        customWords = nil
        result = nil
        let footnote = label("""
            Hark lives in the menu bar. If you can't see its waveform icon, the menu bar is full and \
            macOS hid it behind the notch: hold ⌘ and drag other icons away. Open Hark again anytime to come back here.
            """, style: .callout)
        footnote.textColor = .secondaryLabelColor
        let rows = Permission.allCases.indices.map { row($0, granted: granted) }
        return [
            label("Welcome to Hark", style: .title2),
            label("Hark types what you say into any app. It all runs on your Mac, so nothing you say leaves it. It needs two permissions:"),
        ] + rows + [footnote]
    }

    private func row(_ index: Int, granted: [Bool]) -> NSView {
        let permission = Permission.allCases[index]
        let isGranted = granted[index]
        let icon = NSImageView(image: NSImage(systemSymbolName: isGranted ? "checkmark.circle.fill" : "circle",
                                              accessibilityDescription: isGranted ? "Allowed" : "Not allowed")!)
        icon.contentTintColor = isGranted ? .systemGreen : .tertiaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        let purpose = label(permission.purpose, width: 270)
        purpose.textColor = .secondaryLabelColor
        let text = NSStackView(views: [label(permission.displayName, style: .headline), purpose])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [icon, text, NSView()])
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 392).isActive = true
        if !isGranted {
            let button = NSButton(title: "Allow…", target: self, action: #selector(allow))
            button.tag = index
            if granted.firstIndex(of: false) == index { button.keyEquivalent = "\r" }  // the next one to allow
            row.addArrangedSubview(button)
        }
        return row
    }

    @objc private func allow(_ sender: NSButton) {
        let permission = Permission.allCases[sender.tag]
        let asksInPlace = permission.asksInPlace
        Task {
            await permission.request()
            refresh()
            // The prompt is answered, Allow or not, and macOS has handed focus back to the
            // previous app: come back here for the next step.
            if asksInPlace, window.isVisible { focus() }
        }
    }

    // MARK: Try it

    private func tryItViews() -> [NSView] {
        let field = NSTextField(string: "")
        field.placeholderString = "Hold \(settings.hotkey.displayName) and say “Hark is listening.”"
        field.font = .preferredFont(forTextStyle: .body)
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 392).isActive = true
        field.heightAnchor.constraint(equalToConstant: 64).isActive = true
        tryField = field

        let result = label("Your words show up here, and in any app you're typing in.")
        result.textColor = .secondaryLabelColor
        self.result = result

        // On the first time only, Hark opens at login unless the person unticks this. After
        // that the box shows (and changes) the real login item, so turning it off sticks.
        if !settings.offeredLaunchAtLogin {
            settings.offeredLaunchAtLogin = true
            try? loginItem.setEnabled(true)
        }
        let launchAtLogin = NSButton(checkboxWithTitle: "Open Hark when I log in",
                                     target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLogin.state = loginItem.isEnabled ? .on : .off

        // The same settings as the menu bar menu, which can be hidden behind the notch.
        let hotkey = popUp(Hotkey.allCases.map(\.displayName),
                           selected: Hotkey.allCases.firstIndex(of: settings.hotkey), action: #selector(changeHotkey))
        let language = popUp(Settings.languageChoices.map(\.name),
                             selected: Settings.languageChoices.firstIndex { $0.code == settings.language },
                             action: #selector(changeLanguage))
        let words = NSTextField(string: settings.customWords)
        words.placeholderString = "Separate them with commas"
        words.delegate = self
        words.widthAnchor.constraint(equalToConstant: 280).isActive = true
        customWords = words
        let wordsHint = label("Names or words Hark keeps getting wrong.", style: .callout, width: 280)
        wordsHint.textColor = .secondaryLabelColor
        let wordsColumn = NSStackView(views: [words, wordsHint])
        wordsColumn.orientation = .vertical
        wordsColumn.alignment = .leading
        wordsColumn.spacing = 4

        let indicator = NSButton(checkboxWithTitle: "Show On-Screen Indicator",
                                 target: self, action: #selector(toggleIndicator))
        indicator.state = settings.showsIndicator ? .on : .off

        // In the menu's order.
        let grid = NSGridView(views: [
            [label("Hotkey", width: 104), hotkey],
            [label("Language", width: 104), language],
            [label("Custom words", width: 104), wordsColumn],
            [NSGridCell.emptyContentView, indicator],
            [NSGridCell.emptyContentView, launchAtLogin],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline

        let footnote = label("These settings are also under the waveform icon in the menu bar.", style: .callout)
        footnote.textColor = .secondaryLabelColor

        let about = NSButton(title: "About Hark", target: self, action: #selector(showAbout))
        let quit = NSButton(title: "Quit Hark", target: NSApp, action: #selector(NSApplication.terminate))
        let done = NSButton(title: "Done", target: window, action: #selector(NSWindow.performClose))
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [about, NSView(), quit, done])
        buttons.widthAnchor.constraint(equalToConstant: 392).isActive = true

        return [label("Hark is ready. Try it here.", style: .title2), field, result,
                separator(), grid, footnote, buttons]
    }

    func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField, field === customWords {
            settings.customWords = field.stringValue
            return
        }
        guard tryField?.stringValue.isEmpty == false else { return }
        result?.stringValue = "✓ It works. Hold \(settings.hotkey.displayName) in any app to dictate."
        result?.textColor = .labelColor
    }

    @objc private func changeHotkey(_ sender: NSPopUpButton) {
        settings.hotkey = Hotkey.allCases[sender.indexOfSelectedItem]
        onHotkeyChanged()
        tryField?.placeholderString = "Hold \(settings.hotkey.displayName) and say “Hark is listening.”"
    }

    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        settings.language = Settings.languageChoices[sender.indexOfSelectedItem].code
    }

    @objc private func showAbout() {
        StatusItemController.showAbout()
    }

    @objc private func toggleIndicator(_ sender: NSButton) {
        settings.showsIndicator = sender.state == .on
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        try? loginItem.setEnabled(sender.state == .on)
        sender.state = loginItem.isEnabled ? .on : .off
    }

    private func popUp(_ titles: [String], selected: Int?, action: Selector) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: titles)
        button.selectItem(at: selected ?? 0)
        button.target = self
        button.action = action
        return button
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 392).isActive = true
        return line
    }

    /// A wrapping label in one of the system text styles, so it follows the person's settings.
    private func label(_ text: String, style: NSFont.TextStyle = .body, width: CGFloat = 392) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .preferredFont(forTextStyle: style)
        label.preferredMaxLayoutWidth = width
        return label
    }
}
