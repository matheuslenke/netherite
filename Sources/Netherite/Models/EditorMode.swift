import Foundation

enum EditorMode: String, CaseIterable, Identifiable, Codable {
    case edit
    case preview
    case split

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit:
            "Original"
        case .preview:
            "Preview"
        case .split:
            "Split"
        }
    }
}
