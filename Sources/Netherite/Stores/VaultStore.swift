import AppKit
import Foundation
import UniformTypeIdentifiers

private struct VaultContents {
    let files: [VaultFile]
    let folders: [VaultFolder]
}

private enum VaultCreationError: LocalizedError {
    case vaultUnavailable
    case invalidFolder

    var errorDescription: String? {
        switch self {
        case .vaultUnavailable:
            "Choose a vault before creating files."
        case .invalidFolder:
            "The selected folder is outside this vault."
        }
    }
}

private enum VaultRenameError: LocalizedError {
    case emptyName
    case hiddenName
    case invalidName
    case reservedName(String)
    case sourceMissing
    case destinationExists(String)
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Name can't be empty."
        case .hiddenName:
            "Hidden names are not shown in the vault."
        case .invalidName:
            "Name can't contain / or :."
        case let .reservedName(name):
            "\(name) is reserved by the vault."
        case .sourceMissing:
            "The item no longer exists."
        case let .destinationExists(name):
            "An item named \(name) already exists."
        case .invalidDestination:
            "The renamed item must stay inside this vault."
        }
    }
}

@MainActor
final class VaultStore: ObservableObject {
    @Published var vaultURL: URL?
    @Published var files: [VaultFile] = []
    @Published var folders: [VaultFolder] = []
    @Published var selectedFileID: String?
    @Published var searchText = ""
    @Published var documentText = ""
    @Published var documentSourceDescription = ""
    @Published var documentIsEditable = true
    @Published var isDirty = false
    @Published var editorMode: EditorMode = .split
    @Published var gitSnapshot = GitSnapshot.empty
    @Published var gitHistory: [GitFileVersion] = []
    @Published var selectedVersion: GitFileVersion?
    @Published var selectedVersionDiff = ""
    @Published var statusMessage = "Choose a vault to begin."
    @Published var latexRenderState = LatexRenderState.idle
    @Published var inspectorVisible = true
    @Published var commitMessage = "Update notes"
    @Published var agentPrompt = ""
    @Published var backlinks: [VaultFile] = []
    @Published var agentAvailability: [AgentTool: Bool] = [:]
    @Published var quickLookFileURL: URL?
    @Published var hotReloadEnabled: Bool = UserDefaults.standard.object(forKey: "hotReloadVaultChanges") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hotReloadEnabled, forKey: "hotReloadVaultChanges")
            configureHotReload()
        }
    }

    private var originalDocumentText = ""
    private var hotReloadTask: Task<Void, Never>?
    private var latexRenderTask: Task<Void, Never>?
    private var latexRenderRequestID = UUID()
    private var fileSignature = ""
    private let hotReloadIntervalNanoseconds: UInt64 = 1_500_000_000
    private let gitService = GitService()
    private let terminalService = AgentTerminalService()

    init() {
        agentAvailability = terminalService.availability()
        let shouldReopen = UserDefaults.standard.object(forKey: "launchReopensLastVault") as? Bool ?? true
        if shouldReopen, let path = UserDefaults.standard.string(forKey: "lastVaultPath"), !path.isEmpty {
            openVault(URL(fileURLWithPath: path))
        }
    }

    var currentFile: VaultFile? {
        guard let selectedFileID else { return nil }
        return files.first { $0.id == selectedFileID }
    }

    var filteredFiles: [VaultFile] {
        let query = searchText.trimmed.lowercased()
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.name.lowercased().contains(query) ||
            $0.relativePath.lowercased().contains(query)
        }
    }

    var documentStats: DocumentStats {
        DocumentStats(text: documentText)
    }

    var selectedFileCanRenderLatex: Bool {
        currentFile?.kind == .latex
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to use as your writing vault."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openVault(url)
    }

    func openVault(_ url: URL) {
        vaultURL = url
        UserDefaults.standard.set(url.path, forKey: "lastVaultPath")
        ensureVaultConfiguration(in: url)
        reloadFiles()

        if let selectedFileID, files.contains(where: { $0.id == selectedFileID }) {
            selectFile(id: selectedFileID)
        } else {
            selectFile(id: preferredInitialFileID)
        }

        refreshGitStatus()
        configureHotReload()
        statusMessage = "Opened \(url.lastPathComponent)"
    }

    func importZipRequested() {
        guard let zipURL = promptForZipFile() else { return }
        presentImportDestinationChoice(for: zipURL)
    }

    private func promptForZipFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        panel.message = "Choose a .zip file to import (e.g. an Overleaf export)."
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func presentImportDestinationChoice(for zipURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Import \(zipURL.lastPathComponent)"
        alert.informativeText = "Where should the contents be extracted?"
        alert.addButton(withTitle: "Open as New Vault")
        let addButton = alert.addButton(withTitle: "Add to Current Vault")
        alert.addButton(withTitle: "Cancel")
        addButton.isEnabled = (vaultURL != nil)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            importZipAsNewVault(zipURL: zipURL)
        case .alertSecondButtonReturn:
            importZipIntoCurrentVault(zipURL: zipURL)
        default:
            return
        }
    }

    private func importZipAsNewVault(zipURL: URL) {
        let parentPanel = NSOpenPanel()
        parentPanel.canChooseFiles = false
        parentPanel.canChooseDirectories = true
        parentPanel.canCreateDirectories = true
        parentPanel.allowsMultipleSelection = false
        parentPanel.message = "Choose a parent folder. A new vault will be created inside it."
        guard parentPanel.runModal() == .OK, let parent = parentPanel.url else { return }

        let baseName = zipURL.deletingPathExtension().lastPathComponent
        let destination = uniqueFolderURL(in: parent, baseName: baseName)
        runImport(zipURL: zipURL, destination: destination, openAsVault: true)
    }

    private func importZipIntoCurrentVault(zipURL: URL) {
        guard let vaultURL else { return }
        let baseName = zipURL.deletingPathExtension().lastPathComponent
        let destination = uniqueFolderURL(in: vaultURL, baseName: baseName)
        runImport(zipURL: zipURL, destination: destination, openAsVault: false)
    }

    private func runImport(zipURL: URL, destination: URL, openAsVault: Bool) {
        statusMessage = "Extracting \(zipURL.lastPathComponent)…"
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ZipImportService.extract(zip: zipURL, into: destination) }
            }.value
            await MainActor.run {
                guard let self else { return }
                switch result {
                case let .success(extractedRoot):
                    if openAsVault {
                        self.openVault(extractedRoot)
                    } else {
                        self.reloadFiles()
                    }
                    self.selectAndRenderLatexRoot(in: extractedRoot)
                case let .failure(error):
                    self.statusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func selectAndRenderLatexRoot(in importedRoot: URL) {
        guard let vaultURL else { return }
        do {
            let project = try LatexRenderService.resolveProject(
                vaultURL: vaultURL,
                selectedFileURL: importedRoot
            )
            guard let relPath = relativePath(for: project.rootURL) else {
                statusMessage = "Imported, but the LaTeX root is outside the vault."
                return
            }
            selectFile(id: relPath)
            renderLatexForCurrentFile()
        } catch {
            statusMessage = "Imported, but couldn't find a LaTeX root (\(error.localizedDescription))."
        }
    }

    func reloadFiles() {
        guard let vaultURL else { return }
        setContents(Self.loadContents(in: vaultURL))
    }

    private static func loadContents(in vaultURL: URL) -> VaultContents {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .isPackageKey
        ]

        let enumerator = FileManager.default.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var loadedFiles: [VaultFile] = []
        var loadedFolders: [VaultFolder] = []
        while let item = enumerator?.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: Set(keys)),
                  values.isPackage != true
            else {
                continue
            }

            let relativePath = item.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
            let rootName = relativePath.split(separator: "/", maxSplits: 1).first.map(String.init) ?? relativePath
            guard !AppBrand.ignoredVaultDirectoryNames.contains(rootName) else {
                if values.isDirectory == true {
                    enumerator?.skipDescendants()
                }
                continue
            }

            if values.isDirectory == true {
                loadedFolders.append(
                    VaultFolder(
                        id: relativePath,
                        url: item,
                        relativePath: relativePath,
                        name: item.lastPathComponent,
                        modifiedAt: values.contentModificationDate ?? Date.distantPast
                    )
                )
                continue
            }

            let fileExtension = item.pathExtension
            loadedFiles.append(
                VaultFile(
                    id: relativePath,
                    url: item,
                    relativePath: relativePath,
                    name: item.lastPathComponent,
                    fileExtension: fileExtension,
                    kind: FileKind(fileExtension: fileExtension),
                    byteCount: values.fileSize ?? 0,
                    modifiedAt: values.contentModificationDate ?? Date.distantPast
                )
            )
        }

        return VaultContents(
            files: loadedFiles.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            },
            folders: loadedFolders.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
        )
    }

    func selectFile(id: String?) {
        if isDirty, documentIsEditable {
            saveDocument(renderLatexAfterSave: false)
        }

        selectedFileID = id
        selectedVersion = nil
        selectedVersionDiff = ""
        gitHistory = []
        backlinks = []

        guard let file = currentFile else {
            documentText = ""
            originalDocumentText = ""
            documentSourceDescription = ""
            documentIsEditable = true
            latexRenderState = .idle
            return
        }

        loadDocument(file, statusMessage: "Loaded \(file.relativePath)")
    }

    private func loadDocument(_ file: VaultFile, statusMessage message: String) {
        do {
            let loaded = try FileTextLoader.load(url: file.url)
            documentText = loaded.text
            originalDocumentText = loaded.text
            documentSourceDescription = loaded.sourceDescription
            documentIsEditable = loaded.isEditable
            if file.kind != .latex {
                latexRenderState = .idle
            }
            isDirty = false
            statusMessage = message
            refreshHistoryForSelectedFile()
            rebuildBacklinks(for: file)
        } catch {
            documentText = ""
            originalDocumentText = ""
            documentSourceDescription = "Could not load this file"
            documentIsEditable = false
            isDirty = false
            statusMessage = error.localizedDescription
        }
    }

    private func setContents(_ contents: VaultContents) {
        files = contents.files
        folders = contents.folders
        fileSignature = Self.fileSignature(files: contents.files, folders: contents.folders)
    }

    private static func fileSignature(files: [VaultFile], folders: [VaultFolder]) -> String {
        let folderSignature = folders.map { folder in
            "folder|\(folder.relativePath)|\(folder.modifiedAt.timeIntervalSince1970)"
        }
        let fileSignature = files.map { file in
            "\(file.relativePath)|\(file.byteCount)|\(file.modifiedAt.timeIntervalSince1970)"
        }

        return (folderSignature + fileSignature).joined(separator: "\n")
    }

    private func configureHotReload() {
        hotReloadTask?.cancel()
        hotReloadTask = nil

        guard hotReloadEnabled, vaultURL != nil else { return }

        let interval = hotReloadIntervalNanoseconds
        hotReloadTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                guard let self else { return }
                self.reloadVaultIfChanged()
            }
        }
    }

    private func reloadVaultIfChanged() {
        guard hotReloadEnabled, let vaultURL else { return }

        let loadedContents = Self.loadContents(in: vaultURL)
        let nextSignature = Self.fileSignature(files: loadedContents.files, folders: loadedContents.folders)
        guard nextSignature != fileSignature else { return }

        let previousFile = currentFile
        let previousFileID = selectedFileID

        if isDirty {
            fileSignature = nextSignature
            refreshGitStatus()
            statusMessage = "Vault changed; unsaved edits kept"
            return
        }

        setContents(loadedContents)

        guard let previousFileID else {
            refreshGitStatus()
            statusMessage = "Reloaded vault changes"
            return
        }

        guard files.contains(where: { $0.id == previousFileID }) else {
            selectFile(id: preferredInitialFileID)
            statusMessage = "Reloaded vault changes"
            refreshGitStatus()
            return
        }

        selectedFileID = previousFileID
        guard let updatedFile = currentFile else {
            refreshGitStatus()
            statusMessage = "Reloaded vault changes"
            return
        }

        let selectedFileChanged = previousFile?.modifiedAt != updatedFile.modifiedAt ||
            previousFile?.byteCount != updatedFile.byteCount

        if selectedFileChanged {
            loadDocument(updatedFile, statusMessage: "Reloaded \(updatedFile.relativePath)")
        } else {
            rebuildBacklinks(for: updatedFile)
            statusMessage = "Reloaded vault changes"
        }

        refreshGitStatus()
    }

    func setDocumentText(_ text: String) {
        guard documentText != text else { return }
        documentText = text
        isDirty = documentIsEditable && documentText != originalDocumentText
    }

    func saveDocument(renderLatexAfterSave: Bool = true) {
        guard let file = currentFile else { return }
        guard documentIsEditable else {
            statusMessage = "This preview was extracted from a non-text format and cannot be saved here."
            return
        }

        do {
            try documentText.write(to: file.url, atomically: true, encoding: .utf8)
            originalDocumentText = documentText
            isDirty = false
            reloadFiles()
            statusMessage = "Saved \(file.relativePath)"
            refreshGitStatus()
            rebuildBacklinks(for: file)
            if renderLatexAfterSave && file.kind == .latex && editorMode != .edit {
                renderLatexForCurrentFile()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createNote() {
        guard vaultURL != nil else {
            chooseVault()
            return
        }

        createFile(format: .markdown, in: nil)
    }

    func createFile(format: NewFileFormat, in relativeFolderPath: String?) {
        do {
            let directoryURL = try targetDirectory(relativeFolderPath: relativeFolderPath)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let url = uniqueURL(in: directoryURL, baseName: format.baseName, fileExtension: format.fileExtension)
            let contents = format.initialContents(fileName: url.lastPathComponent)
            try contents.write(to: url, atomically: true, encoding: .utf8)

            reloadFiles()
            if let relativePath = relativePath(for: url) {
                selectFile(id: relativePath)
                statusMessage = "Created \(relativePath)"
            } else {
                statusMessage = "Created \(url.lastPathComponent)"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createFolder(in relativeFolderPath: String?) {
        do {
            let directoryURL = try targetDirectory(relativeFolderPath: relativeFolderPath)
            let folderURL = uniqueFolderURL(in: directoryURL, baseName: "Untitled Folder")
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            reloadFiles()
            statusMessage = "Created \(relativePath(for: folderURL) ?? folderURL.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func renameFile(_ file: VaultFile, to proposedName: String) -> String? {
        renameItem(
            at: file.url,
            currentRelativePath: file.relativePath,
            currentName: file.name,
            proposedName: proposedName,
            isDirectory: false
        )
    }

    @discardableResult
    func renameFolder(_ folder: VaultFolder, to proposedName: String) -> String? {
        renameItem(
            at: folder.url,
            currentRelativePath: folder.relativePath,
            currentName: folder.name,
            proposedName: proposedName,
            isDirectory: true
        )
    }

    func deleteSelectedFile() {
        guard let file = currentFile else { return }
        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: file.url, resultingItemURL: &resultingURL)
            reloadFiles()
            selectFile(id: files.first?.id)
            statusMessage = "Moved \(file.name) to Trash"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func revealSelectedInFinder() {
        guard let file = currentFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func openSelectedExternally() {
        guard let file = currentFile else { return }
        NSWorkspace.shared.open(file.url)
    }

    func previewSelectedFile() {
        quickLookFileURL = currentFile?.url
    }

    func renderLatexForCurrentFileIfNeeded() {
        guard selectedFileCanRenderLatex else { return }
        guard !latexRenderState.isRendering else { return }

        if let vaultURL, let file = currentFile,
           latexRenderState.phase == .rendered,
           latexRenderState.pdfURL != nil {
            let project = try? LatexRenderService.resolveProject(vaultURL: vaultURL, selectedFileURL: file.url)
            if project?.rootRelativePath == latexRenderState.rootRelativePath {
                return
            }
        }

        renderLatexForCurrentFile()
    }

    func renderLatexForCurrentFile() {
        guard let vaultURL, let file = currentFile, file.kind == .latex else {
            latexRenderState = .idle
            statusMessage = "Choose a LaTeX file to render."
            return
        }

        if isDirty && documentIsEditable {
            saveDocument(renderLatexAfterSave: false)
            guard !isDirty else { return }
        }

        latexRenderTask?.cancel()
        let requestID = UUID()
        latexRenderRequestID = requestID
        let request = LatexRenderRequest(
            vaultPath: vaultURL.path,
            filePath: file.url.path,
            selectedRelativePath: file.relativePath
        )
        let selectedRelativePath = file.relativePath

        latexRenderState = LatexRenderState(
            phase: .rendering,
            rootRelativePath: file.relativePath,
            pdfURL: nil,
            log: "",
            message: "Running latexmk for \(file.name)...",
            renderedAt: nil
        )
        statusMessage = "Rendering LaTeX..."

        latexRenderTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try LatexRenderService.render(request: request) }
            }.value

            await MainActor.run {
                guard let self, self.latexRenderRequestID == requestID else { return }

                switch result {
                case let .success(renderResult):
                    self.latexRenderState = LatexRenderState(
                        phase: .rendered,
                        rootRelativePath: renderResult.project.rootRelativePath,
                        pdfURL: renderResult.project.outputPDFURL,
                        log: renderResult.log,
                        message: "Rendered \(renderResult.project.outputPDFURL.lastPathComponent)",
                        renderedAt: renderResult.renderedAt
                    )
                    self.statusMessage = "Rendered \(renderResult.project.rootRelativePath)"
                case let .failure(error):
                    self.applyLatexRenderFailure(error, selectedRelativePath: selectedRelativePath)
                }
            }
        }
    }

    func openRenderedLatexPDF() {
        guard let pdfURL = latexRenderState.pdfURL else { return }
        NSWorkspace.shared.open(pdfURL)
    }

    func revealRenderedLatexPDF() {
        guard let pdfURL = latexRenderState.pdfURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([pdfURL])
    }

    func refreshGitStatus() {
        guard let vaultURL else {
            gitSnapshot = .empty
            return
        }

        do {
            gitSnapshot = try gitService.snapshot(for: vaultURL)
            refreshHistoryForSelectedFile()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func initializeGitRepository() {
        guard let vaultURL else { return }
        do {
            statusMessage = try gitService.initializeRepository(at: vaultURL).trimmed
            refreshGitStatus()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func pullVault() {
        guard let vaultURL else { return }
        do {
            statusMessage = try gitService.pull(vaultURL: vaultURL).trimmed
            reloadFiles()
            if let selectedFileID {
                selectFile(id: selectedFileID)
            }
            refreshGitStatus()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func pushVault() {
        guard let vaultURL else { return }
        do {
            statusMessage = try gitService.push(vaultURL: vaultURL).trimmed
            refreshGitStatus()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func commitVault() {
        guard let vaultURL else { return }
        let message = commitMessage.trimmed.isEmpty ? "Update notes" : commitMessage.trimmed

        if isDirty {
            saveDocument()
        }

        do {
            statusMessage = try gitService.commitAll(vaultURL: vaultURL, message: message).trimmed
            refreshGitStatus()
        } catch {
            statusMessage = error.localizedDescription
            refreshGitStatus()
        }
    }

    func refreshHistoryForSelectedFile() {
        guard let vaultURL, let file = currentFile, gitSnapshot.isRepository else {
            gitHistory = []
            selectedVersionDiff = ""
            return
        }

        do {
            gitHistory = try gitService.history(for: file.relativePath, in: vaultURL)
        } catch {
            gitHistory = []
            statusMessage = error.localizedDescription
        }
    }

    func loadDiff(for version: GitFileVersion) {
        guard let vaultURL, let file = currentFile else { return }
        selectedVersion = version

        do {
            selectedVersionDiff = try gitService.diff(version: version, relativePath: file.relativePath, in: vaultURL)
        } catch {
            selectedVersionDiff = error.localizedDescription
        }
    }

    func openAgentTerminal(tool: AgentTool) {
        guard let vaultURL else {
            chooseVault()
            return
        }

        do {
            try terminalService.open(tool: tool, vaultURL: vaultURL, file: currentFile, prompt: agentPrompt)
            statusMessage = "Opened \(tool.title) in Terminal"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func ensureVaultConfiguration(in vaultURL: URL) {
        let configDirectory = vaultURL.appendingPathComponent(AppBrand.vaultSupportDirectoryName, isDirectory: true)
        let configFile = configDirectory.appendingPathComponent("config.json")

        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configFile.path) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(VaultConfig.current).write(to: configFile)
            }

            if vaultAppearsEmpty(vaultURL) {
                let welcome = vaultURL.appendingPathComponent("Welcome.md")
                let text = """
                # Welcome to \(AppBrand.displayName)

                This vault stores plain files in folders, plus app settings in `\(AppBrand.vaultSupportDirectoryName)/config.json`.

                - Write in Markdown, text, code, CSV, JSON, or any readable text format.
                - Use Preview or Split mode to render Markdown while preserving the source file.
                - Initialize git in the vault when you want version history and sync.
                - Open Codex or Claude Code from the terminal panel to work with the current file.

                """
                try text.write(to: welcome, atomically: true, encoding: .utf8)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func vaultAppearsEmpty(_ vaultURL: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return true
        }

        for case let url as URL in enumerator {
            if AppBrand.ignoredVaultDirectoryNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                return false
            }
        }
        return true
    }

    private func targetDirectory(relativeFolderPath: String?) throws -> URL {
        guard let vaultURL else { throw VaultCreationError.vaultUnavailable }

        let folderPath = relativeFolderPath?.trimmed ?? ""
        let directoryURL = if folderPath.isEmpty {
            vaultURL.standardizedFileURL
        } else {
            vaultURL.appendingPathComponent(folderPath, isDirectory: true).standardizedFileURL
        }

        let vaultPath = vaultURL.standardizedFileURL.path
        guard directoryURL.path == vaultPath || directoryURL.path.hasPrefix(vaultPath + "/") else {
            throw VaultCreationError.invalidFolder
        }

        return directoryURL
    }

    private func renameItem(
        at sourceURL: URL,
        currentRelativePath: String,
        currentName: String,
        proposedName: String,
        isDirectory: Bool
    ) -> String? {
        do {
            let newName = try validatedRenameName(proposedName)
            guard newName != currentName else {
                statusMessage = "Name unchanged"
                return currentRelativePath
            }
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw VaultRenameError.sourceMissing
            }

            if selectedFileIsAffected(by: currentRelativePath, isDirectory: isDirectory), isDirty, documentIsEditable {
                saveDocument(renderLatexAfterSave: false)
                guard !isDirty else { return nil }
            }

            let destinationURL = sourceURL
                .deletingLastPathComponent()
                .appendingPathComponent(newName, isDirectory: isDirectory)
                .standardizedFileURL

            try validateRenameDestination(destinationURL)
            let destinationExists = FileManager.default.fileExists(atPath: destinationURL.path)
            let destinationIsSource = destinationExists && destinationMatchesSource(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
            guard !destinationExists || destinationIsSource else {
                throw VaultRenameError.destinationExists(newName)
            }

            let previousSelection = selectedFileID
            try moveItemForRename(
                from: sourceURL,
                to: destinationURL,
                isDirectory: isDirectory,
                destinationIsSource: destinationIsSource
            )
            guard let newRelativePath = relativePath(for: destinationURL) else {
                throw VaultRenameError.invalidDestination
            }

            reloadFiles()
            restoreSelectionAfterRename(
                previousSelection: previousSelection,
                oldPath: currentRelativePath,
                newPath: newRelativePath,
                isDirectory: isDirectory
            )
            refreshGitStatus()
            statusMessage = "Renamed \(currentName) to \(newName)"
            return newRelativePath
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    private func moveItemForRename(
        from sourceURL: URL,
        to destinationURL: URL,
        isDirectory: Bool,
        destinationIsSource: Bool
    ) throws {
        guard destinationIsSource else {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            return
        }

        let temporaryURL = uniqueTemporaryRenameURL(near: sourceURL, isDirectory: isDirectory)
        try FileManager.default.moveItem(at: sourceURL, to: temporaryURL)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? FileManager.default.moveItem(at: temporaryURL, to: sourceURL)
            throw error
        }
    }

    private func destinationMatchesSource(sourceURL: URL, destinationURL: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let sourceID = try? sourceURL.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject,
              let destinationID = try? destinationURL.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject
        else {
            return false
        }

        return sourceID.isEqual(destinationID)
    }

    private func uniqueTemporaryRenameURL(near sourceURL: URL, isDirectory: Bool) -> URL {
        let parentURL = sourceURL.deletingLastPathComponent()
        var candidate: URL
        repeat {
            candidate = parentURL.appendingPathComponent(
                "\(AppBrand.vaultSupportDirectoryName)-rename-\(UUID().uuidString)",
                isDirectory: isDirectory
            )
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    private func validatedRenameName(_ proposedName: String) throws -> String {
        let name = proposedName.trimmed
        guard !name.isEmpty else { throw VaultRenameError.emptyName }
        guard !name.hasPrefix(".") else { throw VaultRenameError.hiddenName }
        guard !name.contains("/") && !name.contains(":") else { throw VaultRenameError.invalidName }
        guard name != "." && name != ".." else { throw VaultRenameError.invalidName }

        let lowercasedName = name.lowercased()
        guard !AppBrand.ignoredVaultDirectoryNames.contains(lowercasedName) else {
            throw VaultRenameError.reservedName(name)
        }

        return name
    }

    private func validateRenameDestination(_ destinationURL: URL) throws {
        guard let vaultURL else { throw VaultCreationError.vaultUnavailable }

        let vaultPath = vaultURL.standardizedFileURL.path
        let destinationPath = destinationURL.standardizedFileURL.path
        guard destinationPath.hasPrefix(vaultPath + "/") else {
            throw VaultRenameError.invalidDestination
        }
    }

    private func selectedFileIsAffected(by relativePath: String, isDirectory: Bool) -> Bool {
        guard let selectedFileID else { return false }
        if isDirectory {
            return selectedFileID.hasPrefix(relativePath + "/")
        }
        return selectedFileID == relativePath
    }

    private func restoreSelectionAfterRename(
        previousSelection: String?,
        oldPath: String,
        newPath: String,
        isDirectory: Bool
    ) {
        guard let previousSelection else { return }

        let nextSelection: String?
        if isDirectory, previousSelection.hasPrefix(oldPath + "/") {
            nextSelection = newPath + String(previousSelection.dropFirst(oldPath.count))
        } else if !isDirectory, previousSelection == oldPath {
            nextSelection = newPath
        } else {
            nextSelection = previousSelection
        }

        guard let nextSelection else {
            selectFile(id: preferredInitialFileID)
            return
        }

        if nextSelection != previousSelection {
            selectFile(id: files.contains(where: { $0.id == nextSelection }) ? nextSelection : preferredInitialFileID)
        } else if !files.contains(where: { $0.id == nextSelection }) {
            selectFile(id: preferredInitialFileID)
        }
    }

    private func relativePath(for url: URL) -> String? {
        guard let vaultURL else { return nil }
        let vaultPath = vaultURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(vaultPath + "/") else { return nil }
        return String(path.dropFirst(vaultPath.count + 1))
    }

    private func uniqueURL(in folder: URL, baseName: String, fileExtension: String) -> URL {
        var candidate = folder.appendingPathComponent("\(baseName).\(fileExtension)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName)-\(index).\(fileExtension)")
            index += 1
        }
        return candidate
    }

    private func uniqueFolderURL(in folder: URL, baseName: String) -> URL {
        var candidate = folder.appendingPathComponent(baseName, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private func rebuildBacklinks(for file: VaultFile) {
        let titleToken = "[[\(file.titleWithoutExtension)]]"
        let pathToken = file.relativePath
        var matches: [VaultFile] = []

        for candidate in files where candidate.id != file.id {
            guard candidate.byteCount < 2_000_000,
                  let text = try? String(contentsOf: candidate.url, encoding: .utf8)
            else {
                continue
            }
            if text.contains(titleToken) || text.contains(pathToken) {
                matches.append(candidate)
            }
        }

        backlinks = matches
    }

    private var preferredInitialFileID: String? {
        files.first(where: { $0.kind == .markdown })?.id ??
            files.first(where: { $0.name.lowercased() == "main.tex" })?.id ??
            files.first(where: { $0.fileExtension.lowercased() == "tex" })?.id ??
            files.first?.id
    }

    private func applyLatexRenderFailure(_ error: Error, selectedRelativePath: String) {
        let message = error.localizedDescription.trimmed
        let phase: LatexRenderPhase
        if let latexError = error as? LatexRenderError {
            switch latexError {
            case .latexmkNotFound:
                phase = .unavailable
            case .rootNotFound, .outputMissing, .failed:
                phase = .failed
            }
        } else {
            phase = .failed
        }

        latexRenderState = LatexRenderState(
            phase: phase,
            rootRelativePath: selectedRelativePath,
            pdfURL: nil,
            log: message,
            message: message.components(separatedBy: .newlines).first ?? "LaTeX build failed.",
            renderedAt: nil
        )
        statusMessage = "LaTeX build failed"
    }
}
