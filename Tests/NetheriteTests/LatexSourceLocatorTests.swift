import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class LatexSourceLocatorTests: XCTestCase {
    func testParsesSyncTeXEditOutput() {
        let output = """
        This is SyncTeX command line utility, version 1.5
        SyncTeX result begin
        Output:/tmp/build/main.pdf
        Input:/tmp/project/./main.tex
        Line:42
        Column:-1
        Offset:0
        Context:
        SyncTeX result end
        """

        let location = LatexSourceLocator.sourceLocation(fromSyncTeXOutput: output)

        XCTAssertEqual(location?.inputURL.path, URL(fileURLWithPath: "/tmp/project/main.tex").path)
        XCTAssertEqual(location?.inputPath, "/tmp/project/./main.tex")
        XCTAssertEqual(location?.line, 42)
        XCTAssertEqual(location?.column, -1)
    }

    func testSourceOffsetUsesOneBasedLinesAndZeroBasedColumns() {
        let source = "one\nsecond line\nthird"

        XCTAssertEqual(LatexSourceLocator.sourceOffset(in: source, line: 1, column: -1), 0)
        XCTAssertEqual(LatexSourceLocator.sourceOffset(in: source, line: 2, column: 3), 7)
        XCTAssertEqual(LatexSourceLocator.sourceOffset(in: source, line: 99, column: 0), (source as NSString).length)
    }

    func testBestTextMatchReturnsUTF16Offset() {
        let source = "\\section{Résumé}\nBody text"

        XCTAssertEqual(LatexSourceLocator.bestTextMatchOffset(in: source, selectedText: "resume"), 9)
        XCTAssertNil(LatexSourceLocator.bestTextMatchOffset(in: source, selectedText: "x"))
    }
}
#endif
