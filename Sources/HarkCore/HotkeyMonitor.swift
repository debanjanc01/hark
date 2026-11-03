import CoreGraphics
import os

/// A modifier key that is held to dictate.
public enum Hotkey: String, CaseIterable, Sendable {
    case rightOption, rightCommand, fn

    public var displayName: String {
        switch self {
        case .rightOption: "Right Option (⌥)"
        case .rightCommand: "Right Command (⌘)"
        case .fn: "Fn (🌐)"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .fn: 63
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        case .fn: .maskSecondaryFn
        }
    }
}

/// Watches a hold-to-talk modifier key system-wide with a listen-only event tap.
/// Requires the Accessibility permission.
@MainActor
public final class HotkeyMonitor {
    public var hotkey: Hotkey
    /// The key went down.
    public var onPress: () -> Void = {}
    /// The key came up without any other key pressed meanwhile.
    public var onRelease: () -> Void = {}
    /// Another key was pressed while holding the hotkey: it's being used as a
    /// regular modifier (e.g. ⌥← to jump words), so the dictation should be dropped.
    public var onCancel: () -> Void = {}

    private static let log = Logger(subsystem: "io.github.debanjanc01.hark", category: "hotkey")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var isHeld = false

    public init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// Returns false if the event tap could not be created (missing Accessibility permission).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        return true
    }

    fileprivate func handle(_ type: CGEventType, keyCode: Int64, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged where keyCode == hotkey.keyCode:
            let down = flags.contains(hotkey.flag)
            guard down != isHeld else { return }
            isHeld = down
            Self.log.debug("hotkey \(down ? "down" : "up", privacy: .public)")
            down ? onPress() : onRelease()
        case .keyDown where isHeld:
            isHeld = false
            Self.log.debug("another key pressed while holding: cancel")
            onCancel()
        default:
            break
        }
    }
}

// The tap is added to the main run loop, so this always runs on the main thread.
private func hotkeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        MainActor.assumeIsolated { monitor.handle(type, keyCode: keyCode, flags: flags) }
    }
    return Unmanaged.passUnretained(event)
}
