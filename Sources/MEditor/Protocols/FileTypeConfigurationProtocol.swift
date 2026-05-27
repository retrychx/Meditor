import Foundation

protocol FileTypeConfigurationProtocol {
    func editorLanguage(for ext: String) -> EditorLanguage?
    func iconName(for item: FileItem) -> String
}
