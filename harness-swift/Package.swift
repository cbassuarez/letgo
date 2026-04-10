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
    targets: [
        .target(name: "ConductorCore"),
        .executableTarget(
            name: "ConductorHarnessApp",
            dependencies: ["ConductorCore"],
            path: "Sources/ConductorHarnessApp"
        ),
        .testTarget(
            name: "ConductorCoreTests",
            dependencies: ["ConductorCore"],
            path: "Tests/ConductorCoreTests"
        )
    ]
)
