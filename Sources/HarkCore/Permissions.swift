import AppKit
import AVFoundation
import ApplicationServices

/// The macOS privacy permissions Hark needs.
public enum Permission: CaseIterable, Sendable {
    /// Record your voice.
    case microphone
    /// See the hotkey from any app, and paste the transcript into the focused one.
    /// (Accessibility covers the hotkey's event tap too, so Input Monitoring isn't needed.)
    case accessibility

    public var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        }
    }

    /// Why Hark needs it, in a few words.
    public var purpose: String {
        switch self {
        case .microphone: "To hear you while you hold the hotkey."
        case .accessibility: "To see when you press the hotkey, and to type the text for you."
        }
    }

    @MainActor
    public var isGranted: Bool {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: AXIsProcessTrusted()
        }
    }

    /// Shows the system prompt where macOS offers one, otherwise opens the Settings pane.
    @MainActor
    public func request() async {
        switch self {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                openSettings()
            }
        case .accessibility:
            // kAXTrustedCheckOptionPrompt, spelled out to avoid a non-Sendable global.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) { openSettings() }
        }
    }

    @MainActor
    public func openSettings() {
        let anchor = switch self {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
