// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PromptBar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "PromptBarKit",
            targets: ["PromptBarKit"]
        ),
        .executable(
            name: "PromptBar",
            targets: ["PromptBarApp"]
        )
    ],
    targets: [
        .target(
            name: "PromptBarKit",
            path: "Sources/PromptBarKit",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "PromptBarApp",
            dependencies: ["PromptBarKit"],
            path: "Sources/PromptBarApp"
        ),
        .testTarget(
            name: "PromptBarKitTests",
            dependencies: ["PromptBarKit"],
            path: "Tests/PromptBarKitTests"
        )
    ]
)
