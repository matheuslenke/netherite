import Foundation

enum EditorLineCommentStyle: Equatable {
    case prefix(String)
    case wrapping(open: String, close: String)
}

enum EditorTextShortcutAction {
    case toggleLineComment
    case indentLines
    case outdentLines
    case moveLinesUp
    case moveLinesDown
    case duplicateLinesUp
    case duplicateLinesDown
    case deleteLines
    case insertLineAbove
    case insertLineBelow
}

struct EditorTextEdit: Equatable {
    let replacementRange: NSRange
    let replacementText: String
    let selectedRange: NSRange
}

enum EditorTextShortcutEngine {
    static let indentation = "    "

    static func edit(
        for action: EditorTextShortcutAction,
        in text: String,
        selectedRange: NSRange,
        commentStyle: EditorLineCommentStyle
    ) -> EditorTextEdit? {
        let source = text as NSString
        let clampedSelection = clampedRange(selectedRange, length: source.length)

        switch action {
        case .toggleLineComment:
            return toggleLineComment(in: source, selectedRange: clampedSelection, style: commentStyle)
        case .indentLines:
            return transformSelectedLines(in: source, selectedRange: clampedSelection) { indentation + $0 }
        case .outdentLines:
            return transformSelectedLines(in: source, selectedRange: clampedSelection, transform: outdentedLine)
        case .moveLinesUp:
            return moveSelectedLines(in: source, selectedRange: clampedSelection, direction: .up)
        case .moveLinesDown:
            return moveSelectedLines(in: source, selectedRange: clampedSelection, direction: .down)
        case .duplicateLinesUp:
            return duplicateSelectedLines(in: source, selectedRange: clampedSelection, direction: .up)
        case .duplicateLinesDown:
            return duplicateSelectedLines(in: source, selectedRange: clampedSelection, direction: .down)
        case .deleteLines:
            let lineRange = selectedLineRange(in: source, selectedRange: clampedSelection)
            return EditorTextEdit(
                replacementRange: lineRange,
                replacementText: "",
                selectedRange: NSRange(location: lineRange.location, length: 0)
            )
        case .insertLineAbove:
            let lineRange = source.lineRange(for: NSRange(location: clampedSelection.location, length: 0))
            return EditorTextEdit(
                replacementRange: NSRange(location: lineRange.location, length: 0),
                replacementText: "\n",
                selectedRange: NSRange(location: lineRange.location, length: 0)
            )
        case .insertLineBelow:
            let lineRange = source.lineRange(for: NSRange(location: clampedSelection.location, length: 0))
            let insertLocation = NSMaxRange(lineRange)
            return EditorTextEdit(
                replacementRange: NSRange(location: insertLocation, length: 0),
                replacementText: "\n",
                selectedRange: NSRange(location: insertLocation + 1, length: 0)
            )
        }
    }

    private enum LineMoveDirection {
        case up
        case down
    }

    private static func toggleLineComment(
        in source: NSString,
        selectedRange: NSRange,
        style: EditorLineCommentStyle
    ) -> EditorTextEdit {
        switch style {
        case .prefix(let prefix):
            return togglePrefixLineComment(in: source, selectedRange: selectedRange, prefix: prefix)
        case .wrapping(let open, let close):
            return toggleWrappingLineComment(in: source, selectedRange: selectedRange, open: open, close: close)
        }
    }

    private static func togglePrefixLineComment(
        in source: NSString,
        selectedRange: NSRange,
        prefix: String
    ) -> EditorTextEdit {
        let lineRange = selectedLineRange(in: source, selectedRange: selectedRange)
        let lines = lineRanges(in: source, range: lineRange)
            .map { source.substring(with: $0) }
        let nonBlankLines = lines.filter { !$0.lineBody.trimmingCharacters(in: .whitespaces).isEmpty }
        let shouldUncomment = !nonBlankLines.isEmpty && nonBlankLines.allSatisfy { line in
            line.lineBody.hasLineCommentPrefix(prefix)
        }
        let replacement = lines
            .map { shouldUncomment ? $0.removingLineCommentPrefix(prefix) : $0.addingLineCommentPrefix(prefix) }
            .joined()

        return editReplacingLines(lineRange, with: replacement)
    }

    private static func toggleWrappingLineComment(
        in source: NSString,
        selectedRange: NSRange,
        open: String,
        close: String
    ) -> EditorTextEdit {
        let lineRange = selectedLineRange(in: source, selectedRange: selectedRange)
        let lines = lineRanges(in: source, range: lineRange)
            .map { source.substring(with: $0) }
        let nonBlankLines = lines.filter { !$0.lineBody.trimmingCharacters(in: .whitespaces).isEmpty }
        let shouldUncomment = !nonBlankLines.isEmpty && nonBlankLines.allSatisfy { line in
            line.lineBody.hasWrappingLineComment(open: open, close: close)
        }
        let replacement = lines
            .map { line -> String in
                if shouldUncomment {
                    return line.removingWrappingLineComment(open: open, close: close)
                }
                return line.addingWrappingLineComment(open: open, close: close)
            }
            .joined()

        return editReplacingLines(lineRange, with: replacement)
    }

    private static func transformSelectedLines(
        in source: NSString,
        selectedRange: NSRange,
        transform: (String) -> String
    ) -> EditorTextEdit {
        let lineRange = selectedLineRange(in: source, selectedRange: selectedRange)
        let replacement = lineRanges(in: source, range: lineRange)
            .map { transform(source.substring(with: $0)) }
            .joined()

        return editReplacingLines(lineRange, with: replacement)
    }

    private static func moveSelectedLines(
        in source: NSString,
        selectedRange: NSRange,
        direction: LineMoveDirection
    ) -> EditorTextEdit? {
        let lineRange = selectedLineRange(in: source, selectedRange: selectedRange)
        let selectedText = source.substring(with: lineRange)

        switch direction {
        case .up:
            guard lineRange.location > 0 else { return nil }
            let previousLineRange = source.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
            let previousText = source.substring(with: previousLineRange)
            let replacementRange = NSRange(
                location: previousLineRange.location,
                length: previousLineRange.length + lineRange.length
            )

            return EditorTextEdit(
                replacementRange: replacementRange,
                replacementText: selectedText + previousText,
                selectedRange: NSRange(location: previousLineRange.location, length: lineRange.length)
            )
        case .down:
            guard NSMaxRange(lineRange) < source.length else { return nil }
            let nextLineRange = source.lineRange(for: NSRange(location: NSMaxRange(lineRange), length: 0))
            let nextText = source.substring(with: nextLineRange)
            let replacementRange = NSRange(
                location: lineRange.location,
                length: lineRange.length + nextLineRange.length
            )

            return EditorTextEdit(
                replacementRange: replacementRange,
                replacementText: nextText + selectedText,
                selectedRange: NSRange(location: lineRange.location + nextLineRange.length, length: lineRange.length)
            )
        }
    }

    private static func duplicateSelectedLines(
        in source: NSString,
        selectedRange: NSRange,
        direction: LineMoveDirection
    ) -> EditorTextEdit {
        let lineRange = selectedLineRange(in: source, selectedRange: selectedRange)
        let selectedText = source.substring(with: lineRange)
        let selectedLength = (selectedText as NSString).length

        switch direction {
        case .up:
            let replacementText = selectedText.hasLineEnding ? selectedText : selectedText + "\n"
            return EditorTextEdit(
                replacementRange: NSRange(location: lineRange.location, length: 0),
                replacementText: replacementText,
                selectedRange: NSRange(location: lineRange.location, length: selectedLength)
            )
        case .down:
            let needsLeadingLineBreak = !selectedText.hasLineEnding && NSMaxRange(lineRange) == source.length
            let replacementText = needsLeadingLineBreak ? "\n" + selectedText : selectedText
            let selectedLocation = NSMaxRange(lineRange) + (needsLeadingLineBreak ? 1 : 0)
            return EditorTextEdit(
                replacementRange: NSRange(location: NSMaxRange(lineRange), length: 0),
                replacementText: replacementText,
                selectedRange: NSRange(location: selectedLocation, length: selectedLength)
            )
        }
    }

    private static func outdentedLine(_ line: String) -> String {
        if line.hasPrefix("\t") {
            return String(line.dropFirst())
        }

        let removableSpaces = line.prefix(while: { $0 == " " }).prefix(indentation.count).count
        guard removableSpaces > 0 else { return line }
        return String(line.dropFirst(removableSpaces))
    }

    private static func editReplacingLines(_ lineRange: NSRange, with replacement: String) -> EditorTextEdit {
        EditorTextEdit(
            replacementRange: lineRange,
            replacementText: replacement,
            selectedRange: NSRange(location: lineRange.location, length: (replacement as NSString).length)
        )
    }

    private static func selectedLineRange(in source: NSString, selectedRange: NSRange) -> NSRange {
        var range = clampedRange(selectedRange, length: source.length)

        if range.length > 0,
           NSMaxRange(range) > range.location,
           isLineStart(NSMaxRange(range), in: source) {
            range.length -= 1
        }

        return source.lineRange(for: range)
    }

    private static func lineRanges(in source: NSString, range: NSRange) -> [NSRange] {
        guard source.length > 0 else { return [NSRange(location: 0, length: 0)] }

        let lineRange = clampedRange(range, length: source.length)
        var ranges: [NSRange] = []
        var location = lineRange.location
        let end = NSMaxRange(lineRange)

        while location < end {
            let range = source.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            let nextLocation = NSMaxRange(range)
            guard nextLocation > location else { break }
            location = nextLocation
        }

        if ranges.isEmpty {
            ranges.append(source.lineRange(for: NSRange(location: lineRange.location, length: 0)))
        }

        return ranges
    }

    private static func clampedRange(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let maxLength = length - location
        return NSRange(location: location, length: min(max(range.length, 0), maxLength))
    }

    private static func isLineStart(_ location: Int, in source: NSString) -> Bool {
        guard location > 0, location <= source.length else { return location == 0 }
        let previousCharacter = source.substring(with: NSRange(location: location - 1, length: 1))
        return previousCharacter == "\n" || previousCharacter == "\r"
    }
}

private extension String {
    var hasLineEnding: Bool {
        hasSuffix("\n") || hasSuffix("\r")
    }

    var lineBody: String {
        if hasSuffix("\r\n") {
            return String(dropLast(2))
        }
        if hasSuffix("\n") || hasSuffix("\r") {
            return String(dropLast())
        }
        return self
    }

    var lineEnding: String {
        if hasSuffix("\r\n") {
            return "\r\n"
        }
        if hasSuffix("\n") {
            return "\n"
        }
        if hasSuffix("\r") {
            return "\r"
        }
        return ""
    }

    func addingLineCommentPrefix(_ prefix: String) -> String {
        let body = lineBody
        let ending = lineEnding
        let indentationEnd = body.firstIndex { $0 != " " && $0 != "\t" } ?? body.endIndex
        return String(body[..<indentationEnd]) + prefix + String(body[indentationEnd...]) + ending
    }

    func removingLineCommentPrefix(_ prefix: String) -> String {
        let body = lineBody
        let ending = lineEnding
        guard let range = body.lineCommentPrefixRange(prefix) else { return self }
        return body.replacingCharacters(in: range, with: "") + ending
    }

    func hasLineCommentPrefix(_ prefix: String) -> Bool {
        lineCommentPrefixRange(prefix) != nil
    }

    private func lineCommentPrefixRange(_ prefix: String) -> Range<String.Index>? {
        let indentationEnd = firstIndex { $0 != " " && $0 != "\t" } ?? endIndex
        guard self[indentationEnd...].hasPrefix(prefix) else { return nil }

        let prefixEnd = index(indentationEnd, offsetBy: prefix.count)
        if prefix.hasSuffix(" ") || prefixEnd == endIndex || self[prefixEnd] != " " {
            return indentationEnd..<prefixEnd
        }

        return indentationEnd..<index(after: prefixEnd)
    }

    func addingWrappingLineComment(open: String, close: String) -> String {
        let body = lineBody
        let ending = lineEnding
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return self }

        let indentationEnd = body.firstIndex { $0 != " " && $0 != "\t" } ?? body.endIndex
        return body[..<indentationEnd] + open + " " + body[indentationEnd...] + " " + close + ending
    }

    func removingWrappingLineComment(open: String, close: String) -> String {
        let body = lineBody
        let ending = lineEnding
        guard let range = body.wrappingLineCommentContentRange(open: open, close: close) else { return self }

        let indentationEnd = body.firstIndex { $0 != " " && $0 != "\t" } ?? body.endIndex
        return String(body[..<indentationEnd]) + String(body[range]) + ending
    }

    func hasWrappingLineComment(open: String, close: String) -> Bool {
        wrappingLineCommentContentRange(open: open, close: close) != nil
    }

    private func wrappingLineCommentContentRange(open: String, close: String) -> Range<String.Index>? {
        let indentationEnd = firstIndex { $0 != " " && $0 != "\t" } ?? endIndex
        guard self[indentationEnd...].hasPrefix(open), hasSuffix(close) else { return nil }

        var contentStart = index(indentationEnd, offsetBy: open.count)
        if contentStart < endIndex, self[contentStart] == " " {
            contentStart = index(after: contentStart)
        }

        var contentEnd = index(endIndex, offsetBy: -close.count)
        if contentEnd > contentStart, self[index(before: contentEnd)] == " " {
            contentEnd = index(before: contentEnd)
        }

        return contentStart..<contentEnd
    }
}
