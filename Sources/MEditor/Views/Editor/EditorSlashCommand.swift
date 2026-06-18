import SwiftUI
import AppKit

struct SlashCommandExpansion {
    let text: String
    let cursorOffset: Int?
}

struct SlashCommandItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let aliases: [String]
    let keywords: [String]
    let expansion: SlashCommandExpansion

    static func == (lhs: SlashCommandItem, rhs: SlashCommandItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Handles slash command menu: matching, display, and expansion.
/// Owned by EditorCoordinator; textView is set via the coordinator's didSet.
final class SlashCommandHandler {
    weak var textView: NSTextView?

    private var slashPopover: NSPopover?
    private var slashQueryRange: NSRange?
    private var slashItems: [SlashCommandItem] = []
    private var slashSelectedIndex = 0

    /// True while a slash expansion is being inserted, so delegate callbacks are ignored.
    private(set) var isApplyingCommand = false

    var isMenuVisible: Bool {
        slashPopover?.isShown == true && !slashItems.isEmpty
    }

    // MARK: - Command catalogue

    static let allCommands: [SlashCommandItem] = [
        SlashCommandItem(
            title: "Heading 1",
            subtitle: "Large section title",
            icon: "textformat.size.larger",
            aliases: ["/h1", "/heading1", "/title"],
            keywords: ["heading", "title"],
            expansion: SlashCommandExpansion(text: "# ", cursorOffset: nil)
        ),
        SlashCommandItem(
            title: "Heading 2",
            subtitle: "Medium section title",
            icon: "textformat.size",
            aliases: ["/h2", "/heading2"],
            keywords: ["heading", "section"],
            expansion: SlashCommandExpansion(text: "## ", cursorOffset: nil)
        ),
        SlashCommandItem(
            title: "Heading 3",
            subtitle: "Small section title",
            icon: "textformat",
            aliases: ["/h3", "/heading3"],
            keywords: ["heading", "subsection"],
            expansion: SlashCommandExpansion(text: "### ", cursorOffset: nil)
        ),
        SlashCommandItem(
            title: "Todo",
            subtitle: "Checklist item",
            icon: "checklist",
            aliases: ["/todo", "/task"],
            keywords: ["task", "checkbox", "checklist"],
            expansion: SlashCommandExpansion(text: "- [ ] ", cursorOffset: nil)
        ),
        SlashCommandItem(
            title: "Bullet List",
            subtitle: "Unordered list item",
            icon: "list.bullet",
            aliases: ["/bullet", "/bulleted"],
            keywords: ["list", "unordered"],
            expansion: SlashCommandExpansion(text: "- ", cursorOffset: nil)
        ),
        SlashCommandItem(
            title: "Numbered List",
            subtitle: "Ordered list item",
            icon: "list.number",
            aliases: ["/numbered", "/num"],
            keywords: ["list", "ordered"],
            expansion: SlashCommandExpansion(text: "1. ", cursorOffset: nil)
        ),
        SlashCommandItem(
            title: "Quote",
            subtitle: "Block quote",
            icon: "quote.opening",
            aliases: ["/quote"],
            keywords: ["blockquote", "callout"],
            expansion: SlashCommandExpansion(text: "> ", cursorOffset: nil)
        ),
        SlashCommandItem(
            title: "Divider",
            subtitle: "Horizontal rule",
            icon: "minus",
            aliases: ["/hr", "/divider"],
            keywords: ["horizontal", "rule", "separator"],
            expansion: SlashCommandExpansion(text: "---\n", cursorOffset: nil)
        ),
        SlashCommandItem(
            title: "Code Block",
            subtitle: "Fenced code block",
            icon: "curlybraces.square",
            aliases: ["/code"],
            keywords: ["fence", "pre", "snippet"],
            expansion: SlashCommandExpansion(text: "```\n\n```", cursorOffset: 4)
        ),
        SlashCommandItem(
            title: "Table",
            subtitle: "Two-column Markdown table",
            icon: "tablecells",
            aliases: ["/table"],
            keywords: ["grid", "data"],
            expansion: SlashCommandExpansion(
                text: "| Column | Column |\n| --- | --- |\n|  |  |",
                cursorOffset: 36
            )
        )
    ]

    // MARK: - Public interface (called by EditorCoordinator)

    func applyIfNeeded(in textView: NSTextView, at location: Int) -> Bool {
        guard let ctx = slashContext(in: textView, at: location),
              let item = Self.allCommands.first(where: { $0.aliases.contains(ctx.command) }) else { return false }
        return applyCommand(item, in: textView, range: ctx.range)
    }

    func updateMenu(in textView: NSTextView) {
        guard !isApplyingCommand,
              let ctx = slashContext(in: textView, at: textView.selectedRange().location) else {
            closeMenu(); return
        }
        let matches = filteredCommands(for: ctx.command)
        guard !matches.isEmpty else { closeMenu(); return }
        slashQueryRange = ctx.range
        slashItems = matches
        slashSelectedIndex = min(slashSelectedIndex, matches.count - 1)
        showMenu(relativeTo: ctx.range, in: textView)
    }

    func moveSelection(_ delta: Int) {
        guard !slashItems.isEmpty else { return }
        slashSelectedIndex = min(max(0, slashSelectedIndex + delta), slashItems.count - 1)
        if let tv = textView {
            showMenu(relativeTo: slashQueryRange ?? tv.selectedRange(), in: tv)
        }
    }

    func commitSelection() -> Bool {
        guard let tv = textView,
              !slashItems.isEmpty,
              slashSelectedIndex < slashItems.count,
              let range = slashQueryRange else { return false }
        return applyCommand(slashItems[slashSelectedIndex], in: tv, range: range)
    }

    func closeMenu() {
        slashPopover?.close()
        slashPopover = nil
        slashQueryRange = nil
        slashItems = []
        slashSelectedIndex = 0
    }

    /// Filter commands by a slash-prefixed query string (e.g. "/head").
    func filteredCommands(for command: String) -> [SlashCommandItem] {
        let query = String(command.dropFirst()).lowercased()
        guard !query.isEmpty else { return Self.allCommands }
        return Self.allCommands.filter { item in
            if item.aliases.contains(where: { $0.dropFirst().hasPrefix(query) }) { return true }
            if item.title.lowercased().contains(query) { return true }
            if item.subtitle.lowercased().contains(query) { return true }
            return item.keywords.contains { $0.lowercased().contains(query) }
        }
    }

    // MARK: - Private helpers

    private func slashContext(in textView: NSTextView, at location: Int) -> (range: NSRange, command: String)? {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0, selectedRange.location == location else { return nil }

        let nsText = textView.string as NSString
        guard location <= nsText.length else { return nil }

        var lineStart = 0
        if location > 0 {
            let prefixRange = NSRange(location: 0, length: location)
            let newline = nsText.range(of: "\n", options: .backwards, range: prefixRange)
            if newline.location != NSNotFound { lineStart = newline.location + 1 }
        }

        let typedLength = location - lineStart
        guard typedLength >= 1 else { return nil }
        let typed = nsText.substring(with: NSRange(location: lineStart, length: typedLength))
        let indentLength = typed.prefix { $0 == " " || $0 == "\t" }.count
        let command = String(typed.dropFirst(indentLength)).lowercased()
        guard command.hasPrefix("/"),
              !command.dropFirst().contains(where: { $0.isWhitespace }) else { return nil }

        let commandStart = lineStart + indentLength
        return (NSRange(location: commandStart, length: location - commandStart), command)
    }

    private func showMenu(relativeTo range: NSRange, in textView: NSTextView) {
        let popover = slashPopover ?? NSPopover()
        popover.behavior = .semitransient
        popover.animates = false
        popover.contentSize = NSSize(width: 260, height: min(280, 48 + slashItems.count * 43))
        popover.contentViewController = NSHostingController(rootView: SlashCommandMenuView(
            items: slashItems,
            selectedIndex: slashSelectedIndex
        ))
        slashPopover = popover
        let rect = caretRect(for: range, in: textView)
        if popover.isShown { popover.positioningRect = rect }
        else { popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY) }
    }

    private func caretRect(for range: NSRange, in textView: NSTextView) -> NSRect {
        guard let window = textView.window else { return textView.visibleRect }
        let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        guard !screenRect.isEmpty else { return textView.visibleRect }
        let windowRect = window.convertFromScreen(screenRect)
        var viewRect = textView.convert(windowRect, from: nil)
        viewRect.size.width = max(2, viewRect.size.width)
        viewRect.size.height = max(18, viewRect.size.height)
        return viewRect
    }

    private func applyCommand(_ item: SlashCommandItem, in textView: NSTextView, range: NSRange) -> Bool {
        isApplyingCommand = true
        textView.insertText(item.expansion.text, replacementRange: range)
        let len = (item.expansion.text as NSString).length
        let loc = range.location + (item.expansion.cursorOffset ?? len)
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        isApplyingCommand = false
        closeMenu()
        return true
    }
}

// MARK: - Slash menu views

struct SlashCommandMenuView: View {
    let items: [SlashCommandItem]
    let selectedIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                    .font(.system(size: 10, weight: .semibold))
                Text("Insert")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                Spacer()
                Text("↑↓ ↵")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 5)

            Divider().opacity(0.45)

            VStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SlashCommandMenuRow(item: item, isSelected: index == selectedIndex)
                }
            }
            .padding(5)
        }
        .frame(width: 260, alignment: .topLeading)
        .background(.regularMaterial)
    }
}

struct SlashCommandMenuRow: View {
    let item: SlashCommandItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.appAccent : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(item.aliases.first ?? "")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.appAccent.opacity(0.13) : Color.clear)
        )
    }
}
