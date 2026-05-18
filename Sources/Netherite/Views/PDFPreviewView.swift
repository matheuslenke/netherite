import AppKit
import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    let file: VaultFile
    let isCompact: Bool
    let openPDF: () -> Void
    let revealPDF: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            PDFReaderView(
                url: file.url,
                reloadToken: file.modifiedAt,
                state: .constant(PDFReaderState())
            )
        }
        .glassEffect(.regular, in: Rectangle())
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                statusLabel
                Spacer()
                toolbarButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                statusLabel
                toolbarButtons
            }
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, 10)
    }

    private var statusLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("PDF Preview")
                    .font(.headline)
                    .lineLimit(1)
                Text(file.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        if isCompact {
            toolbarButtonRow
                .labelStyle(.iconOnly)
        } else {
            toolbarButtonRow
                .labelStyle(.titleAndIcon)
        }
    }

    private var toolbarButtonRow: some View {
        HStack(spacing: 8) {
            Button {
                openPDF()
            } label: {
                Label("Open PDF", systemImage: "arrow.up.right.square")
            }

            Button {
                revealPDF()
            } label: {
                Label("Reveal", systemImage: "finder")
            }
        }
    }
}

struct PDFKitPreview: NSViewRepresentable {
    let url: URL
    let reloadToken: Date?
    var onSourceLookup: ((PDFSourceLookupRequest) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = SourceLookupPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
        view.onSourceLookup = onSourceLookup
        loadDocument(in: view, context: context)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if let sourceLookupView = view as? SourceLookupPDFView {
            sourceLookupView.onSourceLookup = onSourceLookup
        }

        guard context.coordinator.url != url || context.coordinator.reloadToken != reloadToken else {
            return
        }
        loadDocument(in: view, context: context)
    }

    private func loadDocument(in view: PDFView, context: Context) {
        view.document = PDFDocument(url: url)
        view.autoScales = true
        context.coordinator.url = url
        context.coordinator.reloadToken = reloadToken
    }

    final class Coordinator {
        var url: URL?
        var reloadToken: Date?
    }
}

private final class SourceLookupPDFView: PDFView {
    var onSourceLookup: ((PDFSourceLookupRequest) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let eventPoint = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)

        guard event.clickCount == 2,
              let onSourceLookup,
              let request = sourceLookupRequest(at: eventPoint)
        else {
            return
        }

        onSourceLookup(request)
    }

    private func sourceLookupRequest(at viewPoint: NSPoint) -> PDFSourceLookupRequest? {
        guard let document,
              let pdfURL = document.documentURL,
              let page = page(for: viewPoint, nearest: true)
        else {
            return nil
        }

        let pagePoint = convert(viewPoint, to: page)
        let selectedText = page.selectionForWord(at: pagePoint)?.string?.trimmed

        let pageIndex = document.index(for: page)
        guard pageIndex >= 0 else { return nil }

        let pageBounds = page.bounds(for: displayBox)
        let x = max(pagePoint.x - pageBounds.minX, 0)
        let y = max(pageBounds.maxY - pagePoint.y, 0)

        return PDFSourceLookupRequest(
            pdfURL: pdfURL,
            pageNumber: pageIndex + 1,
            x: Double(x),
            y: Double(y),
            selectedText: selectedText?.isEmpty == true ? nil : selectedText
        )
    }
}

struct PDFReaderView: View {
    let url: URL
    let reloadToken: Date?
    @Binding var state: PDFReaderState
    @State private var pageCount = 0
    @State private var currentPageIndex = 0
    @State private var searchText = ""
    @State private var command: PDFReaderCommand?

    var body: some View {
        VStack(spacing: 0) {
            readerToolbar
            Divider()
            PDFKitReader(
                url: url,
                reloadToken: reloadToken,
                state: $state,
                pageCount: $pageCount,
                currentPageIndex: $currentPageIndex,
                command: command
            )
        }
    }

    private var readerToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                navigationControls
                Divider().frame(height: 18)
                zoomControls
                Spacer()
                searchField(width: 190)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    navigationControls
                    Divider().frame(height: 18)
                    zoomControls
                    Spacer()
                }
                searchField(width: nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.18), in: Rectangle())
    }

    private var navigationControls: some View {
        HStack(spacing: 6) {
            Button {
                send(.previousPage)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Previous Page")
            .accessibilityLabel("Previous Page")
            .disabled(pageCount <= 1 || currentPageIndex <= 0)

            Text(pageStatus)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64)

            Button {
                send(.nextPage)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Next Page")
            .accessibilityLabel("Next Page")
            .disabled(pageCount <= 1 || currentPageIndex >= max(pageCount - 1, 0))
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            Button {
                send(.zoomOut)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom Out")
            .accessibilityLabel("Zoom Out")

            Button {
                send(.zoomIn)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom In")
            .accessibilityLabel("Zoom In")
        }
    }

    private func searchField(width: CGFloat?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search PDF", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .onSubmit {
                    send(.search(searchText))
                }
                .onChange(of: searchText) { _, newValue in
                    send(.search(newValue))
                }
        }
    }

    private var pageStatus: String {
        guard pageCount > 0 else { return "No pages" }
        return "\(min(currentPageIndex + 1, pageCount)) / \(pageCount)"
    }

    private func send(_ action: PDFReaderAction) {
        command = PDFReaderCommand(action: action)
    }
}

private enum PDFReaderAction: Equatable {
    case previousPage
    case nextPage
    case zoomIn
    case zoomOut
    case search(String)
}

private struct PDFReaderCommand: Equatable {
    let id = UUID()
    let action: PDFReaderAction
}

private struct PDFKitReader: NSViewRepresentable {
    let url: URL
    let reloadToken: Date?
    @Binding var state: PDFReaderState
    @Binding var pageCount: Int
    @Binding var currentPageIndex: Int
    let command: PDFReaderCommand?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
        view.minScaleFactor = 0.25
        view.maxScaleFactor = 5
        context.coordinator.pdfView = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: view
        )
        loadDocument(in: view, context: context)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.url != url || context.coordinator.reloadToken != reloadToken {
            loadDocument(in: view, context: context)
        }
        if context.coordinator.lastCommandID != command?.id {
            execute(command, in: view, context: context)
        }
    }

    private func loadDocument(in view: PDFView, context: Context) {
        let document = PDFDocument(url: url)
        view.document = document
        view.autoScales = state.scaleFactor <= 0
        if state.scaleFactor > 0 {
            view.scaleFactor = state.scaleFactor
        }

        context.coordinator.url = url
        context.coordinator.reloadToken = reloadToken
        pageCount = document?.pageCount ?? 0

        if let document, document.pageCount > 0 {
            let pageIndex = min(max(state.lastPageIndex, 0), document.pageCount - 1)
            if let page = document.page(at: pageIndex) {
                view.go(to: page)
                currentPageIndex = pageIndex
            }
        } else {
            currentPageIndex = 0
        }
    }

    private func execute(_ command: PDFReaderCommand?, in view: PDFView, context: Context) {
        guard let command else { return }
        context.coordinator.lastCommandID = command.id

        switch command.action {
        case .previousPage:
            view.goToPreviousPage(nil)
        case .nextPage:
            view.goToNextPage(nil)
        case .zoomIn:
            view.autoScales = false
            view.scaleFactor = min(view.scaleFactor * 1.15, view.maxScaleFactor)
            state.scaleFactor = view.scaleFactor
        case .zoomOut:
            view.autoScales = false
            view.scaleFactor = max(view.scaleFactor / 1.15, view.minScaleFactor)
            state.scaleFactor = view.scaleFactor
        case let .search(query):
            applySearch(query, in: view)
        }

        context.coordinator.capturePageState()
    }

    private func applySearch(_ query: String, in view: PDFView) {
        let trimmedQuery = query.trimmed
        guard !trimmedQuery.isEmpty else {
            view.highlightedSelections = []
            return
        }

        let selections = view.document?.findString(trimmedQuery, withOptions: [.caseInsensitive]) ?? []
        view.highlightedSelections = selections
        if let first = selections.first {
            view.go(to: first)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFKitReader
        weak var pdfView: PDFView?
        var url: URL?
        var reloadToken: Date?
        var lastCommandID: UUID?

        init(_ parent: PDFKitReader) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func pageChanged(_ notification: Notification) {
            capturePageState()
        }

        func capturePageState() {
            guard let pdfView,
                  let document = pdfView.document,
                  let page = pdfView.currentPage
            else {
                return
            }

            let index = document.index(for: page)
            guard index >= 0 else { return }
            parent.currentPageIndex = index
            parent.pageCount = document.pageCount
            parent.state.lastPageIndex = index
            if !pdfView.autoScales {
                parent.state.scaleFactor = pdfView.scaleFactor
            }
        }
    }
}
