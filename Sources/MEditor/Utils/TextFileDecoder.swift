import Foundation

/// 文本文件多编码解码的唯一实现（macOS / iOS 共享）。
///
/// 候选策略：UTF-8 → drop 尾字节重试（截断点可能切断多字节字符）→ UTF-16/32 家族。
/// 故意**不用 isoLatin1 兜底**：该编码对任意字节都"成功"，会把二进制文件
/// 或被截断的 UTF-8 解码成乱码文本（曾导致 CJK 文件整篇乱码的回归）。
enum TextFileDecoder {
    private static let candidateEncodings: [String.Encoding] = [
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian,
        .utf32,
        .utf32LittleEndian,
        .utf32BigEndian
    ]

    static func decode(contentsOf url: URL) throws -> String {
        // iCloud 占位符（本地无数据）：触发后台下载后抛出可读错误，用户稍候重试即可；
        // 下载完成后 FSEvents 会自动刷新文件树/重载 tab。
        if UbiquitousFileHelper.isUbiquitousItemNotDownloaded(url) {
            UbiquitousFileHelper.startDownloadingIfNeeded(url)
            throw UbiquitousFileError.notDownloaded(url)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            // ubiquitous 文件读取失败（如下载中断、已 eviction）时包装成用户可懂的错误
            if UbiquitousFileHelper.isUbiquitousItem(url) {
                UbiquitousFileHelper.startDownloadingIfNeeded(url)
                throw UbiquitousFileError.readFailed(url, underlying: error)
            }
            throw error
        }
        if let decoded = decode(data) {
            return decoded
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    static func decode(_ data: Data) -> String? {
        // 1. 严格 UTF-8
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        // 2. 截断点可能落在多字节字符中间：去掉末尾最多 3 字节重试 UTF-8
        for drop in 1...min(3, data.count) {
            if let decoded = String(data: data.dropLast(drop), encoding: .utf8) {
                return decoded
            }
        }
        // 3. UTF-16 / UTF-32 家族（无 isoLatin1 兜底，见类型注释）
        for encoding in candidateEncodings {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded
            }
        }
        return nil
    }
}
