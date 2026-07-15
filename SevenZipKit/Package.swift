// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SevenZipKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SevenZipKit", targets: ["SevenZipKit"]),
        .executable(name: "sevenzip-cli", targets: ["sevenzip-cli"])
    ],
    targets: [
        .target(
            name: "SevenZipKit"
        ),
        .executableTarget(
            name: "sevenzip-cli",
            dependencies: ["SevenZipKit"]
        ),
        .testTarget(
            name: "SevenZipKitTests",
            dependencies: ["SevenZipKit"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
