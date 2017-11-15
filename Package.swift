// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "CowExample",
    products: [
        .library(
            name: "CowExample",
            targets: ["CowExample"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "CowExample",
            dependencies: []),
        .testTarget(
            name: "CowExampleTests",
            dependencies: ["CowExample"]),
    ]
)
