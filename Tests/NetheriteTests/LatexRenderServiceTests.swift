import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class LatexRenderServiceTests: XCTestCase {
    func testIncludedFilesFindsIncludeAndInputTargets() throws {
        let vaultURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let sectionsURL = vaultURL.appendingPathComponent("sections", isDirectory: true)
        try FileManager.default.createDirectory(at: sectionsURL, withIntermediateDirectories: true)

        let rootURL = vaultURL.appendingPathComponent("main.tex")
        let chapterURL = sectionsURL.appendingPathComponent("chapter-one.tex")
        let appendixURL = sectionsURL.appendingPathComponent("appendix.tex")

        try """
        \\documentclass{article}
        \\begin{document}
        \\include{sections/chapter-one}
        % \\include{sections/commented}
        \\input{sections/appendix.tex}
        \\include{sections/missing}
        \\end{document}
        """.write(to: rootURL, atomically: true, encoding: .utf8)

        try """
        \\section{Chapter One}
        A short chapter.
        """.write(to: chapterURL, atomically: true, encoding: .utf8)

        try "Appendix words here.\n".write(to: appendixURL, atomically: true, encoding: .utf8)

        let includedFiles = LatexRenderService.includedFiles(rootURL: rootURL, vaultURL: vaultURL)

        XCTAssertEqual(includedFiles.map(\.relativePath), [
            "sections/chapter-one.tex",
            "sections/appendix.tex",
            "sections/missing.tex"
        ])
        XCTAssertEqual(includedFiles[0].command, "include")
        XCTAssertEqual(includedFiles[1].command, "input")
        XCTAssertFalse(includedFiles[0].isMissing)
        XCTAssertTrue(includedFiles[2].isMissing)
        XCTAssertEqual(includedFiles[0].sourceRelativePath, "main.tex")
        XCTAssertEqual(includedFiles[0].line, 3)
        XCTAssertNotNil(includedFiles[0].wordCount)
        XCTAssertNotNil(includedFiles[0].byteCount)
    }

    func testIncludedFilesFindsNestedIncludesOnce() throws {
        let vaultURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let rootURL = vaultURL.appendingPathComponent("main.tex")
        let chapterURL = vaultURL.appendingPathComponent("chapter.tex")
        let sectionURL = vaultURL.appendingPathComponent("section.tex")

        try "\\include{chapter}\n".write(to: rootURL, atomically: true, encoding: .utf8)
        try "\\input{section}\n\\include{section}\n".write(to: chapterURL, atomically: true, encoding: .utf8)
        try "Body\n".write(to: sectionURL, atomically: true, encoding: .utf8)

        let includedFiles = LatexRenderService.includedFiles(rootURL: rootURL, vaultURL: vaultURL)

        XCTAssertEqual(includedFiles.map(\.relativePath), [
            "chapter.tex",
            "section.tex"
        ])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NetheriteLatexRenderServiceTests-\(UUID().uuidString)", isDirectory: true)
    }
}
#endif
