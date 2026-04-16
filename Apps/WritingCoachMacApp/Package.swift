// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WritingCoachMacApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WritingCoachMacApp",
            dependencies: [
                .product(name: "WritingCoachCore", package: "WritingCoach")
            ]
        )
    ]
)

