import Foundation

enum LatexSourceLocatorError: LocalizedError {
    case synctexNotFound

    var errorDescription: String? {
        switch self {
        case .synctexNotFound:
            "SyncTeX was not found. Install MacTeX or add synctex to PATH."
        }
    }
}

struct PDFSourceLookupRequest: Sendable {
    let pdfURL: URL
    let pageNumber: Int
    let x: Double
    let y: Double
    let selectedText: String?
}

struct LatexSourceLocation: Equatable, Sendable {
    let inputURL: URL
    let inputPath: String
    let line: Int
    let column: Int
}

enum LatexSourceLocator {
    private static let latexPath = [
        "/Library/TeX/texbin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ].joined(separator: ":")

    static func sourceLocation(for request: PDFSourceLookupRequest) throws -> LatexSourceLocation? {
        let executable = try synctexExecutable()
        let point = "\(request.pageNumber):\(request.x):\(request.y):\(request.pdfURL.path)"
        let result = try ProcessRunner.run(
            arguments: [
                executable,
                "edit",
                "-o",
                point,
                "-d",
                request.pdfURL.deletingLastPathComponent().path
            ],
            environment: ["PATH": latexPath]
        )

        return sourceLocation(fromSyncTeXOutput: result.output)
    }

    static func sourceLocation(fromSyncTeXOutput output: String) -> LatexSourceLocation? {
        var inputPath: String?
        var lineNumber: Int?
        var columnNumber = -1

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmed
            if line.hasPrefix("Input:") {
                inputPath = String(line.dropFirst("Input:".count)).trimmed
            } else if line.hasPrefix("Line:") {
                lineNumber = Int(String(line.dropFirst("Line:".count)).trimmed)
            } else if line.hasPrefix("Column:") {
                columnNumber = Int(String(line.dropFirst("Column:".count)).trimmed) ?? -1
            }
        }

        guard let inputPath, !inputPath.isEmpty, let lineNumber, lineNumber > 0 else {
            return nil
        }

        return LatexSourceLocation(
            inputURL: URL(fileURLWithPath: inputPath).standardizedFileURL,
            inputPath: inputPath,
            line: lineNumber,
            column: columnNumber
        )
    }

    static func sourceOffset(in text: String, line: Int, column: Int) -> Int {
        let source = text as NSString
        guard source.length > 0 else { return 0 }
        guard line > 1 else {
            return clampedColumnOffset(column, lineStart: 0, source: source)
        }

        var lineStart = 0
        var currentLine = 1

        while currentLine < line, lineStart < source.length {
            let searchRange = NSRange(location: lineStart, length: source.length - lineStart)
            let newlineRange = source.range(of: "\n", options: [], range: searchRange)
            guard newlineRange.location != NSNotFound else {
                return source.length
            }

            lineStart = newlineRange.location + newlineRange.length
            currentLine += 1
        }

        return clampedColumnOffset(column, lineStart: lineStart, source: source)
    }

    static func bestTextMatchOffset(in source: String, selectedText: String?) -> Int? {
        guard let query = selectedText?.trimmed, query.count > 1 else {
            return nil
        }

        guard let range = source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        return NSRange(range, in: source).location
    }

    private static func clampedColumnOffset(_ column: Int, lineStart: Int, source: NSString) -> Int {
        let searchRange = NSRange(location: lineStart, length: source.length - lineStart)
        let newlineRange = source.range(of: "\n", options: [], range: searchRange)
        let lineEnd = newlineRange.location == NSNotFound ? source.length : newlineRange.location
        let requestedColumn = max(column, 0)
        return min(lineStart + requestedColumn, lineEnd)
    }

    private static func synctexExecutable() throws -> String {
        let candidates = [
            "/Library/TeX/texbin/synctex",
            "/opt/homebrew/bin/synctex",
            "/usr/local/bin/synctex"
        ]

        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return candidate
        }

        if let result = try? ProcessRunner.run(
            arguments: ["/bin/zsh", "-lc", "command -v synctex"],
            environment: ["PATH": latexPath]
        ),
           !result.output.trimmed.isEmpty {
            return result.output.trimmed
        }

        throw LatexSourceLocatorError.synctexNotFound
    }
}
