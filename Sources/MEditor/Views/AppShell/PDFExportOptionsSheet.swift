import SwiftUI

/// PDF 导出选项（功能9）：纸张大小、页边距档位、页眉（标题）、页脚（页码）、封面页。
/// 选项实时持久化到 AppSettings，下次打开 sheet 即为上次选择。
@MainActor
struct PDFExportOptionsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = state.themeStore.current
        VStack(spacing: 0) {
            header(theme)
            theme.separator.opacity(theme.isDark ? 0.28 : 0.18).frame(height: 1)
            formRows(theme, settings: Bindable(settings))
            theme.separator.opacity(theme.isDark ? 0.28 : 0.18).frame(height: 1)
            footer(theme)
        }
        .frame(width: 420)
        .background(theme.chromeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func header(_ theme: PreviewTheme) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(theme.craftSecondary)
                .font(.system(size: 13))
            Text(L("pdf.options.title"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.craftPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func formRows(_ theme: PreviewTheme, settings: Bindable<AppSettings>) -> some View {
        VStack(spacing: 0) {
            optionRow(theme, label: L("pdf.paperSize")) {
                Picker("", selection: settings.pdfPaperSize) {
                    ForEach(PDFExportOptions.PaperSize.allCases, id: \.self) { size in
                        Text(L(size.labelKey)).tag(size.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider().opacity(0.4)
            optionRow(theme, label: L("pdf.margins")) {
                Picker("", selection: settings.pdfMargins) {
                    ForEach(PDFExportOptions.MarginPreset.allCases, id: \.self) { preset in
                        Text(L(preset.labelKey)).tag(preset.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider().opacity(0.4)
            optionRow(theme, label: L("pdf.showHeader")) {
                Toggle("", isOn: settings.pdfShowHeader).labelsHidden()
            }
            Divider().opacity(0.4)
            optionRow(theme, label: L("pdf.showFooter")) {
                Toggle("", isOn: settings.pdfShowFooter).labelsHidden()
            }
            Divider().opacity(0.4)
            optionRow(theme, label: L("pdf.coverPage")) {
                Toggle("", isOn: settings.pdfCoverPage).labelsHidden()
            }
            // 非默认排版要走 PDFDocumentDecorator 重绘，drawPDFPage 不保留链接 annotation
            if !settings.wrappedValue.pdfExportOptions.isDefault {
                Divider().opacity(0.4)
                HStack {
                    Text(L("pdf.options.linkLossHint"))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.craftSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
    }

    private func optionRow<Control: View>(_ theme: PreviewTheme,
                                          label: String,
                                          @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.craftPrimary)
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func footer(_ theme: PreviewTheme) -> some View {
        HStack {
            Spacer()
            Button(L("common.cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(L("action.export")) {
                dismiss()
                state.confirmPDFExport()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
