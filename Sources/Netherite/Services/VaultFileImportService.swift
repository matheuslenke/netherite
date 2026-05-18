import Foundation

struct VaultFileImportSummary: Sendable {
    let importedRelativePaths: [String]

    var importedItemCount: Int {
        importedRelativePaths.count
    }
}

enum VaultFileImportService {
    static func copyItems(
        from sourceURLs: [URL],
        into destinationDirectoryURL: URL,
        vaultURL: URL
    ) throws -> VaultFileImportSummary {
        guard !sourceURLs.isEmpty else { return VaultFileImportSummary(importedRelativePaths: []) }

        let fileManager = FileManager.default
        let destinationDirectoryURL = destinationDirectoryURL.standardizedFileURL
        let vaultURL = vaultURL.standardizedFileURL

        try validateDestinationDirectory(destinationDirectoryURL, vaultURL: vaultURL)
        try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        var importedRelativePaths: [String] = []
        for sourceURL in sourceURLs {
            let importedURL = try copyItem(
                from: sourceURL.standardizedFileURL,
                into: destinationDirectoryURL,
                vaultURL: vaultURL,
                fileManager: fileManager
            )
            importedRelativePaths.append(try relativePath(for: importedURL, in: vaultURL))
        }

        return VaultFileImportSummary(importedRelativePaths: importedRelativePaths)
    }

    private static func copyItem(
        from sourceURL: URL,
        into destinationDirectoryURL: URL,
        vaultURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        let didAccessResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw VaultFileImportError.sourceMissing(sourceURL.lastPathComponent)
        }

        try validateImportName(sourceURL.lastPathComponent)

        if isDirectory.boolValue {
            try validateDirectoryImport(from: sourceURL, into: destinationDirectoryURL)
        }

        let destinationURL = uniqueDestinationURL(
            in: destinationDirectoryURL,
            preferredName: sourceURL.lastPathComponent,
            isDirectory: isDirectory.boolValue,
            fileManager: fileManager
        )
        try validateDestinationDirectory(destinationURL.deletingLastPathComponent(), vaultURL: vaultURL)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private static func validateImportName(_ name: String) throws {
        guard !name.trimmed.isEmpty else { throw VaultFileImportError.invalidName(name) }
        guard !name.hasPrefix(".") else { throw VaultFileImportError.hiddenName(name) }
        guard !name.contains("/") && !name.contains(":") else { throw VaultFileImportError.invalidName(name) }
        guard name != "." && name != ".." else { throw VaultFileImportError.invalidName(name) }

        let lowercasedName = name.lowercased()
        guard !AppBrand.ignoredVaultDirectoryNames.contains(lowercasedName) else {
            throw VaultFileImportError.reservedName(name)
        }
    }

    private static func validateDestinationDirectory(_ destinationURL: URL, vaultURL: URL) throws {
        let destinationPath = destinationURL.standardizedFileURL.path
        let vaultPath = vaultURL.standardizedFileURL.path
        guard destinationPath == vaultPath || destinationPath.hasPrefix(vaultPath + "/") else {
            throw VaultFileImportError.destinationOutsideVault
        }
    }

    private static func validateDirectoryImport(from sourceURL: URL, into destinationDirectoryURL: URL) throws {
        let sourcePath = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationPath = destinationDirectoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else {
            throw VaultFileImportError.destinationInsideSource(sourceURL.lastPathComponent)
        }
    }

    private static func uniqueDestinationURL(
        in folderURL: URL,
        preferredName: String,
        isDirectory: Bool,
        fileManager: FileManager
    ) -> URL {
        var candidate = folderURL.appendingPathComponent(preferredName, isDirectory: isDirectory)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let nameURL = URL(fileURLWithPath: preferredName)
        let fileExtension = nameURL.pathExtension
        let baseName = nameURL.deletingPathExtension().lastPathComponent
        var index = 2

        repeat {
            let nextName: String
            if isDirectory {
                nextName = "\(preferredName) \(index)"
            } else if fileExtension.isEmpty {
                nextName = "\(baseName)-\(index)"
            } else {
                nextName = "\(baseName)-\(index).\(fileExtension)"
            }
            candidate = folderURL.appendingPathComponent(nextName, isDirectory: isDirectory)
            index += 1
        } while fileManager.fileExists(atPath: candidate.path)

        return candidate
    }

    private static func relativePath(for url: URL, in vaultURL: URL) throws -> String {
        let vaultPath = vaultURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(vaultPath + "/") else {
            throw VaultFileImportError.destinationOutsideVault
        }
        return String(path.dropFirst(vaultPath.count + 1))
    }
}

private enum VaultFileImportError: LocalizedError {
    case sourceMissing(String)
    case invalidName(String)
    case hiddenName(String)
    case reservedName(String)
    case destinationInsideSource(String)
    case destinationOutsideVault

    var errorDescription: String? {
        switch self {
        case let .sourceMissing(name):
            "\(name) no longer exists."
        case let .invalidName(name):
            "\(name) can't be imported because its name is invalid."
        case let .hiddenName(name):
            "\(name) can't be imported because hidden files are not shown in the vault."
        case let .reservedName(name):
            "\(name) is reserved by the vault."
        case let .destinationInsideSource(name):
            "\(name) can't be imported into itself."
        case .destinationOutsideVault:
            "Files must be imported inside the current vault."
        }
    }
}
