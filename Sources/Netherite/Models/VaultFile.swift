import Foundation

enum FileKind: String, Codable, Sendable {
    case markdown
    case latex
    case text
    case code
    case data
    case spreadsheet
    case richText
    case document
    case image
    case binary

    init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "md", "markdown", "mdown":
            self = .markdown
        case "tex", "ltx", "bib", "bst", "cls", "sty", "bbx", "cbx":
            self = .latex
        case "txt", "text", "log":
            self = .text
        case "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "c", "cc", "cpp", "h", "hpp", "css", "scss", "html", "xml", "json", "yaml", "yml", "toml", "sh", "zsh", "bash":
            self = .code
        case "csv", "tsv":
            self = .data
        case "xlsx", "xlxs", "xlsm", "xltx", "xltm", "xls":
            self = .spreadsheet
        case "rtf", "rtfd":
            self = .richText
        case "doc", "docx", "odt", "pages", "pdf":
            self = .document
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "eps":
            self = .image
        default:
            self = .binary
        }
    }

    var systemImage: String {
        switch self {
        case .markdown:
            "doc.richtext"
        case .latex:
            "function"
        case .text:
            "doc.text"
        case .code:
            "chevron.left.forwardslash.chevron.right"
        case .data:
            "tablecells"
        case .spreadsheet:
            "tablecells"
        case .richText:
            "doc.append"
        case .document:
            "doc"
        case .image:
            "photo"
        case .binary:
            "doc.badge.gearshape"
        }
    }

    var canContainBacklinks: Bool {
        switch self {
        case .markdown, .latex, .text, .code, .data:
            true
        case .spreadsheet, .richText, .document, .image, .binary:
            false
        }
    }
}

enum NewFileFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case latex
    case bibtex
    case text
    case json
    case csv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown:
            "Markdown"
        case .latex:
            "LaTeX"
        case .bibtex:
            "BibTeX"
        case .text:
            "Text"
        case .json:
            "JSON"
        case .csv:
            "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            "md"
        case .latex:
            "tex"
        case .bibtex:
            "bib"
        case .text:
            "txt"
        case .json:
            "json"
        case .csv:
            "csv"
        }
    }

    var baseName: String {
        switch self {
        case .markdown:
            "Untitled"
        case .latex:
            "main"
        case .bibtex:
            "bibliography"
        case .text:
            "Untitled"
        case .json:
            "data"
        case .csv:
            "data"
        }
    }

    var systemImage: String {
        FileKind(fileExtension: fileExtension).systemImage
    }

    func initialContents(fileName: String) -> String {
        let title = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent

        switch self {
        case .markdown:
            return "# \(title)\n\n"
        case .latex:
            return """
            \\documentclass{article}

            \\begin{document}

            \\section{\(title)}

            \\end{document}

            """
        case .bibtex:
            return "% BibTeX bibliography\n"
        case .text:
            return ""
        case .json:
            return "{\n  \"title\": \"\(title)\"\n}\n"
        case .csv:
            return "Column 1,Column 2\n"
        }
    }
}

struct VaultFolder: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let relativePath: String
    let name: String
    let modifiedAt: Date

    var parentPath: String {
        let parts = relativePath.split(separator: "/")
        guard parts.count > 1 else { return "Vault root" }
        return parts.dropLast().joined(separator: "/")
    }
}

struct VaultFile: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let relativePath: String
    let name: String
    let fileExtension: String
    let kind: FileKind
    let byteCount: Int
    let modifiedAt: Date

    var isPDF: Bool {
        fileExtension.lowercased() == "pdf"
    }

    var isSpreadsheet: Bool {
        switch fileExtension.lowercased() {
        case "xlsx", "xlxs", "xlsm", "xltx", "xltm", "xls":
            true
        default:
            false
        }
    }

    var parentPath: String {
        let parts = relativePath.split(separator: "/")
        guard parts.count > 1 else { return "Vault root" }
        return parts.dropLast().joined(separator: "/")
    }

    var titleWithoutExtension: String {
        url.deletingPathExtension().lastPathComponent
    }
}

struct DocumentStats: Equatable, Sendable {
    let words: Int
    let characters: Int
    let lines: Int

    static let empty = DocumentStats(text: "")

    init(text: String) {
        var wordCount = 0
        var characterCount = 0
        var lineCount = 1
        var isInsideWord = false

        for character in text {
            characterCount += 1

            if character.isNewline {
                lineCount += 1
            }

            if character.isWhitespace || character.isNewline {
                isInsideWord = false
            } else if !isInsideWord {
                wordCount += 1
                isInsideWord = true
            }
        }

        words = wordCount
        characters = characterCount
        lines = max(1, lineCount)
    }
}
