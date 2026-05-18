import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class BibTeXServiceTests: XCTestCase {
    func testParsesMultipleEntriesAndPreservesUnknownFields() throws {
        let source = """
        @article{smith2023ontology,
          title = {Ontology Engineering with Conceptual Models},
          author = {Smith, John and Brown, Anna},
          year = {2023},
          journal = {Journal of Conceptual Modeling},
          customField = {Preserved}
        }

        @inproceedings{almeida2021ontouml,
          title = "OntoUML Patterns",
          author = "Almeida, Joao",
          booktitle = {MODELS}
        }
        """

        let entries = try BibTeXParser.parseEntries(source)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].type, "article")
        XCTAssertEqual(entries[0].citationKey, "smith2023ontology")
        XCTAssertEqual(entries[0].fields["customfield"], "Preserved")
        XCTAssertTrue(entries[0].raw.contains("@article{smith2023ontology"))
        XCTAssertEqual(entries[1].fields["booktitle"], "MODELS")
    }

    func testValidationDetectsUnbalancedEntries() {
        let message = BibTeXParser.validate("@article{broken, title = {Missing close}")

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("missing its closing delimiter") == true)
    }

    func testSerializesReferenceWithUnknownFields() {
        let reference = ReferenceItem(
            citationKey: "guizzardi2022ufo",
            type: "article",
            fields: [
                "title": "Unified Foundational Ontology",
                "author": "Guizzardi, Giancarlo",
                "year": "2022",
                "custom": "Value"
            ]
        )

        let output = BibTeXSerializer.serialize(reference)

        XCTAssertTrue(output.contains("@article{guizzardi2022ufo,"))
        XCTAssertTrue(output.contains("title = {Unified Foundational Ontology}"))
        XCTAssertTrue(output.contains("custom = {Value}"))
    }

    func testSuggestedCitationKeyUsesAuthorYearAndTitle() {
        let key = BibTeXSerializer.suggestedCitationKey(fields: [
            "author": "Guizzardi, Giancarlo and Almeida, Joao Paulo",
            "year": "2022",
            "title": "The Unified Foundational Ontology"
        ])

        XCTAssertEqual(key, "guizzardi2022unified")
    }
}
#endif
