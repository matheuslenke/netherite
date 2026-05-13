import SwiftUI

struct EditorWorkspaceView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var confirmDelete: Bool
    let isCompact: Bool
    @State private var findText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editorBody
                .animation(contentAnimation, value: store.editorMode)
            Divider()
            footer
        }
        .glassEffect(.regular, in: Rectangle())
    }

    private var header: some View {
        GlassEffectContainer(spacing: 8) {
            Group {
                if isCompact {
                    compactHeader
                } else {
                    regularHeader
                }
            }
            .padding(.horizontal, isCompact ? 12 : 18)
            .padding(.vertical, isCompact ? 9 : 12)
        }
        .animation(contentAnimation, value: isCompact)
    }

    private var regularHeader: some View {
        HStack(spacing: 14) {
            fileTitle

            Spacer(minLength: 16)

            findControl(width: 180)
            latexRenderButton(iconOnly: false)
            modePicker(width: 220)
            moreMenu
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                fileTitle
                Spacer(minLength: 8)
                latexRenderButton(iconOnly: true)
                moreMenu
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    findControl(width: 150)
                    modePicker(width: 200)
                }

                VStack(alignment: .leading, spacing: 8) {
                    findControl(width: nil)
                    modePicker(width: nil)
                }
            }
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        switch store.editorMode {
        case .edit:
            SourceEditor(
                text: documentBinding,
                isEditable: store.documentIsEditable,
                language: SyntaxLanguage(fileKind: store.currentFile?.kind)
            )
        case .preview:
            previewPane
        case .split:
            if isCompact {
                VSplitView {
                    SourceEditor(
                        text: documentBinding,
                        isEditable: store.documentIsEditable,
                        language: SyntaxLanguage(fileKind: store.currentFile?.kind)
                    )
                    .frame(minHeight: 90)
                    previewPane
                        .frame(minHeight: 180)
                }
            } else {
                HSplitView {
                    SourceEditor(
                        text: documentBinding,
                        isEditable: store.documentIsEditable,
                        language: SyntaxLanguage(fileKind: store.currentFile?.kind)
                    )
                    .frame(minWidth: 260)
                    previewPane
                        .frame(minWidth: 320)
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
                revealPDF: store.revealRenderedLatexPDF
            )
            .task(id: store.currentFile?.id) {
                store.renderLatexForCurrentFileIfNeeded()
            }
        } else {
            MarkdownPreviewView(
                text: documentBinding,
                file: store.currentFile,
                isCompact: isCompact,
                isEditable: store.documentIsEditable
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
        .padding(.vertical, isCompact ? 6 : 7)
        .glassEffect(.regular, in: Rectangle())
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

    private var fileTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.currentFile?.name ?? "No file")
                .font(isCompact ? .headline.weight(.semibold) : .title3.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(store.currentFile?.relativePath ?? "")
                Text("•")
                Text(store.documentSourceDescription)
                if store.isDirty {
                    Text("• Unsaved")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
    }

    private func findControl(width: CGFloat?) -> some View {
        HStack(spacing: 6) {
            TextField("Find", text: $findText)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)

            if !findText.isEmpty {
                Text("\(matchCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .frame(minWidth: 24)
                    .animation(contentAnimation, value: matchCount)
            }
        }
        .accessibilityLabel("Find in current document")
        .help("Find in current document")
    }

    private func modePicker(width: CGFloat?) -> some View {
        Picker("Mode", selection: $store.editorMode) {
            ForEach(EditorMode.allCases) { mode in
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

    private var moreMenu: some View {
        Menu {
            Button("Reveal in Finder") {
                store.revealSelectedInFinder()
            }
            Button("Open Externally") {
                store.openSelectedExternally()
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                confirmDelete = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("More File Actions")
        .accessibilityLabel("More File Actions")
    }

    private var documentBinding: Binding<String> {
        Binding {
            store.documentText
        } set: { newValue in
            store.setDocumentText(newValue)
        }
    }

    private var matchCount: Int {
        let query = findText.trimmed
        guard !query.isEmpty else { return 0 }

        var count = 0
        var searchRange = store.documentText.startIndex..<store.documentText.endIndex
        while let range = store.documentText.range(of: query, options: [.caseInsensitive], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<store.documentText.endIndex
        }
        return count
    }

    private var contentAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22)
    }
}

private struct SourceEditor: View {
    @Binding var text: String
    let isEditable: Bool
    let language: SyntaxLanguage

    var body: some View {
        SyntaxHighlightingEditor(text: $text, language: language, isEditable: isEditable)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
    }
}
