import AppKit
import SwiftUI

enum SyntaxLanguage {
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
}

struct SyntaxHighlightingEditor: NSViewRepresentable {
    @Binding var text: String
    let language: SyntaxLanguage
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
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
        guard let textView = scrollView.documentView as? NSTextView else { return }

        textView.isEditable = isEditable
        textView.isSelectable = true

        if textView.string != text {
            context.coordinator.applyText(text, language: language)
        } else if context.coordinator.appliedLanguage != language ||
                  context.coordinator.appliedAppearanceName != textView.effectiveAppearance.name {
            context.coordinator.highlight(language: language)
        }
    }

    static var baseFont: NSFont { .monospacedSystemFont(ofSize: 14, weight: .regular) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightingEditor
        weak var textView: NSTextView?
        var appliedLanguage: SyntaxLanguage = .none
        var appliedAppearanceName: NSAppearance.Name?

        init(_ parent: SyntaxHighlightingEditor) {
            self.parent = parent
        }

        func applyText(_ newText: String, language: SyntaxLanguage) {
            guard let textView else { return }
            let selectedRanges = textView.selectedRanges
            textView.string = newText
            highlight(language: language)
            textView.selectedRanges = selectedRanges
        }

        func highlight(language: SyntaxLanguage) {
            guard let textView, let textStorage = textView.textStorage else { return }
            let appearance = textView.effectiveAppearance
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

            switch language {
            case .markdown:
                SyntaxHighlighter.highlightMarkdown(in: textStorage, palette: palette)
            case .latex:
                SyntaxHighlighter.highlightLatex(in: textStorage, palette: palette)
            case .none:
                break
            }

            textStorage.endEditing()
            appliedLanguage = language
            appliedAppearanceName = appearance.name
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlight(language: parent.language)
        }
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
