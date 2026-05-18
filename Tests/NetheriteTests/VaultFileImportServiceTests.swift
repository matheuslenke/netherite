import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class VaultFileImportServiceTests: XCTestCase {
    func testCopiesDroppedFileIntoVaultWithUniqueName() throws {
        let sourceDirectory = try temporaryDirectory()
        let vaultURL = try temporaryDirectory()
        let sourceURL = sourceDirectory.appendingPathComponent("Draft.md")
        let existingURL = vaultURL.appendingPathComponent("Draft.md")
        try "# Source\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "# Existing\n".write(to: existingURL, atomically: true, encoding: .utf8)

        let summary = try VaultFileImportService.copyItems(
            from: [sourceURL],
            into: vaultURL,
            vaultURL: vaultURL
        )

        XCTAssertEqual(summary.importedRelativePaths, ["Draft-2.md"])
        XCTAssertEqual(
            try String(contentsOf: vaultURL.appendingPathComponent("Draft-2.md"), encoding: .utf8),
            "# Source\n"
        )
        XCTAssertEqual(try String(contentsOf: existingURL, encoding: .utf8), "# Existing\n")
    }

    func testCopiesDroppedFileIntoNestedVaultFolder() throws {
        let sourceDirectory = try temporaryDirectory()
        let vaultURL = try temporaryDirectory()
        let nestedFolderURL = vaultURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolderURL, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent("Reading List.txt")
        try "A paper to read\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let summary = try VaultFileImportService.copyItems(
            from: [sourceURL],
            into: nestedFolderURL,
            vaultURL: vaultURL
        )

        XCTAssertEqual(summary.importedRelativePaths, ["Notes/Reading List.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFolderURL.appendingPathComponent("Reading List.txt").path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetheriteFileImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
#endif
