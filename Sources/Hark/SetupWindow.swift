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
    private var result: NSTextField?

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

        let footnote = label("Hotkey, language and custom words are under the waveform icon in the menu bar.",
                             style: .callout)
        footnote.textColor = .secondaryLabelColor

        let done = NSButton(title: "Done", target: window, action: #selector(NSWindow.performClose))
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), done])
        buttons.widthAnchor.constraint(equalToConstant: 392).isActive = true

        return [label("Hark is ready. Try it here.", style: .title2), field, result, launchAtLogin, footnote, buttons]
    }

    func controlTextDidChange(_ notification: Notification) {
        guard tryField?.stringValue.isEmpty == false else { return }
        result?.stringValue = "✓ It works. Hold \(settings.hotkey.displayName) in any app to dictate."
        result?.textColor = .labelColor
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        try? loginItem.setEnabled(sender.state == .on)
        sender.state = loginItem.isEnabled ? .on : .off
    }

    /// A wrapping label in one of the system text styles, so it follows the person's settings.
    private func label(_ text: String, style: NSFont.TextStyle = .body, width: CGFloat = 392) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .preferredFont(forTextStyle: style)
        label.preferredMaxLayoutWidth = width
        return label
    }
}
