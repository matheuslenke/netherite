import AppKit
import SwiftUI

enum SyntaxLanguage: Sendable {
    case markdown
    case latex
    case none

    init(fileKind: FileKind?) {
        switch fileKind {
        case .markdown:
            self = .markdown
        case .latex:
            self = .latex
        default:
            self = .none
        }
    }

    var lineCommentStyle: EditorLineCommentStyle {
        switch self {
        case .markdown:
            .wrapping(open: "<!--", close: "-->")
        case .latex:
            .prefix("% ")
        case .none:
            .prefix("// ")
        }
    }
}

struct SyntaxHighlightingEditor: NSViewRepresentable {
    @Binding var text: String
    let language: SyntaxLanguage
    let isEditable: Bool
    var scrollSync: Binding<ScrollSyncState>?
    var scrollTargetOffset: Binding<Int?>?
    let scrollSyncSource: ScrollSyncSource

    init(
        text: Binding<String>,
        language: SyntaxLanguage,
        isEditable: Bool,
        scrollSync: Binding<ScrollSyncState>? = nil,
        scrollTargetOffset: Binding<Int?>? = nil,
        scrollSyncSource: ScrollSyncSource = .editor
    ) {
        self._text = text
        self.language = language
        self.isEditable = isEditable
        self.scrollSync = scrollSync
        self.scrollTargetOffset = scrollTargetOffset
        self.scrollSyncSource = scrollSyncSource
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = Self.makeEditorScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        context.coordinator.configureScrollObservation(for: scrollView)

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        if let textView = textView as? ShortcutTextView {
            textView.commentStyle = language.lineCommentStyle
        }
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = SyntaxHighlightingEditor.baseFont
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false

        context.coordinator.textView = textView
        context.coordinator.applyText(text, language: language)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configureScrollObservation(for: scrollView)
        guard let textView = scrollView.documentView as? NSTextView else { return }

        textView.isEditable = isEditable
        textView.isSelectable = true
        if let textView = textView as? ShortcutTextView {
            textView.commentStyle = language.lineCommentStyle
        }

        if textView.string != text {
            context.coordinator.applyText(text, language: language)
        } else if context.coordinator.appliedLanguage != language ||
                  context.coordinator.appliedAppearanceName != textView.effectiveAppearance.name {
            context.coordinator.highlight(language: language, force: true)
        }

        context.coordinator.applyRemoteScrollIfNeeded(in: scrollView)
        context.coordinator.applyScrollTargetIfNeeded(in: scrollView)
    }

    static var baseFont: NSFont { .monospacedSystemFont(ofSize: 14, weight: .regular) }

    private static func makeEditorScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = ShortcutTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private static let liveHighlightDelayNanoseconds: UInt64 = 120_000_000
        private static let maximumHighlightedLength = 220_000

        var parent: SyntaxHighlightingEditor
        weak var textView: NSTextView?
        private weak var scrollView: NSScrollView?
        private weak var observedClipView: NSClipView?
        var appliedLanguage: SyntaxLanguage = .none
        var appliedAppearanceName: NSAppearance.Name?
        private var highlightTask: Task<Void, Never>?
        private var appliedScrollRevision: Int?
        private var isApplyingScrollSync = false

        init(_ parent: SyntaxHighlightingEditor) {
            self.parent = parent
        }

        deinit {
            highlightTask?.cancel()
            NotificationCenter.default.removeObserver(self)
        }

        func configureScrollObservation(for scrollView: NSScrollView) {
            self.scrollView = scrollView

            guard observedClipView !== scrollView.contentView else { return }

            if let observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedClipView
                )
            }

            observedClipView = scrollView.contentView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewDidScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        @objc private func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView else { return }
            publishScrollProgress(from: scrollView)
        }

        func applyRemoteScrollIfNeeded(in scrollView: NSScrollView) {
            guard let state = parent.scrollSync?.wrappedValue,
                  appliedScrollRevision != state.revision
            else {
                return
            }

            scrollView.layoutSubtreeIfNeeded()

            let metrics = scrollMetrics(for: scrollView)
            guard metrics.maxOffset > 0 || state.progress == 0 else { return }

            let targetOffset = state.progress * metrics.maxOffset
            appliedScrollRevision = state.revision
            guard abs(metrics.offset - targetOffset) > SynchronizedScrolling.offsetTolerance else { return }

            isApplyingScrollSync = true
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: targetOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingScrollSync = false
        }

        func applyScrollTargetIfNeeded(in scrollView: NSScrollView) {
            guard let targetOffset = parent.scrollTargetOffset?.wrappedValue,
                  let textView
            else {
                return
            }

            let clampedOffset = min(max(targetOffset, 0), (textView.string as NSString).length)
            let range = NSRange(location: clampedOffset, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)

            if parent.scrollTargetOffset?.wrappedValue == targetOffset {
                parent.scrollTargetOffset?.wrappedValue = nil
            }

            publishScrollProgress(from: scrollView)
        }

        private func publishScrollProgress(from scrollView: NSScrollView) {
            guard !isApplyingScrollSync,
                  let scrollSync = parent.scrollSync
            else {
                return
            }

            let metrics = scrollMetrics(for: scrollView)
            let currentState = scrollSync.wrappedValue
            guard abs(currentState.progress - metrics.progress) > SynchronizedScrolling.progressTolerance else { return }

            let source = parent.scrollSyncSource
            let progress = metrics.progress
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isApplyingScrollSync,
                      let scrollSync = self.parent.scrollSync
                else {
                    return
                }

                let currentState = scrollSync.wrappedValue
                guard abs(currentState.progress - progress) > SynchronizedScrolling.progressTolerance else { return }

                scrollSync.wrappedValue = SynchronizedScrolling.nextState(
                    from: currentState,
                    source: source,
                    progress: progress
                )
            }
        }

        private func scrollMetrics(for scrollView: NSScrollView) -> ScrollSyncMetrics {
            let contentLength = scrollView.documentView?.bounds.height ?? scrollView.contentSize.height
            return SynchronizedScrolling.metrics(
                offset: scrollView.contentView.bounds.origin.y,
                contentLength: contentLength,
                viewportLength: scrollView.contentView.bounds.height
            )
        }

        func applyText(_ newText: String, language: SyntaxLanguage) {
            guard let textView else { return }
            highlightTask?.cancel()
            let selectedRanges = textView.selectedRanges
            applyBaseTextStyle(to: textView)
            textView.string = newText
            textView.selectedRanges = clampedSelectedRanges(selectedRanges, length: (newText as NSString).length)
            appliedLanguage = language
            appliedAppearanceName = textView.effectiveAppearance.name

            guard (newText as NSString).length <= Self.maximumHighlightedLength else { return }
            scheduleHighlight(language: language, delayNanoseconds: 1)
        }

        private func applyBaseTextStyle(to textView: NSTextView) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: SyntaxHighlightingEditor.baseFont,
                .foregroundColor: NSColor.labelColor
            ]
            textView.font = SyntaxHighlightingEditor.baseFont
            textView.textColor = .labelColor
            textView.typingAttributes = attributes
        }

        private func clampedSelectedRanges(_ ranges: [NSValue], length: Int) -> [NSValue] {
            let clampedRanges = ranges.compactMap { value -> NSValue? in
                let range = value.rangeValue
                guard range.location <= length else { return nil }
                return NSValue(range: NSRange(location: range.location, length: min(range.length, length - range.location)))
            }

            return clampedRanges.isEmpty ? [NSValue(range: NSRange(location: length, length: 0))] : clampedRanges
        }

        func highlight(language: SyntaxLanguage, force: Bool = false) {
            guard let textView, let textStorage = textView.textStorage else { return }
            let appearance = textView.effectiveAppearance
            guard force ||
                textStorage.length <= Self.maximumHighlightedLength ||
                appliedLanguage != language ||
                appliedAppearanceName != appearance.name
            else {
                return
            }

            let palette = SyntaxPalette(appearance: appearance)
            let fullRange = NSRange(location: 0, length: textStorage.length)

            textStorage.beginEditing()
            textStorage.setAttributes(
                [
                    .font: SyntaxHighlightingEditor.baseFont,
                    .foregroundColor: palette.body
                ],
                range: fullRange
            )

            if textStorage.length <= Self.maximumHighlightedLength {
                switch language {
                case .markdown:
                    SyntaxHighlighter.highlightMarkdown(in: textStorage, palette: palette)
                case .latex:
                    SyntaxHighlighter.highlightLatex(in: textStorage, palette: palette)
                case .none:
                    break
                }
            }

            textStorage.endEditing()
            appliedLanguage = language
            appliedAppearanceName = appearance.name
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            scheduleHighlight(language: parent.language)
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            TextInsertionService.registerFocusedTextView(textView)
        }

        private func scheduleHighlight(language: SyntaxLanguage) {
            scheduleHighlight(language: language, delayNanoseconds: Self.liveHighlightDelayNanoseconds)
        }

        private func scheduleHighlight(language: SyntaxLanguage, delayNanoseconds: UInt64) {
            highlightTask?.cancel()
            highlightTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }

                guard let self, !Task.isCancelled else { return }
                self.highlight(language: language)
            }
        }
    }
}

private final class ShortcutTextView: NSTextView {
    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let upArrow: UInt16 = 126
        static let downArrow: UInt16 = 125
    }

    var commentStyle: EditorLineCommentStyle = .prefix("// ")

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleEditorShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleEditorShortcut(event) {
            return
        }
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        guard isEditable else {
            super.insertTab(sender)
            return
        }

        if selectedRange().length == 0 {
            insertText(EditorTextShortcutEngine.indentation, replacementRange: selectedRange())
            return
        }
        applyEditorShortcut(.indentLines)
    }

    override func insertBacktab(_ sender: Any?) {
        guard isEditable else {
            super.insertBacktab(sender)
            return
        }

        applyEditorShortcut(.outdentLines)
    }

    private func handleEditorShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == [.command], characters == "f" {
            NotificationCenter.default.post(name: .findRequested, object: nil)
            return true
        }

        guard isEditable else { return false }

        if modifiers == [.command], characters == "/" {
            applyEditorShortcut(.toggleLineComment)
            return true
        }

        if modifiers == [.command], characters == "[" {
            applyEditorShortcut(.outdentLines)
            return true
        }

        if modifiers == [.command], characters == "]" {
            applyEditorShortcut(.indentLines)
            return true
        }

        if modifiers == [.command, .shift], characters == "k" {
            applyEditorShortcut(.deleteLines)
            return true
        }

        if event.keyCode == KeyCode.returnKey, modifiers == [.command] {
            applyEditorShortcut(.insertLineBelow)
            return true
        }

        if event.keyCode == KeyCode.returnKey, modifiers == [.command, .shift] {
            applyEditorShortcut(.insertLineAbove)
            return true
        }

        if event.keyCode == KeyCode.upArrow, modifiers == [.option] {
            applyEditorShortcut(.moveLinesUp)
            return true
        }

        if event.keyCode == KeyCode.downArrow, modifiers == [.option] {
            applyEditorShortcut(.moveLinesDown)
            return true
        }

        if event.keyCode == KeyCode.upArrow, modifiers == [.option, .shift] {
            applyEditorShortcut(.duplicateLinesUp)
            return true
        }

        if event.keyCode == KeyCode.downArrow, modifiers == [.option, .shift] {
            applyEditorShortcut(.duplicateLinesDown)
            return true
        }

        return false
    }

    private func applyEditorShortcut(_ action: EditorTextShortcutAction) {
        guard let textStorage,
              let edit = EditorTextShortcutEngine.edit(
                for: action,
                in: string,
                selectedRange: selectedRange(),
                commentStyle: commentStyle
              ),
              shouldChangeText(in: edit.replacementRange, replacementString: edit.replacementText)
        else {
            return
        }

        textStorage.replaceCharacters(in: edit.replacementRange, with: edit.replacementText)
        didChangeText()
        setSelectedRange(edit.selectedRange)
        scrollRangeToVisible(edit.selectedRange)
    }
}

struct SyntaxPalette {
    let body: NSColor
    let heading: NSColor
    let emphasis: NSColor
    let strong: NSColor
    let codeText: NSColor
    let codeBackground: NSColor
    let link: NSColor
    let wikiLink: NSColor
    let quote: NSColor
    let listMarker: NSColor
    let rule: NSColor
    let command: NSColor
    let environment: NSColor
    let math: NSColor
    let comment: NSColor
    let punctuation: NSColor

    init(appearance: NSAppearance) {
        let isDark = appearance.isDarkMode

        body = .labelColor
        punctuation = .tertiaryLabelColor
        codeBackground = isDark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.06)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05)

        if isDark {
            heading = NSColor(srgbRed: 0.55, green: 0.83, blue: 1.00, alpha: 1.0)
            emphasis = NSColor(srgbRed: 0.93, green: 0.78, blue: 0.55, alpha: 1.0)
            strong = NSColor(srgbRed: 1.00, green: 0.68, blue: 0.60, alpha: 1.0)
            codeText = NSColor(srgbRed: 0.78, green: 0.94, blue: 0.78, alpha: 1.0)
            link = NSColor(srgbRed: 0.55, green: 0.78, blue: 1.00, alpha: 1.0)
            wikiLink = NSColor(srgbRed: 0.78, green: 0.66, blue: 1.00, alpha: 1.0)
            quote = NSColor(srgbRed: 0.74, green: 0.78, blue: 0.83, alpha: 1.0)
            listMarker = NSColor(srgbRed: 0.95, green: 0.74, blue: 0.45, alpha: 1.0)
            rule = .tertiaryLabelColor
            command = NSColor(srgbRed: 0.78, green: 0.66, blue: 1.00, alpha: 1.0)
            environment = NSColor(srgbRed: 0.55, green: 0.83, blue: 1.00, alpha: 1.0)
            math = NSColor(srgbRed: 0.78, green: 0.94, blue: 0.78, alpha: 1.0)
            comment = NSColor(srgbRed: 0.55, green: 0.70, blue: 0.55, alpha: 1.0)
        } else {
            heading = NSColor(srgbRed: 0.09, green: 0.38, blue: 0.67, alpha: 1.0)
            emphasis = NSColor(srgbRed: 0.62, green: 0.42, blue: 0.08, alpha: 1.0)
            strong = NSColor(srgbRed: 0.74, green: 0.21, blue: 0.16, alpha: 1.0)
            codeText = NSColor(srgbRed: 0.15, green: 0.45, blue: 0.22, alpha: 1.0)
            link = NSColor(srgbRed: 0.10, green: 0.39, blue: 0.71, alpha: 1.0)
            wikiLink = NSColor(srgbRed: 0.42, green: 0.27, blue: 0.74, alpha: 1.0)
            quote = NSColor(srgbRed: 0.35, green: 0.40, blue: 0.46, alpha: 1.0)
            listMarker = NSColor(srgbRed: 0.78, green: 0.42, blue: 0.10, alpha: 1.0)
            rule = .tertiaryLabelColor
            command = NSColor(srgbRed: 0.42, green: 0.27, blue: 0.74, alpha: 1.0)
            environment = NSColor(srgbRed: 0.10, green: 0.39, blue: 0.71, alpha: 1.0)
            math = NSColor(srgbRed: 0.15, green: 0.45, blue: 0.22, alpha: 1.0)
            comment = NSColor(srgbRed: 0.40, green: 0.50, blue: 0.40, alpha: 1.0)
        }
    }
}

extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

enum SyntaxHighlighter {
    private static var baseFont: NSFont { .monospacedSystemFont(ofSize: 14, weight: .regular) }
    private static var baseSize: CGFloat { 14 }

    private static func headingSize(forLevel level: Int) -> CGFloat {
        let size = baseSize
        switch level {
        case 1: return size + 6
        case 2: return size + 4
        case 3: return size + 2
        case 4: return size + 1
        default: return size
        }
    }

    static func highlightMarkdown(in textStorage: NSTextStorage, palette: SyntaxPalette) {
        let source = textStorage.string as NSString

        applyLineRegex(
            pattern: ##"^(\#{1,6})(\s+)(.*)$"##,
            in: source,
            textStorage: textStorage
        ) { match in
            let hashRange = match.range(at: 1)
            let level = min(6, max(1, hashRange.length))
            let size = headingSize(forLevel: level)
            let headingFont = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
            textStorage.addAttributes(
                [.font: headingFont, .foregroundColor: palette.heading],
                range: match.range
            )
            textStorage.addAttributes(
                [.foregroundColor: palette.punctuation],
                range: hashRange
            )
        }

        applyLineRegex(
            pattern: #"^>\s.*$"#,
            in: source,
            textStorage: textStorage
        ) { match in
            let italic = italicFont()
            textStorage.addAttributes(
                [.font: italic, .foregroundColor: palette.quote],
                range: match.range
            )
        }

        applyLineRegex(
            pattern: #"^(\s*)([-*+]|\d+\.)\s"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.foregroundColor: palette.listMarker, .font: NSFont.monospacedSystemFont(ofSize: baseSize, weight: .semibold)],
                range: match.range(at: 2)
            )
        }

        applyLineRegex(
            pattern: #"^\s*(-{3,}|\*{3,}|_{3,})\s*$"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.foregroundColor: palette.rule],
                range: match.range
            )
        }

        applyRegex(
            pattern: #"`[^`\n]+`"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [
                    .foregroundColor: palette.codeText,
                    .backgroundColor: palette.codeBackground
                ],
                range: match.range
            )
        }

        highlightFencedCodeBlocks(textStorage: textStorage, palette: palette)

        applyRegex(
            pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#,
            in: source,
            textStorage: textStorage
        ) { match in
            let boldFont = NSFont.monospacedSystemFont(ofSize: baseSize, weight: .bold)
            textStorage.addAttributes(
                [.font: boldFont, .foregroundColor: palette.strong],
                range: match.range
            )
        }

        applyRegex(
            pattern: #"(?<![*_])(\*|_)(?=\S)([^*_\n]+?)(?<=\S)\1(?![*_])"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.font: italicFont(), .foregroundColor: palette.emphasis],
                range: match.range
            )
        }

        applyRegex(
            pattern: #"~~[^~\n]+~~"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: palette.quote],
                range: match.range
            )
        }

        applyRegex(
            pattern: #"\[\[[^\]\n]+\]\]"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.foregroundColor: palette.wikiLink, .underlineStyle: NSUnderlineStyle.single.rawValue],
                range: match.range
            )
        }

        applyRegex(
            pattern: #"!?\[[^\]\n]*\]\([^)\n]+\)"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.foregroundColor: palette.link, .underlineStyle: NSUnderlineStyle.single.rawValue],
                range: match.range
            )
        }
    }

    static func highlightLatex(in textStorage: NSTextStorage, palette: SyntaxPalette) {
        let source = textStorage.string as NSString

        applyRegex(
            pattern: #"%[^\n]*"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.foregroundColor: palette.comment, .font: italicFont()],
                range: match.range
            )
        }

        applyRegex(
            pattern: #"\$\$[\s\S]*?\$\$"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.foregroundColor: palette.math],
                range: match.range
            )
        }

        applyRegex(
            pattern: #"(?<!\$)\$(?!\$)[^\$\n]+?(?<!\$)\$(?!\$)"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.foregroundColor: palette.math],
                range: match.range
            )
        }

        applyRegex(
            pattern: #"\\(?:begin|end)\{([^}\n]+)\}"#,
            in: source,
            textStorage: textStorage
        ) { match in
            let commandFont = NSFont.monospacedSystemFont(ofSize: baseSize, weight: .semibold)
            textStorage.addAttributes(
                [.foregroundColor: palette.command, .font: commandFont],
                range: match.range
            )
            let nameRange = match.range(at: 1)
            if nameRange.location != NSNotFound {
                textStorage.addAttributes(
                    [.foregroundColor: palette.environment],
                    range: nameRange
                )
            }
        }

        applyRegex(
            pattern: #"\\[A-Za-z@]+\*?"#,
            in: source,
            textStorage: textStorage
        ) { match in
            let commandFont = NSFont.monospacedSystemFont(ofSize: baseSize, weight: .semibold)
            textStorage.addAttributes(
                [.foregroundColor: palette.command, .font: commandFont],
                range: match.range
            )
        }

        applyRegex(
            pattern: #"[{}\[\]]"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [.foregroundColor: palette.punctuation],
                range: match.range
            )
        }
    }

    private static func highlightFencedCodeBlocks(textStorage: NSTextStorage, palette: SyntaxPalette) {
        let source = textStorage.string as NSString
        applyRegex(
            pattern: #"(?m)^```[^\n]*\n[\s\S]*?^```\s*$"#,
            in: source,
            textStorage: textStorage
        ) { match in
            textStorage.addAttributes(
                [
                    .foregroundColor: palette.codeText,
                    .backgroundColor: palette.codeBackground
                ],
                range: match.range
            )
        }
    }

    private static func italicFont() -> NSFont {
        let base = baseFont
        let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    private static func applyRegex(
        pattern: String,
        in source: NSString,
        textStorage: NSTextStorage,
        action: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        regex.enumerateMatches(
            in: source as String,
            options: [],
            range: NSRange(location: 0, length: source.length)
        ) { match, _, _ in
            guard let match else { return }
            action(match)
        }
    }

    private static func applyLineRegex(
        pattern: String,
        in source: NSString,
        textStorage: NSTextStorage,
        action: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        regex.enumerateMatches(
            in: source as String,
            options: [],
            range: NSRange(location: 0, length: source.length)
        ) { match, _, _ in
            guard let match else { return }
            action(match)
        }
    }
}
