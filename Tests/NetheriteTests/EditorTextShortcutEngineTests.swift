import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class EditorTextShortcutEngineTests: XCTestCase {
    func testToggleLatexLineCommentsCommentsAndUncommentsSelectedLines() {
        let text = "alpha\n  beta\n"
        let selection = NSRange(location: 0, length: (text as NSString).length)

        let commented = apply(.toggleLineComment, to: text, selection: selection, style: .prefix("% "))
        XCTAssertEqual(commented.text, "% alpha\n  % beta\n")
        XCTAssertEqual(commented.selection, NSRange(location: 0, length: ("% alpha\n  % beta\n" as NSString).length))

        let uncommented = apply(.toggleLineComment, to: commented.text, selection: commented.selection, style: .prefix("% "))
        XCTAssertEqual(uncommented.text, text)
    }

    func testToggleMarkdownLineCommentsWrapsNonBlankLines() {
        let text = "# Heading\n\nBody\n"
        let selection = NSRange(location: 0, length: (text as NSString).length)

        let commented = apply(.toggleLineComment, to: text, selection: selection, style: .wrapping(open: "<!--", close: "-->"))
        XCTAssertEqual(commented.text, "<!-- # Heading -->\n\n<!-- Body -->\n")

        let uncommented = apply(.toggleLineComment, to: commented.text, selection: commented.selection, style: .wrapping(open: "<!--", close: "-->"))
        XCTAssertEqual(uncommented.text, text)
    }

    func testIndentAndOutdentSelectedLines() {
        let text = "one\n  two\n"
        let selection = NSRange(location: 0, length: (text as NSString).length)

        let indented = apply(.indentLines, to: text, selection: selection)
        XCTAssertEqual(indented.text, "    one\n      two\n")

        let outdented = apply(.outdentLines, to: indented.text, selection: indented.selection)
        XCTAssertEqual(outdented.text, text)
    }

    func testMoveLinesUpAndDown() {
        let text = "one\ntwo\nthree\n"
        let selection = NSRange(location: 4, length: 3)

        let movedUp = apply(.moveLinesUp, to: text, selection: selection)
        XCTAssertEqual(movedUp.text, "two\none\nthree\n")
        XCTAssertEqual(movedUp.selection, NSRange(location: 0, length: 4))

        let movedDown = apply(.moveLinesDown, to: movedUp.text, selection: movedUp.selection)
        XCTAssertEqual(movedDown.text, text)
    }

    func testDuplicateAndDeleteLines() {
        let text = "one\ntwo"
        let selection = NSRange(location: 4, length: 0)

        let duplicated = apply(.duplicateLinesDown, to: text, selection: selection)
        XCTAssertEqual(duplicated.text, "one\ntwo\ntwo")
        XCTAssertEqual(duplicated.selection, NSRange(location: 8, length: 3))

        let deleted = apply(.deleteLines, to: duplicated.text, selection: duplicated.selection)
        XCTAssertEqual(deleted.text, "one\ntwo")
        XCTAssertEqual(deleted.selection, NSRange(location: 8, length: 0))
    }

    private func apply(
        _ action: EditorTextShortcutAction,
        to text: String,
        selection: NSRange,
        style: EditorLineCommentStyle = .prefix("// ")
    ) -> (text: String, selection: NSRange) {
        let edit = EditorTextShortcutEngine.edit(
            for: action,
            in: text,
            selectedRange: selection,
            commentStyle: style
        )
        XCTAssertNotNil(edit)

        guard let edit else {
            return (text, selection)
        }

        let updatedText = (text as NSString).replacingCharacters(in: edit.replacementRange, with: edit.replacementText)
        return (updatedText, edit.selectedRange)
    }
}
#endif
