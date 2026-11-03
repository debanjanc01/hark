// Posts keyboard events like a real keyboard would.
//   key down | up   → press or release Right Option (Hark's default hotkey)
//   key tap <code>  → press and release a regular key
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let source = CGEventSource(stateID: .combinedSessionState)
if args[1] == "tap", let code = CGKeyCode(args[2]) {
    for down in [true, false] {
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
    }
} else {
    let down = args[1] == "down"
    let event = CGEvent(keyboardEventSource: source, virtualKey: 61, keyDown: down)!
    event.type = .flagsChanged
    event.flags = down ? .maskAlternate : []
    event.post(tap: .cghidEventTap)
}
// Events are delivered asynchronously; exiting immediately can drop them.
Thread.sleep(forTimeInterval: 0.05)
