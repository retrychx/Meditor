// swift-tools-version: 6.2
import Foundation
import PackageDescription

// Swift 6 语言模式：app 与测试 target 均在 Swift 6 严格并发检查下编译。
// 注意：不能对测试 target 用 defaultIsolation(MainActor.self)——XCTestCase 的
// setUp/tearDown/init(invocation:) 是 nonisolated，默认主 actor 会让所有重写
// 报「different actor isolation from nonisolated overridden declaration」。
let appSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]
let testSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

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
        ],
        swiftSettings: appSwiftSettings
    ),
    // Quick Look 预览扩展（Finder 空格预览 .md）。编译产物是裸可执行文件，
    // appex bundle 由 scripts/bundle.sh 手工组装（Info.plist / 资源 / 签名）。
    // 不内嵌资源：Preview 渲染资源打包时从主 app 拷贝，保证与 app 预览管线同源。
    .executableTarget(
        name: "MEditorQuickLook",
        exclude: ["Info.plist", "Entitlements.plist"],
        resources: [
            .copy("Resources")
        ],
        swiftSettings: appSwiftSettings,
        linkerSettings: [
            // appex 的入口必须是 Foundation 的 NSExtensionMain。该符号由
            // Foundation 导出但没有公开头文件声明（macOS SDK），Swift 侧无法
            // 直接调用——与 Xcode 扩展模板一样，用 -e 链接选项改入口符号。
            // main.swift 只是 SwiftPM 的形式要求，运行时不会被执行。
            .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
        ]
    ),
    // 测试 target 与 app 同等严格（v6 + 默认主 actor 隔离）。
    .testTarget(
        name: "MEditorTests",
        dependencies: ["MEditor"],
        swiftSettings: testSwiftSettings
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
