import AppKit
import Foundation
import UniformTypeIdentifiers

private struct VaultContents: Sendable {
    let files: [VaultFile]
    let folders: [VaultFolder]
}

private enum HistoryLoadResult: Sendable {
    case success([GitFileVersion])
    case failure(String)
}

private struct PreparedDocument: Sendable {
    let loaded: LoadedDocument
    let stats: DocumentStats
}

private enum DocumentLoadResult: Sendable {
    case success(PreparedDocument)
    case failure(String)
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

private extension Array where Element == URL {
    func uniquedByStandardizedPath() -> [URL] {
        var seenPaths: Set<String> = []
        var uniqueURLs: [URL] = []

        for url in self {
            let path = url.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { continue }
            uniqueURLs.append(url)
        }

        return uniqueURLs
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        var unique: [Element] = []

        for element in self where seen.insert(element).inserted {
            unique.append(element)
        }

        return unique
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
    @Published var workspaceSection: WorkspaceSection = .files
    @Published var selectedFileID: String?
    @Published var openFileTabIDs: [String] = []
    @Published var previewTabFileID: String?
    @Published var searchText = ""
    @Published var referenceSearchText = ""
    @Published var references: [ReferenceItem] = []
    @Published var selectedReferenceID: ReferenceItem.ID?
    @Published var showingCitationPicker = false
    @Published var documentText = ""
    @Published var documentSourceDescription = ""
    @Published var documentIsEditable = true
    private(set) var documentStats = DocumentStats.empty
    @Published var isDirty = false
    @Published var editorMode: EditorMode = .split
    @Published var gitSnapshot = GitSnapshot.empty
    @Published var gitChanges: [GitChangedFile] = []
    @Published var selectedGitChangeID: GitChangedFile.ID?
    @Published var selectedGitDiffScope: GitDiffScope = .combined
    @Published var selectedGitDiff = ""
    @Published var selectedGitComparison = GitFileComparison.empty
    @Published var selectedGitComparisonMessage = ""
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
    private var documentLoadTask: Task<Void, Never>?
    private var hotReloadTask: Task<Void, Never>?
    private var latexRenderTask: Task<Void, Never>?
    private var historyLoadTask: Task<Void, Never>?
    private var backlinksTask: Task<Void, Never>?
    private var latexRenderRequestID = UUID()
    private var fileSignature = ""
    private let asyncDocumentLoadByteThreshold = 512_000
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

    var openFileTabs: [VaultFile] {
        openFileTabIDs.compactMap { file(id: $0) }
    }

    var currentReference: ReferenceItem? {
        guard let selectedReferenceID else { return nil }
        return references.first { $0.id == selectedReferenceID }
    }

    var filteredFiles: [VaultFile] {
        let query = searchText.trimmed.lowercased()
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.name.lowercased().contains(query) ||
            $0.relativePath.lowercased().contains(query)
        }
    }

    var filteredReferences: [ReferenceItem] {
        let query = referenceSearchText.trimmed.lowercased()
        guard !query.isEmpty else { return references }
        return references.filter { $0.searchableText.contains(query) }
    }

    var duplicateReferenceKeys: Set<String> {
        ReferenceLibraryStore.duplicateCitationKeys(in: references)
    }

    var selectedFileCanRenderLatex: Bool {
        currentFile?.kind == .latex
    }

    var selectedReferenceValidationMessage: String? {
        guard let reference = currentReference else { return nil }
        if reference.citationKey.trimmed.isEmpty {
            return "Citation key is required."
        }
        if reference.type.trimmed.isEmpty {
            return "BibTeX type is required."
        }
        if isDuplicateReferenceKey(reference.citationKey) {
            return "Duplicate citation key."
        }
        return BibTeXParser.validate(reference.rawBibTeX)
    }

    var availableEditorModes: [EditorMode] {
        selectedFileIsPreviewOnly ? [.preview] : EditorMode.allCases
    }

    var selectedFileIsPDF: Bool {
        currentFile?.isPDF == true
    }

    var selectedFileIsSpreadsheet: Bool {
        currentFile?.isSpreadsheet == true
    }

    var selectedFileIsPreviewOnly: Bool {
        selectedFileIsPDF || selectedFileIsSpreadsheet
    }

    var selectedGitChange: GitChangedFile? {
        guard let selectedGitChangeID else { return nil }
        return gitChanges.first { $0.id == selectedGitChangeID }
    }

    var selectedGitDiffLines: [GitDiffLine] {
        GitDiffLine.parse(selectedGitDiff)
    }

    var stagedGitChangeCount: Int {
        gitChanges.filter(\.hasStagedChanges).count
    }

    var unstagedGitChangeCount: Int {
        gitChanges.filter { $0.hasUnstagedChanges && !$0.isUntracked }.count
    }

    var untrackedGitChangeCount: Int {
        gitChanges.filter(\.isUntracked).count
    }

    var hasStagedGitChanges: Bool {
        gitChanges.contains(where: \.hasStagedChanges)
    }

    func setEditorMode(_ mode: EditorMode) {
        editorMode = selectedFileIsPreviewOnly ? .preview : mode
    }

    func setWorkspaceSection(_ section: WorkspaceSection) {
        workspaceSection = section

        if section == .changes {
            refreshGitStatus()
            if selectedGitChangeID == nil {
                selectGitChange(id: gitChanges.first?.id)
            }
        }
    }

    func previewFile(id fileID: String?) {
        guard let fileID else {
            if openFileTabIDs.isEmpty {
                selectFile(id: nil)
            }
            return
        }
        guard files.contains(where: { $0.id == fileID }) else { return }

        if openFileTabIDs.contains(fileID) {
            selectFile(id: fileID)
            return
        }

        if let previewTabFileID,
           let previewIndex = openFileTabIDs.firstIndex(of: previewTabFileID) {
            openFileTabIDs[previewIndex] = fileID
        } else {
            openFileTabIDs.append(fileID)
        }

        previewTabFileID = fileID
        selectFile(id: fileID)
    }

    func openFile(_ fileID: String) {
        guard files.contains(where: { $0.id == fileID }) else { return }
        if openFileTabIDs.contains(fileID) {
            if previewTabFileID == fileID {
                previewTabFileID = nil
            }
            selectFile(id: fileID)
            return
        }

        if let previewTabFileID,
           let previewIndex = openFileTabIDs.firstIndex(of: previewTabFileID) {
            openFileTabIDs[previewIndex] = fileID
        } else {
            openFileTabIDs.append(fileID)
        }

        previewTabFileID = nil
        selectFile(id: fileID)
    }

    func selectTab(fileID: String) {
        guard openFileTabIDs.contains(fileID) else { return }
        selectFile(id: fileID)
    }

    func pinTab(fileID: String) {
        guard openFileTabIDs.contains(fileID) else { return }
        if previewTabFileID == fileID {
            previewTabFileID = nil
        }
        selectFile(id: fileID)
    }

    func closeCurrentTab() {
        guard let selectedFileID else { return }
        closeTab(fileID: selectedFileID)
    }

    func closeTab(fileID: String) {
        guard let tabIndex = openFileTabIDs.firstIndex(of: fileID) else { return }

        openFileTabIDs.remove(at: tabIndex)
        if previewTabFileID == fileID {
            previewTabFileID = nil
        }

        guard selectedFileID == fileID else { return }

        let nextFileID: String?
        if openFileTabIDs.indices.contains(tabIndex) {
            nextFileID = openFileTabIDs[tabIndex]
        } else {
            nextFileID = openFileTabIDs.last
        }

        selectFile(id: nextFileID)
    }

    func closeOtherTabs(keeping fileID: String) {
        guard openFileTabIDs.contains(fileID) else { return }
        openFileTabIDs = [fileID]
        if previewTabFileID != fileID {
            previewTabFileID = nil
        }
        selectFile(id: fileID)
    }

    func closeAllTabs() {
        openFileTabIDs = []
        previewTabFileID = nil
        selectFile(id: nil)
    }

    func file(id fileID: String) -> VaultFile? {
        files.first { $0.id == fileID }
    }

    func fileID(for url: URL) -> String? {
        let targetPath = Self.normalizedFilePath(url)
        return files.first { Self.normalizedFilePath($0.url) == targetPath }?.id
    }

    func fileID(forLatexSourceLocation location: LatexSourceLocation) -> String? {
        if let fileID = fileID(for: location.inputURL) {
            return fileID
        }

        let inputPath = location.inputPath.replacingOccurrences(of: "\\", with: "/")
        let relativeCandidates = Self.latexSourceRelativePathCandidates(from: inputPath)
        for candidate in relativeCandidates {
            if let file = files.first(where: { $0.relativePath == candidate }) {
                return file.id
            }
        }

        let standardizedPath = location.inputURL.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
        for file in files where standardizedPath.hasSuffix("/" + file.relativePath) {
            return file.id
        }

        let matchingByName = files.filter { $0.name == location.inputURL.lastPathComponent }
        return matchingByName.count == 1 ? matchingByName[0].id : nil
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
        openFileTabIDs = []
        previewTabFileID = nil
        UserDefaults.standard.set(url.path, forKey: "lastVaultPath")
        ensureVaultConfiguration(in: url)
        reloadFiles()
        loadReferenceLibrary()

        previewFile(id: preferredInitialFileID)

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
            openFile(relPath)
            renderLatexForCurrentFile()
        } catch {
            statusMessage = "Imported, but couldn't find a LaTeX root (\(error.localizedDescription))."
        }
    }

    func reloadFiles() {
        guard let vaultURL else { return }
        setContents(Self.loadContents(in: vaultURL))
    }

    nonisolated private static func loadContents(in vaultURL: URL) -> VaultContents {
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
        if let id {
            guard files.contains(where: { $0.id == id }) else { return }
            if !openFileTabIDs.contains(id) {
                openFileTabIDs.append(id)
                previewTabFileID = id
            }
        }

        if isDirty, documentIsEditable {
            saveDocument(renderLatexAfterSave: false)
        }

        documentLoadTask?.cancel()
        historyLoadTask?.cancel()
        backlinksTask?.cancel()
        selectedFileID = id
        selectedVersion = nil
        selectedVersionDiff = ""
        gitHistory = []
        backlinks = []

        guard let file = currentFile else {
            documentStats = .empty
            documentText = ""
            originalDocumentText = ""
            documentSourceDescription = ""
            documentIsEditable = true
            latexRenderState = .idle
            setEditorMode(editorMode)
            return
        }

        setEditorMode(editorMode)
        loadDocument(file, statusMessage: "Loaded \(file.relativePath)")
    }

    private func loadDocument(_ file: VaultFile, statusMessage message: String) {
        if file.isPDF || file.isSpreadsheet {
            editorMode = .preview
        }

        if shouldLoadDocumentAsynchronously(file) {
            loadDocumentAsynchronously(file, statusMessage: message)
            return
        }

        switch Self.prepareDocument(at: file.url) {
        case let .success(prepared):
            applyLoadedDocument(prepared, for: file, statusMessage: message)
        case let .failure(message):
            applyDocumentLoadFailure(message)
        }
    }

    private func shouldLoadDocumentAsynchronously(_ file: VaultFile) -> Bool {
        file.byteCount >= asyncDocumentLoadByteThreshold ||
            file.kind == .richText ||
            file.kind == .document ||
            file.kind == .binary
    }

    private func loadDocumentAsynchronously(_ file: VaultFile, statusMessage message: String) {
        documentLoadTask?.cancel()
        documentStats = .empty
        documentText = ""
        originalDocumentText = ""
        documentSourceDescription = "Loading document"
        documentIsEditable = false
        isDirty = false
        statusMessage = "Loading \(file.relativePath)"

        let selectedFileID = file.id
        documentLoadTask = Task { [weak self, file, selectedFileID, message] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.prepareDocument(at: file.url)
            }.value

            guard let self, !Task.isCancelled, self.selectedFileID == selectedFileID else { return }
            switch result {
            case let .success(prepared):
                self.applyLoadedDocument(prepared, for: file, statusMessage: message)
            case let .failure(message):
                self.applyDocumentLoadFailure(message)
            }
        }
    }

    nonisolated private static func prepareDocument(at url: URL) -> DocumentLoadResult {
        do {
            let loaded = try FileTextLoader.load(url: url)
            return .success(PreparedDocument(loaded: loaded, stats: DocumentStats(text: loaded.text)))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func applyLoadedDocument(_ prepared: PreparedDocument, for file: VaultFile, statusMessage message: String) {
        documentStats = prepared.stats
        documentText = prepared.loaded.text
        originalDocumentText = prepared.loaded.text
        documentSourceDescription = prepared.loaded.sourceDescription
        documentIsEditable = prepared.loaded.isEditable
        if file.kind != .latex {
            latexRenderState = .idle
        }
        isDirty = false
        statusMessage = message
        refreshHistoryForSelectedFile()
        rebuildBacklinks(for: file)
    }

    private func applyDocumentLoadFailure(_ message: String) {
        documentStats = .empty
        documentText = ""
        originalDocumentText = ""
        documentSourceDescription = "Could not load this file"
        documentIsEditable = false
        isDirty = false
        statusMessage = message
    }

    private func setContents(_ contents: VaultContents) {
        files = contents.files
        folders = contents.folders
        fileSignature = Self.fileSignature(files: contents.files, folders: contents.folders)
        pruneInvalidSelection()
    }

    private func pruneInvalidSelection() {
        let validFileIDs = Set(files.map(\.id))
        openFileTabIDs = openFileTabIDs.filter { validFileIDs.contains($0) }.uniqued()
        if let previewTabFileID, !openFileTabIDs.contains(previewTabFileID) {
            self.previewTabFileID = nil
        }

        guard let selectedFileID else { return }
        if !validFileIDs.contains(selectedFileID) {
            self.selectedFileID = nil
        }
    }

    nonisolated private static func fileSignature(files: [VaultFile], folders: [VaultFolder]) -> String {
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

        guard hotReloadEnabled, let vaultURL else { return }

        let interval = hotReloadIntervalNanoseconds
        hotReloadTask = Task { [weak self, vaultURL] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                let loadedContents = await Task.detached(priority: .utility) {
                    Self.loadContents(in: vaultURL)
                }.value

                guard !Task.isCancelled else { return }
                self?.applyHotReloadContents(loadedContents, for: vaultURL)
            }
        }
    }

    private func applyHotReloadContents(_ loadedContents: VaultContents, for loadedVaultURL: URL) {
        guard hotReloadEnabled,
              let vaultURL,
              vaultURL.standardizedFileURL.path == loadedVaultURL.standardizedFileURL.path
        else {
            return
        }

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
            selectFile(id: openFileTabIDs.first ?? preferredInitialFileID)
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
        pinSelectedPreviewTabIfNeeded()
        documentStats = DocumentStats(text: text)
        documentText = text
        isDirty = documentIsEditable && documentText != originalDocumentText
    }

    private func pinSelectedPreviewTabIfNeeded() {
        guard previewTabFileID == selectedFileID else { return }
        previewTabFileID = nil
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
                openFile(relativePath)
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

    func importFiles(_ sourceURLs: [URL], into relativeFolderPath: String?) {
        let sourceURLs = sourceURLs.uniquedByStandardizedPath()
        guard !sourceURLs.isEmpty else { return }
        guard let vaultURL else {
            statusMessage = "Choose a vault before importing files."
            return
        }

        do {
            let directoryURL = try targetDirectory(relativeFolderPath: relativeFolderPath)
            statusMessage = sourceURLs.count == 1
                ? "Importing \(sourceURLs[0].lastPathComponent)..."
                : "Importing \(sourceURLs.count) items..."

            Task { [weak self, sourceURLs, directoryURL, vaultURL] in
                let result = await Task.detached(priority: .userInitiated) {
                    Result {
                        try VaultFileImportService.copyItems(
                            from: sourceURLs,
                            into: directoryURL,
                            vaultURL: vaultURL
                        )
                    }
                }.value

                await MainActor.run {
                    guard let self else { return }
                    switch result {
                    case let .success(summary):
                        self.reloadFiles()
                        self.selectFirstImportedFile(from: summary.importedRelativePaths)
                        self.refreshGitStatus()
                        self.statusMessage = self.importStatusMessage(for: summary)
                    case let .failure(error):
                        self.reloadFiles()
                        self.refreshGitStatus()
                        self.statusMessage = error.localizedDescription
                    }
                }
            }
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
            let deletedFileID = file.id
            let deletedTabIndex = openFileTabIDs.firstIndex(of: deletedFileID)
            reloadFiles()
            if let deletedTabIndex {
                if openFileTabIDs.indices.contains(deletedTabIndex) {
                    selectFile(id: openFileTabIDs[deletedTabIndex])
                } else {
                    selectFile(id: openFileTabIDs.last)
                }
            } else if selectedFileID == deletedFileID {
                selectFile(id: openFileTabIDs.first)
            }
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
        let pendingProject = try? LatexRenderService.resolveProject(vaultURL: vaultURL, selectedFileURL: file.url)
        let pendingRootRelativePath = pendingProject?.rootRelativePath ?? selectedRelativePath
        let pendingIncludedFiles = pendingProject?.includedFiles ?? []

        latexRenderState = LatexRenderState(
            phase: .rendering,
            rootRelativePath: pendingRootRelativePath,
            pdfURL: nil,
            includedFiles: pendingIncludedFiles,
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
                        includedFiles: renderResult.project.includedFiles,
                        log: renderResult.log,
                        message: "Rendered \(renderResult.project.outputPDFURL.lastPathComponent)",
                        renderedAt: renderResult.renderedAt
                    )
                    self.statusMessage = "Rendered \(renderResult.project.rootRelativePath)"
                case let .failure(error):
                    self.applyLatexRenderFailure(
                        error,
                        rootRelativePath: pendingRootRelativePath,
                        includedFiles: pendingIncludedFiles
                    )
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
            gitChanges = []
            selectedGitChangeID = nil
            selectedGitDiffScope = .combined
            selectedGitDiff = ""
            selectedGitComparison = .empty
            selectedGitComparisonMessage = ""
            return
        }

        do {
            gitSnapshot = try gitService.snapshot(for: vaultURL)
            refreshGitChanges()
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

    func commitStagedGitChanges() {
        guard let vaultURL else { return }
        let message = commitMessage.trimmed.isEmpty ? "Update notes" : commitMessage.trimmed

        do {
            statusMessage = try gitService.commitStaged(vaultURL: vaultURL, message: message).trimmed
            refreshGitStatus()
        } catch {
            statusMessage = error.localizedDescription
            refreshGitStatus()
        }
    }

    func refreshHistoryForSelectedFile() {
        guard let vaultURL, let file = currentFile, gitSnapshot.isRepository else {
            historyLoadTask?.cancel()
            gitHistory = []
            selectedVersionDiff = ""
            return
        }

        historyLoadTask?.cancel()
        selectedVersionDiff = ""

        let selectedFileID = file.id
        let relativePath = file.relativePath
        historyLoadTask = Task { [weak self, vaultURL, selectedFileID, relativePath] in
            let result = await Task.detached(priority: .utility) {
                do {
                    return HistoryLoadResult.success(
                        try GitService().history(for: relativePath, in: vaultURL)
                    )
                } catch {
                    return HistoryLoadResult.failure(error.localizedDescription)
                }
            }.value

            guard let self, !Task.isCancelled, self.selectedFileID == selectedFileID else { return }

            switch result {
            case let .success(history):
                self.gitHistory = history
            case let .failure(message):
                self.gitHistory = []
                self.statusMessage = message
            }
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

    func showGitChanges() {
        workspaceSection = .changes
        refreshGitStatus()
        if selectedGitChangeID == nil {
            selectGitChange(id: gitChanges.first?.id)
        }
    }

    func selectGitChange(id: GitChangedFile.ID?) {
        selectedGitChangeID = id
        guard let change = selectedGitChange else {
            selectedGitDiff = ""
            selectedGitComparison = .empty
            selectedGitComparisonMessage = ""
            return
        }

        if !change.supportsDiffScope(selectedGitDiffScope) {
            selectedGitDiffScope = .combined
        }

        loadSelectedGitDiff(for: change)
    }

    func selectGitDiffScope(_ scope: GitDiffScope) {
        selectedGitDiffScope = scope
        guard let change = selectedGitChange else {
            selectedGitDiff = ""
            selectedGitComparison = .empty
            selectedGitComparisonMessage = ""
            return
        }

        loadSelectedGitDiff(for: change)
    }

    func stageSelectedGitChange() {
        guard let vaultURL, let change = selectedGitChange else { return }

        if isDirty {
            saveDocument()
        }

        do {
            try gitService.stage(change, in: vaultURL)
            statusMessage = "Staged \(change.displayName)"
            refreshGitStatus()
        } catch {
            statusMessage = error.localizedDescription
            refreshGitStatus()
        }
    }

    func unstageSelectedGitChange() {
        guard let vaultURL, let change = selectedGitChange else { return }

        do {
            try gitService.unstage(change, in: vaultURL)
            statusMessage = "Unstaged \(change.displayName)"
            refreshGitStatus()
        } catch {
            statusMessage = error.localizedDescription
            refreshGitStatus()
        }
    }

    func discardSelectedGitChange() {
        guard let vaultURL, let change = selectedGitChange else { return }
        let affectedPaths = Set(change.affectedPaths)

        do {
            try gitService.discard(change, in: vaultURL)
            refreshAfterGitWorkingTreeMutation(affectedPaths: affectedPaths)
            statusMessage = "Discarded \(change.displayName)"
        } catch {
            statusMessage = error.localizedDescription
            refreshGitStatus()
        }
    }

    func stageAllGitChanges() {
        guard let vaultURL else { return }

        if isDirty {
            saveDocument()
        }

        do {
            for change in gitChanges where change.canStage {
                try gitService.stage(change, in: vaultURL)
            }
            statusMessage = "Staged all changes"
            refreshGitStatus()
        } catch {
            statusMessage = error.localizedDescription
            refreshGitStatus()
        }
    }

    func unstageAllGitChanges() {
        guard let vaultURL else { return }

        do {
            for change in gitChanges where change.canUnstage {
                try gitService.unstage(change, in: vaultURL)
            }
            statusMessage = "Unstaged all changes"
            refreshGitStatus()
        } catch {
            statusMessage = error.localizedDescription
            refreshGitStatus()
        }
    }

    func discardAllGitChanges() {
        guard let vaultURL else { return }
        let affectedPaths = Set(gitChanges.flatMap(\.affectedPaths))

        do {
            for change in gitChanges {
                try gitService.discard(change, in: vaultURL)
            }
            refreshAfterGitWorkingTreeMutation(affectedPaths: affectedPaths)
            statusMessage = "Discarded all changes"
        } catch {
            statusMessage = error.localizedDescription
            refreshGitStatus()
        }
    }

    private func refreshGitChanges() {
        guard let vaultURL, gitSnapshot.isRepository else {
            gitChanges = []
            selectedGitChangeID = nil
            selectedGitDiffScope = .combined
            selectedGitDiff = ""
            selectedGitComparison = .empty
            selectedGitComparisonMessage = ""
            return
        }

        do {
            let previousSelection = selectedGitChangeID
            gitChanges = try gitService.changedFiles(in: vaultURL)

            if let previousSelection, gitChanges.contains(where: { $0.id == previousSelection }) {
                selectedGitChangeID = previousSelection
            } else {
                selectedGitChangeID = gitChanges.first?.id
            }

            if let selectedGitChange {
                if !selectedGitChange.supportsDiffScope(selectedGitDiffScope) {
                    selectedGitDiffScope = .combined
                }
                loadSelectedGitDiff(for: selectedGitChange)
            } else {
                selectedGitDiff = ""
                selectedGitComparison = .empty
                selectedGitComparisonMessage = ""
            }
        } catch {
            gitChanges = []
            selectedGitChangeID = nil
            selectedGitDiff = ""
            selectedGitComparison = .empty
            selectedGitComparisonMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    private func loadSelectedGitDiff(for change: GitChangedFile) {
        guard let vaultURL else { return }

        do {
            selectedGitDiff = try gitService.diff(for: change, scope: selectedGitDiffScope, in: vaultURL)
        } catch {
            selectedGitDiff = error.localizedDescription
        }

        do {
            selectedGitComparison = try gitService.comparison(for: change, scope: selectedGitDiffScope, in: vaultURL)
            selectedGitComparisonMessage = ""
        } catch {
            selectedGitComparison = .empty
            selectedGitComparisonMessage = error.localizedDescription
        }
    }

    private func refreshAfterGitWorkingTreeMutation(affectedPaths: Set<String>) {
        let previousSelection = selectedFileID
        reloadFiles()

        if let previousSelection,
           affectedPaths.contains(previousSelection),
           let file = file(id: previousSelection) {
            loadDocument(file, statusMessage: "Reloaded \(file.relativePath)")
        }

        refreshGitStatus()
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

    func selectReference(id: ReferenceItem.ID?) {
        selectedReferenceID = id
        workspaceSection = .references
    }

    func isDuplicateReferenceKey(_ citationKey: String) -> Bool {
        duplicateReferenceKeys.contains(citationKey.trimmed.lowercased())
    }

    func referencePDFURL(for reference: ReferenceItem) -> URL? {
        guard let vaultURL, let pdfRelativePath = reference.pdfRelativePath else { return nil }
        return ReferenceLibraryStore.absoluteURL(for: pdfRelativePath, in: vaultURL)
    }

    func referencePDFExists(_ reference: ReferenceItem) -> Bool {
        guard let pdfURL = referencePDFURL(for: reference) else { return false }
        return FileManager.default.fileExists(atPath: pdfURL.path)
    }

    func importBibTeXFileRequested() {
        guard vaultURL != nil else {
            chooseVault()
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "bib") ?? .plainText]
        panel.message = "Choose a .bib file to import."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            importBibTeX(text)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func pasteBibTeXRequested() {
        guard vaultURL != nil else {
            chooseVault()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Paste BibTeX"
        alert.informativeText = "Paste one or more BibTeX entries to import into the reference library."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = NSPasteboard.general.string(forType: .string) ?? ""
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        importBibTeX(textView.string)
    }

    func importBibTeX(_ text: String) {
        guard let vaultURL else { return }

        do {
            let parsedEntries = try BibTeXParser.parseEntries(text)
            let importedReferences = parsedEntries.map(BibTeXSerializer.reference)
            references.append(contentsOf: importedReferences)
            if selectedReferenceID == nil {
                selectedReferenceID = importedReferences.first?.id
            }
            if let firstImportedID = importedReferences.first?.id {
                selectedReferenceID = firstImportedID
            }
            try ReferenceLibraryStore.save(references, in: vaultURL)
            workspaceSection = .references
            statusMessage = "Imported \(importedReferences.count) reference\(importedReferences.count == 1 ? "" : "s")"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateSelectedReferenceCitationKey(_ citationKey: String) {
        guard let selectedReferenceID else { return }
        let nextKey = citationKey.trimmed

        updateReference(id: selectedReferenceID) { reference in
            let previousKey = reference.citationKey
            reference.citationKey = nextKey
            reference.rawBibTeX = BibTeXSerializer.serialize(reference)
            if !nextKey.isEmpty {
                renamePDFForCitationKeyChange(reference: &reference, previousKey: previousKey, nextKey: nextKey)
            }
        }
    }

    func updateSelectedReferenceType(_ type: String) {
        guard let selectedReferenceID else { return }
        let nextType = type.trimmed

        updateReference(id: selectedReferenceID) { reference in
            reference.type = nextType.lowercased()
            reference.rawBibTeX = BibTeXSerializer.serialize(reference)
        }
    }

    func updateSelectedReferenceField(_ field: String, value: String) {
        guard let selectedReferenceID else { return }
        updateReference(id: selectedReferenceID) { reference in
            reference.setField(field, value: value)
            reference.rawBibTeX = BibTeXSerializer.serialize(reference)
        }
    }

    func updateSelectedReferenceRawBibTeX(_ rawBibTeX: String) {
        guard let selectedReferenceID else { return }
        updateReference(id: selectedReferenceID, saveStatus: nil) { reference in
            reference.rawBibTeX = rawBibTeX
            if let parsed = try? BibTeXParser.parseEntries(rawBibTeX).first {
                reference.citationKey = parsed.citationKey
                reference.type = parsed.type
                reference.replaceFields(parsed.fields)
            }
        }

        if let validationMessage = selectedReferenceValidationMessage {
            statusMessage = validationMessage
        } else {
            statusMessage = "Updated BibTeX"
        }
    }

    func updateSelectedReferenceReaderState(_ readerState: PDFReaderState) {
        guard let selectedReferenceID else { return }
        updateReference(id: selectedReferenceID, saveStatus: nil) { reference in
            reference.readerState = readerState
        }
    }

    func attachPDFToSelectedReferenceRequested() {
        guard let selectedReferenceID else {
            statusMessage = "Select a reference before attaching a PDF."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        panel.message = "Choose a PDF to attach to this reference."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        attachPDF(url, to: selectedReferenceID)
    }

    func attachPDF(_ sourceURL: URL, to referenceID: ReferenceItem.ID) {
        guard let vaultURL else { return }
        guard let reference = references.first(where: { $0.id == referenceID }) else { return }

        do {
            let pdfDirectory = ReferenceLibraryStore.pdfDirectoryURL(in: vaultURL)
            try FileManager.default.createDirectory(at: pdfDirectory, withIntermediateDirectories: true)

            let existingAttachmentIsShared = reference.pdfRelativePath.map { existingPath in
                references.contains { $0.id != referenceID && $0.pdfRelativePath == existingPath }
            } ?? false
            let relativePath = if let existingPath = reference.pdfRelativePath, !existingAttachmentIsShared {
                existingPath
            } else {
                ReferenceLibraryStore.uniquePDFRelativePath(
                    for: reference.citationKey,
                    in: vaultURL
                )
            }
            let destinationURL = ReferenceLibraryStore.absoluteURL(for: relativePath, in: vaultURL)
            if sourceURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }

            updateReference(id: referenceID, saveStatus: "Attached \(destinationURL.lastPathComponent)") { reference in
                reference.pdfRelativePath = relativePath
            }
            reloadFiles()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openSelectedReferencePDF() {
        guard let reference = currentReference, let pdfURL = referencePDFURL(for: reference) else { return }
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            statusMessage = "Attached PDF is missing."
            return
        }
        NSWorkspace.shared.open(pdfURL)
    }

    func revealSelectedReferencePDF() {
        guard let reference = currentReference, let pdfURL = referencePDFURL(for: reference) else { return }
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            statusMessage = "Attached PDF is missing."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([pdfURL])
    }

    func insertCitationRequested() {
        guard !references.isEmpty else {
            statusMessage = "Import a reference before inserting citations."
            return
        }
        showingCitationPicker = true
    }

    func insertSelectedCitation() {
        guard let reference = currentReference else {
            insertCitationRequested()
            return
        }
        insertCitation(reference)
    }

    func insertCitation(_ reference: ReferenceItem) {
        let citation = "[@\(reference.citationKey)]"
        if TextInsertionService.insert(citation) {
            statusMessage = "Inserted \(citation)"
            return
        }

        guard currentFile != nil, documentIsEditable else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(citation, forType: .string)
            statusMessage = "Copied \(citation) to Clipboard"
            return
        }

        let separator = documentText.isEmpty || documentText.last?.isWhitespace == true ? "" : " "
        setDocumentText(documentText + separator + citation)
        statusMessage = "Inserted \(citation)"
    }

    func exportAllReferencesRequested() {
        exportReferences(references, defaultFileName: "references.bib")
    }

    func exportSelectedReferencesRequested() {
        guard let reference = currentReference else {
            statusMessage = "Select a reference to export."
            return
        }
        exportReferences([reference], defaultFileName: "\(reference.citationKey).bib")
    }

    func copySelectedBibTeXToClipboard() {
        guard let reference = currentReference else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BibTeXSerializer.exportEntry(reference), forType: .string)
        statusMessage = "Copied BibTeX for \(reference.citationKey)"
    }

    private func loadReferenceLibrary() {
        guard let vaultURL else {
            references = []
            selectedReferenceID = nil
            return
        }

        do {
            references = try ReferenceLibraryStore.load(in: vaultURL)
            if let selectedReferenceID, references.contains(where: { $0.id == selectedReferenceID }) {
                return
            }
            selectedReferenceID = references.first?.id
        } catch {
            references = []
            selectedReferenceID = nil
            statusMessage = error.localizedDescription
        }
    }

    private func updateReference(
        id: ReferenceItem.ID,
        saveStatus: String? = "Updated reference",
        mutate: (inout ReferenceItem) -> Void
    ) {
        guard let vaultURL else { return }
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }

        mutate(&references[index])
        do {
            try ReferenceLibraryStore.save(references, in: vaultURL)
            if let saveStatus {
                statusMessage = saveStatus
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func renamePDFForCitationKeyChange(
        reference: inout ReferenceItem,
        previousKey: String,
        nextKey: String
    ) {
        guard let vaultURL, let pdfRelativePath = reference.pdfRelativePath else { return }

        let previousStem = ReferenceLibraryStore.safePDFFileStem(for: previousKey)
        let expectedPreviousPath = "\(ReferenceLibraryStore.pdfDirectoryRelativePath)/\(previousStem).pdf"
        guard pdfRelativePath == expectedPreviousPath else { return }

        let sourceURL = ReferenceLibraryStore.absoluteURL(for: pdfRelativePath, in: vaultURL)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        let nextStem = ReferenceLibraryStore.safePDFFileStem(for: nextKey)
        let nextRelativePath = "\(ReferenceLibraryStore.pdfDirectoryRelativePath)/\(nextStem).pdf"
        let destinationURL = ReferenceLibraryStore.absoluteURL(for: nextRelativePath, in: vaultURL)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            reference.pdfRelativePath = nextRelativePath
            reloadFiles()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func exportReferences(_ referencesToExport: [ReferenceItem], defaultFileName: String) {
        guard !referencesToExport.isEmpty else {
            statusMessage = "There are no references to export."
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "bib") ?? .plainText]
        panel.nameFieldStringValue = defaultFileName
        panel.message = "Choose where to export the BibTeX file."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try BibTeXSerializer.export(referencesToExport).write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Exported \(referencesToExport.count) reference\(referencesToExport.count == 1 ? "" : "s")"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func selectFirstImportedFile(from relativePaths: [String]) {
        guard let firstFileID = relativePaths.first(where: { path in
            files.contains { $0.id == path }
        }) else {
            return
        }
        openFile(firstFileID)
    }

    private func importStatusMessage(for summary: VaultFileImportSummary) -> String {
        if summary.importedItemCount == 1, let relativePath = summary.importedRelativePaths.first {
            return "Imported \(relativePath)"
        }
        return "Imported \(summary.importedItemCount) items"
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
            let previousOpenFileTabIDs = openFileTabIDs
            let previousPreviewTabFileID = previewTabFileID
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
            restoreTabsAfterRename(
                previousOpenFileTabIDs: previousOpenFileTabIDs,
                previousPreviewTabFileID: previousPreviewTabFileID,
                oldPath: currentRelativePath,
                newPath: newRelativePath,
                isDirectory: isDirectory
            )
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

    private func restoreTabsAfterRename(
        previousOpenFileTabIDs: [String],
        previousPreviewTabFileID: String?,
        oldPath: String,
        newPath: String,
        isDirectory: Bool
    ) {
        let validFileIDs = Set(files.map(\.id))
        openFileTabIDs = previousOpenFileTabIDs
            .map { renamedFileID($0, oldPath: oldPath, newPath: newPath, isDirectory: isDirectory) }
            .filter { validFileIDs.contains($0) }
            .uniqued()

        if let previousPreviewTabFileID {
            let nextPreviewTabFileID = renamedFileID(
                previousPreviewTabFileID,
                oldPath: oldPath,
                newPath: newPath,
                isDirectory: isDirectory
            )
            previewTabFileID = openFileTabIDs.contains(nextPreviewTabFileID) ? nextPreviewTabFileID : nil
        } else {
            previewTabFileID = nil
        }
    }

    private func renamedFileID(_ fileID: String, oldPath: String, newPath: String, isDirectory: Bool) -> String {
        if isDirectory, fileID.hasPrefix(oldPath + "/") {
            return newPath + String(fileID.dropFirst(oldPath.count))
        }
        if !isDirectory, fileID == oldPath {
            return newPath
        }
        return fileID
    }

    private func relativePath(for url: URL) -> String? {
        guard let vaultURL else { return nil }
        let vaultPath = vaultURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(vaultPath + "/") else { return nil }
        return String(path.dropFirst(vaultPath.count + 1))
    }

    nonisolated private static func normalizedFilePath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    nonisolated private static func latexSourceRelativePathCandidates(from inputPath: String) -> [String] {
        let strippedPath = inputPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
        guard !strippedPath.isEmpty else { return [] }

        let normalizedPath = strippedPath.hasPrefix("./")
            ? String(strippedPath.dropFirst(2))
            : strippedPath
        let pathExtension = URL(fileURLWithPath: normalizedPath).pathExtension
        let pathWithExtension = pathExtension.isEmpty ? normalizedPath + ".tex" : normalizedPath

        return [normalizedPath, pathWithExtension].uniqued()
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
        backlinksTask?.cancel()
        let filesSnapshot = files
        backlinksTask = Task { [weak self, file, filesSnapshot] in
            let matches = await Task.detached(priority: .utility) {
                Self.findBacklinks(for: file, in: filesSnapshot)
            }.value

            guard let self, !Task.isCancelled, self.selectedFileID == file.id else { return }
            self.backlinks = matches
        }
    }

    nonisolated private static func findBacklinks(for file: VaultFile, in files: [VaultFile]) -> [VaultFile] {
        let titleToken = "[[\(file.titleWithoutExtension)]]"
        let pathToken = file.relativePath
        var matches: [VaultFile] = []

        for candidate in files where candidate.id != file.id {
            guard candidate.kind.canContainBacklinks,
                  candidate.byteCount < 2_000_000,
                  let text = try? String(contentsOf: candidate.url, encoding: .utf8)
            else {
                continue
            }
            if text.contains(titleToken) || text.contains(pathToken) {
                matches.append(candidate)
            }
        }

        return matches
    }

    private var preferredInitialFileID: String? {
        files.first(where: { $0.kind == .markdown })?.id ??
            files.first(where: { $0.name.lowercased() == "main.tex" })?.id ??
            files.first(where: { $0.fileExtension.lowercased() == "tex" })?.id ??
            files.first?.id
    }

    private func applyLatexRenderFailure(
        _ error: Error,
        rootRelativePath: String,
        includedFiles: [LatexIncludedFile]
    ) {
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
            rootRelativePath: rootRelativePath,
            pdfURL: nil,
            includedFiles: includedFiles,
            log: message,
            message: message.components(separatedBy: .newlines).first ?? "LaTeX build failed.",
            renderedAt: nil
        )
        statusMessage = "LaTeX build failed"
    }
}
