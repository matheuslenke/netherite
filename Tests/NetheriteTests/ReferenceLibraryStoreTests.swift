import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class ReferenceLibraryStoreTests: XCTestCase {
    func testRoundTripsReferenceLibraryJSON() throws {
        let vaultURL = try temporaryVaultURL()
        let references = [
            ReferenceItem(
                citationKey: "smith2023ontology",
                type: "article",
                fields: ["title": "Ontology Engineering"],
                rawBibTeX: "@article{smith2023ontology}"
            )
        ]

        try ReferenceLibraryStore.save(references, in: vaultURL)
        let loaded = try ReferenceLibraryStore.load(in: vaultURL)

        XCTAssertEqual(loaded, references)
    }

    func testDetectsDuplicateCitationKeysCaseInsensitively() {
        let references = [
            ReferenceItem(citationKey: "Smith2023Ontology", type: "article"),
            ReferenceItem(citationKey: "smith2023ontology", type: "book"),
            ReferenceItem(citationKey: "other2024", type: "misc")
        ]

        XCTAssertEqual(ReferenceLibraryStore.duplicateCitationKeys(in: references), ["smith2023ontology"])
    }

    func testPDFRelativePathUsesSuffixForCollision() throws {
        let vaultURL = try temporaryVaultURL()
        let pdfDirectory = ReferenceLibraryStore.pdfDirectoryURL(in: vaultURL)
        try FileManager.default.createDirectory(at: pdfDirectory, withIntermediateDirectories: true)
        try Data().write(to: pdfDirectory.appendingPathComponent("smith2023ontology.pdf"))

        let relativePath = ReferenceLibraryStore.uniquePDFRelativePath(for: "smith2023ontology", in: vaultURL)

        XCTAssertEqual(relativePath, "references/pdfs/smith2023ontology-2.pdf")
    }

    func testExportSelectedReferences() {
        let selected = [
            ReferenceItem(citationKey: "smith2023ontology", type: "article", fields: ["title": "Ontology Engineering"])
        ]

        let output = BibTeXSerializer.export(selected)

        XCTAssertTrue(output.contains("@article{smith2023ontology"))
        XCTAssertFalse(output.contains("@book"))
    }

    private func temporaryVaultURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetheriteReferenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
#endif
