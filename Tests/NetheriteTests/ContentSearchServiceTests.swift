import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class ContentSearchServiceTests: XCTestCase {
    func testSearchCurrentFileReportsLineColumnAndOffset() {
        let file = vaultFile(name: "note.md", kind: .markdown)
        let text = "First line\nSecond needle line\nThird needle"

        let results = ContentSearchService.searchCurrentFile(text: text, file: file, query: "needle")

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].fileID, "note.md")
        XCTAssertEqual(results[0].line, 2)
        XCTAssertEqual(results[0].column, 8)
        XCTAssertEqual(results[0].offset, 18)
        XCTAssertEqual(results[0].snippet, "Second needle line")
        XCTAssertEqual(results[1].line, 3)
    }

    func testSearchFilesLoadsOnlySearchableTextFiles() throws {
        let directory = try temporaryDirectory()
        let noteURL = directory.appendingPathComponent("note.md")
        let imageURL = directory.appendingPathComponent("image.png")
        try "alpha\nneedle here\n".write(to: noteURL, atomically: true, encoding: .utf8)
        try Data(repeating: 0, count: 128).write(to: imageURL)

        let files = [
            vaultFile(url: noteURL, kind: .markdown),
            vaultFile(url: imageURL, kind: .image)
        ]

        let results = ContentSearchService.searchFiles(files, query: "needle")

        XCTAssertEqual(results.map(\.fileID), ["note.md"])
        XCTAssertEqual(results.first?.line, 2)
    }

    private func vaultFile(
        name: String = "note.md",
        kind: FileKind,
        byteCount: Int = 100
    ) -> VaultFile {
        vaultFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            kind: kind,
            byteCount: byteCount
        )
    }

    private func vaultFile(
        url: URL,
        kind: FileKind,
        byteCount: Int? = nil
    ) -> VaultFile {
        VaultFile(
            id: url.lastPathComponent,
            url: url,
            relativePath: url.lastPathComponent,
            name: url.lastPathComponent,
            fileExtension: url.pathExtension,
            kind: kind,
            byteCount: byteCount ?? ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
            modifiedAt: Date.distantPast
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetheriteContentSearchServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
#endif
