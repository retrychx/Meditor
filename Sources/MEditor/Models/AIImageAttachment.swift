import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - AI 聊天图片附件（仅内存，不落盘）

/// AI 聊天消息携带的图片附件。
///
/// 与编辑器图片粘贴（`EditorCoordinator.pasteImageFromPasteboard`）不同：
/// 聊天图片**不写工作区文件**，统一走内存 JPEG + base64，随消息发给多模态模型。
/// 数据不进会话持久化（base64 体积大，见 `AIChatMessage` 的 CodingKeys）。
struct AIImageAttachment: Identifiable, Sendable {
    let id: UUID
    /// 统一为 "image/jpeg"（AIImageProcessor 负责转换）
    let mimeType: String
    /// 处理后的 JPEG 数据（长边 ≤1568、≤1MB，由 AIImageProcessor 保证）
    let data: Data
    /// 处理后的像素尺寸（气泡缩略图 / 预览用）
    let width: Int
    let height: Int

    init(id: UUID = UUID(), mimeType: String, data: Data, width: Int, height: Int) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
        self.width = width
        self.height = height
    }

    /// base64 编码（发送时现算，避免在模型里冗余存一份）
    var base64: String { data.base64EncodedString() }

    /// OpenAI 多模态 data URL：`data:image/jpeg;base64,...`
    var dataURL: String { "data:\(mimeType);base64,\(base64)" }
}

#if os(macOS)
extension AIImageAttachment {
    /// 解码后的 NSImage（进程内缓存：气泡/芯片每次 body 求值都会取图，
    /// 不缓存则每次重渲染都解码一次 JPEG）。
    @MainActor var nsImage: NSImage? {
        let key = id.uuidString as NSString
        if let cached = Self.imageCache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        Self.imageCache.setObject(image, forKey: key)
        return image
    }

    /// 缓存总量很小（单条会话最多 4 张 × 1MB），交给 NSCache 内存压力淘汰即可。
    private static let imageCache = NSCache<NSString, NSImage>()
}
#endif
