// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkEdit",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(url: "https://github.com/JohnSundell/Splash", from: "0.16.0"),
    ],
    targets: [
        .executableTarget(
            name: "MarkEdit",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Splash", package: "Splash"),
            ],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
