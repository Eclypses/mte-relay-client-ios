// swift-tools-version: 5.7

import PackageDescription
import Foundation

// Relay Package Version: 5.2.0
// Mte Version: 4.2.1

// mte-client-ios dependency resolution:
//   - By default, resolve the published package from GitHub by version (SPM resolves
//     by tag, so `from:` matches `v4.2.1`). This is REQUIRED: SPM forbids a package
//     that is itself consumed by version (as this lib is, via the plugins' `from:`)
//     from depending on a *path* (unstable) package. So there is deliberately NO
//     filesystem sibling auto-detection here — that produced an illegal path dep and
//     broke transitive resolution for every version-pinned consumer (CI, TestFlight).
//   - Set MTE_CLIENT_IOS_PATH only when developing mte-client-ios itself locally
//     (i.e. when THIS package is the root, e.g. `swift build`), not for consumers.
let mteClientRemoteURL = "https://github.com/Eclypses/mte-client-ios.git"
let mteClientVersion = "4.2.1"

func mteClientLocalPath() -> String? {
    if let override = ProcessInfo.processInfo.environment["MTE_CLIENT_IOS_PATH"],
       !override.isEmpty {
        return override
    }
    return nil
}

let mteClientDependency: Package.Dependency = {
    if let path = mteClientLocalPath() {
        return .package(path: path)
    }
    return .package(url: mteClientRemoteURL, from: Version(stringLiteral: mteClientVersion))
}()

let package = Package(
    name: "Relay",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Relay",
            targets: ["Relay"]
        )
    ],
    dependencies: [
        mteClientDependency
    ],
    targets: [
        .target(
            name: "Relay",
            dependencies: [
                .product(name: "Mte", package: "mte-client-ios")
            ],
            path: "Classes/Relay"
        ),
        .testTarget(
            name: "RelayTests",
            dependencies: ["Relay"],
            path: "Tests/RelayTests"
        )
    ]
)
