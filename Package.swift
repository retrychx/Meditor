// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Sparkle 2（自动更新）。两种来源二选一：
//   - 默认（CI/全新克隆）：远程 SPM 包，xcframework 由 SwiftPM 自行下载
//   - Vendor/Sparkle.xcframework 存在时（本机 GitHub 直连拉不动二进制时的逃生舱）：
//     本地 binaryTarget，不走网络。Vendor/ 已 gitignore，手动下载放置：
//     https://github.com/sparkle-project/Sparkle/releases/download/<ver>/Sparkle-for-Swift-Package-Manager.zip
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let vendoredSparkle = packageDir + "/Vendor/Sparkle.xcframework"
let useVendoredSparkle = FileManager.default.fileExists(atPath: vendoredSparkle + "/Info.plist")

var targets: [Target] = [
    .executableTarget(
        name: "MEditor",
        dependencies: useVendoredSparkle
            ? [.target(name: "Sparkle")]
            : [.product(name: "Sparkle", package: "Sparkle")],
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
if useVendoredSparkle {
    targets.append(.binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework"))
}

let package = Package(
    name: "MEditor",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: useVendoredSparkle ? [] : [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: targets
)
