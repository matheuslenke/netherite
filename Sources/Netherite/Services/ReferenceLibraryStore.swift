import Foundation

private struct ReferenceLibraryEnvelope: Codable {
    var version: Int
    var references: [ReferenceItem]
}

enum ReferenceLibraryStore {
    static let libraryVersion = 1
    static let pdfDirectoryRelativePath = "references/pdfs"

    static func libraryURL(in vaultURL: URL) -> URL {
        vaultURL
            .appendingPathComponent(AppBrand.vaultSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("references.json")
    }

    static func pdfDirectoryURL(in vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent(pdfDirectoryRelativePath, isDirectory: true)
    }

    static func load(in vaultURL: URL) throws -> [ReferenceItem] {
        let url = libraryURL(in: vaultURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(ReferenceLibraryEnvelope.self, from: data)
        return envelope.references
    }

    static func save(_ references: [ReferenceItem], in vaultURL: URL) throws {
        let directory = vaultURL.appendingPathComponent(AppBrand.vaultSupportDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let envelope = ReferenceLibraryEnvelope(version: libraryVersion, references: references)
        try encoder.encode(envelope).write(to: libraryURL(in: vaultURL), options: .atomic)
    }

    static func duplicateCitationKeys(in references: [ReferenceItem]) -> Set<String> {
        let counts = references.reduce(into: [String: Int]()) { counts, reference in
            let key = reference.citationKey.trimmed.lowercased()
            guard !key.isEmpty else { return }
            counts[key, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.map(\.key))
    }

    static func uniquePDFRelativePath(for citationKey: String, in vaultURL: URL) -> String {
        let safeKey = safePDFFileStem(for: citationKey)
        let directory = pdfDirectoryURL(in: vaultURL)
        var candidateName = "\(safeKey).pdf"
        var candidateURL = directory.appendingPathComponent(candidateName)
        var index = 2

        while FileManager.default.fileExists(atPath: candidateURL.path) {
            candidateName = "\(safeKey)-\(index).pdf"
            candidateURL = directory.appendingPathComponent(candidateName)
            index += 1
        }

        return "\(pdfDirectoryRelativePath)/\(candidateName)"
    }

    static func safePDFFileStem(for citationKey: String) -> String {
        citationKey.asSafeFileStem.nilIfEmpty ?? "reference"
    }

    static func absoluteURL(for relativePath: String, in vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent(relativePath)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var asSafeFileStem: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" {
                    return
                }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .lowercased()
    }
}
