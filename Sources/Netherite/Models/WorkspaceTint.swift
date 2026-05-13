import SwiftUI

enum WorkspaceTint: String, CaseIterable, Identifiable {
    case none
    case graphite
    case sage
    case sky
    case lilac
    case rose
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            "None"
        case .graphite:
            "Graphite"
        case .sage:
            "Sage"
        case .sky:
            "Sky"
        case .lilac:
            "Lilac"
        case .rose:
            "Rose"
        case .amber:
            "Amber"
        }
    }

    var color: Color {
        switch self {
        case .none:
            Color.clear
        case .graphite:
            Color(red: 0.36, green: 0.38, blue: 0.42)
        case .sage:
            Color(red: 0.36, green: 0.52, blue: 0.43)
        case .sky:
            Color(red: 0.30, green: 0.48, blue: 0.68)
        case .lilac:
            Color(red: 0.55, green: 0.45, blue: 0.74)
        case .rose:
            Color(red: 0.70, green: 0.38, blue: 0.48)
        case .amber:
            Color(red: 0.72, green: 0.51, blue: 0.25)
        }
    }

    var opacity: Double {
        switch self {
        case .none:
            0
        case .graphite:
            0.10
        default:
            0.14
        }
    }
}
