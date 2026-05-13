import Foundation

extension Notification.Name {
    static let openVaultRequested = Notification.Name("Netherite.openVaultRequested")
    static let newNoteRequested = Notification.Name("Netherite.newNoteRequested")
    static let saveRequested = Notification.Name("Netherite.saveRequested")
    static let refreshVaultRequested = Notification.Name("Netherite.refreshVaultRequested")
    static let renderLatexRequested = Notification.Name("Netherite.renderLatexRequested")
    static let gitPullRequested = Notification.Name("Netherite.gitPullRequested")
    static let gitCommitRequested = Notification.Name("Netherite.gitCommitRequested")
    static let gitPushRequested = Notification.Name("Netherite.gitPushRequested")
    static let importZipRequested = Notification.Name("Netherite.importZipRequested")
    static let deleteSelectedFileRequested = Notification.Name("Netherite.deleteSelectedFileRequested")
}
