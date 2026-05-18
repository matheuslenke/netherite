import AppKit
import SwiftUI

struct EditorWorkspaceView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var confirmDelete: Bool
    let isCompact: Bool
    @Binding var markdownScrollTargetID: Int?
    @Binding var sourceScrollTargetOffset: Int?
    @State private var findText = ""
    @State private var findPanelVisible = false
    @State private var findScope = EditorFindScope.currentFile
    @State private var findResults: [ContentSearchResult] = []
    @State private var selectedFindResultID: ContentSearchResult.ID?
    @State private var findTask: Task<Void, Never>?
    @State private var isSearchingAllFiles = false
    @State private var controlsMenuVisible = false
    @State private var documentScrollSync = ScrollSyncState.initial
    @State private var pendingLatexSourceNavigation: PendingLatexSourceNavigation?
    @State private var pendingFindNavigation: PendingFindNavigation?
    @State private var editorSplitOriginalFraction = SplitPaneMetrics.editorSplitOriginalFraction
    @FocusState private var findFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !store.openFileTabIDs.isEmpty {
                FileTabBar(isCompact: isCompact) {
                    controlsMenuButton
                }
                Divider()
            }
            if findPanelVisible {
                findPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }
            editorBody
                .animation(contentAnimation, value: store.editorMode)
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor), in: Rectangle())
        .onChange(of: store.currentFile?.id) { _, _ in
            handleSelectedFileChanged()
            resetEditorSplit()
        }
        .onChange(of: store.editorMode) { _, newMode in
            if newMode == .split {
                resetEditorSplit()
            }
        }
        .onChange(of: store.documentIsEditable) { _, _ in
            applyPendingLatexSourceNavigationIfReady()
        }
        .onChange(of: store.documentText) { _, _ in
            applyPendingLatexSourceNavigationIfReady()
            refreshFindResults()
            applyPendingFindNavigationIfReady()
        }
        .onChange(of: findText) { _, _ in
            refreshFindResults()
        }
        .onChange(of: findScope) { _, _ in
            refreshFindResults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findRequested)) { _ in
            showFindPanel()
        }
        .onDisappear {
            findTask?.cancel()
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        switch store.editorMode {
        case .edit:
            SourceEditor(
                text: documentBinding,
                isEditable: store.documentIsEditable,
                language: SyntaxLanguage(fileKind: store.currentFile?.kind),
                scrollSync: nil,
                scrollTargetOffset: $sourceScrollTargetOffset
            )
        case .preview:
            previewPane
        case .split:
            if isCompact {
                VSplitView {
                    SourceEditor(
                        text: documentBinding,
                        isEditable: store.documentIsEditable,
                        language: SyntaxLanguage(fileKind: store.currentFile?.kind),
                        scrollSync: synchronizedScrollBinding,
                        scrollTargetOffset: $sourceScrollTargetOffset
                    )
                    .frame(minHeight: 90)
                    previewPane
                        .frame(minHeight: 180)
                }
            } else {
                EditorSplitView(originalFraction: $editorSplitOriginalFraction) {
                    SourceEditor(
                        text: documentBinding,
                        isEditable: store.documentIsEditable,
                        language: SyntaxLanguage(fileKind: store.currentFile?.kind),
                        scrollSync: synchronizedScrollBinding,
                        scrollTargetOffset: $sourceScrollTargetOffset
                    )
                } preview: {
                    previewPane
                }
            }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if store.selectedFileCanRenderLatex {
            LatexPreviewView(
                state: store.latexRenderState,
                isCompact: isCompact,
                render: store.renderLatexForCurrentFile,
                openPDF: store.openRenderedLatexPDF,
                revealPDF: store.revealRenderedLatexPDF,
                openIncludedFile: openIncludedLatexFile,
                navigateToSource: navigateToLatexSource
            )
            .task(id: store.currentFile?.id) {
                store.renderLatexForCurrentFileIfNeeded()
            }
        } else if let file = store.currentFile, file.isPDF {
            PDFPreviewView(
                file: file,
                isCompact: isCompact,
                openPDF: store.openSelectedExternally,
                revealPDF: store.revealSelectedInFinder
            )
        } else if let file = store.currentFile, file.isSpreadsheet {
            ExcelPreviewView(
                file: file,
                isCompact: isCompact,
                openWorkbook: store.openSelectedExternally,
                revealWorkbook: store.revealSelectedInFinder
            )
        } else {
            MarkdownPreviewView(
                text: documentBinding,
                file: store.currentFile,
                isCompact: isCompact,
                isEditable: store.editorMode == .preview && store.documentIsEditable,
                scrollSync: synchronizedScrollBinding,
                scrollTargetID: $markdownScrollTargetID
            )
        }
    }

    private var footer: some View {
        Group {
            if isCompact {
                compactFooter
            } else {
                regularFooter
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, isCompact ? 12 : 18)
        .padding(.vertical, isCompact ? 4 : 5)
        .background(.regularMaterial, in: Rectangle())
    }

    private var regularFooter: some View {
        HStack(spacing: 14) {
            Label("\(store.documentStats.words) words", systemImage: "text.word.spacing")
            Label("\(store.documentStats.lines) lines", systemImage: "list.number")
            Label(ByteCountFormatter.string(fromByteCount: Int64(store.currentFile?.byteCount ?? 0), countStyle: .file), systemImage: "internaldrive")

            Spacer()

            if !store.documentIsEditable {
                Label("Read-only", systemImage: "lock")
            }

            Text(store.gitSnapshot.summary)
        }
    }

    private var compactFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text("\(store.documentStats.words) words")
                Text("\(store.documentStats.lines) lines")
                Text(ByteCountFormatter.string(fromByteCount: Int64(store.currentFile?.byteCount ?? 0), countStyle: .file))

                Spacer()

                if !store.documentIsEditable {
                    Label("Read-only", systemImage: "lock")
                }
            }

            Text(store.gitSnapshot.summary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var findPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                TextField("Find", text: $findText)
                    .textFieldStyle(.roundedBorder)
                    .focused($findFieldFocused)
                    .onSubmit {
                        selectNextFindResult()
                    }

                Picker("Scope", selection: $findScope) {
                    ForEach(EditorFindScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: isCompact ? 180 : 210)

                Text(findStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .frame(minWidth: 68, alignment: .trailing)

                Button {
                    selectPreviousFindResult()
                } label: {
                    Label("Previous Result", systemImage: "chevron.up")
                }
                .labelStyle(.iconOnly)
                .disabled(findResults.isEmpty)
                .help("Previous result")

                Button {
                    selectNextFindResult()
                } label: {
                    Label("Next Result", systemImage: "chevron.down")
                }
                .labelStyle(.iconOnly)
                .disabled(findResults.isEmpty)
                .help("Next result")

                Button {
                    hideFindPanel()
                } label: {
                    Label("Close Find", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .help("Close find")
            }
            .padding(.horizontal, isCompact ? 10 : 14)
            .padding(.vertical, 8)

            if shouldShowFindResults {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if findResults.isEmpty {
                            findEmptyState
                        } else {
                            ForEach(findResults) { result in
                                FindResultRow(
                                    result: result,
                                    showsFileName: findScope == .allFiles,
                                    isSelected: result.id == selectedFindResultID
                                ) {
                                    selectFindResult(result)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: isCompact ? 140 : 180)
            }
        }
        .background(.bar, in: Rectangle())
    }

    private var controlsMenuButton: some View {
        Button {
            withAnimation(contentAnimation) {
                controlsMenuVisible.toggle()
            }
        } label: {
            Label(controlsMenuVisible ? "Hide View Controls" : "Show View Controls", systemImage: "slider.horizontal.3")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(controlsMenuVisible ? "Hide View Controls" : "Show View Controls")
        .accessibilityLabel(controlsMenuVisible ? "Hide View Controls" : "Show View Controls")
        .popover(isPresented: $controlsMenuVisible, arrowEdge: .bottom) {
            controlsMenu
        }
    }

    private var controlsMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            modePicker(width: 230)

            Divider()

            Button {
                controlsMenuVisible = false
                showFindPanel()
            } label: {
                Label("Find...", systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)

            if store.selectedFileCanRenderLatex {
                Divider()

                latexRenderButton(iconOnly: false)
            }

            Divider()

            fileActionButtons
        }
        .padding(12)
        .frame(width: 270)
    }

    private func modePicker(width: CGFloat?) -> some View {
        Picker("Mode", selection: editorModeBinding) {
            ForEach(store.availableEditorModes) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: width)
    }

    @ViewBuilder
    private func latexRenderButton(iconOnly: Bool) -> some View {
        if store.selectedFileCanRenderLatex {
            if iconOnly {
                Button {
                    store.renderLatexForCurrentFile()
                } label: {
                    Label(store.latexRenderState.isRendering ? "Rendering" : "Render", systemImage: "arrow.triangle.2.circlepath")
                }
                .labelStyle(.iconOnly)
                .disabled(store.latexRenderState.isRendering)
                .help("Render LaTeX")
            } else {
                Button {
                    store.renderLatexForCurrentFile()
                } label: {
                    Label(store.latexRenderState.isRendering ? "Rendering" : "Render", systemImage: "arrow.triangle.2.circlepath")
                }
                .labelStyle(.titleAndIcon)
                .disabled(store.latexRenderState.isRendering)
                .help("Render LaTeX")
            }
        }
    }

    private var fileActionButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                controlsMenuVisible = false
                store.revealSelectedInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .buttonStyle(.plain)

            Button {
                controlsMenuVisible = false
                store.openSelectedExternally()
            } label: {
                Label("Open Externally", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                controlsMenuVisible = false
                confirmDelete = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var documentBinding: Binding<String> {
        Binding {
            store.documentText
        } set: { newValue in
            store.setDocumentText(newValue)
        }
    }

    private var editorModeBinding: Binding<EditorMode> {
        Binding {
            store.editorMode
        } set: { newValue in
            store.setEditorMode(newValue)
        }
    }

    private var synchronizedScrollBinding: Binding<ScrollSyncState>? {
        guard store.editorMode == .split,
              isCompact || editorSplitIsBalanced
        else {
            return nil
        }

        return $documentScrollSync
    }

    private var editorSplitIsBalanced: Bool {
        abs(editorSplitOriginalFraction - SplitPaneMetrics.editorSplitOriginalFraction)
            <= SplitPaneMetrics.editorSplitSyncFractionTolerance
    }

    private func navigateToLatexSource(_ request: PDFSourceLookupRequest) {
        Task {
            let location = await Task.detached(priority: .userInitiated) {
                try? LatexSourceLocator.sourceLocation(for: request)
            }.value

            await MainActor.run {
                revealLatexSource(location: location, fallbackText: request.selectedText)
            }
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
        store.statusMessage = "Opened \(includedFile.relativePath)"
    }

    private func revealLatexSource(location: LatexSourceLocation?, fallbackText: String?) {
        if let location,
           let fileID = store.fileID(forLatexSourceLocation: location),
           let file = store.file(id: fileID) {
            pendingLatexSourceNavigation = PendingLatexSourceNavigation(fileID: fileID, location: location)
            if store.selectedFileID != fileID {
                store.openFile(fileID)
            }
            store.setEditorMode(.split)
            applyPendingLatexSourceNavigationIfReady()
            store.statusMessage = "Jumped to \(file.relativePath):\(location.line)"
            return
        }

        if let offset = LatexSourceLocator.bestTextMatchOffset(in: store.documentText, selectedText: fallbackText) {
            store.setEditorMode(.split)
            sourceScrollTargetOffset = offset
            store.statusMessage = "Jumped to selected PDF text in source"
        } else {
            store.statusMessage = "Could not map the PDF selection to the LaTeX source."
        }
    }

    private var contentAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22)
    }

    private func resetDocumentScrollSync() {
        documentScrollSync = ScrollSyncState(
            source: .editor,
            progress: 0,
            revision: documentScrollSync.revision + 1
        )
    }

    private func handleSelectedFileChanged() {
        resetDocumentScrollSync()
        if let pendingLatexSourceNavigation,
           pendingLatexSourceNavigation.fileID != store.selectedFileID {
            self.pendingLatexSourceNavigation = nil
        }
        applyPendingLatexSourceNavigationIfReady()
        refreshFindResults()
        applyPendingFindNavigationIfReady()
    }

    private func resetEditorSplit() {
        editorSplitOriginalFraction = SplitPaneMetrics.editorSplitOriginalFraction
    }

    private func applyPendingLatexSourceNavigationIfReady() {
        guard let pendingLatexSourceNavigation,
              store.selectedFileID == pendingLatexSourceNavigation.fileID,
              store.documentIsEditable
        else {
            return
        }

        sourceScrollTargetOffset = LatexSourceLocator.sourceOffset(
            in: store.documentText,
            line: pendingLatexSourceNavigation.location.line,
            column: pendingLatexSourceNavigation.location.column
        )
        self.pendingLatexSourceNavigation = nil
    }

    private var findStatusText: String {
        if isSearchingAllFiles {
            return "Searching..."
        }

        guard !findText.trimmed.isEmpty else {
            return "Ready"
        }

        let count = findResults.count
        guard count > 0 else { return "No results" }

        if let selectedIndex = selectedFindResultIndex {
            return "\(selectedIndex + 1) of \(count)"
        }

        return "\(count) result\(count == 1 ? "" : "s")"
    }

    private var shouldShowFindResults: Bool {
        findPanelVisible && !findText.trimmed.isEmpty
    }

    private var selectedFindResultIndex: Int? {
        guard let selectedFindResultID else { return nil }
        return findResults.firstIndex { $0.id == selectedFindResultID }
    }

    private var findEmptyState: some View {
        Text(isSearchingAllFiles ? "Searching files..." : "No matches")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isCompact ? 10 : 14)
            .padding(.vertical, 10)
    }

    private func showFindPanel() {
        controlsMenuVisible = false
        withAnimation(contentAnimation) {
            findPanelVisible = true
        }
        refreshFindResults()

        DispatchQueue.main.async {
            findFieldFocused = true
        }
    }

    private func hideFindPanel() {
        findTask?.cancel()
        isSearchingAllFiles = false
        withAnimation(contentAnimation) {
            findPanelVisible = false
        }
    }

    private func refreshFindResults() {
        findTask?.cancel()

        guard findPanelVisible else { return }

        let query = findText.trimmed
        guard !query.isEmpty else {
            isSearchingAllFiles = false
            findResults = []
            selectedFindResultID = nil
            return
        }

        switch findScope {
        case .currentFile:
            isSearchingAllFiles = false
            guard let file = store.currentFile else {
                findResults = []
                selectedFindResultID = nil
                return
            }

            applyFindResults(ContentSearchService.searchCurrentFile(
                text: store.documentText,
                file: file,
                query: query
            ))
        case .allFiles:
            isSearchingAllFiles = true
            let files = store.files
            findTask = Task { [query, files] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }

                let results = await Task.detached(priority: .userInitiated) {
                    ContentSearchService.searchFiles(files, query: query)
                }.value

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    isSearchingAllFiles = false
                    applyFindResults(results)
                }
            }
        }
    }

    private func applyFindResults(_ results: [ContentSearchResult]) {
        findResults = results
        if let selectedFindResultID,
           results.contains(where: { $0.id == selectedFindResultID }) {
            return
        }

        selectedFindResultID = results.first?.id
        if findScope == .currentFile, let first = results.first {
            jumpToFindResult(first, openingFile: false)
        }
    }

    private func selectPreviousFindResult() {
        guard !findResults.isEmpty else { return }

        let currentIndex = selectedFindResultIndex ?? 0
        let nextIndex = currentIndex == 0 ? findResults.count - 1 : currentIndex - 1
        selectFindResult(findResults[nextIndex])
    }

    private func selectNextFindResult() {
        guard !findResults.isEmpty else { return }

        let currentIndex = selectedFindResultIndex ?? -1
        let nextIndex = currentIndex >= findResults.count - 1 ? 0 : currentIndex + 1
        selectFindResult(findResults[nextIndex])
    }

    private func selectFindResult(_ result: ContentSearchResult) {
        selectedFindResultID = result.id
        jumpToFindResult(result, openingFile: true)
    }

    private func jumpToFindResult(_ result: ContentSearchResult, openingFile: Bool) {
        pendingFindNavigation = PendingFindNavigation(fileID: result.fileID, offset: result.offset)

        if store.selectedFileID != result.fileID, openingFile {
            store.openFile(result.fileID)
        } else {
            applyPendingFindNavigationIfReady()
        }
    }

    private func applyPendingFindNavigationIfReady() {
        guard let pendingFindNavigation,
              store.selectedFileID == pendingFindNavigation.fileID
        else {
            return
        }

        store.setEditorMode(store.selectedFileIsPreviewOnly ? .preview : .split)
        sourceScrollTargetOffset = pendingFindNavigation.offset
        self.pendingFindNavigation = nil
    }
}

private struct EditorSplitView<Original: View, Preview: View>: NSViewRepresentable {
    @Binding private var originalFraction: CGFloat
    private let original: Original
    private let preview: Preview

    init(
        originalFraction: Binding<CGFloat>,
        @ViewBuilder original: () -> Original,
        @ViewBuilder preview: () -> Preview
    ) {
        self._originalFraction = originalFraction
        self.original = original()
        self.preview = preview()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(originalFraction: $originalFraction)
    }

    func makeNSView(context: Context) -> EditorNSSplitView {
        let splitView = EditorNSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = nil
        splitView.delegate = context.coordinator

        let originalHostingView = NSHostingView(rootView: original)
        let previewHostingView = NSHostingView(rootView: preview)
        originalHostingView.translatesAutoresizingMaskIntoConstraints = false
        previewHostingView.translatesAutoresizingMaskIntoConstraints = false

        splitView.addArrangedSubview(originalHostingView)
        splitView.addArrangedSubview(previewHostingView)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        context.coordinator.originalHostingView = originalHostingView
        context.coordinator.previewHostingView = previewHostingView
        context.coordinator.applyFractionIfNeeded(to: splitView, force: true)

        return splitView
    }

    func updateNSView(_ splitView: EditorNSSplitView, context: Context) {
        context.coordinator.originalFraction = $originalFraction
        context.coordinator.originalHostingView?.rootView = original
        context.coordinator.previewHostingView?.rootView = preview
        context.coordinator.applyFractionIfNeeded(to: splitView)
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        var originalFraction: Binding<CGFloat>
        weak var originalHostingView: NSHostingView<Original>?
        weak var previewHostingView: NSHostingView<Preview>?
        private var isApplyingFraction = false

        init(originalFraction: Binding<CGFloat>) {
            self.originalFraction = originalFraction
        }

        func applyFractionIfNeeded(to splitView: NSSplitView, force: Bool = false) {
            let availableWidth = max(splitView.bounds.width - splitView.dividerThickness, 0)
            guard availableWidth > 0 else {
                DispatchQueue.main.async { [weak self, weak splitView] in
                    guard let self, let splitView else { return }
                    self.applyFractionIfNeeded(to: splitView, force: force)
                }
                return
            }

            let targetPosition = originalWidth(for: availableWidth)
            let currentPosition = splitView.arrangedSubviews.first?.frame.width ?? 0
            guard force || abs(currentPosition - targetPosition) > 0.5 else { return }

            isApplyingFraction = true
            splitView.setPosition(targetPosition, ofDividerAt: 0)
            isApplyingFraction = false
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !isApplyingFraction,
                  let splitView = notification.object as? NSSplitView
            else {
                return
            }

            let availableWidth = max(splitView.bounds.width - splitView.dividerThickness, 0)
            guard availableWidth > 0,
                  let originalWidth = splitView.arrangedSubviews.first?.frame.width
            else {
                return
            }

            let newFraction = min(max(originalWidth / availableWidth, 0), 1)
            guard abs(originalFraction.wrappedValue - newFraction) > SynchronizedScrolling.progressTolerance else { return }

            DispatchQueue.main.async { [originalFraction] in
                originalFraction.wrappedValue = newFraction
            }
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let availableWidth = max(splitView.bounds.width - splitView.dividerThickness, 0)
            let minimumTotalWidth = SplitPaneMetrics.editorOriginalMinWidth + SplitPaneMetrics.editorPreviewMinWidth
            return availableWidth > minimumTotalWidth ? SplitPaneMetrics.editorOriginalMinWidth : proposedMinimumPosition
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let availableWidth = max(splitView.bounds.width - splitView.dividerThickness, 0)
            let minimumTotalWidth = SplitPaneMetrics.editorOriginalMinWidth + SplitPaneMetrics.editorPreviewMinWidth
            return availableWidth > minimumTotalWidth
                ? availableWidth - SplitPaneMetrics.editorPreviewMinWidth
                : proposedMaximumPosition
        }

        func splitView(
            _ splitView: NSSplitView,
            effectiveRect proposedEffectiveRect: NSRect,
            forDrawnRect drawnRect: NSRect,
            ofDividerAt dividerIndex: Int
        ) -> NSRect {
            let extraWidth = max(SplitPaneMetrics.editorSplitResizeHitWidth - drawnRect.width, 0)
            return drawnRect.insetBy(dx: -extraWidth / 2, dy: 0)
        }

        private func originalWidth(for availableWidth: CGFloat) -> CGFloat {
            let minimumTotalWidth = SplitPaneMetrics.editorOriginalMinWidth + SplitPaneMetrics.editorPreviewMinWidth

            guard availableWidth > minimumTotalWidth else {
                return availableWidth * SplitPaneMetrics.editorSplitOriginalFraction
            }

            return min(
                max(availableWidth * originalFraction.wrappedValue, SplitPaneMetrics.editorOriginalMinWidth),
                availableWidth - SplitPaneMetrics.editorPreviewMinWidth
            )
        }
    }
}

private final class EditorNSSplitView: NSSplitView {
    override var dividerThickness: CGFloat {
        SplitPaneMetrics.editorSplitDividerWidth
    }

    override func drawDivider(in rect: NSRect) {
        NSColor.separatorColor.setFill()
        rect.fill()
    }
}

private struct PendingLatexSourceNavigation: Equatable {
    let fileID: String
    let location: LatexSourceLocation
}

private struct PendingFindNavigation: Equatable {
    let fileID: String
    let offset: Int
}

private enum EditorFindScope: String, CaseIterable, Identifiable {
    case currentFile
    case allFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentFile:
            "Current File"
        case .allFiles:
            "All Files"
        }
    }
}

private struct FindResultRow: View {
    let result: ContentSearchResult
    let showsFileName: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(result.line)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    if showsFileName {
                        Text(result.relativePath)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text(result.snippet.isEmpty ? result.fileName : result.snippet)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SourceEditor: View {
    @Binding var text: String
    let isEditable: Bool
    let language: SyntaxLanguage
    var scrollSync: Binding<ScrollSyncState>?
    var scrollTargetOffset: Binding<Int?>?

    var body: some View {
        SyntaxHighlightingEditor(
            text: $text,
            language: language,
            isEditable: isEditable,
            scrollSync: scrollSync,
            scrollTargetOffset: scrollTargetOffset,
            scrollSyncSource: .editor
        )
            .background(Color(nsColor: .textBackgroundColor), in: Rectangle())
    }
}

private struct FileTabBar<TrailingAccessory: View>: View {
    @EnvironmentObject private var store: VaultStore
    let isCompact: Bool
    let trailingAccessory: TrailingAccessory

    init(isCompact: Bool, @ViewBuilder trailingAccessory: () -> TrailingAccessory) {
        self.isCompact = isCompact
        self.trailingAccessory = trailingAccessory()
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(store.openFileTabIDs, id: \.self) { fileID in
                        if let file = store.file(id: fileID) {
                            FileTabButton(
                                file: file,
                                isSelected: store.selectedFileID == file.id,
                                isPreview: store.previewTabFileID == file.id,
                                isDirty: store.selectedFileID == file.id && store.isDirty,
                                isCompact: isCompact
                            )
                        }
                    }
                }
            }

            Divider()

            trailingAccessory
                .padding(.horizontal, 8)
        }
        .frame(height: isCompact ? 30 : 32)
        .background(.bar, in: Rectangle())
    }
}

private struct FileTabButton: View {
    @EnvironmentObject private var store: VaultStore
    let file: VaultFile
    let isSelected: Bool
    let isPreview: Bool
    let isDirty: Bool
    let isCompact: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: file.kind.systemImage)
                .font(.system(size: isCompact ? 10 : 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            tabTitle

            Spacer(minLength: 4)

            if isDirty && !isHovering {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .help("Unsaved changes")
            } else {
                Button {
                    store.closeTab(fileID: file.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .frame(width: 17, height: 17)
                }
                .buttonStyle(.borderless)
                .opacity(isSelected || isHovering ? 1 : 0)
                .allowsHitTesting(isSelected || isHovering)
                .help("Close")
                .accessibilityLabel("Close \(file.name)")
            }
        }
        .padding(.leading, isCompact ? 9 : 11)
        .padding(.trailing, 6)
        .frame(
            minWidth: isCompact ? 106 : 126,
            maxWidth: isCompact ? 168 : 210,
            minHeight: isCompact ? 30 : 32
        )
        .background(tabBackground, in: Rectangle())
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTab(fileID: file.id)
        }
        .onTapGesture(count: 2) {
            store.pinTab(fileID: file.id)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            if isPreview {
                Button("Keep Open") {
                    store.pinTab(fileID: file.id)
                }
            }
            Button("Close") {
                store.closeTab(fileID: file.id)
            }
            Button("Close Others") {
                store.closeOtherTabs(keeping: file.id)
            }
            Button("Close All") {
                store.closeAllTabs()
            }
        }
        .help(isPreview ? "\(file.relativePath) (preview)" : file.relativePath)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPreview ? "\(file.name), preview tab" : "\(file.name), tab")
    }

    @ViewBuilder
    private var tabTitle: some View {
        Text(file.name)
            .font(tabFont)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
    }

    private var tabFont: Font {
        let font = Font.system(size: isCompact ? 11 : 11.5, weight: isSelected ? .semibold : .regular)
        return isPreview ? font.italic() : font
    }

    private var tabBackground: Color {
        if isSelected {
            return Color(nsColor: .textBackgroundColor)
        }
        if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.9)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.55)
    }
}
