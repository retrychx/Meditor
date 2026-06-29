import Foundation

/// 代表 Markdown 文件中的一个 checkbox 条目。
struct TodoItem: Identifiable {
    /// 稳定 id：基于文件路径 + 行号，扫描结果 id 不再每次随机，避免列表动画重置。
    let id: UUID
    var text: String
    var isChecked: Bool
    let fileURL: URL
    let lineIndex: Int

    /// 根据文件路径 + 行号生成确定性 UUID（v5 命名空间）。
    static func stableID(fileURL: URL, lineIndex: Int) -> UUID {
        let key = "\(fileURL.path):\(lineIndex)"
        // 用简单哈希映射到 UUID 字节（不要求密码安全，只需稳定唯一）
        var hash1: UInt64 = 14695981039346656037
        var hash2: UInt64 = 14695981039346656037
        for (i, byte) in key.utf8.enumerated() {
            if i % 2 == 0 {
                hash1 ^= UInt64(byte)
                hash1 &*= 1099511628211
            } else {
                hash2 ^= UInt64(byte)
                hash2 &*= 1099511628211
            }
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: hash1.bigEndian) { bytes.replaceSubrange(0..<8, with: $0) }
        withUnsafeBytes(of: hash2.bigEndian) { bytes.replaceSubrange(8..<16, with: $0) }
        // 设置 variant（RFC 4122）和 version（4，随机）位
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
