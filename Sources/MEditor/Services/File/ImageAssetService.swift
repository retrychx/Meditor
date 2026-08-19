import Foundation

// MARK: - ImageAssetService

/// 图片粘贴/拖拽的落盘与 Markdown 引用生成。
///
/// 落盘策略（paste 与 drop 共用同一套目录决策）：
/// - 首选文档同级的 `assets/` 目录，插入相对路径引用（文档移动时引用不失效）；
/// - 文档目录不可写（只读卷、权限不足）时退到 Application Support 下的
///   `MEditor/PastedImages/`，插入百分号编码的绝对路径；
/// - 两级都失败则抛错，调用方降级为默认粘贴行为并报错。
///
/// 拖拽进编辑器的图片文件另有一条「不复制」快路径：文件已在工作区内时
/// 直接生成相对路径引用，不产生副本。
final class ImageAssetService {

    struct Result: Equatable {
        /// 图片文件最终在磁盘上的位置。
        let fileURL: URL
        /// 可直接插入文档的 Markdown 图片语法（不含尾随换行）。
        let markdown: String
    }

    enum ImageAssetError: LocalizedError {
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let e): return L("image.pasteFailed", e.localizedDescription)
            }
        }
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff"]

    /// urlPathAllowed 本身不含空格；再剔除 () 防止提前闭合 Markdown 链接。
    static let markdownLinkPathAllowed: CharacterSet =
        CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))

    /// 粘贴落盘失败时的兜底目录（Application Support/MEditor/PastedImages）。
    private let fallbackDir: URL
    private let fm = FileManager.default

    init(fallbackBaseDir: URL? = nil) {
        let base = fallbackBaseDir
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fallbackDir = base.appendingPathComponent("MEditor/PastedImages", isDirectory: true)
    }

    // MARK: - Paste（粘贴板图片数据）

    /// 把粘贴板里的图片数据落盘并生成 Markdown 引用。
    /// 优先写入文档同级 assets/（相对路径引用）；失败时写兜底目录（绝对路径引用）。
    func savePastedImage(data: Data, fileExtension ext: String,
                         documentURL: URL, now: Date = Date()) throws -> Result {
        let docDir = documentURL.deletingLastPathComponent()
        let baseName = Self.timestampedBaseName(date: now, suffix: Self.randomSuffix())
        if let url = try? writeImage(data, baseName: baseName, ext: ext, into: docDir.appendingPathComponent("assets", isDirectory: true)) {
            return Result(fileURL: url, markdown: Self.markdownReference(alt: url.deletingPathExtension().lastPathComponent,
                                                                         path: relativeOrAbsolute(from: docDir, to: url)))
        }
        do {
            let url = try writeImage(data, baseName: baseName, ext: ext, into: fallbackDir)
            return Result(fileURL: url, markdown: Self.markdownReference(alt: url.deletingPathExtension().lastPathComponent,
                                                                         path: url.path))
        } catch {
            throw ImageAssetError.writeFailed(error)
        }
    }

    // MARK: - Drop（Finder 拖入的图片文件）

    /// 为拖入的图片文件生成 Markdown 引用。
    /// 文件已在工作区内 → 直接引用（相对路径，不复制）；否则复制进 assets/ 再引用。
    func referenceForDroppedFile(_ url: URL, documentURL: URL, workspaceRoot: URL?) throws -> Result {
        let std = url.standardizedFileURL
        let docDir = documentURL.deletingLastPathComponent().standardizedFileURL
        let alt = std.deletingPathExtension().lastPathComponent

        if let root = workspaceRoot?.standardizedFileURL,
           std.path == root.path || std.path.hasPrefix(root.path + "/") {
            return Result(fileURL: std, markdown: Self.markdownReference(alt: alt,
                                                                         path: relativeOrAbsolute(from: docDir, to: std)))
        }

        let filename = std.lastPathComponent
        if let dest = try? copyImage(from: std, filename: filename,
                                     into: docDir.appendingPathComponent("assets", isDirectory: true)) {
            return Result(fileURL: dest, markdown: Self.markdownReference(alt: alt,
                                                                          path: relativeOrAbsolute(from: docDir, to: dest)))
        }
        do {
            let dest = try copyImage(from: std, filename: filename, into: fallbackDir)
            return Result(fileURL: dest, markdown: Self.markdownReference(alt: alt, path: dest.path))
        } catch {
            throw ImageAssetError.writeFailed(error)
        }
    }

    // MARK: - 命名与路径（纯逻辑，供测试）

    /// 粘贴图片的文件名主干：yyyyMMdd-HHmmss-xxxx（xxxx 为随机 4 位十六进制）。
    static func timestampedBaseName(date: Date, suffix: String) -> String {
        "\(timestampFormatter.string(from: date))-\(suffix)"
    }

    static func randomSuffix() -> String {
        String(format: "%04x", Int.random(in: 0...0xFFFF))
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// 文件名去重：同名已存在时追加 -2、-3…
    static func uniqueURL(in dir: URL, filename: String, fileManager fm: FileManager = .default) -> URL {
        var candidate = dir.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let ns = filename as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var i = 2
        while true {
            let name = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    /// baseDir → target 的相对路径（支持 ../）；两者相同返回 nil。
    static func relativePath(from baseDir: URL, to target: URL) -> String? {
        let base = baseDir.standardizedFileURL.pathComponents
        let dest = target.standardizedFileURL.pathComponents
        var i = 0
        while i < base.count, i < dest.count, base[i] == dest[i] { i += 1 }
        var parts = Array(repeating: "..", count: base.count - i)
        parts.append(contentsOf: dest[i...])
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// 能算相对路径就用相对路径，否则退回绝对路径。
    private func relativeOrAbsolute(from baseDir: URL, to target: URL) -> String {
        Self.relativePath(from: baseDir, to: target) ?? target.path
    }

    /// Markdown 链接路径：空格/括号/非 ASCII 字符做百分号编码。
    static func escapedPath(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: markdownLinkPathAllowed) ?? path
    }

    /// alt 文本里的方括号会破坏图片语法，直接剔除（与既有拖拽行为一致）。
    static func sanitizedAlt(_ name: String) -> String {
        name.replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
    }

    static func markdownReference(alt: String, path: String) -> String {
        "![\(sanitizedAlt(alt))](\(escapedPath(path)))"
    }

    // MARK: - Private

    private func writeImage(_ data: Data, baseName: String, ext: String, into dir: URL) throws -> URL {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = Self.uniqueURL(in: dir, filename: "\(baseName).\(ext)", fileManager: fm)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func copyImage(from source: URL, filename: String, into dir: URL) throws -> URL {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = Self.uniqueURL(in: dir, filename: filename, fileManager: fm)
        try fm.copyItem(at: source, to: dest)
        return dest
    }
}
