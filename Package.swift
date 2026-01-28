// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AztecLib",
    products: [
        .library(
            name: "AztecLib",
            targets: ["AztecLib"]
        ),
    ],
    targets: [
        .target(
            name: "AztecLib",
            path: "AztecLib"
        ),
        .testTarget(
            name: "AztecLibTests",
            dependencies: ["AztecLib"],
            path: "AztecLibTests"
        ),
    ]
)
