import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var confirmDelete: Bool
    @Binding var sidebarVisible: Bool
    @State private var expandedFolders: Set<String> = []
    @State private var renamingNodeID: String?
    @State private var renameDraft = ""
    @State private var isRootFileDropTargeted = false
    @State private var refreshRotation = 0.0

    private var isSearching: Bool {
        !store.searchText.trimmed.isEmpty
    }

    private var treeNodes: [FileTreeNode] {
        FileTreeNode.build(files: store.filteredFiles, folders: visibleFolders)
    }

    private var visibleFolders: [VaultFolder] {
        let query = store.searchText.trimmed.lowercased()
        guard !query.isEmpty else { return store.folders }

        let ancestorPaths = Set(store.filteredFiles.flatMap { FileTreeNode.ancestorFolderPaths(for: $0.relativePath) })
        return store.folders.filter { folder in
            ancestorPaths.contains(folder.relativePath) ||
                folder.name.lowercased().contains(query) ||
                folder.relativePath.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            Divider()

            sectionPicker

            sectionContent

            statusFooter
        }
        .onAppear {
            expandAncestors(of: store.selectedFileID)
        }
        .onChange(of: store.selectedFileID) { _, fileID in
            expandAncestors(of: fileID)
        }
        .onChange(of: store.searchText) { _, _ in
            if isSearching {
                withAnimation(sidebarAnimation) {
                    expandedFolders.formUnion(FileTreeNode.folderPaths(in: treeNodes))
                }
            }
        }
    }

    private var sectionContent: some View {
        ZStack {
            switch store.workspaceSection {
            case .files:
                fileList
                    .transition(sectionTransition)
            case .changes:
                changesList
                    .transition(sectionTransition)
            case .references:
                referenceList
                    .transition(sectionTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(sidebarAnimation, value: store.workspaceSection)
    }

    private var selectionBinding: Binding<String?> {
        Binding {
            store.selectedFileID
        } set: { newValue in
            store.previewFile(id: newValue)
        }
    }

    private var referenceSelectionBinding: Binding<ReferenceItem.ID?> {
        Binding {
            store.selectedReferenceID
        } set: { newValue in
            store.selectReference(id: newValue)
        }
    }

    private var gitSelectionBinding: Binding<GitChangedFile.ID?> {
        Binding {
            store.selectedGitChangeID
        } set: { newValue in
            store.selectGitChange(id: newValue)
        }
    }

    private var sectionPicker: some View {
        Picker("Library Section", selection: workspaceSectionBinding) {
            ForEach(WorkspaceSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var workspaceSectionBinding: Binding<WorkspaceSection> {
        Binding {
            store.workspaceSection
        } set: { newValue in
            withAnimation(sidebarAnimation) {
                store.setWorkspaceSection(newValue)
            }
        }
    }

    private var fileList: some View {
        List(selection: selectionBinding) {
            if treeNodes.isEmpty {
                emptyTreeRow
            } else {
                ForEach(treeNodes) { node in
                    FileTreeRow(
                        node: node,
                        expandedFolders: $expandedFolders,
                        renamingNodeID: $renamingNodeID,
                        renameDraft: $renameDraft,
                        confirmDelete: $confirmDelete,
                        forceExpanded: isSearching
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .font(.system(size: 12))
        .environment(\.defaultMinListRowHeight, FileTreeMetrics.rowHeight)
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search files")
        .contextMenu {
            creationMenu(folderPath: nil)
        }
        .background(isRootFileDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear, in: Rectangle())
        .overlay {
            FileDropTargetOverlay(isTargeted: isRootFileDropTargeted)
        }
        .animation(sidebarAnimation, value: isRootFileDropTargeted)
        .animation(sidebarAnimation, value: expandedFolders)
        .animation(sidebarAnimation, value: treeNodes.map(\.id))
        .onDrop(of: [UTType.fileURL], isTargeted: $isRootFileDropTargeted) { providers in
            handleFileDrop(providers, into: nil)
        }
    }

    private var referenceList: some View {
        List(selection: referenceSelectionBinding) {
            if store.filteredReferences.isEmpty {
                ReferenceEmptyRow()
            } else {
                ForEach(store.filteredReferences) { reference in
                    ReferenceSidebarRow(
                        reference: reference,
                        isDuplicate: store.isDuplicateReferenceKey(reference.citationKey),
                        pdfExists: store.referencePDFExists(reference)
                    )
                    .sidebarRowMotion()
                    .tag(reference.id)
                    .contextMenu {
                        Button {
                            store.selectReference(id: reference.id)
                            store.insertSelectedCitation()
                        } label: {
                            Label("Insert Citation", systemImage: "text.badge.plus")
                        }
                        Button {
                            store.selectReference(id: reference.id)
                            store.copySelectedBibTeXToClipboard()
                        } label: {
                            Label("Copy BibTeX", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button {
                            store.selectReference(id: reference.id)
                            store.attachPDFToSelectedReferenceRequested()
                        } label: {
                            Label("Attach PDF", systemImage: "paperclip")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .font(.system(size: 13))
        .environment(\.defaultMinListRowHeight, 34)
        .searchable(text: $store.referenceSearchText, placement: .sidebar, prompt: "Search references")
        .contextMenu {
            Button {
                store.importBibTeXFileRequested()
            } label: {
                Label("Import .bib", systemImage: "square.and.arrow.down")
            }
            Button {
                store.pasteBibTeXRequested()
            } label: {
                Label("Paste BibTeX", systemImage: "doc.on.clipboard")
            }
            Divider()
            Button {
                store.exportAllReferencesRequested()
            } label: {
                Label("Export All", systemImage: "square.and.arrow.up")
            }
            .disabled(store.references.isEmpty)
        }
        .animation(sidebarAnimation, value: store.filteredReferences.map(\.id))
    }

    private var changesList: some View {
        List(selection: gitSelectionBinding) {
            if !store.gitSnapshot.isRepository {
                GitSidebarEmptyRow(
                    title: "No Repository",
                    message: "Initialize git to inspect file changes.",
                    systemImage: "nosign"
                )
            } else if store.gitChanges.isEmpty {
                GitSidebarEmptyRow(
                    title: "Working Tree Clean",
                    message: "No changed files.",
                    systemImage: "checkmark.circle"
                )
            } else {
                Section("Changed Files") {
                    ForEach(store.gitChanges) { change in
                        GitSidebarChangeRow(change: change)
                            .tag(change.id)
                            .contextMenu {
                                Button {
                                    store.selectGitChange(id: change.id)
                                    store.stageSelectedGitChange()
                                } label: {
                                    Label("Stage File", systemImage: "plus.circle")
                                }
                                .disabled(!change.canStage)

                                Button {
                                    store.selectGitChange(id: change.id)
                                    store.unstageSelectedGitChange()
                                } label: {
                                    Label("Unstage File", systemImage: "minus.circle")
                                }
                                .disabled(!change.canUnstage)

                                if store.files.contains(where: { $0.id == change.path }) {
                                    Divider()
                                    Button {
                                        store.openFile(change.path)
                                    } label: {
                                        Label("Open File", systemImage: "doc.text")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .font(.system(size: 12))
        .environment(\.defaultMinListRowHeight, 42)
        .animation(sidebarAnimation, value: store.gitChanges.map(\.id))
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BrandLogoView(size: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(sidebarTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)

                    Text(sidebarSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 4) {
                    headerButton("Hide Sidebar", systemImage: "sidebar.left") {
                        withAnimation(sidebarAnimation) {
                            sidebarVisible = false
                        }
                    }

                    Menu {
                        Button {
                            store.createNote()
                        } label: {
                            Label("New Note", systemImage: "square.and.pencil")
                        }
                        .disabled(store.vaultURL == nil)

                        Menu("New File") {
                            ForEach(NewFileFormat.allCases) { format in
                                Button {
                                    store.createFile(format: format, in: nil)
                                } label: {
                                    Label(format.title, systemImage: format.systemImage)
                                }
                            }
                        }
                        .disabled(store.vaultURL == nil)

                        Button {
                            store.createFolder(in: nil)
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        .disabled(store.vaultURL == nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .help("Create")
                    .accessibilityLabel("Create")

                    headerButton("Open Vault", systemImage: "folder") {
                        store.chooseVault()
                    }
                }
            }

            HStack(spacing: 12) {
                Label(fileCountText, systemImage: "doc.text")
                Label(gitSummaryText, systemImage: store.gitSnapshot.isRepository ? "point.3.connected.trianglepath.dotted" : "nosign")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contextMenu {
            creationMenu(folderPath: nil)
            Divider()
            Button("Open Vault") {
                store.chooseVault()
            }
        }
    }

    private var emptyTreeRow: some View {
        Text(store.vaultURL == nil ? "Open a vault" : "No files")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .contextMenu {
                creationMenu(folderPath: nil)
            }
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.gitSnapshot.isClean ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)

            Text(store.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button {
                refreshRotation += 360
                store.reloadFiles()
                store.refreshGitStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(refreshRotation))
            }
            .buttonStyle(.borderless)
            .disabled(store.vaultURL == nil)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Rectangle())
        .animation(sidebarAnimation, value: refreshRotation)
    }

    private var sidebarTitle: String {
        store.vaultURL?.lastPathComponent ?? AppBrand.displayName
    }

    private var sidebarSubtitle: String {
        store.vaultURL == nil ? "No vault open" : "Vault"
    }

    private var fileCountText: String {
        let count = store.files.count
        return count == 1 ? "1 file" : "\(count) files"
    }

    private var gitSummaryText: String {
        if store.gitSnapshot.isRepository {
            return store.gitSnapshot.summary
        }
        return store.vaultURL == nil ? "No vault" : "No git"
    }

    private func headerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .disabled(store.vaultURL == nil && title != "Open Vault")
    }

    @ViewBuilder
    private func creationMenu(folderPath: String?) -> some View {
        Button {
            expand(folderPath)
            store.createFolder(in: folderPath)
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        .disabled(store.vaultURL == nil)

        Menu("New File") {
            ForEach(NewFileFormat.allCases) { format in
                Button {
                    expand(folderPath)
                    store.createFile(format: format, in: folderPath)
                } label: {
                    Label(format.title, systemImage: format.systemImage)
                }
                .disabled(store.vaultURL == nil)
            }
        }
    }

    private func expand(_ folderPath: String?) {
        guard let folderPath, !folderPath.isEmpty else { return }
        withAnimation(sidebarAnimation) {
            expandedFolders.insert(folderPath)
        }
    }

    private func expandAncestors(of fileID: String?) {
        guard let fileID else { return }
        withAnimation(sidebarAnimation) {
            expandedFolders.formUnion(FileTreeNode.ancestorFolderPaths(for: fileID))
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider], into folderPath: String?) -> Bool {
        handleVaultFileDrop(providers, store: store, folderPath: folderPath) {
            expand(folderPath)
        }
    }

    private var sidebarAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22)
    }

    private var sectionTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

private struct ReferenceEmptyRow: View {
    var body: some View {
        Text("No references")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}

private struct GitSidebarEmptyRow: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

private struct GitSidebarChangeRow: View {
    let change: GitChangedFile

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: change.systemImage)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(change.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(change.parentPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            GitSidebarStatusDot(change: change)
        }
        .frame(minHeight: 34)
        .contentShape(Rectangle())
        .help("\(change.displayStatus): \(change.path)")
        .accessibilityElement(children: .combine)
    }
}

private struct GitSidebarStatusDot: View {
    let change: GitChangedFile

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .help(change.displayStatus)
            .accessibilityLabel(change.displayStatus)
    }

    private var color: Color {
        if change.isUntracked {
            return .green
        }
        if change.hasStagedChanges, change.hasUnstagedChanges {
            return .purple
        }
        if change.hasStagedChanges {
            return .blue
        }
        return .orange
    }
}

private struct ReferenceSidebarRow: View {
    let reference: ReferenceItem
    let isDuplicate: Bool
    let pdfExists: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "book.closed")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(reference.citationKey)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if isDuplicate {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                    if reference.pdfRelativePath != nil {
                        Image(systemName: pdfExists ? "paperclip" : "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(pdfExists ? Color.secondary : Color.orange)
                    }
                }

                Text(reference.displayTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct FileTreeRow: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let node: FileTreeNode
    @Binding var expandedFolders: Set<String>
    @Binding var renamingNodeID: String?
    @Binding var renameDraft: String
    @Binding var confirmDelete: Bool
    let forceExpanded: Bool
    @State private var isDropTargeted = false

    var body: some View {
        if node.isFolder {
            DisclosureGroup(isExpanded: expansionBinding) {
                ForEach(node.children) { child in
                    FileTreeRow(
                        node: child,
                        expandedFolders: $expandedFolders,
                        renamingNodeID: $renamingNodeID,
                        renameDraft: $renameDraft,
                        confirmDelete: $confirmDelete,
                        forceExpanded: forceExpanded
                    )
                }
            } label: {
                folderLabel
                    .dropTargetHighlight(isTargeted: isDropTargeted)
                    .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                        handleFileDrop(providers, into: node.relativePath)
                    }
                    .contextMenu {
                        folderContextMenu
                    }
            }
            .contextMenu {
                folderContextMenu
            }
            .listRowInsets(FileTreeMetrics.rowInsets)
            .animation(rowAnimation, value: expansionBinding.wrappedValue)
            .animation(rowAnimation, value: isDropTargeted)
        } else if let file = node.file {
            fileLabel(file)
                .dropTargetHighlight(isTargeted: isDropTargeted)
                .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleFileDrop(providers, into: FileTreeNode.parentFolderPath(for: file.relativePath))
                }
                .tag(file.id)
                .contextMenu {
                    fileContextMenu(file)
                }
                .listRowInsets(FileTreeMetrics.rowInsets)
                .animation(rowAnimation, value: isDropTargeted)
        }
    }

    @ViewBuilder
    private var folderLabel: some View {
        if isRenaming {
            EditableTreeLabel(
                systemImage: "folder",
                text: $renameDraft,
                onCommit: commitRename,
                onCancel: cancelRename
            )
        } else {
            FolderTreeLabel(name: node.name, isExpanded: expansionBinding.wrappedValue)
                .sidebarRowMotion()
        }
    }

    @ViewBuilder
    private func fileLabel(_ file: VaultFile) -> some View {
        if isRenaming {
            EditableTreeLabel(
                systemImage: file.kind.systemImage,
                text: $renameDraft,
                onCommit: commitRename,
                onCancel: cancelRename
            )
        } else {
            FileTreeLabel(file: file)
                .sidebarRowMotion()
                .simultaneousGesture(TapGesture().onEnded {
                    store.previewFile(id: file.id)
                })
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    store.openFile(file.id)
                })
        }
    }

    private var expansionBinding: Binding<Bool> {
        Binding {
            forceExpanded || expandedFolders.contains(node.relativePath)
        } set: { isExpanded in
            guard !forceExpanded else { return }
            withAnimation(rowAnimation) {
                if isExpanded {
                    expandedFolders.insert(node.relativePath)
                } else {
                    expandedFolders.remove(node.relativePath)
                }
            }
        }
    }

    private var isRenaming: Bool {
        renamingNodeID == node.id
    }

    @ViewBuilder
    private var folderContextMenu: some View {
        Button {
            expandedFolders.insert(node.relativePath)
            store.createFolder(in: node.relativePath)
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }

        Menu("New File") {
            ForEach(NewFileFormat.allCases) { format in
                Button {
                    expandedFolders.insert(node.relativePath)
                    store.createFile(format: format, in: node.relativePath)
                } label: {
                    Label(format.title, systemImage: format.systemImage)
                }
            }
        }

        Divider()

        Button {
            beginRename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        .disabled(node.folder == nil)

        Button("Reveal in Finder") {
            if let folder = node.folder {
                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
            }
        }
        .disabled(node.folder == nil)
    }

    @ViewBuilder
    private func fileContextMenu(_ file: VaultFile) -> some View {
        Menu("New File Here") {
            ForEach(NewFileFormat.allCases) { format in
                Button {
                    let folderPath = FileTreeNode.parentFolderPath(for: file.relativePath)
                    store.createFile(format: format, in: folderPath)
                } label: {
                    Label(format.title, systemImage: format.systemImage)
                }
            }
        }

        Button {
            store.createFolder(in: FileTreeNode.parentFolderPath(for: file.relativePath))
        } label: {
            Label("New Folder Here", systemImage: "folder.badge.plus")
        }

        Divider()

        Button {
            beginRename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        }
        Button("Open Externally") {
            NSWorkspace.shared.open(file.url)
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            store.openFile(file.id)
            confirmDelete = true
        }
    }

    private func beginRename() {
        renameDraft = node.name
        renamingNodeID = node.id
    }

    private func cancelRename() {
        guard isRenaming else { return }
        renameDraft = ""
        renamingNodeID = nil
    }

    private func commitRename() {
        guard isRenaming else { return }
        let proposedName = renameDraft
        defer { cancelRename() }

        guard proposedName.trimmed != node.name else { return }

        if let file = node.file {
            store.renameFile(file, to: proposedName)
        } else if let folder = node.folder,
                  let newPath = store.renameFolder(folder, to: proposedName) {
            replaceExpandedFolderPaths(oldPrefix: node.relativePath, newPrefix: newPath)
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider], into folderPath: String?) -> Bool {
        handleVaultFileDrop(providers, store: store, folderPath: folderPath) {
            if let folderPath {
                withAnimation(rowAnimation) {
                    expandedFolders.insert(folderPath)
                }
            }
        }
    }

    private func replaceExpandedFolderPaths(oldPrefix: String, newPrefix: String) {
        expandedFolders = Set(expandedFolders.map { path in
            if path == oldPrefix {
                return newPrefix
            }
            if path.hasPrefix(oldPrefix + "/") {
                return newPrefix + String(path.dropFirst(oldPrefix.count))
            }
            return path
        })
    }

    private var rowAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.18)
    }
}

private enum FileTreeMetrics {
    static let rowHeight: CGFloat = 18
    static let rowInsets = EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
    static let rowSpacing: CGFloat = 5
    static let iconSize: CGFloat = 10.5
    static let iconWidth: CGFloat = 13
}

private struct FolderTreeLabel: View {
    let name: String
    let isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: FileTreeMetrics.rowSpacing) {
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .foregroundStyle(isExpanded ? Color.accentColor : Color.secondary)
                .font(.system(size: FileTreeMetrics.iconSize))
                .frame(width: FileTreeMetrics.iconWidth)
                .scaleEffect(isExpanded && !reduceMotion ? 1.06 : 1)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: FileTreeMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .animation(labelAnimation, value: isExpanded)
    }

    private var labelAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.18)
    }
}

private struct EditableTreeLabel: View {
    let systemImage: String
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var fieldFocused: Bool
    @State private var canCommitOnFocusLoss = false

    var body: some View {
        HStack(spacing: FileTreeMetrics.rowSpacing) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .font(.system(size: FileTreeMetrics.iconSize))
                .frame(width: FileTreeMetrics.iconWidth)

            TextField("Name", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1)
                .padding(.horizontal, 3)
                .padding(.vertical, 0)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
                .focused($fieldFocused)
                .onSubmit(onCommit)
                .onExitCommand(perform: onCancel)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: FileTreeMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onAppear {
            DispatchQueue.main.async {
                fieldFocused = true
                canCommitOnFocusLoss = true
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
        .onChange(of: fieldFocused) { oldValue, newValue in
            guard canCommitOnFocusLoss, oldValue, !newValue else { return }
            onCommit()
        }
        .accessibilityElement(children: .contain)
    }
}

private struct FileTreeLabel: View {
    let file: VaultFile

    var body: some View {
        HStack(spacing: FileTreeMetrics.rowSpacing) {
            Image(systemName: file.kind.systemImage)
                .foregroundStyle(.secondary)
                .font(.system(size: FileTreeMetrics.iconSize))
                .frame(width: FileTreeMetrics.iconWidth)
            Text(file.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: FileTreeMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct FileDropTargetOverlay: View {
    let isTargeted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    Color.accentColor.opacity(0.65),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .padding(4)
                .allowsHitTesting(false)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.985).combined(with: .opacity))
        }
    }
}

private struct DropTargetHighlightModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isTargeted: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isTargeted ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .scaleEffect(isTargeted && !reduceMotion ? 1.012 : 1, anchor: .leading)
            .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: isTargeted)
    }
}

private struct SidebarRowMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .offset(x: isHovered && !reduceMotion ? 1.5 : 0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private extension View {
    func dropTargetHighlight(isTargeted: Bool) -> some View {
        modifier(DropTargetHighlightModifier(isTargeted: isTargeted))
    }

    func sidebarRowMotion() -> some View {
        modifier(SidebarRowMotionModifier())
    }
}

@MainActor
private func handleVaultFileDrop(
    _ providers: [NSItemProvider],
    store: VaultStore,
    folderPath: String?,
    onAccepted: () -> Void
) -> Bool {
    guard store.vaultURL != nil else {
        store.statusMessage = "Choose a vault before dropping files."
        return false
    }

    let fileProviders = providers.filter {
        $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }
    guard !fileProviders.isEmpty else { return false }

    onAccepted()
    loadDroppedFileURLs(from: fileProviders) { urls in
        guard !urls.isEmpty else { return }
        store.importFiles(urls, into: folderPath)
    }
    return true
}

private final class DroppedFileURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var urlsByProvider: [URL?]

    init(count: Int) {
        urlsByProvider = Array(repeating: nil, count: count)
    }

    func set(_ url: URL, at index: Int) {
        lock.lock()
        urlsByProvider[index] = url
        lock.unlock()
    }

    func compactURLs() -> [URL] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return urlsByProvider.compactMap(\.self)
    }
}

private func loadDroppedFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    let accumulator = DroppedFileURLAccumulator(count: providers.count)

    for (index, provider) in providers.enumerated() {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let url = droppedFileURL(from: item) {
                accumulator.set(url, at: index)
            }
            group.leave()
        }
    }

    group.notify(queue: .main) {
        completion(accumulator.compactURLs())
    }
}

private func droppedFileURL(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
        return url.isFileURL ? url : nil
    }
    if let data = item as? Data,
       let string = String(data: data, encoding: .utf8) {
        return fileURL(fromDropString: string)
    }
    if let string = item as? String {
        return fileURL(fromDropString: string)
    }
    return nil
}

private func fileURL(fromDropString string: String) -> URL? {
    let string = string.trimmed
    if let url = URL(string: string), url.isFileURL {
        return url
    }
    guard string.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: string)
}

private struct FileTreeNode: Identifiable, Hashable {
    let id: String
    let name: String
    let relativePath: String
    let file: VaultFile?
    let folder: VaultFolder?
    let children: [FileTreeNode]

    var isFolder: Bool {
        file == nil
    }

    static func build(files: [VaultFile], folders: [VaultFolder]) -> [FileTreeNode] {
        var folderPaths = Set(folders.map(\.relativePath))
        for file in files {
            folderPaths.formUnion(ancestorFolderPaths(for: file.relativePath))
        }

        let foldersByPath = Dictionary(uniqueKeysWithValues: folders.map { ($0.relativePath, $0) })
        return buildNodes(parentPath: "", files: files, folderPaths: folderPaths, foldersByPath: foldersByPath)
    }

    static func folderPaths(in nodes: [FileTreeNode]) -> Set<String> {
        var paths: Set<String> = []
        for node in nodes {
            if node.isFolder {
                paths.insert(node.relativePath)
            }
            paths.formUnion(folderPaths(in: node.children))
        }
        return paths
    }

    static func ancestorFolderPaths(for relativePath: String) -> [String] {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return [] }

        var paths: [String] = []
        for index in 1..<parts.count {
            paths.append(parts.prefix(index).joined(separator: "/"))
        }
        return paths
    }

    static func parentFolderPath(for relativePath: String) -> String? {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return nil }
        return parts.dropLast().joined(separator: "/")
    }

    private static func buildNodes(
        parentPath: String,
        files: [VaultFile],
        folderPaths: Set<String>,
        foldersByPath: [String: VaultFolder]
    ) -> [FileTreeNode] {
        let childFolderPaths = directChildFolderPaths(parentPath: parentPath, folderPaths: folderPaths)
        let folderNodes = childFolderPaths.map { folderPath in
            let folder = foldersByPath[folderPath]
            return FileTreeNode(
                id: "folder:\(folderPath)",
                name: folder?.name ?? folderPath.split(separator: "/").last.map(String.init) ?? folderPath,
                relativePath: folderPath,
                file: nil,
                folder: folder,
                children: buildNodes(
                    parentPath: folderPath,
                    files: files,
                    folderPaths: folderPaths,
                    foldersByPath: foldersByPath
                )
            )
        }

        let fileNodes = files
            .filter { parentFolderPath(for: $0.relativePath) == normalizedParent(parentPath) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { file in
                FileTreeNode(
                    id: "file:\(file.id)",
                    name: file.name,
                    relativePath: file.relativePath,
                    file: file,
                    folder: nil,
                    children: []
                )
            }

        return folderNodes.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        } + fileNodes
    }

    private static func directChildFolderPaths(parentPath: String, folderPaths: Set<String>) -> [String] {
        let prefix = parentPath.isEmpty ? "" : parentPath + "/"
        var directPaths: Set<String> = []

        for folderPath in folderPaths {
            guard folderPath.hasPrefix(prefix) else { continue }
            let remainder = String(folderPath.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }

            let firstSegment = remainder.split(separator: "/", maxSplits: 1).first.map(String.init) ?? remainder
            directPaths.insert(prefix + firstSegment)
        }

        return Array(directPaths)
    }

    private static func normalizedParent(_ parentPath: String) -> String? {
        parentPath.isEmpty ? nil : parentPath
    }
}
