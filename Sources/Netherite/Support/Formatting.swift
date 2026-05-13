import Foundation

@MainActor
enum AppFormatters {
    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let fileSafeDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shellQuoted() -> String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func appleScriptQuoted() -> String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

extension URL {
    func appendingPathComponentIfNeeded(_ component: String) -> URL {
        appendingPathComponent(component, isDirectory: false)
    }
}
