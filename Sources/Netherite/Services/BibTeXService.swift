import Foundation

struct BibTeXEntry: Equatable {
    var type: String
    var citationKey: String
    var fields: [String: String]
    var raw: String
}

enum BibTeXError: LocalizedError, Equatable {
    case noEntries
    case missingEntryType
    case missingOpeningDelimiter(String)
    case unbalancedEntry(String)
    case missingCitationKey(String)
    case malformedField(String)

    var errorDescription: String? {
        switch self {
        case .noEntries:
            "No BibTeX entries were found."
        case .missingEntryType:
            "A BibTeX entry is missing its type after @."
        case let .missingOpeningDelimiter(type):
            "The @\(type) entry is missing an opening { or (."
        case let .unbalancedEntry(type):
            "The @\(type) entry is missing its closing delimiter."
        case let .missingCitationKey(type):
            "The @\(type) entry is missing a citation key."
        case let .malformedField(field):
            "The BibTeX field '\(field)' is missing an equals sign."
        }
    }
}

enum BibTeXParser {
    static func parseEntries(_ source: String) throws -> [BibTeXEntry] {
        var entries: [BibTeXEntry] = []
        var index = source.startIndex

        while let atIndex = source[index...].firstIndex(of: "@") {
            var cursor = source.index(after: atIndex)
            skipWhitespace(in: source, from: &cursor)

            let typeStart = cursor
            while cursor < source.endIndex, isEntryTypeCharacter(source[cursor]) {
                cursor = source.index(after: cursor)
            }

            let type = String(source[typeStart..<cursor]).trimmed
            guard !type.isEmpty else { throw BibTeXError.missingEntryType }

            skipWhitespace(in: source, from: &cursor)
            guard cursor < source.endIndex, source[cursor] == "{" || source[cursor] == "(" else {
                throw BibTeXError.missingOpeningDelimiter(type)
            }

            let openingDelimiter = source[cursor]
            let closingDelimiter: Character = openingDelimiter == "{" ? "}" : ")"
            let contentStart = source.index(after: cursor)
            guard let closeIndex = closingIndex(
                in: source,
                from: contentStart,
                openingDelimiter: openingDelimiter,
                closingDelimiter: closingDelimiter
            ) else {
                throw BibTeXError.unbalancedEntry(type)
            }

            let rawEnd = source.index(after: closeIndex)
            let raw = String(source[atIndex..<rawEnd])
            let content = String(source[contentStart..<closeIndex])
            let parsed = try parseContent(content, type: type, raw: raw)
            entries.append(parsed)
            index = rawEnd
        }

        guard !entries.isEmpty else { throw BibTeXError.noEntries }
        return entries
    }

    static func validate(_ source: String) -> String? {
        do {
            _ = try parseEntries(source)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func parseContent(_ content: String, type: String, raw: String) throws -> BibTeXEntry {
        guard let keySeparator = topLevelSeparator(",", in: content) else {
            throw BibTeXError.missingCitationKey(type)
        }

        let citationKey = String(content[..<keySeparator]).trimmed
        guard !citationKey.isEmpty else { throw BibTeXError.missingCitationKey(type) }

        let fieldsSource = String(content[content.index(after: keySeparator)...])
        var fields: [String: String] = [:]
        for fieldSource in splitTopLevel(fieldsSource, separator: ",") {
            let trimmedField = fieldSource.trimmed
            guard !trimmedField.isEmpty else { continue }
            guard let equals = topLevelSeparator("=", in: trimmedField) else {
                throw BibTeXError.malformedField(trimmedField)
            }

            let name = String(trimmedField[..<equals]).trimmed
            guard !name.isEmpty else { throw BibTeXError.malformedField(trimmedField) }

            let rawValue = String(trimmedField[trimmedField.index(after: equals)...]).trimmed
            fields[ReferenceItem.normalizedFieldName(name)] = unwrappedValue(rawValue)
        }

        return BibTeXEntry(
            type: type.lowercased(),
            citationKey: citationKey,
            fields: fields,
            raw: raw.trimmed
        )
    }

    private static func closingIndex(
        in source: String,
        from start: String.Index,
        openingDelimiter: Character,
        closingDelimiter: Character
    ) -> String.Index? {
        var cursor = start
        var delimiterDepth = 1
        var braceDepth = 0
        var inQuote = false
        var escaped = false

        while cursor < source.endIndex {
            let character = source[cursor]

            if inQuote {
                if character == "\"" && !escaped {
                    inQuote = false
                }
                escaped = character == "\\" && !escaped
                cursor = source.index(after: cursor)
                continue
            }

            if character == "\"" {
                inQuote = true
            } else if openingDelimiter == "{", character == "{" {
                delimiterDepth += 1
            } else if openingDelimiter == "{", character == "}" {
                delimiterDepth -= 1
                if delimiterDepth == 0 { return cursor }
            } else if openingDelimiter == "(", character == "(" {
                delimiterDepth += 1
            } else if openingDelimiter == "(", character == ")" {
                delimiterDepth -= 1
                if delimiterDepth == 0 { return cursor }
            } else if openingDelimiter == "(", character == "{" {
                braceDepth += 1
            } else if openingDelimiter == "(", character == "}" {
                braceDepth = max(0, braceDepth - 1)
            } else if character == closingDelimiter, braceDepth == 0 {
                delimiterDepth -= 1
                if delimiterDepth == 0 { return cursor }
            }

            cursor = source.index(after: cursor)
        }

        return nil
    }

    private static func splitTopLevel(_ source: String, separator: Character) -> [String] {
        var parts: [String] = []
        var start = source.startIndex
        var cursor = source.startIndex
        var braceDepth = 0
        var parenDepth = 0
        var inQuote = false
        var escaped = false

        while cursor < source.endIndex {
            let character = source[cursor]

            if inQuote {
                if character == "\"" && !escaped {
                    inQuote = false
                }
                escaped = character == "\\" && !escaped
            } else if character == "\"" {
                inQuote = true
            } else if character == "{" {
                braceDepth += 1
            } else if character == "}" {
                braceDepth = max(0, braceDepth - 1)
            } else if character == "(" {
                parenDepth += 1
            } else if character == ")" {
                parenDepth = max(0, parenDepth - 1)
            } else if character == separator, braceDepth == 0, parenDepth == 0 {
                parts.append(String(source[start..<cursor]))
                start = source.index(after: cursor)
            }

            cursor = source.index(after: cursor)
        }

        parts.append(String(source[start..<source.endIndex]))
        return parts
    }

    private static func topLevelSeparator(_ separator: Character, in source: String) -> String.Index? {
        splitTopLevelWithIndices(source, separator: separator).first
    }

    private static func splitTopLevelWithIndices(_ source: String, separator: Character) -> [String.Index] {
        var indices: [String.Index] = []
        var cursor = source.startIndex
        var braceDepth = 0
        var parenDepth = 0
        var inQuote = false
        var escaped = false

        while cursor < source.endIndex {
            let character = source[cursor]

            if inQuote {
                if character == "\"" && !escaped {
                    inQuote = false
                }
                escaped = character == "\\" && !escaped
            } else if character == "\"" {
                inQuote = true
            } else if character == "{" {
                braceDepth += 1
            } else if character == "}" {
                braceDepth = max(0, braceDepth - 1)
            } else if character == "(" {
                parenDepth += 1
            } else if character == ")" {
                parenDepth = max(0, parenDepth - 1)
            } else if character == separator, braceDepth == 0, parenDepth == 0 {
                indices.append(cursor)
            }

            cursor = source.index(after: cursor)
        }

        return indices
    }

    private static func unwrappedValue(_ source: String) -> String {
        let value = source.trimmed
        if value.hasPrefix("{"), value.hasSuffix("}"), value.count >= 2 {
            return String(value.dropFirst().dropLast()).trimmed
        }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return String(value.dropFirst().dropLast()).trimmed
        }
        return value
    }

    private static func skipWhitespace(in source: String, from index: inout String.Index) {
        while index < source.endIndex, source[index].isWhitespace {
            index = source.index(after: index)
        }
    }

    private static func isEntryTypeCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }
}

enum BibTeXSerializer {
    static let standardFieldOrder = [
        "title",
        "author",
        "year",
        "journal",
        "booktitle",
        "publisher",
        "doi",
        "url",
        "abstract",
        "keywords"
    ]

    static func reference(from entry: BibTeXEntry) -> ReferenceItem {
        ReferenceItem(
            citationKey: entry.citationKey,
            type: entry.type,
            fields: entry.fields,
            rawBibTeX: entry.raw
        )
    }

    static func serialize(_ reference: ReferenceItem) -> String {
        let type = reference.type.trimmed.nilIfEmpty ?? "misc"
        let key = reference.citationKey.trimmed.nilIfEmpty ?? "untitled"
        let orderedFields = orderedFieldNames(reference.fields)

        guard !orderedFields.isEmpty else {
            return "@\(type){\(key)\n}"
        }

        var lines = ["@\(type){\(key),"]
        for (index, field) in orderedFields.enumerated() {
            let value = reference.fields[field] ?? ""
            let suffix = index == orderedFields.count - 1 ? "" : ","
            lines.append("  \(field) = {\(value)}\(suffix)")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func export(_ references: [ReferenceItem]) -> String {
        references
            .map(exportEntry)
            .joined(separator: "\n\n") + (references.isEmpty ? "" : "\n")
    }

    static func exportEntry(_ reference: ReferenceItem) -> String {
        let raw = reference.rawBibTeX.trimmed
        if let parsed = try? BibTeXParser.parseEntries(raw).first,
           parsed.citationKey == reference.citationKey,
           parsed.type.lowercased() == reference.type.lowercased() {
            return raw
        }
        return serialize(reference)
    }

    static func suggestedCitationKey(fields: [String: String], fallback: String = "reference") -> String {
        let normalized = ReferenceItem.normalizedFields(fields)
        let author = normalized["author"].flatMap(firstAuthorToken) ?? fallback
        let year = normalized["year"]?.filter(\.isNumber) ?? ""
        let title = normalized["title"].flatMap(firstTitleToken) ?? ""
        let key = "\(author)\(year)\(title)".asciiIdentifier.lowercased()
        return key.isEmpty ? fallback.asciiIdentifier.lowercased() : key
    }

    private static func orderedFieldNames(_ fields: [String: String]) -> [String] {
        let presentStandardFields = standardFieldOrder.filter { fields[$0] != nil }
        let remainingFields = fields.keys
            .filter { !standardFieldOrder.contains($0) }
            .sorted()
        return presentStandardFields + remainingFields
    }

    private static func firstAuthorToken(_ authorField: String) -> String? {
        let firstAuthor = authorField
            .components(separatedBy: " and ")
            .first?
            .trimmed
        guard let firstAuthor, !firstAuthor.isEmpty else { return nil }

        let familyName: String
        if firstAuthor.contains(",") {
            familyName = firstAuthor.components(separatedBy: ",").first ?? firstAuthor
        } else {
            familyName = firstAuthor.split(separator: " ").last.map(String.init) ?? firstAuthor
        }
        return familyName.asciiIdentifier.lowercased().nilIfEmpty
    }

    private static func firstTitleToken(_ title: String) -> String? {
        let stopWords: Set<String> = ["a", "an", "the", "on", "of", "for", "and", "with", "in"]
        for word in title.components(separatedBy: CharacterSet.alphanumerics.inverted) {
            let normalized = word.asciiIdentifier.lowercased()
            guard !normalized.isEmpty, !stopWords.contains(normalized) else { continue }
            return normalized
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var asciiIdentifier: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}
