import Foundation

struct VaultConfig: Codable {
    var version: Int
    var createdAt: Date
    var preferredEditorMode: EditorMode
    var appName: String

    static let current = VaultConfig(
        version: 1,
        createdAt: Date(),
        preferredEditorMode: .split,
        appName: AppBrand.displayName
    )
}
