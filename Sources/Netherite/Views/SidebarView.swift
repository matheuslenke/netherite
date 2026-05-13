import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: VaultStore
    @Binding var confirmDelete: Bool
    @State private var expandedFolders: Set<String> = []
    @State private var renamingNodeID: String?
    @State private var renameDraft = ""

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
            .font(.system(size: 12, design: .monospaced))
            .environment(\.defaultMinListRowHeight, 20)
            .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search files")
            .contextMenu {
                creationMenu(folderPath: nil)
            }

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
                expandedFolders.formUnion(FileTreeNode.folderPaths(in: treeNodes))
            }
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding {
            store.selectedFileID
        } set: { newValue in
            store.selectFile(id: newValue)
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                BrandLogoView(size: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(AppBrand.displayName)
                        .font(AppBrand.monoFont(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text("EXPLORER")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                }

                Spacer()

                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        headerButton("New File", systemImage: "doc.badge.plus") {
                            store.createFile(format: .markdown, in: nil)
                        }
                        headerButton("New Folder", systemImage: "folder.badge.plus") {
                            store.createFolder(in: nil)
                        }
                        headerButton("Open Vault", systemImage: "folder") {
                            store.chooseVault()
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(store.vaultURL?.lastPathComponent ?? "No Vault")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(store.files.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func headerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.glass)
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
        expandedFolders.insert(folderPath)
    }

    private func expandAncestors(of fileID: String?) {
        guard let fileID else { return }
        expandedFolders.formUnion(FileTreeNode.ancestorFolderPaths(for: fileID))
    }
}

private struct FileTreeRow: View {
    @EnvironmentObject private var store: VaultStore
    let node: FileTreeNode
    @Binding var expandedFolders: Set<String>
    @Binding var renamingNodeID: String?
    @Binding var renameDraft: String
    @Binding var confirmDelete: Bool
    let forceExpanded: Bool

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
                    .contextMenu {
                        folderContextMenu
                    }
            }
            .contextMenu {
                folderContextMenu
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        } else if let file = node.file {
            fileLabel(file)
                .tag(file.id)
                .contextMenu {
                    fileContextMenu(file)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
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
            FolderTreeLabel(name: node.name)
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
        }
    }

    private var expansionBinding: Binding<Bool> {
        Binding {
            forceExpanded || expandedFolders.contains(node.relativePath)
        } set: { isExpanded in
            guard !forceExpanded else { return }
            if isExpanded {
                expandedFolders.insert(node.relativePath)
            } else {
                expandedFolders.remove(node.relativePath)
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
            store.selectFile(id: file.id)
            store.revealSelectedInFinder()
        }
        Button("Open Externally") {
            store.selectFile(id: file.id)
            store.openSelectedExternally()
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            store.selectFile(id: file.id)
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
}

private struct FolderTreeLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .frame(width: 14)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .frame(width: 14)

            TextField("Name", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
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
        .frame(minHeight: 20)
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
        HStack(spacing: 6) {
            Image(systemName: file.kind.systemImage)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .frame(width: 14)
            Text(file.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
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
