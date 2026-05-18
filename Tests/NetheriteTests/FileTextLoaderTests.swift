import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class FileTextLoaderTests: XCTestCase {
    func testPDFSelectionUsesMetadataPreview() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("Paper.pdf")
        try "This body should not be decoded as editable text.".write(to: url, atomically: true, encoding: .utf8)

        let loaded = try FileTextLoader.load(url: url)

        XCTAssertFalse(loaded.isEditable)
        XCTAssertEqual(loaded.sourceDescription, "PDF preview; source file is read-only here")
        XCTAssertTrue(loaded.text.contains("PDF: Paper.pdf"))
        XCTAssertFalse(loaded.text.contains("This body should not be decoded"))
    }

    func testSpreadsheetSelectionUsesMetadataPreview() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("Workbook.xlsx")
        try Data(repeating: 0x41, count: 1024).write(to: url)

        let loaded = try FileTextLoader.load(url: url)

        XCTAssertFalse(loaded.isEditable)
        XCTAssertEqual(loaded.sourceDescription, "Excel workbook preview; source file is read-only here")
        XCTAssertTrue(loaded.text.contains("Spreadsheet: Workbook.xlsx"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetheriteFileTextLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
#endif
