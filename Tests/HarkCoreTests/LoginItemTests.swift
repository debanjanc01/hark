import Foundation
import Testing
@testable import HarkCore

struct LoginItemTests {
    private func makeItem() -> (LoginItem, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hark-tests-\(UUID().uuidString)")
        return (LoginItem(bundleIdentifier: "com.example.hark", launchAgentsDirectory: directory), directory)
    }

    @Test func togglesLaunchAgent() throws {
        let (item, directory) = makeItem()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!item.isEnabled)

        try item.setEnabled(true)
        #expect(item.isEnabled)
        let data = try Data(contentsOf: directory.appendingPathComponent("com.example.hark.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == "com.example.hark")
        #expect(plist["ProgramArguments"] as? [String] == ["/usr/bin/open", "-b", "com.example.hark"])
        #expect(plist["RunAtLoad"] as? Bool == true)

        try item.setEnabled(false)
        #expect(!item.isEnabled)
        try item.setEnabled(false)  // disabling twice is fine
    }
}
