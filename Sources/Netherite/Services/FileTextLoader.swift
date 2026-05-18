import Foundation
import ImageIO

struct LoadedDocument: Sendable {
    let text: String
    let sourceDescription: String
    let isEditable: Bool
}

enum FileTextLoader {
    private static let binaryPreviewByteLimit = 16_384

    static func load(url: URL) throws -> LoadedDocument {
        let kind = FileKind(fileExtension: url.pathExtension)
        let byteCount = fileSize(at: url)

        if url.pathExtension.lowercased() == "pdf" {
            return LoadedDocument(
                text: documentDescription(url: url, byteCount: byteCount, label: "PDF"),
                sourceDescription: "PDF preview; source file is read-only here",
                isEditable: false
            )
        }

        if kind == .spreadsheet {
            return LoadedDocument(
                text: spreadsheetDescription(url: url, byteCount: byteCount),
                sourceDescription: "Excel workbook preview; source file is read-only here",
                isEditable: false
            )
        }

        if kind == .image {
            return LoadedDocument(
                text: imageDescription(url: url, byteCount: byteCount),
                sourceDescription: "Image metadata rendered as text; source file is read-only here",
                isEditable: false
            )
        }

        if kind == .richText || kind == .document {
            if let converted = try? convertWithTextUtil(url: url), !converted.trimmed.isEmpty {
                return LoadedDocument(
                    text: converted,
                    sourceDescription: "Extracted with textutil; source file is read-only here",
                    isEditable: false
                )
            }

            return LoadedDocument(
                text: documentDescription(
                    url: url,
                    byteCount: byteCount,
                    label: kind == .richText ? "Rich Text" : "Document"
                ),
                sourceDescription: "Document metadata; source file is read-only here",
                isEditable: false
            )
        }

        if kind == .binary, byteCount > binaryPreviewByteLimit {
            let sample = try readPrefix(url: url, byteLimit: binaryPreviewByteLimit)
            if !looksLikeText(data: sample) {
                return LoadedDocument(
                    text: hexDump(data: sample, totalByteCount: byteCount),
                    sourceDescription: "Binary preview as hexadecimal text; source file is read-only here",
                    isEditable: false
                )
            }
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])

        if data.isEmpty {
            return LoadedDocument(text: "", sourceDescription: "Empty text file", isEditable: true)
        }

        if let string = decodeText(data: data) {
            return LoadedDocument(text: string, sourceDescription: "Original text", isEditable: true)
        }

        if let converted = try? convertWithTextUtil(url: url), !converted.trimmed.isEmpty {
            return LoadedDocument(
                text: converted,
                sourceDescription: "Extracted with textutil; source file is read-only here",
                isEditable: false
            )
        }

        return LoadedDocument(
            text: hexDump(data: data, totalByteCount: byteCount),
            sourceDescription: "Binary preview as hexadecimal text; source file is read-only here",
            isEditable: false
        )
    }

    private static func decodeText(data: Data) -> String? {
        if data.prefix(4).contains(0), String(data: data, encoding: .utf16) == nil {
            return nil
        }

        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian]
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding), looksLikeText(string: string) {
                return string
            }
        }

        if looksLikeText(data: data), let string = String(data: data, encoding: .isoLatin1) {
            return string
        }

        return nil
    }

    private static func looksLikeText(data: Data) -> Bool {
        let sample = data.prefix(4096)
        var printable = 0

        for byte in sample {
            if byte == 0 { return false }
            if byte == 9 || byte == 10 || byte == 13 || byte >= 32 {
                printable += 1
            }
        }

        return Double(printable) / Double(max(sample.count, 1)) > 0.92
    }

    private static func looksLikeText(string: String) -> Bool {
        let sample = string.prefix(4096)
        guard !sample.isEmpty else { return true }

        let printable = sample.filter { character in
            !character.unicodeScalars.contains { scalar in
                scalar.value < 9 || (scalar.value > 13 && scalar.value < 32)
            }
        }.count

        return Double(printable) / Double(sample.count) > 0.92
    }

    private static func convertWithTextUtil(url: URL) throws -> String {
        let result = try ProcessRunner.run(arguments: [
            "/usr/bin/textutil",
            "-convert",
            "txt",
            "-stdout",
            url.path
        ])
        return result.output
    }

    private static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func readPrefix(url: URL, byteLimit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        return try handle.read(upToCount: byteLimit) ?? Data()
    }

    private static func imageDescription(url: URL, byteCount: Int) -> String {
        var lines = [
            "Image: \(url.lastPathComponent)",
            "Format: \(url.pathExtension.uppercased())",
            "Size: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))"
        ]

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                lines.append("Dimensions: \(width) x \(height) px")
            }
            if let colorModel = properties[kCGImagePropertyColorModel] as? String {
                lines.append("Color model: \(colorModel)")
            }
        }

        lines.append("Path: \(url.path)")
        return lines.joined(separator: "\n")
    }

    private static func documentDescription(url: URL, byteCount: Int, label: String) -> String {
        [
            "\(label): \(url.lastPathComponent)",
            "Size: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))",
            "Path: \(url.path)"
        ].joined(separator: "\n")
    }

    private static func spreadsheetDescription(url: URL, byteCount: Int) -> String {
        [
            "Spreadsheet: \(url.lastPathComponent)",
            "Format: \(url.pathExtension.uppercased())",
            "Size: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))",
            "Path: \(url.path)"
        ].joined(separator: "\n")
    }

    private static func hexDump(data: Data, totalByteCount: Int) -> String {
        let bytes = Array(data.prefix(16_384))
        var lines: [String] = []

        for offset in stride(from: 0, to: bytes.count, by: 16) {
            let chunk = Array(bytes[offset..<min(offset + 16, bytes.count)])
            let hex = chunk
                .map { String(format: "%02x", $0) }
                .joined(separator: " ")
                .padding(toLength: 47, withPad: " ", startingAt: 0)
            let ascii = chunk.map { byte -> Character in
                if byte >= 32 && byte <= 126 {
                    return Character(UnicodeScalar(byte))
                }
                return "."
            }
            lines.append(String(format: "%08x  %@  %@", offset, hex, String(ascii)))
        }

        if totalByteCount > bytes.count {
            lines.append("")
            lines.append("Preview truncated at \(bytes.count) bytes of \(totalByteCount) total bytes.")
        }

        return lines.joined(separator: "\n")
    }
}
