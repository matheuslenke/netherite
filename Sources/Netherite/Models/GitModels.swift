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

struct GitFileVersion: Identifiable, Hashable {
    let id: String
    let shortHash: String
    let author: String
    let date: String
    let subject: String
}
