// swift-tools-version: 5.7

import PackageDescription
import Foundation

// Relay Package Version: 5.0.0
// MteClient Version: 4.2.1

// mte-client-ios dependency resolution:
//   - If the sibling package is checked out next to this repo (local development),
//     resolve it by path so local edits are picked up with no publish step.
//   - Otherwise (CI agents, external consumers), resolve the published package
//     from GitHub by version. SPM resolves by tag, so `from:` matches `v4.2.1`.
// An explicit MTE_CLIENT_IOS_PATH env var overrides the auto-detection.
let mteClientRemoteURL = "https://github.com/Eclypses/mte-client-ios.git"
let mteClientVersion = "4.2.1"

func mteClientLocalPath() -> String? {
    if let override = ProcessInfo.processInfo.environment["MTE_CLIENT_IOS_PATH"],
       !override.isEmpty {
        return override
    }
    let sibling = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // .../mte-relay-client-ios
        .deletingLastPathComponent()   // .../Packages
        .appendingPathComponent("mte-client-ios")
    return FileManager.default.fileExists(atPath: sibling.path) ? sibling.path : nil
}

let mteClientDependency: Package.Dependency = {
    if let path = mteClientLocalPath() {
        return .package(path: path)
    }
    return .package(url: mteClientRemoteURL, from: Version(stringLiteral: mteClientVersion))
}()

let package = Package(
    name: "MteRelay",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MteRelay",
            targets: ["MteRelay"]
        )
    ],
    dependencies: [
        mteClientDependency
    ],
    targets: [
        .target(
            name: "MteRelay",
            dependencies: [
                .product(name: "MteClient", package: "mte-client-ios")
            ],
            path: "Classes/MteRelay"
        ),
        .testTarget(
            name: "MteRelayTests",
            dependencies: ["MteRelay"],
            path: "Tests/MteRelayTests"
        )
    ]
)
