import Foundation

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case files
    case changes
    case references

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files:
            "Files"
        case .changes:
            "Changes"
        case .references:
            "References"
        }
    }

    var systemImage: String {
        switch self {
        case .files:
            "doc.text"
        case .changes:
            "point.3.connected.trianglepath.dotted"
        case .references:
            "books.vertical"
        }
    }
}

enum ReferenceEditorMode: String, CaseIterable, Identifiable {
    case form
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .form:
            "Form"
        case .raw:
            "Raw BibTeX"
        }
    }
}

struct PDFReaderState: Codable, Hashable {
    var lastPageIndex: Int
    var scaleFactor: Double

    init(lastPageIndex: Int = 0, scaleFactor: Double = 0) {
        self.lastPageIndex = lastPageIndex
        self.scaleFactor = scaleFactor
    }
}

struct ReferenceItem: Identifiable, Codable, Hashable {
    var id: UUID
    var citationKey: String
    var type: String
    var fields: [String: String]
    var rawBibTeX: String
    var pdfRelativePath: String?
    var readerState: PDFReaderState

    init(
        id: UUID = UUID(),
        citationKey: String,
        type: String,
        fields: [String: String] = [:],
        rawBibTeX: String = "",
        pdfRelativePath: String? = nil,
        readerState: PDFReaderState = PDFReaderState()
    ) {
        self.id = id
        self.citationKey = citationKey
        self.type = type
        self.fields = ReferenceItem.normalizedFields(fields)
        self.rawBibTeX = rawBibTeX
        self.pdfRelativePath = pdfRelativePath
        self.readerState = readerState
    }

    var displayTitle: String {
        field("title")?.trimmed.nilIfEmpty ?? citationKey
    }

    var authorText: String {
        field("author")?.trimmed.nilIfEmpty ?? "Unknown author"
    }

    var yearText: String {
        field("year")?.trimmed.nilIfEmpty ?? "n.d."
    }

    var venueText: String {
        field("journal")?.trimmed.nilIfEmpty ??
            field("booktitle")?.trimmed.nilIfEmpty ??
            field("publisher")?.trimmed.nilIfEmpty ??
            ""
    }

    var bibliographyPreview: String {
        var parts: [String] = []
        parts.append(authorText)
        parts.append("(\(yearText)).")
        parts.append(displayTitle.hasSuffix(".") ? displayTitle : "\(displayTitle).")
        if !venueText.isEmpty {
            parts.append(venueText.hasSuffix(".") ? venueText : "\(venueText).")
        }
        if let doi = field("doi")?.trimmed.nilIfEmpty {
            parts.append("doi:\(doi)")
        } else if let url = field("url")?.trimmed.nilIfEmpty {
            parts.append(url)
        }
        return parts.joined(separator: " ")
    }

    var searchableText: String {
        ([citationKey, type, rawBibTeX, pdfRelativePath ?? ""] + fields.flatMap { [$0.key, $0.value] })
            .joined(separator: " ")
            .lowercased()
    }

    func field(_ name: String) -> String? {
        fields[ReferenceItem.normalizedFieldName(name)]
    }

    mutating func setField(_ name: String, value: String) {
        let key = ReferenceItem.normalizedFieldName(name)
        if value.trimmed.isEmpty {
            fields.removeValue(forKey: key)
        } else {
            fields[key] = value
        }
    }

    mutating func replaceFields(_ nextFields: [String: String]) {
        fields = ReferenceItem.normalizedFields(nextFields)
    }

    static func normalizedFieldName(_ name: String) -> String {
        name.trimmed.lowercased()
    }

    static func normalizedFields(_ fields: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for (key, value) in fields {
            let normalizedKey = normalizedFieldName(key)
            guard !normalizedKey.isEmpty else { continue }
            normalized[normalizedKey] = value
        }
        return normalized
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
