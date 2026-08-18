// Quick Look 预览扩展。
//
// 这个文件是 SwiftPM 对 executable target 的形式要求（必须有 main.swift 或 @main）。
// 真正的入口由 Package.swift 里的链接选项 `-e _NSExtensionMain` 指定：
// 进程启动后直接进入 Foundation 的 NSExtensionMain，由系统扩展运行时读取
// Info.plist 的 NSExtensionPrincipalClass（MEditorQLPreviewViewController）并实例化。
// 这里的任何顶层代码都不会被执行，所以保持为空。
