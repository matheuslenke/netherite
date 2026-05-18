import SwiftUI

private enum InspectorTab: String, CaseIterable, Identifiable {
    case contents
    case metadata
    case latex
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contents:
            "Contents"
        case .metadata:
            "Meta"
        case .latex:
            "LaTeX"
        case .history:
            "History"
        }
    }

    var systemImage: String {
        switch self {
        case .contents:
            "list.bullet.indent"
        case .metadata:
            "info.circle"
        case .latex:
            "function"
        case .history:
            "clock.arrow.circlepath"
        }
    }
}

struct InspectorView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var markdownScrollTargetID: Int?
    @Binding var sourceScrollTargetOffset: Int?
    @State private var selectedTab: InspectorTab = .contents
    @State private var selectedTableOfContentsItemID: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                tabContent
                    .padding(14)
            }

            Divider()
            gitFooter
        }
        .background(Color(nsColor: .controlBackgroundColor), in: Rectangle())
        .animation(contentAnimation, value: selectedTab)
        .animation(contentAnimation, value: store.gitSnapshot.statusText)
        .animation(contentAnimation, value: store.gitChanges.count)
        .animation(contentAnimation, value: store.gitHistory.count)
        .animation(contentAnimation, value: store.latexRenderState.phase)
        .onChange(of: store.currentFile?.id) { _, _ in
            selectedTab = .contents
            selectedTableOfContentsItemID = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("Inspector", systemImage: selectedTab.systemImage)
                    .font(.headline.weight(.semibold))

                Spacer(minLength: 8)

                Text(store.currentFile?.name ?? "No File")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Picker("Details Content", selection: $selectedTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Choose details content")
            .accessibilityLabel("Details content")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Rectangle())
    }

    private var tabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch selectedTab {
            case .contents:
                contentsTab
            case .metadata:
                documentSection
                backlinksSection
                agentSection
            case .latex:
                latexTab
            case .history:
                historySection
            }
        }
    }

    @ViewBuilder
    private var contentsTab: some View {
        if store.currentFile?.kind == .markdown || store.currentFile?.kind == .latex {
            if tableOfContentsItems.isEmpty {
                EmptyInspectorState(
                    title: "No Headings",
                    message: "Add document headings to build the contents.",
                    systemImage: "list.bullet.indent"
                )
            } else {
                MarkdownTableOfContentsView(
                    items: tableOfContentsItems,
                    selectedItemID: selectedTableOfContentsItemID,
                    isCompact: false
                ) { item in
                    selectedTableOfContentsItemID = item.id
                    jumpToContentsItem(item)
                }
            }
        } else {
            EmptyInspectorState(
                title: store.currentFile == nil ? "No Document" : "No Contents",
                message: store.currentFile == nil ? "Select a markdown or LaTeX document to show its contents." : "Contents are available for markdown and LaTeX documents.",
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

    private var tableOfContentsItems: [MarkdownTableOfContentsItem] {
        switch store.currentFile?.kind {
        case .markdown:
            markdownTableOfContentsItems
        case .latex:
            LatexStructureItem.parse(store.documentText).map { item in
                MarkdownTableOfContentsItem(
                    id: item.sourceStartOffset,
                    level: item.level,
                    title: item.title
                )
            }
        default:
            []
        }
    }

    private var markdownTableOfContentsItems: [MarkdownTableOfContentsItem] {
        MarkdownBlock.parse(store.documentText).compactMap { block in
            guard case let .heading(level) = block.kind else { return nil }

            let title = block.text.trimmed
            guard !title.isEmpty else { return nil }

            return MarkdownTableOfContentsItem(
                id: block.sourceStartOffset,
                level: level,
                title: title
            )
        }
    }

    private func jumpToContentsItem(_ item: MarkdownTableOfContentsItem) {
        switch store.currentFile?.kind {
        case .markdown:
            markdownScrollTargetID = item.id
        case .latex:
            if store.editorMode == .preview {
                store.setEditorMode(.split)
            }
            sourceScrollTargetOffset = item.id
        default:
            break
        }
    }

    private var documentSection: some View {
        GroupBox("Document") {
            VStack(alignment: .leading, spacing: 10) {
                metadataRow("Path", store.currentFile?.relativePath ?? "No file")
                metadataRow("Kind", store.currentFile?.kind.rawValue.capitalized ?? "Unknown")
                metadataRow("Characters", "\(store.documentStats.characters)")
                metadataRow("Words", "\(store.documentStats.words)")
                metadataRow("Size", ByteCountFormatter.string(fromByteCount: Int64(store.currentFile?.byteCount ?? 0), countStyle: .file))
                metadataRow("Modified", store.currentFile.map { AppFormatters.shortDateTime.string(from: $0.modifiedAt) } ?? "Unknown")

                ViewThatFits(in: .horizontal) {
                    HStack {
                        revealButton
                        openButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        revealButton
                        openButton
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var latexTab: some View {
        if store.selectedFileCanRenderLatex {
            latexSection
        } else {
            EmptyInspectorState(
                title: store.currentFile == nil ? "No Document" : "Not a LaTeX File",
                message: store.currentFile == nil ? "Select a document to inspect its build state." : "Select a .tex file to show build controls.",
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

    private var latexSection: some View {
        GroupBox("LaTeX Build") {
            VStack(alignment: .leading, spacing: 10) {
                metadataRow("Status", latexStatusText)
                metadataRow("Root", store.latexRenderState.rootRelativePath ?? store.currentFile?.relativePath ?? "Unknown")
                metadataRow("Includes", "\(store.latexRenderState.includedFiles.count)")

                ViewThatFits(in: .horizontal) {
                    HStack {
                        renderButton
                        openPDFButton
                        revealPDFButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        renderButton
                        openPDFButton
                        revealPDFButton
                    }
                }

                if !store.latexRenderState.includedFiles.isEmpty {
                    includedLatexFiles
                }

                if !store.latexRenderState.log.isEmpty {
                    Text(store.latexRenderState.log)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var includedLatexFiles: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Included Files")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(store.latexRenderState.includedFiles) { file in
                Button {
                    openIncludedLatexFile(file)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: file.isMissing ? "exclamationmark.triangle" : "doc.text")
                            .foregroundStyle(file.isMissing ? .orange : .secondary)
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.relativePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(includedLatexFileDetail(file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(file.isMissing)
                .help(file.isMissing ? "Missing included file" : "Open included source")
            }
        }
        .font(.caption)
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }

    private var historySection: some View {
        GroupBox("Version History") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(store.gitHistory.count) revisions")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.refreshHistoryForSelectedFile()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!store.gitSnapshot.isRepository)
                    .help("Refresh Version History")
                    .accessibilityLabel("Refresh Version History")
                }

                if store.gitHistory.isEmpty {
                    Text(store.gitSnapshot.isRepository ? "No commits for this file yet." : "Initialize git to track history.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(store.gitHistory.prefix(12)) { version in
                            Button {
                                store.loadDiff(for: version)
                            } label: {
                                VersionRow(version: version, selected: store.selectedVersion == version)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !store.selectedVersionDiff.isEmpty {
                    TextEditor(text: .constant(store.selectedVersionDiff))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minHeight: 180)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var agentSection: some View {
        GroupBox("Terminal Agents") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Prompt", text: $store.agentPrompt, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)

                ViewThatFits(in: .horizontal) {
                    HStack {
                        ForEach(AgentTool.allCases) { tool in
                            agentButton(tool)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(AgentTool.allCases) { tool in
                            agentButton(tool)
                        }
                    }
                }

                missingAgentText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var backlinksSection: some View {
        GroupBox("Linked Mentions") {
            VStack(alignment: .leading, spacing: 8) {
                if store.backlinks.isEmpty {
                    Text("No backlinks found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.backlinks) { file in
                        Button {
                            store.openFile(file.id)
                        } label: {
                            Label(file.relativePath, systemImage: file.kind.systemImage)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var gitFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(gitFooterTitle, systemImage: gitFooterImage)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if store.gitSnapshot.isRepository {
                    Text(gitChangeSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                gitIconButton("Refresh Git Status", systemImage: "arrow.clockwise", disabled: store.vaultURL == nil) {
                    store.refreshGitStatus()
                }

                if store.gitSnapshot.isRepository {
                    gitIconButton("Show Git Changes", systemImage: "point.3.connected.trianglepath.dotted", disabled: false) {
                        store.showGitChanges()
                    }

                    gitIconButton("Pull", systemImage: "arrow.down.circle", disabled: false) {
                        store.pullVault()
                    }

                    gitIconButton("Push", systemImage: "arrow.up.circle", disabled: false) {
                        store.pushVault()
                    }
                } else {
                    gitIconButton("Initialize Repository", systemImage: "plus.circle", disabled: store.vaultURL == nil) {
                        store.initializeGitRepository()
                    }
                }
            }

            if store.gitSnapshot.isRepository {
                HStack(spacing: 6) {
                    TextField("Commit message", text: $store.commitMessage)
                        .textFieldStyle(.roundedBorder)

                    gitIconButton("Commit All", systemImage: "checkmark.circle", disabled: store.gitSnapshot.isClean) {
                        store.commitVault()
                    }
                }
            }

            Text(store.statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: Rectangle())
    }

    private var revealButton: some View {
        Button {
            store.revealSelectedInFinder()
        } label: {
            Label("Reveal", systemImage: "finder")
        }
        .disabled(store.currentFile == nil)
    }

    private var openButton: some View {
        Button {
            store.openSelectedExternally()
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }
        .disabled(store.currentFile == nil)
    }

    private var renderButton: some View {
        Button {
            store.renderLatexForCurrentFile()
        } label: {
            Label(store.latexRenderState.isRendering ? "Rendering" : "Render", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(store.latexRenderState.isRendering)
    }

    private var openPDFButton: some View {
        Button {
            store.openRenderedLatexPDF()
        } label: {
            Label("Open PDF", systemImage: "arrow.up.right.square")
        }
        .disabled(!store.latexRenderState.canOpenPDF)
    }

    private var revealPDFButton: some View {
        Button {
            store.revealRenderedLatexPDF()
        } label: {
            Label("Reveal PDF", systemImage: "finder")
        }
        .disabled(!store.latexRenderState.canOpenPDF)
    }

    private func agentButton(_ tool: AgentTool) -> some View {
        Button {
            store.openAgentTerminal(tool: tool)
        } label: {
            Label(tool.title, systemImage: tool.systemImage)
        }
        .disabled(store.agentAvailability[tool] == false)
    }

    @ViewBuilder
    private var missingAgentText: some View {
        let missing = AgentTool.allCases
            .filter { store.agentAvailability[$0] == false }
            .map(\.title)

        if !missing.isEmpty {
            Text("Unavailable: \(missing.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func gitIconButton(
        _ title: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
    }

    private var gitFooterTitle: String {
        if store.gitSnapshot.isRepository {
            store.gitSnapshot.branch
        } else if store.vaultURL == nil {
            "No Vault"
        } else {
            "No Repository"
        }
    }

    private var gitFooterImage: String {
        store.gitSnapshot.isRepository ? "point.3.connected.trianglepath.dotted" : "nosign"
    }

    private var gitChangeSummary: String {
        guard store.gitSnapshot.isRepository else { return "" }
        let changeCount = store.gitChanges.count
        return changeCount == 0 ? "Clean" : "\(changeCount) changes"
    }

    private var latexStatusText: String {
        switch store.latexRenderState.phase {
        case .idle:
            "Not rendered"
        case .rendering:
            "Rendering"
        case .rendered:
            store.latexRenderState.renderedAt.map { AppFormatters.shortDateTime.string(from: $0) } ?? "Rendered"
        case .failed:
            "Build failed"
        case .unavailable:
            "Tool unavailable"
        }
    }

    private func openIncludedLatexFile(_ includedFile: LatexIncludedFile) {
        guard !includedFile.isMissing,
              let url = includedFile.url,
              let fileID = store.fileID(for: url)
        else {
            store.statusMessage = "Included file is not available in this vault."
            return
        }

        store.openFile(fileID)
        store.setEditorMode(.split)
        sourceScrollTargetOffset = nil
        store.statusMessage = "Opened \(includedFile.relativePath)"
    }

    private func includedLatexFileDetail(_ file: LatexIncludedFile) -> String {
        if file.isMissing {
            return "\\\(file.command) at \(file.sourceRelativePath):\(file.line) - missing"
        }

        var parts = ["\\\(file.command) at \(file.sourceRelativePath):\(file.line)"]
        if let lineCount = file.lineCount {
            parts.append("\(lineCount) lines")
        }
        if let wordCount = file.wordCount {
            parts.append("\(wordCount) words")
        }
        if let byteCount = file.byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
        }
        return parts.joined(separator: " - ")
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private var contentAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22)
    }
}

private struct EmptyInspectorState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(18)
    }
}

private struct LatexStructureItem {
    let sourceStartOffset: Int
    let command: String
    let title: String

    var level: Int {
        switch command {
        case "part", "chapter":
            1
        case "section":
            2
        case "subsection":
            3
        case "subsubsection":
            4
        case "paragraph":
            5
        case "subparagraph":
            6
        default:
            6
        }
    }

    static func parse(_ source: String) -> [LatexStructureItem] {
        var items: [LatexStructureItem] = []
        var lineStartOffset = 0
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, line) in lines.enumerated() {
            let lineText = String(line)
            if let item = parseLine(lineText, lineStartOffset: lineStartOffset) {
                items.append(item)
            }
            lineStartOffset += lineText.count + (index == lines.count - 1 ? 0 : 1)
        }

        return items
    }

    private static func parseLine(_ line: String, lineStartOffset: Int) -> LatexStructureItem? {
        let commands = [
            "subparagraph",
            "subsubsection",
            "subsection",
            "paragraph",
            "chapter",
            "section",
            "part"
        ]

        for command in commands {
            guard let commandRange = line.range(of: "\\\(command)") else { continue }
            guard commandIsContent(at: commandRange.lowerBound, in: line) else { continue }

            var cursor = commandRange.upperBound
            if cursor < line.endIndex, line[cursor] == "*" {
                cursor = line.index(after: cursor)
            }

            cursor = skipWhitespace(from: cursor, in: line)
            if cursor < line.endIndex, line[cursor] == "[" {
                guard let optionalEnd = closingDelimiterIndex(
                    from: cursor,
                    open: "[",
                    close: "]",
                    in: line
                ) else {
                    continue
                }
                cursor = skipWhitespace(from: line.index(after: optionalEnd), in: line)
            }

            guard cursor < line.endIndex, line[cursor] == "{",
                  let titleEnd = closingDelimiterIndex(from: cursor, open: "{", close: "}", in: line)
            else {
                continue
            }

            let titleStart = line.index(after: cursor)
            let rawTitle = String(line[titleStart..<titleEnd])
            let title = cleanedTitle(rawTitle)
            guard !title.isEmpty else { continue }

            let offset = line.distance(from: line.startIndex, to: commandRange.lowerBound)
            return LatexStructureItem(
                sourceStartOffset: lineStartOffset + offset,
                command: command,
                title: title
            )
        }

        return nil
    }

    private static func commandIsContent(at index: String.Index, in line: String) -> Bool {
        guard !isEscaped(index, in: line) else { return false }

        if let commentIndex = unescapedCommentIndex(in: line), commentIndex < index {
            return false
        }

        return true
    }

    private static func unescapedCommentIndex(in line: String) -> String.Index? {
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "%", !isEscaped(index, in: line) {
                return index
            }
            index = line.index(after: index)
        }
        return nil
    }

    private static func isEscaped(_ index: String.Index, in line: String) -> Bool {
        guard index > line.startIndex else { return false }

        var slashCount = 0
        var cursor = line.index(before: index)
        while true {
            guard line[cursor] == "\\" else { break }
            slashCount += 1
            guard cursor > line.startIndex else { break }
            cursor = line.index(before: cursor)
        }

        return slashCount % 2 == 1
    }

    private static func skipWhitespace(from startIndex: String.Index, in line: String) -> String.Index {
        var cursor = startIndex
        while cursor < line.endIndex, line[cursor].isWhitespace {
            cursor = line.index(after: cursor)
        }
        return cursor
    }

    private static func closingDelimiterIndex(
        from openIndex: String.Index,
        open: Character,
        close: Character,
        in line: String
    ) -> String.Index? {
        var depth = 0
        var cursor = openIndex

        while cursor < line.endIndex {
            let character = line[cursor]
            if character == open, !isEscaped(cursor, in: line) {
                depth += 1
            } else if character == close, !isEscaped(cursor, in: line) {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }

            cursor = line.index(after: cursor)
        }

        return nil
    }

    private static func cleanedTitle(_ rawTitle: String) -> String {
        rawTitle
            .replacingOccurrences(of: #"\\([A-Za-z]+)\{([^{}]*)\}"#, with: "$2", options: .regularExpression)
            .replacingOccurrences(of: #"\\[A-Za-z]+\*?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\{\}]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"~"#, with: " ")
            .trimmed
    }
}

private struct VersionRow: View {
    let version: GitFileVersion
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(version.subject)
                    .lineLimit(1)
                Text("\(version.shortHash) • \(version.author) • \(version.date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(6)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
