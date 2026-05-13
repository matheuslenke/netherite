import Foundation

enum ZipImportError: LocalizedError {
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .extractionFailed(detail):
            "ditto failed: \(detail)"
        }
    }
}

enum ZipImportService {
    static func extract(zip zipURL: URL, into destination: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            try ProcessRunner.run(arguments: [
                "/usr/bin/ditto",
                "-x", "-k", "--noqtn",
                zipURL.path,
                destination.path
            ])
        } catch let error as ProcessRunnerError {
            if case let .failed(_, result) = error {
                throw ZipImportError.extractionFailed(result.output.trimmed)
            }
            throw error
        }

        return collapseSingleTopLevelDirectory(in: destination)
    }

    private static func collapseSingleTopLevelDirectory(in folder: URL) -> URL {
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ),
            entries.count == 1,
            (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
            return folder
        }
        return entries[0]
    }
}
