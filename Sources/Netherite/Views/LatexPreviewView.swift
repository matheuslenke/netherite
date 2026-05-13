import AppKit
import PDFKit
import SwiftUI

struct LatexPreviewView: View {
    let state: LatexRenderState
    let isCompact: Bool
    let render: () -> Void
    let openPDF: () -> Void
    let revealPDF: () -> Void

    @State private var showsLog = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
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
            Image(systemName: statusImage)
                .foregroundStyle(statusColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(state.rootRelativePath ?? state.message)
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
                render()
            } label: {
                Label(state.isRendering ? "Rendering" : "Render", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(state.isRendering)

            Button {
                openPDF()
            } label: {
                Label("Open PDF", systemImage: "arrow.up.right.square")
            }
            .disabled(!state.canOpenPDF)

            Button {
                revealPDF()
            } label: {
                Label("Reveal", systemImage: "finder")
            }
            .disabled(!state.canOpenPDF)

            Button {
                showsLog.toggle()
            } label: {
                Label("Log", systemImage: "terminal")
            }
            .disabled(state.log.isEmpty)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            EmptyLatexState(
                title: "No PDF rendered yet",
                message: state.message,
                systemImage: "doc.richtext",
                actionTitle: "Render",
                action: render
            )
        case .rendering:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(state.message)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .rendered:
            if let pdfURL = state.pdfURL {
                VStack(spacing: 0) {
                    PDFKitPreview(url: pdfURL, renderedAt: state.renderedAt)
                    if showsLog {
                        Divider()
                        LatexLogView(log: state.log)
                            .frame(height: isCompact ? 130 : 180)
                    }
                }
            } else {
                EmptyLatexState(
                    title: "PDF is unavailable",
                    message: "Render the LaTeX project again.",
                    systemImage: "exclamationmark.triangle",
                    actionTitle: "Render",
                    action: render
                )
            }
        case .failed, .unavailable:
            VStack(spacing: 0) {
                EmptyLatexState(
                    title: statusTitle,
                    message: state.message,
                    systemImage: statusImage,
                    actionTitle: "Render Again",
                    action: render
                )
                if !state.log.isEmpty {
                    Divider()
                    LatexLogView(log: state.log)
                        .frame(minHeight: isCompact ? 160 : 220)
                }
            }
        }
    }

    private var statusTitle: String {
        switch state.phase {
        case .idle:
            "LaTeX Preview"
        case .rendering:
            "Rendering LaTeX"
        case .rendered:
            "PDF Preview"
        case .failed:
            "Build Failed"
        case .unavailable:
            "LaTeX Unavailable"
        }
    }

    private var statusImage: String {
        switch state.phase {
        case .idle:
            "doc.richtext"
        case .rendering:
            "hourglass"
        case .rendered:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .unavailable:
            "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch state.phase {
        case .idle, .rendering:
            .secondary
        case .rendered:
            .green
        case .failed, .unavailable:
            .orange
        }
    }
}

private struct PDFKitPreview: NSViewRepresentable {
    let url: URL
    let renderedAt: Date?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
        loadDocument(in: view, context: context)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.url != url || context.coordinator.renderedAt != renderedAt else {
            return
        }
        loadDocument(in: view, context: context)
    }

    private func loadDocument(in view: PDFView, context: Context) {
        view.document = PDFDocument(url: url)
        view.autoScales = true
        context.coordinator.url = url
        context.coordinator.renderedAt = renderedAt
    }

    final class Coordinator {
        var url: URL?
        var renderedAt: Date?
    }
}

private struct EmptyLatexState: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            VStack(spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            Button(actionTitle) {
                action()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LatexLogView: View {
    let log: String

    var body: some View {
        ScrollView {
            Text(log)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(.quaternary.opacity(0.35))
    }
}
