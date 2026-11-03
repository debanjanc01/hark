import AppKit
import HarkCore

/// The welcome window: what Hark needs and why, with an Allow button per permission, so
/// macOS's own prompts only appear once the person asks for them. It opens on launch
/// while a permission is missing, and whenever Hark is opened again: the menu bar icon
/// can be hidden (behind the notch when the menu bar is full), so this is the one place
/// that's always reachable.
@MainActor
final class SetupWindow {
    private let window: NSWindow
    private var shown: [Bool] = []
    private var targets: [ClosureTarget] = []  // NSButton.target is weak

    init() {
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Hark"
        window.isReleasedWhenClosed = false
    }

    func show(hotkey: Hotkey) {
        shown = []
        refresh(hotkey: hotkey)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Redraws if a permission changed.
    func refresh(hotkey: Hotkey) {
        let granted = Permission.allCases.map(\.isGranted)
        guard granted != shown else { return }
        shown = granted
        targets = []

        let ready = !granted.contains(false)
        let title = label(ready ? "Hark is ready" : "Welcome to Hark", style: .title2)
        let intro = label(ready
            ? "You can close this window. Hark keeps running in the menu bar."
            : "Hark types what you say into any app. It all runs on your Mac, so nothing you say leaves it. It needs two permissions:")
        let rows = zip(Permission.allCases, granted).map(row)
        let howTo = label("To dictate, click where you want the text, hold \(hotkey.displayName) and talk, then let go.")
        let footnote = label("""
            Settings are under the waveform icon in the menu bar. If you can't see it, the menu bar is full \
            and macOS hid it behind the notch: hold ⌘ and drag other icons away. Open Hark again anytime to come back here.
            """, style: .callout)
        footnote.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, intro] + rows + [howTo, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 22, right: 24)
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
    }

    private func row(_ permission: Permission, granted: Bool) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: granted ? "checkmark.circle.fill" : "circle",
                                              accessibilityDescription: granted ? "Allowed" : "Not allowed")!)
        icon.contentTintColor = granted ? .systemGreen : .tertiaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        let name = label(permission.displayName, style: .headline)
        let purpose = label(permission.purpose, width: 270)
        purpose.textColor = .secondaryLabelColor
        let text = NSStackView(views: [name, purpose])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [icon, text, NSView()])
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 392).isActive = true
        if !granted {
            let target = ClosureTarget { Task { await permission.request() } }
            targets.append(target)
            let button = NSButton(title: "Allow…", target: target, action: #selector(ClosureTarget.invoke))
            if targets.count == 1 { button.keyEquivalent = "\r" }  // the first missing one is the default
            row.addArrangedSubview(button)
        }
        return row
    }

    /// A wrapping label in one of the system text styles, so it follows the person's settings.
    private func label(_ text: String, style: NSFont.TextStyle = .body, width: CGFloat = 392) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .preferredFont(forTextStyle: style)
        label.preferredMaxLayoutWidth = width
        return label
    }
}
