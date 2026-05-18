import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class GitServiceTests: XCTestCase {
    func testStageUnstageAndCommitStagedChange() throws {
        let repoURL = try makeRepository()
        let service = GitService()

        let noteURL = repoURL.appendingPathComponent("Note.md")
        try "# Updated\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let modifiedChange = try XCTUnwrap(try service.changedFiles(in: repoURL).first { $0.path == "Note.md" })
        XCTAssertTrue(modifiedChange.hasUnstagedChanges)
        XCTAssertFalse(modifiedChange.hasStagedChanges)

        try service.stage(modifiedChange, in: repoURL)
        let stagedChange = try XCTUnwrap(try service.changedFiles(in: repoURL).first { $0.path == "Note.md" })
        XCTAssertTrue(stagedChange.hasStagedChanges)
        XCTAssertFalse(stagedChange.hasUnstagedChanges)

        try service.unstage(stagedChange, in: repoURL)
        let unstagedChange = try XCTUnwrap(try service.changedFiles(in: repoURL).first { $0.path == "Note.md" })
        XCTAssertFalse(unstagedChange.hasStagedChanges)
        XCTAssertTrue(unstagedChange.hasUnstagedChanges)

        try service.stage(unstagedChange, in: repoURL)
        _ = try service.commitStaged(vaultURL: repoURL, message: "Update note")

        let status = try service.changedFiles(in: repoURL)
        XCTAssertFalse(status.contains { $0.path == "Note.md" })
        let log = try ProcessRunner.run(arguments: ["git", "log", "--oneline", "-1"], currentDirectory: repoURL).output
        XCTAssertTrue(log.contains("Update note"))
    }

    func testDiscardRestoresTrackedFileAndRemovesUntrackedFile() throws {
        let repoURL = try makeRepository()
        let service = GitService()

        let noteURL = repoURL.appendingPathComponent("Note.md")
        try "# Changed\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let untrackedURL = repoURL.appendingPathComponent("Draft.md")
        try "# Draft\n".write(to: untrackedURL, atomically: true, encoding: .utf8)

        var changes = try service.changedFiles(in: repoURL)
        let trackedChange = try XCTUnwrap(changes.first { $0.path == "Note.md" })
        let untrackedChange = try XCTUnwrap(changes.first { $0.path == "Draft.md" })

        try service.discard(trackedChange, in: repoURL)
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "# Original\n")

        try service.discard(untrackedChange, in: repoURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: untrackedURL.path))

        changes = try service.changedFiles(in: repoURL)
        XCTAssertTrue(changes.isEmpty)
    }

    func testComparisonReturnsPreviousAndWorkingTreeText() throws {
        let repoURL = try makeRepository()
        let service = GitService()

        let noteURL = repoURL.appendingPathComponent("Note.md")
        try "# Updated\n\nNew line\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let change = try XCTUnwrap(try service.changedFiles(in: repoURL).first { $0.path == "Note.md" })
        let comparison = try service.comparison(for: change, scope: .combined, in: repoURL)

        XCTAssertEqual(comparison.previousTitle, "Previous")
        XCTAssertEqual(comparison.changedTitle, "Changes")
        XCTAssertTrue(comparison.previousText.contains("# Original"))
        XCTAssertTrue(comparison.changedText.contains("# Updated"))
        XCTAssertTrue(comparison.rows.contains { $0.kind == .modification })
        XCTAssertTrue(comparison.rows.contains { $0.kind == .insertion })
    }

    func testComparisonUsesIndexAsPreviousForUnstagedPartialChange() throws {
        let repoURL = try makeRepository()
        let service = GitService()

        let noteURL = repoURL.appendingPathComponent("Note.md")
        try "# Staged\n".write(to: noteURL, atomically: true, encoding: .utf8)
        var change = try XCTUnwrap(try service.changedFiles(in: repoURL).first { $0.path == "Note.md" })
        try service.stage(change, in: repoURL)

        try "# Working Tree\n".write(to: noteURL, atomically: true, encoding: .utf8)
        change = try XCTUnwrap(try service.changedFiles(in: repoURL).first { $0.path == "Note.md" })

        let comparison = try service.comparison(for: change, scope: .unstaged, in: repoURL)

        XCTAssertEqual(comparison.previousTitle, "Staged")
        XCTAssertEqual(comparison.changedTitle, "Changes")
        XCTAssertTrue(comparison.previousText.contains("# Staged"))
        XCTAssertTrue(comparison.changedText.contains("# Working Tree"))
    }

    func testChangedFilesIgnoresAppSupportDirectory() throws {
        let repoURL = try makeRepository()
        let service = GitService()

        let supportURL = repoURL
            .appendingPathComponent(AppBrand.vaultSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("latex-build", isDirectory: true)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try "generated\n".write(
            to: supportURL.appendingPathComponent("main.aux"),
            atomically: true,
            encoding: .utf8
        )

        try "# Visible\n".write(
            to: repoURL.appendingPathComponent("Visible.md"),
            atomically: true,
            encoding: .utf8
        )

        let changes = try service.changedFiles(in: repoURL)

        XCTAssertEqual(changes.map(\.path), ["Visible.md"])
        XCTAssertFalse(try service.snapshot(for: repoURL).isClean)
    }

    private func makeRepository() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetheriteGitServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        try ProcessRunner.run(arguments: ["git", "init"], currentDirectory: repoURL)
        try ProcessRunner.run(arguments: ["git", "config", "user.email", "tests@example.com"], currentDirectory: repoURL)
        try ProcessRunner.run(arguments: ["git", "config", "user.name", "Netherite Tests"], currentDirectory: repoURL)

        let noteURL = repoURL.appendingPathComponent("Note.md")
        try "# Original\n".write(to: noteURL, atomically: true, encoding: .utf8)
        try ProcessRunner.run(arguments: ["git", "add", "Note.md"], currentDirectory: repoURL)
        try ProcessRunner.run(arguments: ["git", "commit", "-m", "Initial commit"], currentDirectory: repoURL)

        return repoURL
    }
}
#endif
