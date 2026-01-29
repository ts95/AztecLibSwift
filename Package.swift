// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AztecLib",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "AztecLib",
            targets: ["AztecLib"]
        ),
    ],
    targets: [
        .target(
            name: "AztecLib",
            path: "AztecLib",
            exclude: ["Docs"]
        ),
        .testTarget(
            name: "AztecLibTests",
            dependencies: ["AztecLib"],
            path: "AztecLibTests"
        ),
    ]
)
