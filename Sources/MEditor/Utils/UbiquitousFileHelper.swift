import Foundation

/// iCloud Drive 占位符（dataless ubiquitous item）的检测与下载触发（macOS / iOS 共享）。
///
/// 下载完成后由 FSEvents 触发文件树刷新和未修改 tab 的静默重载，
/// 这里只负责"识别 + 踢一下下载"，不做进度跟踪。
enum UbiquitousFileHelper {
    /// 是否为 ubiquitous item（iCloud Drive 容器内的文件）。普通本地文件返回 false。
    static func isUbiquitousItem(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]) else { return false }
        return values.isUbiquitousItem == true
    }

    /// 是否为尚未下载到本地的 iCloud 文件（本地只有占位符）。
    /// 仅对 ubiquitous item 有意义；普通文件或 resourceValues 取不到时返回 false。
    static func isUbiquitousItemNotDownloaded(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]), values.isUbiquitousItem == true else { return false }
        return values.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// 未下载则触发后台下载。静默失败：下载本身可能因网络等原因失败，
    /// 调用方随后的读取会走正常错误路径。
    static func startDownloadingIfNeeded(_ url: URL) {
        guard isUbiquitousItemNotDownloaded(url) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}

/// iCloud 文件读取路径的可读错误：面向用户（Tab 打开）和 Agent 工具各自包装语义。
enum UbiquitousFileError: LocalizedError {
    case notDownloaded(URL)
    case readFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notDownloaded(let url):
            return L("error.icloudNotDownloaded", url.lastPathComponent)
        case .readFailed(let url, let e):
            return L("error.icloudReadFailed", url.lastPathComponent, e.localizedDescription)
        }
    }
}
