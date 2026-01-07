// swift-tools-version: 5.7

import PackageDescription

// Relay Package Version: 4.4.9
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
                .target(name: "Mte"),
            ],
            path: "Classes",
            sources: [
               "Core/",
               "MKE/",
               "Kyber/",
               "MteRelay/"
           ],
           swiftSettings: [
               .define("MTE_SWIFT_PACKAGE_MANAGER")
            ],
        ),
        .binaryTarget(
            name: "mteBinary",
            path: "Classes/Mte/mte.xcframework"
        ),
        .target(
           name: "Mte",
           dependencies: [
               .target(name: "mteBinary")
           ],
           path: "Classes/Mte",
           exclude: ["mte.xcframework"]
       ),
    ]
)
