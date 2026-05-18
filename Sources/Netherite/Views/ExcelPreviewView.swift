import SwiftUI

struct ExcelPreviewView: View {
    let file: VaultFile
    let isCompact: Bool
    let openWorkbook: () -> Void
    let revealWorkbook: () -> Void

    @State private var loadState: ExcelPreviewLoadState = .idle
    @State private var selectedSheetID: ExcelSheetPreview.ID?
    @State private var reloadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .glassEffect(.regular, in: Rectangle())
        .task(id: reloadKey) {
            await loadWorkbook()
        }
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                statusLabel
                Spacer()
                sheetPicker
                toolbarButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                statusLabel
                HStack(spacing: 8) {
                    sheetPicker
                    toolbarButtons
                }
            }
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, 10)
    }

    private var statusLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("Excel Preview")
                    .font(.headline)
                    .lineLimit(1)

                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private var sheetPicker: some View {
        if case let .loaded(workbook) = loadState, workbook.sheets.count > 1 {
            Picker("Sheet", selection: selectedSheetBinding(in: workbook)) {
                ForEach(workbook.sheets) { sheet in
                    Text(sheet.name).tag(Optional(sheet.id))
                }
            }
            .labelsHidden()
            .frame(width: isCompact ? 150 : 190)
            .help("Choose Sheet")
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        let row = HStack(spacing: 8) {
            Button {
                reloadID = UUID()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(loadState.isLoading)
            .help("Reload Preview")

            Button {
                openWorkbook()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                revealWorkbook()
            } label: {
                Label("Reveal", systemImage: "finder")
            }
        }

        if isCompact {
            row.labelStyle(.iconOnly)
        } else {
            row.labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(message):
            ExcelPreviewMessage(
                title: "Preview Unavailable",
                message: message,
                systemImage: "exclamationmark.triangle"
            )

        case let .loaded(workbook):
            if let sheet = selectedSheet(in: workbook) {
                ExcelSheetGridView(sheet: sheet)
            } else {
                ExcelPreviewMessage(
                    title: "No Sheets",
                    message: "This workbook does not contain readable worksheet data.",
                    systemImage: "tablecells"
                )
            }
        }
    }

    private var reloadKey: String {
        "\(file.id)|\(file.modifiedAt.timeIntervalSinceReferenceDate)|\(reloadID.uuidString)"
    }

    private var statusDetail: String {
        switch loadState {
        case .idle, .loading:
            return file.relativePath
        case let .failed(message):
            return message
        case let .loaded(workbook):
            guard let sheet = selectedSheet(in: workbook) else {
                return file.relativePath
            }
            let rowText = sheet.truncatedRows ? "\(sheet.rows.count)+" : "\(sheet.rows.count)"
            let columnText = sheet.truncatedColumns ? "\(sheet.columnCount)+" : "\(sheet.columnCount)"
            return "\(sheet.name) - \(rowText) rows x \(columnText) columns"
        }
    }

    private func selectedSheet(in workbook: ExcelWorkbookPreview) -> ExcelSheetPreview? {
        if let selectedSheetID,
           let sheet = workbook.sheets.first(where: { $0.id == selectedSheetID }) {
            return sheet
        }
        return workbook.sheets.first
    }

    private func selectedSheetBinding(in workbook: ExcelWorkbookPreview) -> Binding<ExcelSheetPreview.ID?> {
        Binding {
            selectedSheet(in: workbook)?.id
        } set: { nextID in
            selectedSheetID = nextID
        }
    }

    private func loadWorkbook() async {
        loadState = .loading
        let fileURL = file.url

        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try ExcelWorkbookPreviewService.load(url: fileURL)
            }
        }.value

        switch result {
        case let .success(workbook):
            loadState = .loaded(workbook)
            if selectedSheet(in: workbook) == nil {
                selectedSheetID = workbook.sheets.first?.id
            }

        case let .failure(error):
            loadState = .failed(error.localizedDescription)
            selectedSheetID = nil
        }
    }
}

private enum ExcelPreviewLoadState {
    case idle
    case loading
    case loaded(ExcelWorkbookPreview)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

private struct ExcelSheetGridView: View {
    let sheet: ExcelSheetPreview

    private var columnWidths: [CGFloat] {
        (0..<sheet.columnCount).map { columnIndex in
            let headerLength = ExcelColumnName.name(for: columnIndex).count
            let contentLength = sheet.rows
                .compactMap { row in
                    row.values.indices.contains(columnIndex) ? row.values[columnIndex] : nil
                }
                .map { min($0.count, 42) }
                .max() ?? 0
            let characterCount = max(headerLength, contentLength)
            return min(220, max(74, CGFloat(characterCount * 7 + 26)))
        }
    }

    var body: some View {
        if sheet.isEmpty {
            ExcelPreviewMessage(
                title: sheet.name,
                message: "This sheet is empty.",
                systemImage: "tablecells"
            )
        } else {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        cornerHeader
                        ForEach(0..<sheet.columnCount, id: \.self) { columnIndex in
                            columnHeader(columnIndex)
                        }
                    }

                    ForEach(sheet.rows) { row in
                        GridRow {
                            rowHeader(row.rowIndex)
                            ForEach(0..<sheet.columnCount, id: \.self) { columnIndex in
                                cell(row.values.indices.contains(columnIndex) ? row.values[columnIndex] : "", columnIndex: columnIndex)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(.quaternary.opacity(0.12), in: Rectangle())
        }
    }

    private var cornerHeader: some View {
        Text("")
            .frame(width: 54, height: 28)
            .background(headerBackground)
            .overlay(cellBorder)
    }

    private func columnHeader(_ columnIndex: Int) -> some View {
        Text(ExcelColumnName.name(for: columnIndex))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: columnWidths[columnIndex], height: 28)
            .background(headerBackground)
            .overlay(cellBorder)
    }

    private func rowHeader(_ rowIndex: Int) -> some View {
        Text("\(rowIndex)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.trailing, 8)
            .frame(width: 54, height: 28, alignment: .trailing)
            .background(headerBackground)
            .overlay(cellBorder)
    }

    private func cell(_ text: String, columnIndex: Int) -> some View {
        Text(text)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .padding(.horizontal, 8)
            .frame(width: columnWidths[columnIndex], height: 28, alignment: .leading)
            .background(.background.opacity(0.72), in: Rectangle())
            .overlay(cellBorder)
    }

    private var headerBackground: some ShapeStyle {
        .quaternary.opacity(0.28)
    }

    private var cellBorder: some View {
        Rectangle()
            .stroke(.separator.opacity(0.55), lineWidth: 0.5)
    }
}

private struct ExcelPreviewMessage: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .textSelection(.enabled)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
