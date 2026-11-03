// swift-tools-version: 6.0
import PackageDescription

// Fetched by scripts/fetch-deps.sh (pinned + checksum-verified).
let needleLibDir = Context.packageDirectory + "/vendor/needle"

let package = Package(
    name: "Hark",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Hark", targets: ["Hark"]),
    ],
    targets: [
        .target(
            name: "CNeedle",
            linkerSettings: [
                .unsafeFlags(["-L\(needleLibDir)"]),
                .linkedLibrary("needle"),
                .linkedLibrary("c++"),
            ]
        ),
        .target(name: "HarkCore", dependencies: ["CNeedle"]),
        .executableTarget(name: "Hark", dependencies: ["HarkCore"]),
        .testTarget(name: "HarkCoreTests", dependencies: ["HarkCore"]),
    ]
)
