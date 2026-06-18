import AppKit

extension EditorCoordinator {
    /// Wrap selection with markdown delimiters. If nothing is selected, inserts a
    /// placeholder and selects it. Calling again while already wrapped unwraps.
    func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        guard let textView = textView else { return }
        let range = textView.selectedRange()
        let text = textView.string as NSString

        if range.length > 0 {
            let selected = text.substring(with: range)
            let before = range.location >= prefix.count
                ? text.substring(with: NSRange(location: range.location - prefix.count, length: prefix.count))
                : ""
            let after = (range.location + range.length + suffix.count <= text.length)
                ? text.substring(with: NSRange(location: range.location + range.length, length: suffix.count))
                : ""
            if before == prefix && after == suffix {
                let fullRange = NSRange(
                    location: range.location - prefix.count,
                    length: range.length + prefix.count + suffix.count
                )
                textView.insertText(selected, replacementRange: fullRange)
                textView.setSelectedRange(NSRange(location: range.location - prefix.count, length: range.length))
            } else {
                textView.insertText(prefix + selected + suffix, replacementRange: range)
                textView.setSelectedRange(NSRange(location: range.location + prefix.count, length: range.length))
            }
        } else {
            let insert = prefix + placeholder + suffix
            textView.insertText(insert, replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + prefix.count, length: placeholder.count))
        }
    }

    func toggleBold()   { wrapSelection(prefix: "**", suffix: "**",    placeholder: "bold") }
    func toggleItalic() { wrapSelection(prefix: "*",  suffix: "*",     placeholder: "italic") }
    func insertLink()   { wrapSelection(prefix: "[",  suffix: "](url)", placeholder: "text") }

    @objc func meditorToggleBold(_ sender: Any?)   { toggleBold() }
    @objc func meditorToggleItalic(_ sender: Any?) { toggleItalic() }
    @objc func meditorInsertLink(_ sender: Any?)   { insertLink() }
}
