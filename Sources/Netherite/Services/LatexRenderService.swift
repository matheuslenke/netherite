import Foundation

enum LatexRenderError: LocalizedError {
    case rootNotFound
    case latexmkNotFound
    case outputMissing(log: String)
    case failed(log: String)

    var errorDescription: String? {
        switch self {
        case .rootNotFound:
            "Could not find a LaTeX root file with \\documentclass and \\begin{document}."
        case .latexmkNotFound:
            "latexmk was not found. Install MacTeX or add latexmk to PATH."
        case let .outputMissing(log):
            "LaTeX finished without producing a PDF.\n\(log)"
        case let .failed(log):
            log
        }
    }
}

enum LatexRenderService {
    private static let latexPath = [
        "/Library/TeX/texbin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ].joined(separator: ":")

    private static let texExtensions = Set(["tex", "ltx"])
    private static let generatedFolderNames = AppBrand.ignoredVaultDirectoryNames
    private static let includeCommands = Set(["include", "input"])

    static func render(request: LatexRenderRequest) throws -> LatexRenderResult {
        let vaultURL = URL(fileURLWithPath: request.vaultPath, isDirectory: true)
        let fileURL = URL(fileURLWithPath: request.filePath)
        let project = try resolveProject(vaultURL: vaultURL, selectedFileURL: fileURL)
        let executable = try latexmkExecutable()

        try prepareBuildDirectory(project: project)

        let outputDirectory = project.buildDirectory.path
        let rootFileName = project.rootURL.lastPathComponent

        do {
            let result = try ProcessRunner.run(
                arguments: [
                    executable,
                    "-pdf",
                    "-interaction=nonstopmode",
                    "-halt-on-error",
                    "-file-line-error",
                    "-synctex=1",
                    "-outdir=\(outputDirectory)",
                    rootFileName
                ],
                currentDirectory: project.projectDirectory,
                environment: ["PATH": latexPath]
            )

            guard FileManager.default.fileExists(atPath: project.outputPDFURL.path) else {
                throw LatexRenderError.outputMissing(log: trimmedLog(result.output))
            }

            return LatexRenderResult(
                project: project,
                log: trimmedLog(result.output),
                renderedAt: Date()
            )
        } catch let error as ProcessRunnerError {
            switch error {
            case let .failed(_, result):
                throw LatexRenderError.failed(log: trimmedLog(result.output))
            }
        }
    }

    static func resolveProject(vaultURL: URL, selectedFileURL: URL) throws -> LatexProject {
        if let explicitRoot = explicitRootURL(from: selectedFileURL),
           FileManager.default.fileExists(atPath: explicitRoot.path) {
            return project(rootURL: explicitRoot, vaultURL: vaultURL)
        }

        let rootCandidates = try latexRootCandidates(in: vaultURL)
        guard !rootCandidates.isEmpty else {
            throw LatexRenderError.rootNotFound
        }

        if rootCandidates.contains(selectedFileURL.standardizedFileURL) {
            return project(rootURL: selectedFileURL.standardizedFileURL, vaultURL: vaultURL)
        }

        let selectedPath = selectedFileURL.standardizedFileURL.path
        let rankedCandidates = rootCandidates.sorted { lhs, rhs in
            candidateScore(rootURL: lhs, selectedPath: selectedPath) < candidateScore(rootURL: rhs, selectedPath: selectedPath)
        }

        return project(rootURL: rankedCandidates[0], vaultURL: vaultURL)
    }

    static func includedFiles(rootURL: URL, vaultURL: URL) -> [LatexIncludedFile] {
        includedFiles(
            rootURL: rootURL.standardizedFileURL,
            vaultURL: vaultURL.standardizedFileURL,
            visitedPaths: []
        )
    }

    private static func latexmkExecutable() throws -> String {
        let candidates = [
            "/Library/TeX/texbin/latexmk",
            "/opt/homebrew/bin/latexmk",
            "/usr/local/bin/latexmk"
        ]

        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return candidate
        }

        if let result = try? ProcessRunner.run(
            arguments: ["/bin/zsh", "-lc", "command -v latexmk"],
            environment: ["PATH": latexPath]
        ),
           !result.output.trimmed.isEmpty {
            return result.output.trimmed
        }

        throw LatexRenderError.latexmkNotFound
    }

    private static func explicitRootURL(from fileURL: URL) -> URL? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let firstLines = contents.split(separator: "\n", omittingEmptySubsequences: false).prefix(30)

        for line in firstLines {
            let lowered = line.lowercased()
            guard lowered.contains("tex root"), let separator = line.firstIndex(of: "=") else {
                continue
            }

            let rawPath = String(line[line.index(after: separator)...]).trimmed
            guard !rawPath.isEmpty else { continue }

            if rawPath.hasPrefix("/") {
                return URL(fileURLWithPath: rawPath).standardizedFileURL
            }
            return fileURL.deletingLastPathComponent().appendingPathComponent(rawPath).standardizedFileURL
        }

        return nil
    }

    private static func latexRootCandidates(in vaultURL: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if generatedFolderNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true || values.isPackage == true {
                continue
            }

            guard texExtensions.contains(url.pathExtension.lowercased()),
                  (values.fileSize ?? 0) < 5_000_000,
                  let contents = try? String(contentsOf: url, encoding: .utf8),
                  contents.contains("\\documentclass"),
                  contents.contains("\\begin{document}")
            else {
                continue
            }

            candidates.append(url.standardizedFileURL)
        }

        return candidates
    }

    private static func candidateScore(rootURL: URL, selectedPath: String) -> (Int, Int, Int, String) {
        let rootDirectory = rootURL.deletingLastPathComponent().path
        let containsSelectedFile = selectedPath.hasPrefix(rootDirectory + "/") || selectedPath == rootURL.path
        let namePriority = rootURL.lastPathComponent.lowercased() == "main.tex" ? 0 : 1
        let distance = abs(selectedPath.split(separator: "/").count - rootDirectory.split(separator: "/").count)
        return (containsSelectedFile ? 0 : 1, namePriority, distance, rootURL.path)
    }

    private static func project(rootURL: URL, vaultURL: URL) -> LatexProject {
        let rootRelativePath = relativePath(for: rootURL, in: vaultURL)
        let rootSlug = safeBuildSlug(rootRelativePath)
        let buildDirectory = vaultURL
            .appendingPathComponent(AppBrand.vaultSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("latex-build", isDirectory: true)
            .appendingPathComponent(rootSlug, isDirectory: true)
        let pdfName = rootURL.deletingPathExtension().lastPathComponent + ".pdf"

        return LatexProject(
            rootURL: rootURL,
            rootRelativePath: rootRelativePath,
            projectDirectory: rootURL.deletingLastPathComponent(),
            buildDirectory: buildDirectory,
            outputPDFURL: buildDirectory.appendingPathComponent(pdfName),
            includedFiles: includedFiles(rootURL: rootURL, vaultURL: vaultURL)
        )
    }

    private static func includedFiles(
        rootURL: URL,
        vaultURL: URL,
        visitedPaths: Set<String>
    ) -> [LatexIncludedFile] {
        let standardizedRootURL = rootURL.standardizedFileURL
        let rootPath = standardizedRootURL.path
        guard !visitedPaths.contains(rootPath),
              let contents = try? String(contentsOf: standardizedRootURL, encoding: .utf8)
        else {
            return []
        }

        let nextVisitedPaths = visitedPaths.union([rootPath])
        let references = parseIncludeReferences(in: contents)
        var files: [LatexIncludedFile] = []

        for reference in references {
            let resolvedURL = resolveIncludedFile(
                rawPath: reference.rawPath,
                sourceURL: standardizedRootURL,
                vaultURL: vaultURL
            )
            let fileExists = resolvedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let stats = resolvedURL.flatMap { includedFileStats(at: $0) }
            let includedRelativePath = resolvedURL.map { relativePath(for: $0, in: vaultURL) } ?? reference.rawPath
            let sourceRelativePath = relativePath(for: standardizedRootURL, in: vaultURL)

            files.append(
                LatexIncludedFile(
                    id: "\(sourceRelativePath):\(reference.line):\(reference.command):\(reference.rawPath)",
                    url: fileExists ? resolvedURL : nil,
                    relativePath: includedRelativePath,
                    sourceRelativePath: sourceRelativePath,
                    command: reference.command,
                    line: reference.line,
                    byteCount: stats?.byteCount,
                    wordCount: stats?.wordCount,
                    lineCount: stats?.lineCount,
                    modifiedAt: stats?.modifiedAt,
                    isMissing: !fileExists
                )
            )

            if fileExists, let resolvedURL {
                files.append(contentsOf: includedFiles(
                    rootURL: resolvedURL,
                    vaultURL: vaultURL,
                    visitedPaths: nextVisitedPaths
                ))
            }
        }

        return files.uniquedByResolvedPath()
    }

    private static func parseIncludeReferences(in source: String) -> [LatexIncludeReference] {
        var references: [LatexIncludeReference] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, line) in lines.enumerated() {
            references.append(contentsOf: parseIncludeReferences(inLine: String(line), lineNumber: index + 1))
        }

        return references
    }

    private static func parseIncludeReferences(inLine line: String, lineNumber: Int) -> [LatexIncludeReference] {
        let uncommentedLine = lineBeforeComment(in: line)
        var references: [LatexIncludeReference] = []
        var searchStart = uncommentedLine.startIndex

        while let commandStart = uncommentedLine[searchStart...].firstIndex(of: "\\") {
            let nameStart = uncommentedLine.index(after: commandStart)
            var nameEnd = nameStart
            while nameEnd < uncommentedLine.endIndex,
                  uncommentedLine[nameEnd].isLetter {
                nameEnd = uncommentedLine.index(after: nameEnd)
            }

            guard nameStart < nameEnd else {
                searchStart = nameEnd
                continue
            }

            let command = String(uncommentedLine[nameStart..<nameEnd])
            guard includeCommands.contains(command) else {
                searchStart = nameEnd
                continue
            }

            let cursor = skipWhitespace(from: nameEnd, in: uncommentedLine)
            guard cursor < uncommentedLine.endIndex, uncommentedLine[cursor] == "{" else {
                searchStart = nameEnd
                continue
            }

            guard let closeIndex = closingBraceIndex(from: cursor, in: uncommentedLine) else {
                searchStart = uncommentedLine.index(after: cursor)
                continue
            }

            let pathStart = uncommentedLine.index(after: cursor)
            let rawPath = String(uncommentedLine[pathStart..<closeIndex]).trimmed
            if !rawPath.isEmpty {
                references.append(LatexIncludeReference(command: command, rawPath: rawPath, line: lineNumber))
            }

            searchStart = uncommentedLine.index(after: closeIndex)
        }

        return references
    }

    private static func lineBeforeComment(in line: String) -> String {
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "%", !isEscaped(index, in: line) {
                return String(line[..<index])
            }
            index = line.index(after: index)
        }
        return line
    }

    private static func isEscaped(_ index: String.Index, in line: String) -> Bool {
        guard index > line.startIndex else { return false }

        var backslashCount = 0
        var cursor = line.index(before: index)
        while true {
            guard line[cursor] == "\\" else { break }
            backslashCount += 1
            if cursor == line.startIndex { break }
            cursor = line.index(before: cursor)
        }

        return backslashCount % 2 == 1
    }

    private static func closingBraceIndex(from openIndex: String.Index, in line: String) -> String.Index? {
        var depth = 0
        var index = openIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "{", !isEscaped(index, in: line) {
                depth += 1
            } else if character == "}", !isEscaped(index, in: line) {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = line.index(after: index)
        }

        return nil
    }

    private static func skipWhitespace(from index: String.Index, in line: String) -> String.Index {
        var cursor = index
        while cursor < line.endIndex, line[cursor].isWhitespace {
            cursor = line.index(after: cursor)
        }
        return cursor
    }

    private static func resolveIncludedFile(
        rawPath: String,
        sourceURL: URL,
        vaultURL: URL
    ) -> URL? {
        guard !rawPath.hasPrefix("|"),
              !rawPath.contains("://")
        else {
            return nil
        }

        let rawURL = URL(fileURLWithPath: rawPath)
        let pathWithExtension = rawURL.pathExtension.isEmpty ? rawPath + ".tex" : rawPath
        let baseURL = rawPath.hasPrefix("/")
            ? URL(fileURLWithPath: pathWithExtension)
            : sourceURL.deletingLastPathComponent().appendingPathComponent(pathWithExtension)
        let standardizedURL = baseURL.standardizedFileURL

        if FileManager.default.fileExists(atPath: standardizedURL.path) {
            return standardizedURL
        }

        let projectRelativeURL = vaultURL.appendingPathComponent(pathWithExtension).standardizedFileURL
        if FileManager.default.fileExists(atPath: projectRelativeURL.path) {
            return projectRelativeURL
        }

        return standardizedURL
    }

    private static func includedFileStats(at url: URL) -> LatexIncludedFileStats? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }

        let stats = DocumentStats(text: contents)
        return LatexIncludedFileStats(
            byteCount: values.fileSize ?? 0,
            wordCount: stats.words,
            lineCount: stats.lines,
            modifiedAt: values.contentModificationDate
        )
    }

    private static func prepareBuildDirectory(project: LatexProject) throws {
        try FileManager.default.createDirectory(at: project.buildDirectory, withIntermediateDirectories: true)

        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: project.projectDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            if generatedFolderNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isDirectory == true else { continue }

            let relativeDirectory = relativePath(for: url, in: project.projectDirectory)
            guard !relativeDirectory.isEmpty else { continue }

            try FileManager.default.createDirectory(
                at: project.buildDirectory.appendingPathComponent(relativeDirectory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private static func relativePath(for url: URL, in parentURL: URL) -> String {
        let parentPath = parentURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(parentPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(parentPath.count + 1))
    }

    private static func safeBuildSlug(_ relativePath: String) -> String {
        let stem = relativePath
            .replacingOccurrences(of: ".tex", with: "")
            .replacingOccurrences(of: "/", with: "__")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return stem.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.map(String.init).joined()
    }

    private static func trimmedLog(_ log: String) -> String {
        let limit = 80_000
        guard log.count > limit else { return log.trimmed }
        return "...\n" + String(log.suffix(limit)).trimmed
    }
}

private struct LatexIncludeReference {
    let command: String
    let rawPath: String
    let line: Int
}

private struct LatexIncludedFileStats {
    let byteCount: Int
    let wordCount: Int
    let lineCount: Int
    let modifiedAt: Date?
}

private extension Array where Element == LatexIncludedFile {
    func uniquedByResolvedPath() -> [LatexIncludedFile] {
        var seenPaths: Set<String> = []
        var uniqueFiles: [LatexIncludedFile] = []

        for file in self where seenPaths.insert(file.url?.path ?? file.relativePath).inserted {
            uniqueFiles.append(file)
        }

        return uniqueFiles
    }
}
