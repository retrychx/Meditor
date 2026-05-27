// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MEditor",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MEditor",
            dependencies: [],
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "MEditorTests",
            dependencies: ["MEditor"]
        ),
    ]
)
