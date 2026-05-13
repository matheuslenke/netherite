import SwiftUI

private enum InspectorTab: String, CaseIterable, Identifiable {
    case metadata
    case latex
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
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
    @State private var selectedTab: InspectorTab = .metadata

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
        .glassEffect(.regular, in: Rectangle())
        .animation(contentAnimation, value: selectedTab)
        .animation(contentAnimation, value: store.gitSnapshot.statusText)
        .animation(contentAnimation, value: store.gitHistory.count)
        .animation(contentAnimation, value: store.latexRenderState.phase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("DETAILS", systemImage: selectedTab.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

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
    }

    private var tabContent: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                switch selectedTab {
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
                            store.selectFile(id: file.id)
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
        let changeCount = store.gitSnapshot.statusText.split(whereSeparator: \.isNewline).count
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
