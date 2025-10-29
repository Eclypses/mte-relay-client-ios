// swift-tools-version: 5.7

import PackageDescription

// Relay Package Version: 4.4.4
// Mte Version: 4.1.0

let package = Package(
    name: "MteRelay",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "MteRelay",
            targets: ["MteRelay"]
        ),
    ],
    targets: [
        .target(
            name: "MteRelay",
            dependencies: [
                .target(name: "mteBinary") // Our binary dependency
            ],
            // 'path' points to the root of your Swift source files.
            // Since Mte/ has no Swift, it's not a direct source root.
            // If your actual Swift files are primarily in Core, MKE, Kyber, MteRelay,
            // and those are directly inside 'Classes/', then 'Classes' is the path.
            path: "Classes",
            // We need to tell SPM which subdirectories *within* 'Classes' contain Swift code
            // for the MteRelay module.
            // Exclude the 'Mte' directory itself from Swift compilation,
            // as it only contains the binary and headers.
            exclude: ["Mte"], // Exclude the entire 'Mte' subdirectory from Swift source compilation
            // Explicitly list the directories that contain Swift source files
            sources: [
                "Core",   // Includes all Swift files in Classes/Core
                "MKE",    // Includes all Swift files in Classes/MKE
                "Kyber",  // Includes all Swift files in Classes/Kyber
                "MteRelay" // Includes all Swift files in Classes/MteRelay
            ],
            // Remove all swiftSettings that defined MTE_SWIFT_PACKAGE_MANAGER
            swiftSettings: []
        ),
        
        // This binary target remains separate.
        // It points directly to the xcframework within the 'Mte' subdirectory.
        .binaryTarget(
            name: "mteBinary",
            path: "Classes/Mte/mte.xcframework" // Path to the binary framework
        ),
    ]
)