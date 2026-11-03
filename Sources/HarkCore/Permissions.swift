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
            guard !AXIsProcessTrusted() else { return }
            // Hark isn't signed with a developer certificate, so macOS ties the grant to one
            // exact build. After an update, the Hark switched on in Settings is the old build
            // and doesn't count. Clearing that entry makes macOS list this build instead.
            await Self.resetAccessibilityEntry()
            // kAXTrustedCheckOptionPrompt, spelled out to avoid a non-Sendable global.
            // The prompt it shows links to the Accessibility settings.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    private nonisolated static func resetAccessibilityEntry() async {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", id]
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            reset.terminationHandler = { _ in done.resume() }
            do { try reset.run() } catch { done.resume() }
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
