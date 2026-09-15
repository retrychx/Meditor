import Foundation

/// 导出协调器协议。AppKit 的保存面板 / WKWebView 均在主线程使用，故整体 @MainActor。
@MainActor
protocol PreviewExporterProtocol {
    var isExportAvailable: Bool { get }
    func export(format: PreviewExporter.ExportFormat,
                suggestedName: String,
                completion: @escaping @Sendable (Result<URL, PreviewExporter.ExportError>) -> Void)
}
