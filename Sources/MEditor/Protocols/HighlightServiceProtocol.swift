import Foundation

protocol HighlightServiceProtocol {
    func register(_ language: EditorLanguage, engine: SyntaxHighlightEngine)
    func engine(for language: EditorLanguage) -> SyntaxHighlightEngine?
}
