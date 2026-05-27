import Foundation

protocol PreviewExporterProtocol {
    var isExportAvailable: Bool { get }
    func export(format: PreviewExporter.ExportFormat,
                suggestedName: String,
                completion: @escaping (Result<URL, PreviewExporter.ExportError>) -> Void)
}
