// A window with a focused text view. After N seconds it writes its text to a file and quits.
// Usage: target <seconds> <output file>
import AppKit

let seconds = Double(CommandLine.arguments[1])!
let output = CommandLine.arguments[2]
let app = NSApplication.shared
app.setActivationPolicy(.regular)

// ⌘V only works through an Edit menu, as in any real app.
let mainMenu = NSMenu(), appItem = NSMenuItem(), editItem = NSMenuItem()
mainMenu.addItem(appItem)
mainMenu.addItem(editItem)
appItem.submenu = NSMenu()
let edit = NSMenu(title: "Edit")
edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editItem.submenu = edit
app.mainMenu = mainMenu

let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 600, height: 200), styleMask: [.titled],
                      backing: .buffered, defer: false)
window.title = "Hark E2E target"
let text = NSTextView(frame: window.contentView!.bounds)
text.font = .systemFont(ofSize: 18)
window.contentView = text
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(text)
app.activate(ignoringOtherApps: true)

DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    try? text.string.write(toFile: output, atomically: true, encoding: .utf8)
    exit(0)
}
app.run()
