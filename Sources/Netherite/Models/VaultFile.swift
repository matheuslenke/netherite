import Foundation

enum FileKind: String, Codable {
    case markdown
    case latex
    case text
    case code
    case data
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
}

enum NewFileFormat: String, CaseIterable, Identifiable {
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

struct VaultFolder: Identifiable, Hashable {
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

struct VaultFile: Identifiable, Hashable {
    let id: String
    let url: URL
    let relativePath: String
    let name: String
    let fileExtension: String
    let kind: FileKind
    let byteCount: Int
    let modifiedAt: Date

    var parentPath: String {
        let parts = relativePath.split(separator: "/")
        guard parts.count > 1 else { return "Vault root" }
        return parts.dropLast().joined(separator: "/")
    }

    var titleWithoutExtension: String {
        url.deletingPathExtension().lastPathComponent
    }
}

struct DocumentStats {
    let words: Int
    let characters: Int
    let lines: Int

    init(text: String) {
        words = text
            .split { $0.isWhitespace || $0.isNewline }
            .count
        characters = text.count
        lines = max(1, text.components(separatedBy: .newlines).count)
    }
}
