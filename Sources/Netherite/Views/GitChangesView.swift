import AppKit
import SwiftUI

struct GitChangesView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var discardTarget: GitDiscardTarget?
    let isCompact: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.gitSnapshot.isRepository {
                Divider()
                actionBar
            }
            Divider()
            content
        }
        .glassEffect(.regular, in: Rectangle())
        .animation(contentAnimation, value: store.gitChanges)
        .animation(contentAnimation, value: store.selectedGitChangeID)
        .animation(contentAnimation, value: store.selectedGitDiffScope)
        .alert("Discard Changes?", isPresented: discardAlertBinding) {
            Button("Cancel", role: .cancel) {}
            Button(discardTarget?.buttonTitle ?? "Discard", role: .destructive) {
                switch discardTarget {
                case .selected:
                    store.discardSelectedGitChange()
                case .all:
                    store.discardAllGitChanges()
                case .none:
                    break
                }
                discardTarget = nil
            }
        } message: {
            Text(discardTarget?.message ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Changes")
                    .font(isCompact ? .headline.weight(.semibold) : .title3.weight(.semibold))

                HStack(spacing: 8) {
                    Text(store.gitSnapshot.branch)
                    Text("•")
                    Text(changeSummary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                store.refreshGitStatus()
            } label: {
                if isCompact {
                    Image(systemName: "arrow.clockwise")
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .help("Refresh Git Changes")
            .accessibilityLabel("Refresh Git Changes")

            if store.currentFile != nil {
                Button {
                    store.setWorkspaceSection(.files)
                } label: {
                    if isCompact {
                        Image(systemName: "doc.text")
                    } else {
                        Label("Editor", systemImage: "doc.text")
                    }
                }
                .help("Return to Editor")
                .accessibilityLabel("Return to Editor")
            }
        }
        .padding(.horizontal, isCompact ? 12 : 18)
        .padding(.vertical, isCompact ? 9 : 12)
    }

    @ViewBuilder
    private var actionBar: some View {
        if store.gitSnapshot.isRepository {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    summaryPills
                    Spacer(minLength: 12)
                    globalActions
                    Divider()
                        .frame(height: 20)
                    commitControls
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        summaryPills
                        Spacer(minLength: 8)
                        globalActions
                    }

                    commitControls
                }
            }
            .padding(.horizontal, isCompact ? 12 : 18)
            .padding(.vertical, 8)
        }
    }

    private var summaryPills: some View {
        HStack(spacing: 6) {
            GitSummaryPill(title: "Staged", count: store.stagedGitChangeCount, color: .blue)
            GitSummaryPill(title: "Unstaged", count: store.unstagedGitChangeCount, color: .orange)
            GitSummaryPill(title: "Untracked", count: store.untrackedGitChangeCount, color: .green)
        }
    }

    private var globalActions: some View {
        ControlGroup {
            Button {
                store.stageAllGitChanges()
            } label: {
                Label("Stage All", systemImage: "plus.circle")
            }
            .disabled(store.gitChanges.isEmpty)
            .help("Stage All Changes")

            Button {
                store.unstageAllGitChanges()
            } label: {
                Label("Unstage All", systemImage: "minus.circle")
            }
            .disabled(!store.hasStagedGitChanges)
            .help("Unstage All Changes")

            Button(role: .destructive) {
                discardTarget = .all
            } label: {
                Label("Discard All", systemImage: "trash")
            }
            .disabled(store.gitChanges.isEmpty)
            .help("Discard All Changes")
        }
        .controlGroupStyle(.compactMenu)
    }

    private var commitControls: some View {
        HStack(spacing: 8) {
            TextField("Commit message", text: $store.commitMessage)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, idealWidth: 260)

            Button {
                store.commitStagedGitChanges()
            } label: {
                Label("Commit Staged", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.hasStagedGitChanges)
            .help("Commit Staged Changes")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.gitSnapshot.isRepository {
            GitChangesEmptyState(
                title: "No Repository",
                message: "Initialize git in this vault to inspect file changes.",
                systemImage: "nosign"
            )
        } else if store.gitChanges.isEmpty {
            GitChangesEmptyState(
                title: "Working Tree Clean",
                message: "No tracked or untracked file changes were reported by git.",
                systemImage: "checkmark.circle"
            )
        } else {
            GitDiffPane { change in
                discardTarget = .selected(change)
            }
            .frame(minWidth: 380, minHeight: 260)
        }
    }

    private var changeSummary: String {
        let count = store.gitChanges.count
        return count == 1 ? "1 changed file" : "\(count) changed files"
    }

    private var contentAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22)
    }

    private var discardAlertBinding: Binding<Bool> {
        Binding {
            discardTarget != nil
        } set: { isPresented in
            if !isPresented {
                discardTarget = nil
            }
        }
    }
}

private enum GitDiscardTarget: Identifiable {
    case selected(GitChangedFile)
    case all

    var id: String {
        switch self {
        case let .selected(change):
            "selected-\(change.id)"
        case .all:
            "all"
        }
    }

    var buttonTitle: String {
        switch self {
        case .selected:
            "Discard File"
        case .all:
            "Discard All"
        }
    }

    var message: String {
        switch self {
        case let .selected(change):
            "This will permanently discard local changes for \(change.displayName)."
        case .all:
            "This will permanently discard every staged, unstaged, and untracked change in this vault."
        }
    }
}

private struct GitSummaryPill: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title)
                .foregroundStyle(.secondary)

            Text("\(count)")
                .fontWeight(.semibold)
                .foregroundStyle(count == 0 ? .secondary : .primary)
        }
        .font(.caption2)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct GitChangeBadge: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(color)
    }
}

private struct GitDiffPane: View {
    @EnvironmentObject private var store: VaultStore
    let requestDiscard: (GitChangedFile) -> Void

    var body: some View {
        VStack(spacing: 0) {
            diffHeader
            Divider()
            diffBody
        }
    }

    @ViewBuilder
    private var diffHeader: some View {
        if let change = store.selectedGitChange {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    selectedFileTitle(change)
                    Spacer(minLength: 8)
                    diffScopePicker
                    selectedFileActions(change)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        selectedFileTitle(change)
                        Spacer(minLength: 8)
                        selectedFileActions(change)
                    }

                    diffScopePicker
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        } else {
            Text("No file selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
    }

    private func selectedFileTitle(_ change: GitChangedFile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(change.path)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            HStack(spacing: 5) {
                if let stagedStatusText = change.stagedStatusText {
                    GitChangeBadge(title: "Index", value: stagedStatusText, color: .blue)
                }

                if let unstagedStatusText = change.unstagedStatusText {
                    GitChangeBadge(
                        title: change.isUntracked ? "New" : "Worktree",
                        value: unstagedStatusText,
                        color: change.isUntracked ? .green : .orange
                    )
                }
            }

            if let originalPath = change.originalPath {
                Text("Renamed from \(originalPath)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var diffScopePicker: some View {
        Picker("Diff Scope", selection: diffScopeBinding) {
            ForEach(GitDiffScope.allCases) { scope in
                Text(scope.title)
                    .tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
        .help("Choose Diff Scope")
    }

    private func selectedFileActions(_ change: GitChangedFile) -> some View {
        ControlGroup {
            Button {
                store.stageSelectedGitChange()
            } label: {
                Label("Stage File", systemImage: "plus.circle")
            }
            .disabled(!change.canStage)
            .help("Stage File")

            Button {
                store.unstageSelectedGitChange()
            } label: {
                Label("Unstage File", systemImage: "minus.circle")
            }
            .disabled(!change.canUnstage)
            .help("Unstage File")

            Button(role: .destructive) {
                requestDiscard(change)
            } label: {
                Label("Discard File", systemImage: "trash")
            }
            .disabled(!change.canDiscard)
            .help("Discard File")

            if store.files.contains(where: { $0.id == change.path }) {
                Button {
                    store.openFile(change.path)
                } label: {
                    Label("Open File", systemImage: "doc.text")
                }
                .help("Open File")
            }
        }
        .controlGroupStyle(.compactMenu)
    }

    private var diffScopeBinding: Binding<GitDiffScope> {
        Binding {
            store.selectedGitDiffScope
        } set: { newValue in
            store.selectGitDiffScope(newValue)
        }
    }

    @ViewBuilder
    private var diffBody: some View {
        if store.selectedGitChange == nil {
            GitChangesEmptyState(
                title: "Select a File",
                message: "Choose a changed file in the sidebar to compare versions.",
                systemImage: "doc.text.magnifyingglass"
            )
        } else if !store.selectedGitComparisonMessage.isEmpty {
            GitChangesEmptyState(
                title: "Could Not Load Diff",
                message: store.selectedGitComparisonMessage,
                systemImage: "exclamationmark.triangle"
            )
        } else if store.selectedGitComparison.rows.isEmpty {
            GitChangesEmptyState(
                title: "No Text Changes",
                message: "No side-by-side textual changes were found for this file.",
                systemImage: "doc"
            )
        } else {
            GitSideBySideDiffView(comparison: store.selectedGitComparison)
        }
    }
}

private struct GitSideBySideDiffView: View {
    let comparison: GitFileComparison

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = max((proxy.size.width - 1) / 2, 360)
            let contentWidth = columnWidth * 2 + 1

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    GitDiffColumnHeader(title: comparison.previousTitle, systemImage: "clock.arrow.circlepath")
                        .frame(width: columnWidth, alignment: .leading)
                    GitVerticalRule()
                    GitDiffColumnHeader(title: comparison.changedTitle, systemImage: "pencil.line")
                        .frame(width: columnWidth, alignment: .leading)
                }
                .frame(width: contentWidth, height: 34, alignment: .leading)
                .background(.regularMaterial, in: Rectangle())

                Divider()

                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(comparison.rows) { row in
                            GitSideBySideDiffRowView(row: row, columnWidth: columnWidth)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(width: contentWidth, alignment: .topLeading)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct GitDiffColumnHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

private struct GitSideBySideDiffRowView: View {
    let row: GitSideBySideDiffRow
    let columnWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            GitDiffCell(
                lineNumber: row.previousLineNumber,
                text: row.previousText,
                kind: previousKind,
                width: columnWidth
            )
            GitVerticalRule()
            GitDiffCell(
                lineNumber: row.changedLineNumber,
                text: row.changedText,
                kind: changedKind,
                width: columnWidth
            )
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private var previousKind: GitSideBySideDiffKind {
        switch row.kind {
        case .context:
            .context
        case .insertion:
            .context
        case .deletion, .modification:
            row.previousText == nil ? .context : row.kind
        }
    }

    private var changedKind: GitSideBySideDiffKind {
        switch row.kind {
        case .context:
            .context
        case .deletion:
            .context
        case .insertion, .modification:
            row.changedText == nil ? .context : row.kind
        }
    }
}

private struct GitDiffCell: View {
    let lineNumber: Int?
    let text: String?
    let kind: GitSideBySideDiffKind
    let width: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(lineNumber.map(String.init) ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 42, alignment: .trailing)
                .textSelection(.disabled)

            Text(renderedText)
                .foregroundStyle(foregroundStyle)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: 17, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(backgroundStyle)
    }

    private var renderedText: String {
        guard let text, !text.isEmpty else { return " " }
        return text
    }

    private var foregroundStyle: Color {
        switch kind {
        case .insertion:
            .green
        case .deletion:
            .red
        case .modification:
            .primary
        case .context:
            .primary
        }
    }

    private var backgroundStyle: Color {
        switch kind {
        case .insertion:
            Color.green.opacity(0.13)
        case .deletion:
            Color.red.opacity(0.13)
        case .modification:
            Color.yellow.opacity(0.14)
        case .context:
            Color.clear
        }
    }
}

private struct GitVerticalRule: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.7))
            .frame(width: 1)
    }
}

private struct GitChangesEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(22)
    }
}
