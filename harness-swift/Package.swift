// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ConductorHarness",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ConductorCore", targets: ["ConductorCore"]),
        .executable(name: "ConductorHarnessApp", targets: ["ConductorHarnessApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.16.0")
    ],
    targets: [
        .target(name: "ConductorCore"),
        .executableTarget(
            name: "ConductorHarnessApp",
            dependencies: [
                "ConductorCore",
                .product(name: "Collections", package: "swift-collections")
            ],
            path: "Sources/ConductorHarnessApp"
        ),
        .testTarget(
            name: "ConductorCoreTests",
            dependencies: ["ConductorCore"],
            path: "Tests/ConductorCoreTests"
        ),
        .testTarget(
            name: "ConductorHarnessAppTests",
            dependencies: [
                "ConductorCore",
                "ConductorHarnessApp",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/ConductorHarnessAppTests"
        )
    ]
)
