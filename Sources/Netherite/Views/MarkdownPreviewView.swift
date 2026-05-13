import AppKit
import SwiftUI

struct MarkdownPreviewView: View {
    @Binding var text: String
    let file: VaultFile?
    let isCompact: Bool
    let isEditable: Bool
    @State private var focusedBlockStartOffset: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if file?.kind == .markdown {
                    let blocks = MarkdownBlock.parse(text, includeEmptyLines: isEditable)
                    if blocks.isEmpty, isEditable {
                        EditableMarkdownField(
                            title: "Start writing",
                            text: $text,
                            focusID: 0,
                            focusedBlockStartOffset: $focusedBlockStartOffset,
                            onSlashCommand: applyCommandToWholeDocument
                        )
                    } else {
                        ForEach(blocks) { block in
                            blockView(block)
                        }
                    }
                } else {
                    PlainPreviewEditor(text: $text, isEditable: isEditable)
                }
            }
            .padding(isCompact ? 16 : 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassEffect(.regular, in: Rectangle())
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case let .heading(level):
            if isEditable {
                EditableMarkdownField(
                    title: "Heading",
                    text: blockTextBinding(for: block),
                    focusID: block.sourceStartOffset,
                    focusedBlockStartOffset: $focusedBlockStartOffset,
                    font: .systemFont(ofSize: headingSize(level), weight: .semibold),
                    onSlashCommand: { applyCommand($0, to: block) },
                    onReturn: { insertNewBlock(after: block) }
                )
                .padding(.top, level == 1 ? 8 : 4)
            } else {
                InlineMarkdownText(text: block.text)
                    .font(.system(size: headingSize(level), weight: .semibold))
                    .padding(.top, level == 1 ? 8 : 4)
            }

        case .paragraph:
            if isEditable {
                EditableMarkdownField(
                    title: "Paragraph",
                    text: blockTextBinding(for: block),
                    focusID: block.sourceStartOffset,
                    focusedBlockStartOffset: $focusedBlockStartOffset,
                    font: .systemFont(ofSize: NSFont.systemFontSize),
                    lineSpacing: 4,
                    onSlashCommand: { applyCommand($0, to: block) },
                    onReturn: { insertNewBlock(after: block) }
                )
            } else {
                InlineMarkdownText(text: block.text)
                    .font(.body)
                    .lineSpacing(4)
            }

        case .bullet:
            HStack(alignment: .top, spacing: 10) {
                Text("•")
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                if isEditable {
                    EditableMarkdownField(
                        title: "List item",
                        text: blockTextBinding(for: block),
                        focusID: block.sourceStartOffset,
                        focusedBlockStartOffset: $focusedBlockStartOffset,
                        lineSpacing: 3,
                        onSlashCommand: { applyCommand($0, to: block) },
                        onReturn: { insertNewBlock(after: block) }
                    )
                } else {
                    InlineMarkdownText(text: block.text)
                        .lineSpacing(3)
                }
            }

        case let .checkbox(isChecked):
            HStack(alignment: .top, spacing: 10) {
                if isEditable {
                    Button {
                        toggleCheckbox(block)
                    } label: {
                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                    .help(isChecked ? "Mark task incomplete" : "Mark task complete")
                    .accessibilityLabel(isChecked ? "Mark task incomplete" : "Mark task complete")
                } else {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                        .frame(width: 14)
                }

                if isEditable {
                    EditableMarkdownField(
                        title: "Task",
                        text: blockTextBinding(for: block),
                        focusID: block.sourceStartOffset,
                        focusedBlockStartOffset: $focusedBlockStartOffset,
                        lineSpacing: 3,
                        onSlashCommand: { applyCommand($0, to: block) },
                        onReturn: { insertNewBlock(after: block) }
                    )
                } else {
                    InlineMarkdownText(text: block.text)
                        .lineSpacing(3)
                }
            }

        case .quote:
            if isEditable {
                EditableMarkdownField(
                    title: "Quote",
                    text: blockTextBinding(for: block),
                    focusID: block.sourceStartOffset,
                    focusedBlockStartOffset: $focusedBlockStartOffset,
                    onSlashCommand: { applyCommand($0, to: block) },
                    onReturn: { insertNewBlock(after: block) }
                )
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: 3)
                }
                .foregroundStyle(.secondary)
            } else {
                InlineMarkdownText(text: block.text)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.secondary.opacity(0.35))
                            .frame(width: 3)
                    }
                    .foregroundStyle(.secondary)
            }

        case .code:
            if isEditable {
                EditableMarkdownField(
                    title: "Code",
                    text: blockTextBinding(for: block),
                    focusID: block.sourceStartOffset,
                    focusedBlockStartOffset: $focusedBlockStartOffset,
                    font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                    lineSpacing: 2,
                    onSlashCommand: { applyCommand($0, to: block) }
                )
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text(block.text)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

        case .rule:
            Divider()
                .padding(.vertical, 8)
        }
    }

    private func blockTextBinding(for block: MarkdownBlock) -> Binding<String> {
        Binding {
            currentBlock(matching: block).text
        } set: { newValue in
            replaceBlockContent(block, with: newValue)
        }
    }

    private func replaceBlockContent(_ block: MarkdownBlock, with newValue: String) {
        guard isEditable, let range = currentBlock(matching: block).contentRange else { return }
        replaceText(in: range, with: newValue)
    }

    private func applyCommand(_ command: SlashCommand, to block: MarkdownBlock) {
        guard isEditable else { return }
        let current = currentBlock(matching: block)
        let content = commandContent(from: current.text)
        replaceText(in: current.sourceRange, with: command.style.markdownSource(for: content))
    }

    private func applyCommandToWholeDocument(_ command: SlashCommand) {
        guard isEditable else { return }
        text = command.style.markdownSource(for: commandContent(from: text))
    }

    private func insertNewBlock(after block: MarkdownBlock) {
        guard isEditable else { return }
        let current = currentBlock(matching: block)
        let prefix = newBlockPrefix(after: current.kind)
        let insertionOffset = current.sourceRange.upperBound
        replaceText(in: insertionOffset..<insertionOffset, with: "\n\(prefix)")
        focusedBlockStartOffset = insertionOffset + 1
    }

    private func newBlockPrefix(after kind: MarkdownBlock.Kind) -> String {
        switch kind {
        case .bullet:
            "- "
        case .checkbox:
            "- [ ] "
        case .quote:
            "> "
        case .heading, .paragraph, .code, .rule:
            ""
        }
    }

    private func commandContent(from source: String) -> String {
        guard source.hasPrefix("/") else { return source }
        let remainder = source.dropFirst()
        guard let firstWhitespace = remainder.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return ""
        }

        return String(remainder[remainder.index(after: firstWhitespace)...])
    }

    private func toggleCheckbox(_ block: MarkdownBlock) {
        let current = currentBlock(matching: block)
        guard isEditable,
              case let .checkbox(isChecked) = current.kind,
              let markerRange = current.markerRange
        else {
            return
        }

        replaceText(in: markerRange, with: isChecked ? "[ ]" : "[x]")
    }

    private func currentBlock(matching block: MarkdownBlock) -> MarkdownBlock {
        let blocks = MarkdownBlock.parse(text, includeEmptyLines: true)
        if let sameOrdinal = blocks.first(where: { $0.ordinal == block.ordinal && $0.kind.editingShape == block.kind.editingShape }) {
            return sameOrdinal
        }
        if let sameStart = blocks.first(where: { $0.sourceStartOffset == block.sourceStartOffset && $0.kind.editingShape == block.kind.editingShape }) {
            return sameStart
        }
        return block
    }

    private func replaceText(in range: Range<Int>, with replacement: String) {
        let lowerOffset = min(max(range.lowerBound, 0), text.count)
        let upperOffset = min(max(range.upperBound, lowerOffset), text.count)

        var updatedText = text
        let lowerIndex = updatedText.index(updatedText.startIndex, offsetBy: lowerOffset)
        let upperIndex = updatedText.index(updatedText.startIndex, offsetBy: upperOffset)
        updatedText.replaceSubrange(lowerIndex..<upperIndex, with: replacement)
        text = updatedText
    }

    private func headingSize(_ level: Int) -> CGFloat {
        let compactAdjustment: CGFloat = isCompact ? -3 : 0
        return switch level {
        case 1:
            28 + compactAdjustment
        case 2:
            23 + compactAdjustment
        case 3:
            19 + compactAdjustment
        default:
            16
        }
    }
}

private struct PlainPreviewEditor: View {
    @Binding var text: String
    let isEditable: Bool

    var body: some View {
        Group {
            if isEditable {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
            } else {
                Text(text)
                    .textSelection(.enabled)
            }
        }
        .font(.system(size: 14, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EditableMarkdownField: View {
    let title: String
    @Binding var text: String
    let focusID: Int
    @Binding var focusedBlockStartOffset: Int?
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var lineSpacing: CGFloat = 0
    var onSlashCommand: ((SlashCommand) -> Void)?
    var onReturn: (() -> Void)?

    @State private var slashCommandsVisible = false
    @State private var measuredHeight: CGFloat = 22

    var body: some View {
        ExpandingMarkdownTextView(
            text: $text,
            height: $measuredHeight,
            placeholder: title,
            font: font,
            lineSpacing: lineSpacing,
            isFocused: focusedBlockStartOffset == focusID,
            onFocus: {
                focusedBlockStartOffset = focusID
            },
            onReturn: onReturn
        )
            .frame(height: measuredHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: text) { _, newValue in
                slashCommandsVisible = onSlashCommand != nil && newValue.hasPrefix("/")
            }
            .popover(isPresented: $slashCommandsVisible, arrowEdge: .bottom) {
                SlashCommandMenu(query: SlashCommand.query(from: text)) { command in
                    slashCommandsVisible = false
                    onSlashCommand?(command)
                }
            }
    }
}

private struct ExpandingMarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let placeholder: String
    let font: NSFont
    let lineSpacing: CGFloat
    let isFocused: Bool
    let onFocus: () -> Void
    let onReturn: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = ReturnHandlingTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ReturnHandlingTextView else { return }

        textView.onReturn = onReturn
        textView.placeholder = placeholder
        updateTextContainerSize(for: textView, in: scrollView)
        applyTextAttributes(to: textView)

        if textView.string != text {
            textView.string = text
            applyTextAttributes(to: textView)
        }

        context.coordinator.updateHeight()

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func applyTextAttributes(to textView: NSTextView) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
        textView.font = font
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = attributes
        textView.textStorage?.setAttributes(
            attributes,
            range: NSRange(location: 0, length: (textView.string as NSString).length)
        )
    }

    private func updateTextContainerSize(for textView: NSTextView, in scrollView: NSScrollView) {
        let availableWidth = max(scrollView.contentSize.width, 1)
        if abs(textView.frame.width - availableWidth) > 0.5 {
            textView.frame.size.width = availableWidth
        }
        textView.textContainer?.containerSize = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ExpandingMarkdownTextView
        weak var textView: NSTextView?

        init(_ parent: ExpandingMarkdownTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight()
        }

        func updateHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let lineHeight = ceil(parent.font.ascender - parent.font.descender + parent.lineSpacing)
            let newHeight = max(lineHeight, ceil(usedRect.height))

            guard abs(parent.height - newHeight) > 0.5 else { return }
            DispatchQueue.main.async {
                self.parent.height = newHeight
            }
        }
    }
}

private final class ReturnHandlingTextView: NSTextView {
    var onReturn: (() -> Void)?
    var placeholder = "" {
        didSet {
            needsDisplay = true
        }
    }

    override func insertNewline(_ sender: Any?) {
        if let onReturn {
            onReturn()
        } else {
            super.insertNewline(sender)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        placeholder.draw(at: .zero, withAttributes: attributes)
    }
}

private struct SlashCommandMenu: View {
    let query: String
    let onSelect: (SlashCommand) -> Void

    private var matchingCommands: [SlashCommand] {
        let commands = SlashCommand.allCases.filter { $0.matches(query) }
        return commands.isEmpty ? SlashCommand.allCases : commands
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(matchingCommands) { command in
                Button {
                    onSelect(command)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: command.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(command.title)
                                .font(.body)
                            Text(command.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 240)
    }
}

private struct InlineMarkdownText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}

private struct SlashCommand: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let style: MarkdownBlockStyle
    let aliases: [String]

    var id: String { title }

    static let allCases: [SlashCommand] = [
        SlashCommand(
            title: "Text",
            subtitle: "Plain paragraph",
            systemImage: "text.alignleft",
            style: .paragraph,
            aliases: ["p", "plain", "paragraph"]
        ),
        SlashCommand(
            title: "Heading 1",
            subtitle: "Large section title",
            systemImage: "textformat.size.larger",
            style: .heading(level: 1),
            aliases: ["h1", "heading1", "title"]
        ),
        SlashCommand(
            title: "Heading 2",
            subtitle: "Medium section title",
            systemImage: "textformat.size",
            style: .heading(level: 2),
            aliases: ["h2", "heading2", "subtitle"]
        ),
        SlashCommand(
            title: "Heading 3",
            subtitle: "Small section title",
            systemImage: "textformat",
            style: .heading(level: 3),
            aliases: ["h3", "heading3"]
        ),
        SlashCommand(
            title: "Bulleted List",
            subtitle: "Create a list item",
            systemImage: "list.bullet",
            style: .bullet,
            aliases: ["bullet", "bullets", "list", "ul"]
        ),
        SlashCommand(
            title: "To-do",
            subtitle: "Track a task",
            systemImage: "checkmark.square",
            style: .checkbox(isChecked: false),
            aliases: ["todo", "task", "checkbox", "check"]
        ),
        SlashCommand(
            title: "Quote",
            subtitle: "Call out text",
            systemImage: "text.quote",
            style: .quote,
            aliases: ["blockquote", "callout"]
        ),
        SlashCommand(
            title: "Code",
            subtitle: "Code block",
            systemImage: "chevron.left.forwardslash.chevron.right",
            style: .code,
            aliases: ["pre", "snippet"]
        )
    ]

    static func query(from text: String) -> String {
        guard text.hasPrefix("/") else { return "" }
        return text
            .dropFirst()
            .split { $0 == " " || $0 == "\t" }
            .first
            .map(String.init)?
            .lowercased() ?? ""
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let normalizedTitle = title.lowercased()
        return normalizedTitle.contains(query) || aliases.contains { $0.contains(query) }
    }
}

private enum MarkdownBlockStyle: Equatable {
    case paragraph
    case heading(level: Int)
    case bullet
    case checkbox(isChecked: Bool)
    case quote
    case code

    func markdownSource(for content: String) -> String {
        switch self {
        case .paragraph:
            content
        case let .heading(level):
            "\(String(repeating: "#", count: level)) \(content)"
        case .bullet:
            "- \(content)"
        case let .checkbox(isChecked):
            "- [\(isChecked ? "x" : " ")] \(content)"
        case .quote:
            "> \(content)"
        case .code:
            "```\n\(content)\n```"
        }
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int)
        case paragraph
        case bullet
        case checkbox(isChecked: Bool)
        case quote
        case code
        case rule

        var editingShape: String {
            switch self {
            case .heading:
                "heading"
            case .paragraph:
                "paragraph"
            case .bullet:
                "bullet"
            case .checkbox:
                "checkbox"
            case .quote:
                "quote"
            case .code:
                "code"
            case .rule:
                "rule"
            }
        }
    }

    let ordinal: Int
    let sourceStartOffset: Int
    let sourceRange: Range<Int>
    let kind: Kind
    let text: String
    let contentRange: Range<Int>?
    let markerRange: Range<Int>?

    var id: String {
        "\(ordinal)-\(kind.editingShape)"
    }

    static func parse(_ source: String, includeEmptyLines: Bool = false) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var paragraphStartOffset: Int?
        var paragraphEndOffset: Int?
        var codeLines: [String] = []
        var codeFenceStartOffset: Int?
        var codeStartOffset: Int?
        var codeEndOffset: Int?
        var codeSourceEndOffset: Int?
        var inCodeBlock = false

        func resetParagraph() {
            paragraphStartOffset = nil
            paragraphEndOffset = nil
        }

        func resetCode() {
            codeFenceStartOffset = nil
            codeStartOffset = nil
            codeEndOffset = nil
            codeSourceEndOffset = nil
        }

        func appendBlock(
            kind: Kind,
            text: String,
            sourceStartOffset: Int,
            sourceRange: Range<Int>,
            contentRange: Range<Int>? = nil,
            markerRange: Range<Int>? = nil
        ) {
            blocks.append(
                MarkdownBlock(
                    ordinal: blocks.count,
                    sourceStartOffset: sourceStartOffset,
                    sourceRange: sourceRange,
                    kind: kind,
                    text: text,
                    contentRange: contentRange,
                    markerRange: markerRange
                )
            )
        }

        func flushParagraph() {
            guard !paragraph.isEmpty,
                  let paragraphStartOffset,
                  let paragraphEndOffset
            else {
                return
            }

            appendBlock(
                kind: .paragraph,
                text: paragraph.joined(separator: " "),
                sourceStartOffset: paragraphStartOffset,
                sourceRange: paragraphStartOffset..<paragraphEndOffset,
                contentRange: paragraphStartOffset..<paragraphEndOffset
            )
            paragraph.removeAll()
            resetParagraph()
        }

        func flushCode(sourceEndOffset: Int? = nil) {
            guard let codeFenceStartOffset,
                  let codeStartOffset,
                  let codeEndOffset
            else {
                return
            }

            let blockEndOffset = sourceEndOffset ?? codeSourceEndOffset ?? codeEndOffset
            appendBlock(
                kind: .code,
                text: codeLines.joined(separator: "\n"),
                sourceStartOffset: codeFenceStartOffset,
                sourceRange: codeFenceStartOffset..<blockEndOffset,
                contentRange: codeStartOffset..<codeEndOffset
            )
            codeLines.removeAll()
            resetCode()
        }

        for fragment in MarkdownLine.fragments(in: source) {
            let rawLine = fragment.text
            let leadingWhitespace = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let lineWithoutIndent = String(rawLine.dropFirst(leadingWhitespace))
            let trimmedLine = lineWithoutIndent.trimmingCharacters(in: .whitespaces)
            let trimmedStartOffset = fragment.lineStartOffset + leadingWhitespace
            let trimmedEndOffset = trimmedStartOffset + trimmedLine.count

            if trimmedLine.hasPrefix("```") {
                if inCodeBlock {
                    codeSourceEndOffset = fragment.lineEndOffset
                    flushCode(sourceEndOffset: fragment.lineEndOffset)
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                    codeFenceStartOffset = trimmedStartOffset
                    codeStartOffset = fragment.nextLineStartOffset
                    codeEndOffset = fragment.nextLineStartOffset
                    codeSourceEndOffset = source.count
                }
                continue
            }

            if inCodeBlock {
                codeEndOffset = fragment.lineEndOffset
                codeLines.append(rawLine)
                continue
            }

            if trimmedLine.isEmpty {
                flushParagraph()
                if includeEmptyLines {
                    appendBlock(
                        kind: .paragraph,
                        text: "",
                        sourceStartOffset: fragment.lineStartOffset,
                        sourceRange: fragment.lineStartOffset..<fragment.lineEndOffset,
                        contentRange: fragment.lineStartOffset..<fragment.lineEndOffset
                    )
                }
                continue
            }

            if trimmedLine == "---" || trimmedLine == "***" {
                flushParagraph()
                appendBlock(
                    kind: .rule,
                    text: "",
                    sourceStartOffset: trimmedStartOffset,
                    sourceRange: trimmedStartOffset..<fragment.lineEndOffset
                )
                continue
            }

            if lineWithoutIndent.hasPrefix("#") {
                let hashes = lineWithoutIndent.prefix { $0 == "#" }.count
                let remainderStart = lineWithoutIndent.index(lineWithoutIndent.startIndex, offsetBy: hashes)
                let whitespaceAfterHashes = lineWithoutIndent[remainderStart...].prefix { $0 == " " || $0 == "\t" }.count
                let remainder = lineWithoutIndent[remainderStart...]
                    .dropFirst(whitespaceAfterHashes)
                    .trimmingCharacters(in: .whitespaces)

                if hashes <= 6, !remainder.isEmpty || whitespaceAfterHashes > 0 {
                    flushParagraph()
                    let contentStartOffset = trimmedStartOffset + hashes + whitespaceAfterHashes
                    appendBlock(
                        kind: .heading(level: hashes),
                        text: remainder,
                        sourceStartOffset: trimmedStartOffset,
                        sourceRange: trimmedStartOffset..<fragment.lineEndOffset,
                        contentRange: contentStartOffset..<fragment.lineEndOffset
                    )
                    continue
                }
            }

            if lineWithoutIndent.hasPrefix(">") {
                flushParagraph()
                let remainderStart = lineWithoutIndent.index(after: lineWithoutIndent.startIndex)
                let whitespaceAfterMarker = lineWithoutIndent[remainderStart...].prefix { $0 == " " || $0 == "\t" }.count
                let quote = lineWithoutIndent[remainderStart...]
                    .dropFirst(whitespaceAfterMarker)
                    .trimmingCharacters(in: .whitespaces)
                let contentStartOffset = trimmedStartOffset + 1 + whitespaceAfterMarker
                appendBlock(
                    kind: .quote,
                    text: quote,
                    sourceStartOffset: trimmedStartOffset,
                    sourceRange: trimmedStartOffset..<fragment.lineEndOffset,
                    contentRange: contentStartOffset..<fragment.lineEndOffset
                )
                continue
            }

            if lineWithoutIndent.hasPrefix("- [ ] ") || lineWithoutIndent == "- [ ]" ||
                lineWithoutIndent.hasPrefix("* [ ] ") || lineWithoutIndent == "* [ ]"
            {
                flushParagraph()
                let hasTrailingSpace = lineWithoutIndent.count > 5
                let contentStartOffset = trimmedStartOffset + 5 + (hasTrailingSpace ? 1 : 0)
                appendBlock(
                    kind: .checkbox(isChecked: false),
                    text: String(lineWithoutIndent.dropFirst(min(6, lineWithoutIndent.count))).trimmed,
                    sourceStartOffset: trimmedStartOffset,
                    sourceRange: trimmedStartOffset..<fragment.lineEndOffset,
                    contentRange: contentStartOffset..<fragment.lineEndOffset,
                    markerRange: (trimmedStartOffset + 2)..<(trimmedStartOffset + 5)
                )
                continue
            }

            if lineWithoutIndent.hasPrefix("- [x] ") || lineWithoutIndent == "- [x]" ||
                lineWithoutIndent.hasPrefix("* [x] ") || lineWithoutIndent == "* [x]" ||
                lineWithoutIndent.hasPrefix("- [X] ") || lineWithoutIndent == "- [X]" ||
                lineWithoutIndent.hasPrefix("* [X] ") || lineWithoutIndent == "* [X]"
            {
                flushParagraph()
                let hasTrailingSpace = lineWithoutIndent.count > 5
                let contentStartOffset = trimmedStartOffset + 5 + (hasTrailingSpace ? 1 : 0)
                appendBlock(
                    kind: .checkbox(isChecked: true),
                    text: String(lineWithoutIndent.dropFirst(min(6, lineWithoutIndent.count))).trimmed,
                    sourceStartOffset: trimmedStartOffset,
                    sourceRange: trimmedStartOffset..<fragment.lineEndOffset,
                    contentRange: contentStartOffset..<fragment.lineEndOffset,
                    markerRange: (trimmedStartOffset + 2)..<(trimmedStartOffset + 5)
                )
                continue
            }

            if lineWithoutIndent.hasPrefix("- ") || lineWithoutIndent.hasPrefix("* ") {
                flushParagraph()
                appendBlock(
                    kind: .bullet,
                    text: String(lineWithoutIndent.dropFirst(2)).trimmed,
                    sourceStartOffset: trimmedStartOffset,
                    sourceRange: trimmedStartOffset..<fragment.lineEndOffset,
                    contentRange: (trimmedStartOffset + 2)..<fragment.lineEndOffset
                )
                continue
            }

            if paragraphStartOffset == nil {
                paragraphStartOffset = trimmedStartOffset
            }
            paragraphEndOffset = trimmedEndOffset
            paragraph.append(trimmedLine)
        }

        if inCodeBlock {
            flushCode(sourceEndOffset: source.count)
        }
        flushParagraph()

        return blocks
    }
}

private struct MarkdownLine {
    let text: String
    let lineStartOffset: Int
    let lineEndOffset: Int
    let nextLineStartOffset: Int

    static func fragments(in source: String) -> [MarkdownLine] {
        guard !source.isEmpty else { return [] }

        var fragments: [MarkdownLine] = []
        var lineStartOffset = 0
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, line) in lines.enumerated() {
            let text = String(line)
            let lineEndOffset = lineStartOffset + text.count
            let nextLineStartOffset = lineEndOffset + (index == lines.count - 1 ? 0 : 1)
            fragments.append(
                MarkdownLine(
                    text: text,
                    lineStartOffset: lineStartOffset,
                    lineEndOffset: lineEndOffset,
                    nextLineStartOffset: nextLineStartOffset
                )
            )
            lineStartOffset = nextLineStartOffset
        }

        return fragments
    }
}
