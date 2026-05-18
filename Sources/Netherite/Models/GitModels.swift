import Foundation

struct GitSnapshot {
    var isRepository: Bool
    var branch: String
    var statusText: String
    var lastUpdated: Date?

    static let empty = GitSnapshot(
        isRepository: false,
        branch: "No repository",
        statusText: "Choose a vault to inspect git status.",
        lastUpdated: nil
    )

    var isClean: Bool {
        isRepository && statusText.trimmed.isEmpty
    }

    var summary: String {
        guard isRepository else { return "Not a git repository" }
        return isClean ? "Clean on \(branch)" : "Changes on \(branch)"
    }
}

struct GitFileVersion: Identifiable, Hashable, Sendable {
    let id: String
    let shortHash: String
    let author: String
    let date: String
    let subject: String
}

enum GitDiffScope: String, CaseIterable, Identifiable, Sendable {
    case combined
    case staged
    case unstaged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined:
            "All"
        case .staged:
            "Staged"
        case .unstaged:
            "Unstaged"
        }
    }
}

struct GitChangedFile: Identifiable, Hashable, Sendable {
    let path: String
    let originalPath: String?
    let indexStatus: Character
    let workTreeStatus: Character

    var id: String {
        "\(indexStatus)\(workTreeStatus):\(originalPath ?? ""):\(path)"
    }

    var statusCode: String {
        let raw = "\(indexStatus)\(workTreeStatus)"
        let trimmed = raw.trimmed
        return trimmed.isEmpty ? "?" : trimmed
    }

    var displayStatus: String {
        if isUntracked { return "Untracked" }
        if isConflicted { return "Conflict" }
        if hasStagedChanges && hasUnstagedChanges { return "Partially Staged" }
        if indexStatus == "R" || workTreeStatus == "R" { return "Renamed" }
        if indexStatus == "C" || workTreeStatus == "C" { return "Copied" }
        if indexStatus == "A" || workTreeStatus == "A" { return "Added" }
        if indexStatus == "D" || workTreeStatus == "D" { return "Deleted" }
        if indexStatus == "T" || workTreeStatus == "T" { return "Type Changed" }
        if indexStatus == "M" || workTreeStatus == "M" { return "Modified" }
        return "Changed"
    }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var parentPath: String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return "Vault root" }
        return parts.dropLast().joined(separator: "/")
    }

    var hasStagedChanges: Bool {
        indexStatus != " " && indexStatus != "?"
    }

    var hasUnstagedChanges: Bool {
        isUntracked || (workTreeStatus != " " && workTreeStatus != "?")
    }

    var canStage: Bool {
        isUntracked || hasUnstagedChanges
    }

    var canUnstage: Bool {
        hasStagedChanges
    }

    var canDiscard: Bool {
        isUntracked || hasStagedChanges || hasUnstagedChanges
    }

    var stagedStatusText: String? {
        guard hasStagedChanges else { return nil }
        return Self.statusDescription(for: indexStatus)
    }

    var unstagedStatusText: String? {
        guard hasUnstagedChanges else { return nil }
        return isUntracked ? "Untracked" : Self.statusDescription(for: workTreeStatus)
    }

    var affectedPaths: [String] {
        [originalPath, path].compactMap(\.self).uniquedKeepingOrder()
    }

    func supportsDiffScope(_ scope: GitDiffScope) -> Bool {
        switch scope {
        case .combined:
            true
        case .staged:
            hasStagedChanges
        case .unstaged:
            hasUnstagedChanges
        }
    }

    var systemImage: String {
        if indexStatus == "D" || workTreeStatus == "D" {
            return "trash"
        }
        return FileKind(fileExtension: URL(fileURLWithPath: path).pathExtension).systemImage
    }

    var isUntracked: Bool {
        indexStatus == "?" && workTreeStatus == "?"
    }

    var isConflicted: Bool {
        let code = "\(indexStatus)\(workTreeStatus)"
        return ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains(code)
    }

    private static func statusDescription(for status: Character) -> String {
        switch status {
        case "A":
            "Added"
        case "C":
            "Copied"
        case "D":
            "Deleted"
        case "M":
            "Modified"
        case "R":
            "Renamed"
        case "T":
            "Type Changed"
        case "U":
            "Unmerged"
        case "?":
            "Untracked"
        default:
            "Changed"
        }
    }
}

enum GitDiffLineKind: Hashable {
    case fileHeader
    case metadata
    case hunk
    case addition
    case deletion
    case context
}

struct GitDiffLine: Identifiable, Hashable {
    let id: Int
    let text: String
    let kind: GitDiffLineKind

    static func parse(_ diff: String) -> [GitDiffLine] {
        diff
            .components(separatedBy: .newlines)
            .enumerated()
            .map { offset, line in
                GitDiffLine(id: offset, text: line, kind: kind(for: line))
            }
    }

    private static func kind(for line: String) -> GitDiffLineKind {
        if line.hasPrefix("@@") {
            return .hunk
        }

        if line.hasPrefix("+"), !line.hasPrefix("+++") {
            return .addition
        }

        if line.hasPrefix("-"), !line.hasPrefix("---") {
            return .deletion
        }

        if line.hasPrefix("diff --git") ||
            line.hasPrefix("--- ") ||
            line.hasPrefix("+++ ") {
            return .fileHeader
        }

        if line.hasPrefix("index ") ||
            line.hasPrefix("new file mode") ||
            line.hasPrefix("deleted file mode") ||
            line.hasPrefix("similarity index") ||
            line.hasPrefix("rename from") ||
            line.hasPrefix("rename to") {
            return .metadata
        }

        return .context
    }
}

struct GitFileComparison: Equatable, Sendable {
    let previousTitle: String
    let changedTitle: String
    let previousText: String
    let changedText: String
    let rows: [GitSideBySideDiffRow]

    static let empty = GitFileComparison(
        previousTitle: "Previous",
        changedTitle: "Changes",
        previousText: "",
        changedText: ""
    )

    init(
        previousTitle: String,
        changedTitle: String,
        previousText: String,
        changedText: String
    ) {
        self.previousTitle = previousTitle
        self.changedTitle = changedTitle
        self.previousText = previousText
        self.changedText = changedText
        self.rows = GitSideBySideDiffRow.align(previousText: previousText, changedText: changedText)
    }
}

enum GitSideBySideDiffKind: Hashable, Sendable {
    case context
    case insertion
    case deletion
    case modification
}

struct GitSideBySideDiffRow: Identifiable, Hashable, Sendable {
    let id: Int
    let previousLineNumber: Int?
    let changedLineNumber: Int?
    let previousText: String?
    let changedText: String?
    let kind: GitSideBySideDiffKind

    static func align(previousText: String, changedText: String) -> [GitSideBySideDiffRow] {
        let previousLines = comparableLines(from: previousText)
        let changedLines = comparableLines(from: changedText)

        guard !previousLines.isEmpty || !changedLines.isEmpty else { return [] }

        let cellCount = previousLines.count * changedLines.count
        guard cellCount <= 900_000 else {
            return fallbackAlign(previousLines: previousLines, changedLines: changedLines)
        }

        let lcs = lcsTable(previousLines: previousLines, changedLines: changedLines)
        return align(previousLines: previousLines, changedLines: changedLines, lcs: lcs)
    }

    private static func comparableLines(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var lines = text.components(separatedBy: .newlines)
        if text.hasSuffix("\n") || text.hasSuffix("\r\n") {
            lines.removeLast()
        }
        return lines
    }

    private static func lcsTable(previousLines: [String], changedLines: [String]) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: changedLines.count + 1),
            count: previousLines.count + 1
        )

        guard !previousLines.isEmpty, !changedLines.isEmpty else { return table }

        for previousIndex in stride(from: previousLines.count - 1, through: 0, by: -1) {
            for changedIndex in stride(from: changedLines.count - 1, through: 0, by: -1) {
                if previousLines[previousIndex] == changedLines[changedIndex] {
                    table[previousIndex][changedIndex] = table[previousIndex + 1][changedIndex + 1] + 1
                } else {
                    table[previousIndex][changedIndex] = max(
                        table[previousIndex + 1][changedIndex],
                        table[previousIndex][changedIndex + 1]
                    )
                }
            }
        }

        return table
    }

    private static func align(
        previousLines: [String],
        changedLines: [String],
        lcs: [[Int]]
    ) -> [GitSideBySideDiffRow] {
        var rows: [GitSideBySideDiffRow] = []
        var previousIndex = 0
        var changedIndex = 0

        func appendChangedRows(
            deleted: [(lineNumber: Int, text: String)],
            inserted: [(lineNumber: Int, text: String)]
        ) {
            let count = max(deleted.count, inserted.count)
            guard count > 0 else { return }

            for offset in 0..<count {
                let deletedLine = offset < deleted.count ? deleted[offset] : nil
                let insertedLine = offset < inserted.count ? inserted[offset] : nil
                let kind: GitSideBySideDiffKind

                if deletedLine != nil, insertedLine != nil {
                    kind = .modification
                } else if deletedLine != nil {
                    kind = .deletion
                } else {
                    kind = .insertion
                }

                rows.append(
                    GitSideBySideDiffRow(
                        id: rows.count,
                        previousLineNumber: deletedLine?.lineNumber,
                        changedLineNumber: insertedLine?.lineNumber,
                        previousText: deletedLine?.text,
                        changedText: insertedLine?.text,
                        kind: kind
                    )
                )
            }
        }

        while previousIndex < previousLines.count || changedIndex < changedLines.count {
            if previousIndex < previousLines.count,
               changedIndex < changedLines.count,
               previousLines[previousIndex] == changedLines[changedIndex] {
                rows.append(
                    GitSideBySideDiffRow(
                        id: rows.count,
                        previousLineNumber: previousIndex + 1,
                        changedLineNumber: changedIndex + 1,
                        previousText: previousLines[previousIndex],
                        changedText: changedLines[changedIndex],
                        kind: .context
                    )
                )
                previousIndex += 1
                changedIndex += 1
                continue
            }

            var deleted: [(lineNumber: Int, text: String)] = []
            var inserted: [(lineNumber: Int, text: String)] = []

            while previousIndex < previousLines.count || changedIndex < changedLines.count {
                if previousIndex < previousLines.count,
                   changedIndex < changedLines.count,
                   previousLines[previousIndex] == changedLines[changedIndex] {
                    break
                }

                if changedIndex >= changedLines.count ||
                    (previousIndex < previousLines.count &&
                        lcs[previousIndex + 1][changedIndex] >= lcs[previousIndex][changedIndex + 1]) {
                    deleted.append((previousIndex + 1, previousLines[previousIndex]))
                    previousIndex += 1
                } else if changedIndex < changedLines.count {
                    inserted.append((changedIndex + 1, changedLines[changedIndex]))
                    changedIndex += 1
                }
            }

            appendChangedRows(deleted: deleted, inserted: inserted)
        }

        return rows
    }

    private static func fallbackAlign(
        previousLines: [String],
        changedLines: [String]
    ) -> [GitSideBySideDiffRow] {
        let count = max(previousLines.count, changedLines.count)

        return (0..<count).map { index in
            let previousLine = index < previousLines.count ? previousLines[index] : nil
            let changedLine = index < changedLines.count ? changedLines[index] : nil
            let kind: GitSideBySideDiffKind

            if previousLine == changedLine {
                kind = .context
            } else if previousLine == nil {
                kind = .insertion
            } else if changedLine == nil {
                kind = .deletion
            } else {
                kind = .modification
            }

            return GitSideBySideDiffRow(
                id: index,
                previousLineNumber: previousLine == nil ? nil : index + 1,
                changedLineNumber: changedLine == nil ? nil : index + 1,
                previousText: previousLine,
                changedText: changedLine,
                kind: kind
            )
        }
    }
}

private extension Array where Element: Hashable {
    func uniquedKeepingOrder() -> [Element] {
        var seen: Set<Element> = []
        var unique: [Element] = []

        for element in self where seen.insert(element).inserted {
            unique.append(element)
        }

        return unique
    }
}
