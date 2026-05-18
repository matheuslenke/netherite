import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class ExcelWorkbookPreviewServiceTests: XCTestCase {
    func testLoadsSharedStringsInlineStringsAndBooleans() throws {
        let workbookURL = try makeWorkbook(
            sheet1XML: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <sheetData>
                <row r="1">
                  <c r="A1" t="s"><v>0</v></c>
                  <c r="B1" t="s"><v>1</v></c>
                  <c r="C1" t="s"><v>2</v></c>
                </row>
                <row r="2">
                  <c r="A2" t="s"><v>3</v></c>
                  <c r="B2"><v>42</v></c>
                  <c r="C2" t="b"><v>1</v></c>
                </row>
                <row r="3">
                  <c r="A3" t="inlineStr"><is><t>Inline note</t></is></c>
                  <c r="B3"><f>SUM(B2,8)</f><v>50</v></c>
                  <c r="C3" t="b"><v>0</v></c>
                </row>
              </sheetData>
            </worksheet>
            """,
            sheet2XML: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <sheetData>
                <row r="1">
                  <c r="A1" t="s"><v>4</v></c>
                </row>
              </sheetData>
            </worksheet>
            """
        )

        let workbook = try ExcelWorkbookPreviewService.load(url: workbookURL, maxRows: 10, maxColumns: 10)

        XCTAssertEqual(workbook.sheets.map(\.name), ["Summary", "Data"])

        let summary = try XCTUnwrap(workbook.sheets.first)
        XCTAssertEqual(summary.columnCount, 3)
        XCTAssertEqual(summary.rows[0].values, ["Name", "Score", "Passed"])
        XCTAssertEqual(summary.rows[1].values, ["Alice", "42", "TRUE"])
        XCTAssertEqual(summary.rows[2].values, ["Inline note", "50", "FALSE"])

        let data = try XCTUnwrap(workbook.sheets.last)
        XCTAssertEqual(data.rows[0].values, ["Dataset"])
    }

    func testMarksRowsAndColumnsAsTruncated() throws {
        let workbookURL = try makeWorkbook(
            sheet1XML: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <sheetData>
                <row r="1">
                  <c r="A1" t="s"><v>0</v></c>
                  <c r="C1" t="s"><v>1</v></c>
                </row>
                <row r="2">
                  <c r="A2" t="s"><v>3</v></c>
                </row>
              </sheetData>
            </worksheet>
            """,
            sheet2XML: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <sheetData />
            </worksheet>
            """
        )

        let workbook = try ExcelWorkbookPreviewService.load(url: workbookURL, maxRows: 1, maxColumns: 2)

        let summary = try XCTUnwrap(workbook.sheets.first)
        XCTAssertTrue(summary.truncatedRows)
        XCTAssertTrue(summary.truncatedColumns)
        XCTAssertEqual(summary.rows.count, 1)
        XCTAssertEqual(summary.columnCount, 1)
        XCTAssertEqual(summary.rows[0].values, ["Name"])
    }

    private func makeWorkbook(sheet1XML: String, sheet2XML: String) throws -> URL {
        let rootURL = try temporaryDirectory()
        let workbookURL = rootURL.appendingPathComponent("workbook.xlsx")
        let packageURL = rootURL.appendingPathComponent("package", isDirectory: true)

        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent("_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent("xl/_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent("xl/worksheets", isDirectory: true),
            withIntermediateDirectories: true
        )

        try write("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """, to: packageURL.appendingPathComponent("[Content_Types].xml"))

        try write("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """, to: packageURL.appendingPathComponent("_rels/.rels"))

        try write("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Summary" sheetId="1" r:id="rId1"/>
            <sheet name="Data" sheetId="2" r:id="rId2"/>
          </sheets>
        </workbook>
        """, to: packageURL.appendingPathComponent("xl/workbook.xml"))

        try write("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
        </Relationships>
        """, to: packageURL.appendingPathComponent("xl/_rels/workbook.xml.rels"))

        try write("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="5" uniqueCount="5">
          <si><t>Name</t></si>
          <si><t>Score</t></si>
          <si><t>Passed</t></si>
          <si><t>Alice</t></si>
          <si><t>Dataset</t></si>
        </sst>
        """, to: packageURL.appendingPathComponent("xl/sharedStrings.xml"))

        try write(sheet1XML, to: packageURL.appendingPathComponent("xl/worksheets/sheet1.xml"))
        try write(sheet2XML, to: packageURL.appendingPathComponent("xl/worksheets/sheet2.xml"))

        try ProcessRunner.run(
            arguments: ["/usr/bin/zip", "-qr", workbookURL.path, "[Content_Types].xml", "_rels", "xl"],
            currentDirectory: packageURL
        )

        return workbookURL
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetheriteExcelPreviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
#endif
