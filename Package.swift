// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WritingCoach",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WritingCoachCore",
            targets: ["WritingCoachCore"]
        ),
        .executable(
            name: "writingcoach",
            targets: ["WritingCoachCLI"]
        )
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite3"
        ),
        .target(
            name: "WritingCoachCore",
            dependencies: ["CSQLite3"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "WritingCoachCLI",
            dependencies: ["WritingCoachCore"]
        ),
        .testTarget(
            name: "WritingCoachCoreTests",
            dependencies: ["WritingCoachCore"]
        )
    ]
)
