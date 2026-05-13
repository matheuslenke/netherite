import AppKit
import SwiftUI

@main
struct NetheriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = VaultStore()
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.system.rawValue

    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup(AppBrand.displayName) {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 660, minHeight: 480)
                .preferredColorScheme(appTheme.preferredColorScheme)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            NetheriteCommands(store: store)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .preferredColorScheme(appTheme.preferredColorScheme)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppBrand.logoImage
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct NetheriteCommands: Commands {
    @ObservedObject var store: VaultStore
    @AppStorage("sidebarVisible") private var sidebarVisible = true

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note") {
                store.createNote()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Folder") {
                store.createFolder(in: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(store.vaultURL == nil)

            Divider()

            Button("Open Vault...") {
                store.chooseVault()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Import .zip…") {
                store.importZipRequested()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                store.saveDocument()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!store.isDirty || !store.documentIsEditable)
        }

        CommandGroup(after: .toolbar) {
            Button(sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Button(store.inspectorVisible ? "Hide Details Sidebar" : "Show Details Sidebar") {
                store.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandMenu("Editor") {
            Button("Original") {
                store.editorMode = .edit
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Preview") {
                store.editorMode = .preview
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Split") {
                store.editorMode = .split
            }
            .keyboardShortcut("3", modifiers: [.command])

            Divider()

            Button("Quick Look") {
                store.previewSelectedFile()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(store.currentFile == nil)

            Button("Reveal in Finder") {
                store.revealSelectedInFinder()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(store.currentFile == nil)

            Button("Open Externally") {
                store.openSelectedExternally()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(store.currentFile == nil)

            Divider()

            Button("Move File to Trash...", role: .destructive) {
                NotificationCenter.default.post(name: .deleteSelectedFileRequested, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(store.currentFile == nil)
        }

        CommandMenu("Vault") {
            Button("Refresh Files") {
                store.reloadFiles()
                store.refreshGitStatus()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(store.vaultURL == nil)

            Button("Render LaTeX") {
                store.renderLatexForCurrentFile()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!store.selectedFileCanRenderLatex || store.latexRenderState.isRendering)

            Divider()

            Button("Pull") {
                store.pullVault()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!store.gitSnapshot.isRepository)

            Button("Commit All...") {
                store.commitVault()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(!store.gitSnapshot.isRepository)

            Button("Push") {
                store.pushVault()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!store.gitSnapshot.isRepository)
        }
    }
}
