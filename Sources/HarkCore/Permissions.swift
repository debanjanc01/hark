import AppKit
import AVFoundation
import ApplicationServices

/// The macOS privacy permissions Hark needs.
public enum Permission: CaseIterable, Sendable {
    /// Record your voice.
    case microphone
    /// See the hotkey from any app.
    case inputMonitoring
    /// Paste the transcript into the focused app.
    case accessibility

    public var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }

    @MainActor
    public var isGranted: Bool {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .inputMonitoring: CGPreflightListenEventAccess()
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
        case .inputMonitoring:
            if !CGRequestListenEventAccess() { openSettings() }
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
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
