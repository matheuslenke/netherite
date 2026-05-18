import SwiftUI

struct BibTeXPreviewView: View {
    let text: String
    let isCompact: Bool

    private var parsedEntries: Result<[ReferenceItem], Error> {
        Result {
            try BibTeXParser.parseEntries(text).map(BibTeXSerializer.reference)
        }
    }

    var body: some View {
        switch parsedEntries {
        case let .success(references):
            if references.isEmpty {
                emptyState
            } else {
                referencesView(references)
            }
        case let .failure(error):
            parseErrorView(error)
        }
    }

    private func referencesView(_ references: [ReferenceItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("\(references.count) reference\(references.count == 1 ? "" : "s")", systemImage: "books.vertical")
                    .font(.headline)
                Spacer()
            }

            ForEach(references) { reference in
                BibTeXReferencePreviewCard(reference: reference)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No BibTeX entries")
                .font(.headline)
            Text("Add one or more @article, @book, or other BibTeX entries.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func parseErrorView(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("BibTeX preview unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BibTeXReferencePreviewCard: View {
    let reference: ReferenceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(reference.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(reference.type)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }

            HStack(spacing: 8) {
                Label(reference.citationKey, systemImage: "at")
                Text(reference.yearText)
                if !reference.venueText.isEmpty {
                    Text(reference.venueText)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(reference.authorText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(reference.bibliographyPreview)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !detailRows.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(detailRows, id: \.name) { row in
                        HStack(alignment: .top, spacing: 8) {
                            Text(row.name.capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 76, alignment: .leading)
                            Text(row.value)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var detailRows: [(name: String, value: String)] {
        let hiddenFields = Set(["title", "author", "year", "journal", "booktitle", "publisher"])
        return reference.fields
            .filter { !hiddenFields.contains($0.key) && !$0.value.trimmed.isEmpty }
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, value: $0.value) }
    }
}
