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
            outputPDFURL: buildDirectory.appendingPathComponent(pdfName)
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
