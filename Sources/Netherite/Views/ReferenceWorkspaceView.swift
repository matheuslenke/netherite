import SwiftUI
import UniformTypeIdentifiers

struct ReferenceWorkspaceView: View {
    @EnvironmentObject private var store: VaultStore
    let isCompact: Bool
    @State private var editorMode: ReferenceEditorMode = .form
    @State private var isPDFDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if let reference = store.currentReference {
                header(reference)
                Divider()
                content(reference)
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: Rectangle())
    }

    private func header(_ reference: ReferenceItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                titleBlock(reference)
                Spacer(minLength: 12)
                headerButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                titleBlock(reference)
                headerButtons
            }
        }
        .padding(.horizontal, isCompact ? 12 : 18)
        .padding(.vertical, isCompact ? 10 : 12)
        .background(.regularMaterial, in: Rectangle())
    }

    private func titleBlock(_ reference: ReferenceItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(reference.displayTitle)
                    .font(isCompact ? .headline.weight(.semibold) : .title3.weight(.semibold))
                    .lineLimit(1)

                if store.isDuplicateReferenceKey(reference.citationKey) {
                    Label("Duplicate key", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text("\(reference.citationKey) - \(reference.type) - \(reference.yearText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var headerButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                referenceModePicker(width: 190)
                Button {
                    store.insertSelectedCitation()
                } label: {
                    Label("Insert Citation", systemImage: "text.badge.plus")
                }
                Button {
                    store.attachPDFToSelectedReferenceRequested()
                } label: {
                    Label("Attach PDF", systemImage: "paperclip")
                }
                Button {
                    store.exportAllReferencesRequested()
                } label: {
                    Label("Export All", systemImage: "square.and.arrow.up")
                }
                .disabled(store.references.isEmpty)
                Menu {
                    Button("Copy BibTeX") {
                        store.copySelectedBibTeXToClipboard()
                    }
                    Button("Export Selected...") {
                        store.exportSelectedReferencesRequested()
                    }
                    Divider()
                    Button("Open PDF") {
                        store.openSelectedReferencePDF()
                    }
                    .disabled(!(store.currentReference.map(store.referencePDFExists) ?? false))
                    Button("Reveal PDF") {
                        store.revealSelectedReferencePDF()
                    }
                    .disabled(!(store.currentReference.map(store.referencePDFExists) ?? false))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .help("More Reference Actions")
                .accessibilityLabel("More Reference Actions")
            }

            VStack(alignment: .leading, spacing: 8) {
                referenceModePicker(width: nil)
                HStack(spacing: 8) {
                    Button {
                        store.insertSelectedCitation()
                    } label: {
                        Label("Insert Citation", systemImage: "text.badge.plus")
                    }
                    Button {
                        store.attachPDFToSelectedReferenceRequested()
                    } label: {
                        Label("Attach PDF", systemImage: "paperclip")
                    }
                    Button {
                        store.exportAllReferencesRequested()
                    } label: {
                        Label("Export All", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.references.isEmpty)
                }
            }
        }
    }

    private func referenceModePicker(width: CGFloat?) -> some View {
        Picker("Reference Editor", selection: $editorMode) {
            ForEach(ReferenceEditorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: width)
    }

    @ViewBuilder
    private func content(_ reference: ReferenceItem) -> some View {
        if isCompact {
            VSplitView {
                editorPanel(reference)
                    .frame(minHeight: 260)
                pdfPanel(reference)
                    .frame(minHeight: 260)
            }
        } else {
            HSplitView {
                editorPanel(reference)
                    .frame(minWidth: 360, idealWidth: 460)
                pdfPanel(reference)
                    .frame(minWidth: 360)
            }
        }
    }

    private func editorPanel(_ reference: ReferenceItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                validationBanner

                switch editorMode {
                case .form:
                    formEditor(reference)
                case .raw:
                    rawEditor
                }

                GroupBox("Bibliography Preview") {
                    Text(reference.bibliographyPreview)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(isCompact ? 12 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var validationBanner: some View {
        if let message = store.selectedReferenceValidationMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func formEditor(_ reference: ReferenceItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("BibTeX") {
                VStack(alignment: .leading, spacing: 10) {
                    labeledField("Citation key", text: citationKeyBinding)
                    labeledField("Type", text: typeBinding)
                    labeledField("Title", text: fieldBinding("title"))
                    labeledField("Authors", text: fieldBinding("author"))
                    labeledField("Year", text: fieldBinding("year"))
                    labeledField("Journal", text: fieldBinding("journal"))
                    labeledField("Booktitle", text: fieldBinding("booktitle"))
                    labeledField("Publisher", text: fieldBinding("publisher"))
                    labeledField("DOI", text: fieldBinding("doi"))
                    labeledField("URL", text: fieldBinding("url"))
                }
            }

            GroupBox("Notes Fields") {
                VStack(alignment: .leading, spacing: 10) {
                    labeledField("Keywords", text: fieldBinding("keywords"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Abstract")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Abstract", text: fieldBinding("abstract"), axis: .vertical)
                            .lineLimit(3...8)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private var rawEditor: some View {
        GroupBox("Raw BibTeX") {
            TextEditor(text: rawBibTeXBinding)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 320)
                .textSelection(.enabled)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func pdfPanel(_ reference: ReferenceItem) -> some View {
        VStack(spacing: 0) {
            pdfHeader(reference)
            Divider()
            pdfBody(reference)
        }
        .background(isPDFDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear, in: Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isPDFDropTargeted) { providers in
            handlePDFDrop(providers)
        }
    }

    private func pdfHeader(_ reference: ReferenceItem) -> some View {
        HStack(spacing: 10) {
            Label(reference.pdfRelativePath == nil ? "No PDF Attached" : "Attached PDF", systemImage: "doc")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button {
                store.attachPDFToSelectedReferenceRequested()
            } label: {
                Label(reference.pdfRelativePath == nil ? "Attach" : "Replace", systemImage: "paperclip")
            }
            if reference.pdfRelativePath != nil {
                Button {
                    store.openSelectedReferencePDF()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .disabled(!store.referencePDFExists(reference))
                Button {
                    store.revealSelectedReferencePDF()
                } label: {
                    Label("Reveal", systemImage: "finder")
                }
                .disabled(!store.referencePDFExists(reference))
            }
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func pdfBody(_ reference: ReferenceItem) -> some View {
        if let pdfURL = store.referencePDFURL(for: reference), store.referencePDFExists(reference) {
            PDFReaderView(
                url: pdfURL,
                reloadToken: fileModifiedAt(pdfURL),
                state: readerStateBinding
            )
        } else if reference.pdfRelativePath != nil {
            EmptyReferencePDFState(
                title: "PDF is missing",
                message: reference.pdfRelativePath ?? "",
                systemImage: "doc.badge.ellipsis"
            )
        } else {
            EmptyReferencePDFState(
                title: "Attach a PDF",
                message: "Drop a PDF here or choose Attach PDF.",
                systemImage: "paperclip"
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No references")
                .font(.title3.weight(.semibold))
            HStack(spacing: 10) {
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
                Button {
                    store.exportAllReferencesRequested()
                } label: {
                    Label("Export All", systemImage: "square.and.arrow.up")
                }
                .disabled(store.references.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var citationKeyBinding: Binding<String> {
        Binding {
            store.currentReference?.citationKey ?? ""
        } set: { newValue in
            store.updateSelectedReferenceCitationKey(newValue)
        }
    }

    private var typeBinding: Binding<String> {
        Binding {
            store.currentReference?.type ?? ""
        } set: { newValue in
            store.updateSelectedReferenceType(newValue)
        }
    }

    private var rawBibTeXBinding: Binding<String> {
        Binding {
            store.currentReference?.rawBibTeX ?? ""
        } set: { newValue in
            store.updateSelectedReferenceRawBibTeX(newValue)
        }
    }

    private func fieldBinding(_ field: String) -> Binding<String> {
        Binding {
            store.currentReference?.field(field) ?? ""
        } set: { newValue in
            store.updateSelectedReferenceField(field, value: newValue)
        }
    }

    private var readerStateBinding: Binding<PDFReaderState> {
        Binding {
            store.currentReference?.readerState ?? PDFReaderState()
        } set: { newValue in
            store.updateSelectedReferenceReaderState(newValue)
        }
    }

    private func fileModifiedAt(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func handlePDFDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let referenceID = store.selectedReferenceID else { return false }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = droppedFileURL(from: item), url.pathExtension.lowercased() == "pdf" else { return }
                DispatchQueue.main.async {
                    store.attachPDF(url, to: referenceID)
                }
            }
            return true
        }
        return false
    }

    nonisolated private func droppedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }
}

private struct EmptyReferencePDFState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CitationPickerView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedID: ReferenceItem.ID?

    private var matches: [ReferenceItem] {
        let trimmedQuery = query.trimmed.lowercased()
        guard !trimmedQuery.isEmpty else { return store.references }
        return store.references.filter { $0.searchableText.contains(trimmedQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(selection: $selectedID) {
                ForEach(matches) { reference in
                    ReferencePickerRow(reference: reference)
                        .tag(reference.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedID = reference.id
                        }
                }
            }
            .frame(minHeight: 260)
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 390)
        .onAppear {
            selectedID = store.currentReference?.id ?? matches.first?.id
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insert Citation")
                .font(.title3.weight(.semibold))
            TextField("Search references", text: $query)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Insert") {
                insertSelected()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedReference == nil)
        }
        .padding(16)
    }

    private var selectedReference: ReferenceItem? {
        guard let selectedID else { return nil }
        return store.references.first { $0.id == selectedID }
    }

    private func insertSelected() {
        guard let selectedReference else { return }
        store.insertCitation(selectedReference)
        dismiss()
    }
}

private struct ReferencePickerRow: View {
    let reference: ReferenceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(reference.citationKey)
                .font(.system(.body, design: .monospaced).weight(.semibold))
            Text("\(reference.displayTitle) - \(reference.yearText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
