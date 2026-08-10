// swift-tools-version: 6.2
// A Swift line editor and interactive command shell for ArgumentParser tools.
//
// Backed by bestline (https://github.com/mattt/bestline-swift), which vendors
// Justine Tunney's single-file bestline.c. Unlike readline/libedit, bestline
// hands the completion callback the whole buffer plus the cursor position and
// supports inline hints -- both prerequisites for context-aware completion.

import PackageDescription

let package = Package(
    name: "LineEditor",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "LineEditor",
            targets: [
                "LineEditor",
            ]
        ),
        .library(
            name: "CommandREPL",
            targets: [
                "CommandREPL",
                "LineEditor",
            ]
        ),
        .executable(name: "repl", targets: ["repl"])
    ],
    dependencies: [
        // 1.8.0 is the floor for the ToolInfoV0 fields the completion engine
        // reads: CommandInfoV0.aliases plus ArgumentInfoV0.allValues,
        // allValueDescriptions, and completionKind.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
        .package(url: "https://github.com/mattt/bestline-swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "LineEditor",
            dependencies: [
                .product(name: "Bestline", package: "bestline-swift"),
            ],
        ),
        .target(
            name: "CommandREPL",
            dependencies: [
                "LineEditor",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .executableTarget(
            name: "repl",
            dependencies: [
                "LineEditor",
                "CommandREPL",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .testTarget(
            name: "CommandREPLTests",
            dependencies: [
                "CommandREPL",
                "LineEditor",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
    ]
)
