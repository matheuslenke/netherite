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
                .appTheme(appTheme)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            NetheriteCommands(store: store)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .appTheme(appTheme)
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

        CommandGroup(after: .pasteboard) {
            Button("Find...") {
                NotificationCenter.default.post(name: .findRequested, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(store.currentFile == nil)
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
                store.setEditorMode(.edit)
            }
            .keyboardShortcut("1", modifiers: [.command])
            .disabled(store.selectedFileIsPreviewOnly)

            Button("Preview") {
                store.setEditorMode(.preview)
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Split") {
                store.setEditorMode(.split)
            }
            .keyboardShortcut("3", modifiers: [.command])
            .disabled(store.selectedFileIsPreviewOnly)

            Divider()

            Button("Keep Editor Open") {
                if let fileID = store.selectedFileID {
                    store.pinTab(fileID: fileID)
                }
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(store.selectedFileID == nil || store.previewTabFileID != store.selectedFileID)

            Button("Close Editor") {
                store.closeCurrentTab()
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(store.selectedFileID == nil)

            Button("Close All Editors") {
                store.closeAllTabs()
            }
            .disabled(store.openFileTabIDs.isEmpty)

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

        CommandMenu("References") {
            Button("Show References") {
                store.setWorkspaceSection(.references)
            }
            .keyboardShortcut("4", modifiers: [.command])
            .disabled(store.vaultURL == nil)

            Divider()

            Button("Import BibTeX File…") {
                store.importBibTeXFileRequested()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(store.vaultURL == nil)

            Button("Paste BibTeX…") {
                store.pasteBibTeXRequested()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
            .disabled(store.vaultURL == nil)

            Divider()

            Button("Insert Citation…") {
                store.insertCitationRequested()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(store.references.isEmpty)

            Button("Attach PDF…") {
                store.attachPDFToSelectedReferenceRequested()
            }
            .disabled(store.currentReference == nil)

            Divider()

            Button("Export All…") {
                store.exportAllReferencesRequested()
            }
            .disabled(store.references.isEmpty)

            Button("Export Selected…") {
                store.exportSelectedReferencesRequested()
            }
            .disabled(store.currentReference == nil)
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

            Button("Show Changes") {
                store.showGitChanges()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(!store.gitSnapshot.isRepository)

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
