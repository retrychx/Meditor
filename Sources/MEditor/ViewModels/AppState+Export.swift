import Foundation

/// 导出前检查清单的上下文：待导出的格式 + 建议文件名 + 检出的问题。
struct ExportPreflightContext: Identifiable {
    let id = UUID()
    let format: PreviewExporter.ExportFormat
    let suggestedName: String
    let issues: [DocumentIssue]

    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.count - errorCount }
}

// MARK: - 导出统一入口（预检 → PDF 选项 → 真正导出）

extension AppState {

    /// 导出统一入口。markdown 文档导出 HTML/PDF 且开启了预检时，
    /// 先跑 DocumentDiagnostics；有问题弹检查清单，无问题直接走后续流程。
    func requestExport(_ format: PreviewExporter.ExportFormat) {
        let suggestedName = selectedTab?.url.deletingPathExtension().lastPathComponent ?? "Untitled"
        if AppSettings.shared.exportPreflightEnabled,
           format == .html || format == .pdf,
           let tab = selectedTab, tab.language == .markdown {
            let issues = DocumentDiagnostics.issues(in: tab.content, fileURL: tab.url) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            if !issues.isEmpty {
                exportPreflight = ExportPreflightContext(
                    format: format, suggestedName: suggestedName, issues: issues)
                return
            }
        }
        proceedWithExport(format, suggestedName: suggestedName)
    }

    /// 预检通过（或用户选择「仍然导出」）后的流程：PDF 先弹选项 sheet，其余直接导出。
    func proceedWithExport(_ format: PreviewExporter.ExportFormat, suggestedName: String) {
        if format == .pdf {
            pdfExportSuggestedName = suggestedName
            showingPDFExportOptions = true
            return
        }
        runExport(format, suggestedName: suggestedName, pdfOptions: nil)
    }

    /// PDF 选项 sheet 确认：以当前持久化选项导出。
    func confirmPDFExport() {
        showingPDFExportOptions = false
        runExport(.pdf, suggestedName: pdfExportSuggestedName,
                  pdfOptions: AppSettings.shared.pdfExportOptions)
    }

    private func runExport(_ format: PreviewExporter.ExportFormat,
                           suggestedName: String,
                           pdfOptions: PDFExportOptions?) {
        previewExporter.export(format: format, suggestedName: suggestedName,
                               pdfOptions: pdfOptions) { [weak self] result in
            if case .failure(let error) = result {
                self?.setError(error.localizedDescription)
            }
        }
    }

    // MARK: - 复制为富文本（功能8）

    /// 把预览渲染出的正文 HTML 转成富文本写进剪贴板（RTF/HTML/纯文本三 flavor）。
    /// 纯文本 flavor 回退到当前 markdown 源，保证任何目标 App 都能贴出内容。
    func copyRichTextToPasteboard() {
        guard let webView = previewExporter.webView else {
            showToast(L("richText.failed"), icon: "doc.on.doc")
            return
        }
        let plainText = selectedTab?.content ?? ""
        let title = selectedTab?.url.deletingPathExtension().lastPathComponent ?? "Untitled"
        // markdown 预览的正文在 #content；HTML 文件预览退到 body
        let js = """
        (function() {
            var el = document.getElementById('content') || document.body;
            return el ? el.innerHTML : '';
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let bodyHTML = result as? String, !bodyHTML.isEmpty else {
                    self.showToast(L("richText.failed"), icon: "doc.on.doc")
                    return
                }
                let ok = RichTextCopyService.copyRichText(
                    bodyHTML: bodyHTML, title: title, plainText: plainText,
                    imageBaseURL: self.selectedTab?.url.deletingLastPathComponent())
                self.showToast(ok ? L("richText.copied") : L("richText.failed"),
                               icon: ok ? "doc.on.doc.fill" : "doc.on.doc")
            }
        }
    }
}
