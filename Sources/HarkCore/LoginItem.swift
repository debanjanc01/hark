import Foundation
import ServiceManagement

/// Starts Hark at login with a LaunchAgent that opens the app by bundle identifier.
///
/// `SMAppService.mainApp` remembers the app's path, which breaks when Homebrew upgrades
/// Hark into a new versioned folder; opening by bundle identifier always finds the
/// current copy.
public struct LoginItem {
    public let bundleIdentifier: String
    private let agentURL: URL

    public init(bundleIdentifier: String,
                launchAgentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/LaunchAgents")) {
        self.bundleIdentifier = bundleIdentifier
        agentURL = launchAgentsDirectory.appendingPathComponent("\(bundleIdentifier).plist")
    }

    public var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            let agent: [String: Any] = [
                "Label": bundleIdentifier,
                "ProgramArguments": ["/usr/bin/open", "-b", bundleIdentifier],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
                // Lets System Settings → Login Items show this as Hark rather than "open".
                "AssociatedBundleIdentifiers": [bundleIdentifier],
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: agentURL, options: .atomic)
        } else if isEnabled {
            try FileManager.default.removeItem(at: agentURL)
        }
    }

    /// Moves a login item registered by Hark 0.1 (via SMAppService) to the LaunchAgent.
    @MainActor
    public func migrateFromAppService() {
        guard SMAppService.mainApp.status == .enabled else { return }
        try? SMAppService.mainApp.unregister()
        try? setEnabled(true)
    }
}
