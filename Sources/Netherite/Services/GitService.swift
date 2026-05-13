import Foundation

final class GitService {
    func snapshot(for vaultURL: URL) throws -> GitSnapshot {
        guard isRepository(vaultURL: vaultURL) else {
            return GitSnapshot(
                isRepository: false,
                branch: "No repository",
                statusText: "This vault is not initialized with git.",
                lastUpdated: Date()
            )
        }

        let branch = (try? ProcessRunner.run(arguments: ["git", "branch", "--show-current"], currentDirectory: vaultURL).output.trimmed)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Detached HEAD"
        let status = (try? ProcessRunner.run(arguments: ["git", "status", "--short"], currentDirectory: vaultURL).output) ?? ""

        return GitSnapshot(
            isRepository: true,
            branch: branch,
            statusText: status,
            lastUpdated: Date()
        )
    }

    func initializeRepository(at vaultURL: URL) throws -> String {
        try ProcessRunner.run(arguments: ["git", "init"], currentDirectory: vaultURL).output
    }

    func pull(vaultURL: URL) throws -> String {
        try ProcessRunner.run(arguments: ["git", "pull", "--ff-only"], currentDirectory: vaultURL).output
    }

    func push(vaultURL: URL) throws -> String {
        try ProcessRunner.run(arguments: ["git", "push"], currentDirectory: vaultURL).output
    }

    func commitAll(vaultURL: URL, message: String) throws -> String {
        try ProcessRunner.run(arguments: ["git", "add", "-A"], currentDirectory: vaultURL)
        return try ProcessRunner.run(arguments: ["git", "commit", "-m", message], currentDirectory: vaultURL).output
    }

    func history(for relativePath: String, in vaultURL: URL) throws -> [GitFileVersion] {
        guard isRepository(vaultURL: vaultURL) else { return [] }

        let output: String
        do {
            output = try ProcessRunner.run(arguments: [
                "git",
                "log",
                "--follow",
                "--date=short",
                "--pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s",
                "--",
                relativePath
            ], currentDirectory: vaultURL).output
        } catch {
            return []
        }

        return output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                guard parts.count >= 5 else { return nil }
                return GitFileVersion(
                    id: String(parts[0]),
                    shortHash: String(parts[1]),
                    author: String(parts[2]),
                    date: String(parts[3]),
                    subject: parts.dropFirst(4).joined(separator: "\u{1f}")
                )
            }
    }

    func diff(version: GitFileVersion, relativePath: String, in vaultURL: URL) throws -> String {
        try ProcessRunner.run(arguments: [
            "git",
            "show",
            "--stat",
            "--patch",
            "--find-renames",
            version.id,
            "--",
            relativePath
        ], currentDirectory: vaultURL).output
    }

    private func isRepository(vaultURL: URL) -> Bool {
        let output = try? ProcessRunner.run(arguments: ["git", "rev-parse", "--is-inside-work-tree"], currentDirectory: vaultURL).output.trimmed
        return output == "true"
    }
}
