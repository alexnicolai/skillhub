// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SkillHub",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "SkillHub",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "SkillHub",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SkillHubTests",
            dependencies: ["SkillHub"],
            path: "SkillHubTests"
        ),
    ]
)
