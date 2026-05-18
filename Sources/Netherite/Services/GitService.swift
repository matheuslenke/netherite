import Foundation

enum GitServiceError: LocalizedError {
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case let .unsafePath(path):
            "Refusing to modify a path outside the vault: \(path)"
        }
    }
}

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
        let status = ((try? changedFiles(in: vaultURL)) ?? [])
            .map { "\($0.statusCode) \($0.path)" }
            .joined(separator: "\n")

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
        try stageAll(in: vaultURL)
        return try commitStaged(vaultURL: vaultURL, message: message)
    }

    func commitStaged(vaultURL: URL, message: String) throws -> String {
        try ProcessRunner.run(arguments: ["git", "commit", "-m", message], currentDirectory: vaultURL).output
    }

    func stage(_ change: GitChangedFile, in vaultURL: URL) throws {
        try ProcessRunner.run(arguments: ["git", "add", "--", change.path], currentDirectory: vaultURL)
    }

    func stageAll(in vaultURL: URL) throws {
        try ProcessRunner.run(arguments: ["git", "add", "-A"], currentDirectory: vaultURL)
    }

    func unstage(_ change: GitChangedFile, in vaultURL: URL) throws {
        try unstage(paths: change.affectedPaths, in: vaultURL)
    }

    func unstageAll(in vaultURL: URL) throws {
        do {
            try ProcessRunner.run(arguments: ["git", "restore", "--staged", "--", "."], currentDirectory: vaultURL)
        } catch {
            try ProcessRunner.run(arguments: ["git", "rm", "--cached", "-r", "--force", "--", "."], currentDirectory: vaultURL)
        }
    }

    func discard(_ change: GitChangedFile, in vaultURL: URL) throws {
        guard isRepository(vaultURL: vaultURL) else { return }

        if change.isUntracked {
            try removePathFromWorkingTree(change.path, vaultURL: vaultURL)
            return
        }

        if change.hasStagedChanges {
            try unstage(change, in: vaultURL)
        }

        let paths = change.affectedPaths
        let trackedPaths = paths.filter { pathExistsInHead($0, in: vaultURL) }
        if !trackedPaths.isEmpty {
            try ProcessRunner.run(
                arguments: [
                    "git",
                    "restore",
                    "--source=HEAD",
                    "--worktree",
                    "--"
                ] + trackedPaths,
                currentDirectory: vaultURL
            )
        }

        for path in paths where !pathExistsInHead(path, in: vaultURL) {
            try removePathFromWorkingTree(path, vaultURL: vaultURL)
        }
    }

    func discardAll(in vaultURL: URL) throws {
        guard isRepository(vaultURL: vaultURL) else { return }

        if repositoryHasHead(vaultURL) {
            try ProcessRunner.run(arguments: ["git", "reset", "--hard", "HEAD"], currentDirectory: vaultURL)
            try ProcessRunner.run(arguments: ["git", "clean", "-fd"], currentDirectory: vaultURL)
        } else {
            try? ProcessRunner.run(arguments: ["git", "rm", "--cached", "-r", "--force", "--", "."], currentDirectory: vaultURL)
            try ProcessRunner.run(arguments: ["git", "clean", "-fd"], currentDirectory: vaultURL)
        }
    }

    func changedFiles(in vaultURL: URL) throws -> [GitChangedFile] {
        guard isRepository(vaultURL: vaultURL) else { return [] }

        let output = try ProcessRunner.run(arguments: [
            "git",
            "status",
            "--porcelain=v1",
            "-z",
            "--untracked-files=all"
        ], currentDirectory: vaultURL).output

        return parsePorcelainStatus(output)
            .filter { !isIgnoredVaultPath($0.path) && !($0.originalPath.map(isIgnoredVaultPath) ?? false) }
    }

    func workingTreeDiff(for change: GitChangedFile, in vaultURL: URL) throws -> String {
        try diff(for: change, scope: .combined, in: vaultURL)
    }

    func comparison(for change: GitChangedFile, scope: GitDiffScope, in vaultURL: URL) throws -> GitFileComparison {
        guard isRepository(vaultURL: vaultURL) else { return .empty }

        let previousPath = change.originalPath ?? change.path
        let previousText: String
        let changedText: String
        let previousTitle: String
        let changedTitle: String

        switch scope {
        case .combined:
            previousText = headText(path: previousPath, in: vaultURL)
            changedText = try workingTreeText(path: change.path, in: vaultURL)
            previousTitle = "Previous"
            changedTitle = "Changes"
        case .staged:
            guard change.hasStagedChanges else { return .empty }
            previousText = headText(path: previousPath, in: vaultURL)
            changedText = indexText(path: change.path, in: vaultURL)
            previousTitle = "Previous"
            changedTitle = "Staged"
        case .unstaged:
            guard change.hasUnstagedChanges else { return .empty }
            if change.isUntracked {
                previousText = ""
                previousTitle = "Previous"
            } else {
                previousText = pathExistsInIndex(previousPath, in: vaultURL) ?
                    indexText(path: previousPath, in: vaultURL) :
                    headText(path: previousPath, in: vaultURL)
                previousTitle = change.hasStagedChanges ? "Staged" : "Previous"
            }
            changedText = try workingTreeText(path: change.path, in: vaultURL)
            changedTitle = "Changes"
        }

        return GitFileComparison(
            previousTitle: previousTitle,
            changedTitle: changedTitle,
            previousText: previousText,
            changedText: changedText
        )
    }

    func diff(for change: GitChangedFile, scope: GitDiffScope, in vaultURL: URL) throws -> String {
        guard isRepository(vaultURL: vaultURL) else { return "" }

        switch scope {
        case .combined:
            return try combinedDiff(for: change, in: vaultURL)
        case .staged:
            guard change.hasStagedChanges else { return "" }
            return try runDiff(arguments: [
                "git",
                "diff",
                "--no-ext-diff",
                "--find-renames",
                "--find-copies",
                "--cached",
                "--patch",
                "--stat",
                "--"
            ] + change.affectedPaths, currentDirectory: vaultURL)
        case .unstaged:
            if change.isUntracked {
                return try untrackedDiff(for: change, in: vaultURL)
            }

            guard change.hasUnstagedChanges else { return "" }
            return try runDiff(arguments: [
                "git",
                "diff",
                "--no-ext-diff",
                "--find-renames",
                "--find-copies",
                "--patch",
                "--stat",
                "--",
                change.path
            ], currentDirectory: vaultURL)
        }
    }

    private func combinedDiff(for change: GitChangedFile, in vaultURL: URL) throws -> String {
        if change.isUntracked {
            return try untrackedDiff(for: change, in: vaultURL)
        }

        do {
            let diff = try runDiff(arguments: [
                "git",
                "diff",
                "--no-ext-diff",
                "--find-renames",
                "--find-copies",
                "--patch",
                "--stat",
                "HEAD",
                "--",
            ] + change.affectedPaths, currentDirectory: vaultURL)

            if !diff.trimmed.isEmpty {
                return diff
            }
        } catch {
            let scopedDiffs = [
                (try? diff(for: change, scope: .staged, in: vaultURL)) ?? "",
                (try? diff(for: change, scope: .unstaged, in: vaultURL)) ?? ""
            ]
            let combined = scopedDiffs
                .map(\.trimmed)
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")

            if !combined.isEmpty {
                return combined
            }

            throw error
        }

        return ""
    }

    private func untrackedDiff(for change: GitChangedFile, in vaultURL: URL) throws -> String {
        try runDiff(arguments: [
            "git",
            "diff",
            "--no-ext-diff",
            "--no-index",
            "--",
            "/dev/null",
            change.path
        ], currentDirectory: vaultURL)
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

    private func unstage(paths: [String], in vaultURL: URL) throws {
        guard !paths.isEmpty else { return }

        do {
            try ProcessRunner.run(
                arguments: ["git", "restore", "--staged", "--"] + paths,
                currentDirectory: vaultURL
            )
        } catch {
            try ProcessRunner.run(
                arguments: ["git", "rm", "--cached", "-r", "--force", "--"] + paths,
                currentDirectory: vaultURL
            )
        }
    }

    private func repositoryHasHead(_ vaultURL: URL) -> Bool {
        let result = try? ProcessRunner.run(
            arguments: ["git", "rev-parse", "--verify", "HEAD"],
            currentDirectory: vaultURL
        )
        return result?.exitCode == 0
    }

    private func pathExistsInHead(_ path: String, in vaultURL: URL) -> Bool {
        let result = try? ProcessRunner.run(
            arguments: ["git", "cat-file", "-e", "HEAD:\(path)"],
            currentDirectory: vaultURL
        )
        return result?.exitCode == 0
    }

    private func pathExistsInIndex(_ path: String, in vaultURL: URL) -> Bool {
        let result = try? ProcessRunner.run(
            arguments: ["git", "cat-file", "-e", ":\(path)"],
            currentDirectory: vaultURL
        )
        return result?.exitCode == 0
    }

    private func headText(path: String, in vaultURL: URL) -> String {
        (try? ProcessRunner.run(
            arguments: ["git", "show", "HEAD:\(path)"],
            currentDirectory: vaultURL
        ).output) ?? ""
    }

    private func indexText(path: String, in vaultURL: URL) -> String {
        (try? ProcessRunner.run(
            arguments: ["git", "show", ":\(path)"],
            currentDirectory: vaultURL
        ).output) ?? ""
    }

    private func workingTreeText(path: String, in vaultURL: URL) throws -> String {
        let rootURL = vaultURL.standardizedFileURL
        let fileURL = vaultURL.appendingPathComponent(path).standardizedFileURL
        let rootPath = rootURL.path
        let filePath = fileURL.path

        guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else {
            throw GitServiceError.unsafePath(path)
        }

        guard FileManager.default.fileExists(atPath: filePath) else { return "" }

        return try FileTextLoader.load(url: fileURL).text
    }

    private func removePathFromWorkingTree(_ path: String, vaultURL: URL) throws {
        let rootURL = vaultURL.standardizedFileURL
        let targetURL = vaultURL.appendingPathComponent(path).standardizedFileURL
        let rootPath = rootURL.path
        let targetPath = targetURL.path

        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            throw GitServiceError.unsafePath(path)
        }

        if FileManager.default.fileExists(atPath: targetPath) {
            try FileManager.default.removeItem(at: targetURL)
        }
    }

    private func parsePorcelainStatus(_ output: String) -> [GitChangedFile] {
        let records = output
            .split(separator: "\u{0}", omittingEmptySubsequences: true)
            .map(String.init)

        var changes: [GitChangedFile] = []
        var index = 0

        while index < records.count {
            let record = records[index]
            guard record.count >= 3 else {
                index += 1
                continue
            }

            let status = Array(record.prefix(2))
            guard status.count == 2 else {
                index += 1
                continue
            }

            let path = String(record.dropFirst(3))
            var originalPath: String?

            if status.contains("R") || status.contains("C") {
                let originalIndex = index + 1
                if originalIndex < records.count {
                    originalPath = records[originalIndex]
                    index += 1
                }
            }

            changes.append(
                GitChangedFile(
                    path: path,
                    originalPath: originalPath,
                    indexStatus: status[0],
                    workTreeStatus: status[1]
                )
            )
            index += 1
        }

        return changes
    }

    private func isIgnoredVaultPath(_ path: String) -> Bool {
        let rootName = path
            .split(separator: "/", maxSplits: 1)
            .first
            .map(String.init) ?? path
        return AppBrand.ignoredVaultDirectoryNames.contains(rootName)
    }

    private func runDiff(arguments: [String], currentDirectory: URL) throws -> String {
        do {
            return try ProcessRunner.run(arguments: arguments, currentDirectory: currentDirectory).output
        } catch let ProcessRunnerError.failed(_, result) where result.exitCode == 1 {
            return result.output
        }
    }
}
