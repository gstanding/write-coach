// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WritingCoachiOSApp",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WritingCoachiOSApp",
            dependencies: [
                .product(name: "WritingCoachCore", package: "WritingCoach")
            ]
        )
    ]
)

