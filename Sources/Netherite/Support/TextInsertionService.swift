import AppKit

@MainActor
enum TextInsertionService {
    private weak static var focusedEditableTextView: NSTextView?

    static func registerFocusedTextView(_ textView: NSTextView) {
        focusedEditableTextView = textView
    }

    @discardableResult
    static func insert(_ text: String) -> Bool {
        guard let textView = focusedEditableTextView,
              textView.window != nil,
              textView.isEditable
        else {
            return false
        }

        textView.insertText(text, replacementRange: textView.selectedRange())
        return true
    }
}
