// swift-tools-version: 6.2
// This package builds a simple Swift wrapper for libedit (BSD readline).
// On macOS, libedit is available by default.
// On Linux, install the dev package (e.g., `sudo apt-get install libedit-dev`).
// Some Linux distros require linking ncurses as well; we include it as needed.

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
                "CLibEdit",
            ]
        ),
        .library(
            name: "CommandREPL",
            targets: [
                "CommandREPL",
                "LineEditor",
                "CLibEdit",
            ]
        ),
        .executable(name: "repl", targets: ["repl"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "repl",
            dependencies: [
                "LineEditor",
                "CommandREPL",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .target(
            name: "LineEditor",
            dependencies: [
                "CLibEdit",
            ],
        ),
        .target(
            name: "CommandREPL",
            dependencies: [
                "LineEditor",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        // C shim target that wraps libedit functions in a stable ABI
        .target(
            name: "CLibEdit",
            path: "Sources/CLibEdit",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("edit"),
                .linkedLibrary("ncurses", .when(platforms: [.linux]))
            ]
        ),
    ]
)
