// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FileWidgets",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "FileWidgetsApp",
            targets: ["FileWidgetsApp"]
        ),
    ],
    targets: [
        .target(
            name: "FileWidgetsSupport",
            path: "Sources/FileWidgetsSupport"
        ),
        .executableTarget(
            name: "FileWidgetsApp",
            dependencies: ["FileWidgetsSupport"],
            path: "Sources/FileWidgetsApp"
        ),
        .executableTarget(
            name: "VisibilityGuardian",
            dependencies: ["FileWidgetsSupport"],
            path: "Sources/VisibilityGuardian"
        ),
    ]
)
