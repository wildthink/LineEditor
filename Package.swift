// swift-tools-version: 6.2
// This package builds a simple CLI using libedit (BSD readline).
// On macOS, libedit is available by default.
// On Linux, install the dev package (e.g., `sudo apt-get install libedit-dev`).
// Some Linux distros require linking ncurses as well; we include it as needed.

import PackageDescription

let package = Package(
    name: "repl",
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
        .executable(name: "repl", targets: ["repl"])
    ],
    targets: [
        .executableTarget(
            name: "repl",
            dependencies: [
                "LineEditor"
            ],
        ),
        .target(
            name: "LineEditor",
            dependencies: [
                "CLibEdit",
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
