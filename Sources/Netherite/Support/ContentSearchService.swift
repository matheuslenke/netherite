import Foundation

struct ContentSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let fileID: String
    let fileName: String
    let relativePath: String
    let line: Int
    let column: Int
    let offset: Int
    let snippet: String
}

enum ContentSearchService {
    static let defaultResultLimit = 250
    private static let maximumSearchableByteCount = 2_000_000
    private static let snippetLength = 160

    static func searchCurrentFile(
        text: String,
        file: VaultFile,
        query: String,
        limit: Int = defaultResultLimit
    ) -> [ContentSearchResult] {
        search(text: text, file: file, query: query, limit: limit)
    }

    static func searchFiles(
        _ files: [VaultFile],
        query: String,
        limit: Int = defaultResultLimit
    ) -> [ContentSearchResult] {
        let query = query.trimmed
        guard !query.isEmpty else { return [] }

        var results: [ContentSearchResult] = []
        for file in files where isSearchable(file) {
            guard let loaded = try? FileTextLoader.load(url: file.url),
                  loaded.isEditable
            else {
                continue
            }

            results.append(contentsOf: search(
                text: loaded.text,
                file: file,
                query: query,
                limit: limit - results.count
            ))

            if results.count >= limit {
                break
            }
        }

        return results
    }

    private static func isSearchable(_ file: VaultFile) -> Bool {
        file.kind.canContainBacklinks && file.byteCount <= maximumSearchableByteCount
    }

    private static func search(
        text: String,
        file: VaultFile,
        query: String,
        limit: Int
    ) -> [ContentSearchResult] {
        let query = query.trimmed
        guard !query.isEmpty, limit > 0 else { return [] }

        let source = text as NSString
        var results: [ContentSearchResult] = []
        var searchRange = NSRange(location: 0, length: source.length)

        while searchRange.length > 0, results.count < limit {
            let match = source.range(of: query, options: [.caseInsensitive], range: searchRange)
            guard match.location != NSNotFound else { break }

            let lineRange = source.lineRange(for: NSRange(location: match.location, length: 0))
            let line = lineNumber(at: match.location, in: source)
            let column = match.location - lineRange.location + 1
            let snippet = snippetForLine(source.substring(with: lineRange))
            let id = "\(file.id):\(match.location):\(match.length)"

            results.append(ContentSearchResult(
                id: id,
                fileID: file.id,
                fileName: file.name,
                relativePath: file.relativePath,
                line: line,
                column: column,
                offset: match.location,
                snippet: snippet
            ))

            let nextLocation = match.location + max(match.length, 1)
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }

        return results
    }

    private static func lineNumber(at offset: Int, in source: NSString) -> Int {
        guard offset > 0 else { return 1 }
        let prefix = source.substring(with: NSRange(location: 0, length: min(offset, source.length)))
        return prefix.reduce(1) { count, character in
            character.isNewline ? count + 1 : count
        }
    }

    private static func snippetForLine(_ line: String) -> String {
        let trimmed = line.trimmed
        guard trimmed.count > snippetLength else { return trimmed }

        let end = trimmed.index(trimmed.startIndex, offsetBy: snippetLength)
        return String(trimmed[..<end]) + "..."
    }
}
