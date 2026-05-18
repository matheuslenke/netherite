import Foundation

enum LatexRenderPhase: String {
    case idle
    case rendering
    case rendered
    case failed
    case unavailable
}

struct LatexRenderState: Equatable {
    let phase: LatexRenderPhase
    let rootRelativePath: String?
    let pdfURL: URL?
    let includedFiles: [LatexIncludedFile]
    let log: String
    let message: String
    let renderedAt: Date?

    static let idle = LatexRenderState(
        phase: .idle,
        rootRelativePath: nil,
        pdfURL: nil,
        includedFiles: [],
        log: "",
        message: "Choose a LaTeX project file to render.",
        renderedAt: nil
    )

    var isRendering: Bool {
        phase == .rendering
    }

    var canOpenPDF: Bool {
        pdfURL != nil && phase == .rendered
    }
}

struct LatexRenderRequest: Sendable {
    let vaultPath: String
    let filePath: String
    let selectedRelativePath: String
}

struct LatexProject: Sendable {
    let rootURL: URL
    let rootRelativePath: String
    let projectDirectory: URL
    let buildDirectory: URL
    let outputPDFURL: URL
    let includedFiles: [LatexIncludedFile]
}

struct LatexRenderResult: Sendable {
    let project: LatexProject
    let log: String
    let renderedAt: Date
}

struct LatexIncludedFile: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL?
    let relativePath: String
    let sourceRelativePath: String
    let command: String
    let line: Int
    let byteCount: Int?
    let wordCount: Int?
    let lineCount: Int?
    let modifiedAt: Date?
    let isMissing: Bool
}
