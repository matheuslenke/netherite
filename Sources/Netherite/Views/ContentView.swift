import QuickLook
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    @State private var confirmDelete = false

    var body: some View {
        HSplitView {
            if sidebarVisible {
                SidebarView(confirmDelete: $confirmDelete)
                    .frame(minWidth: 190, idealWidth: 250, maxWidth: 360)
            }
            WorkspaceView(confirmDelete: $confirmDelete)
                .frame(minWidth: 360)
        }
        .frame(minWidth: 660, minHeight: 480)
        .navigationTitle(windowTitle)
        .quickLookPreview($store.quickLookFileURL)
        .animation(layoutAnimation, value: sidebarVisible)
        .animation(layoutAnimation, value: store.inspectorVisible)
        .animation(layoutAnimation, value: store.editorMode)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    sidebarVisible.toggle()
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle Sidebar")
                .accessibilityLabel(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")

                Button {
                    store.chooseVault()
                } label: {
                    Label("Open Vault", systemImage: "folder")
                }

                Button {
                    store.createNote()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .disabled(store.vaultURL == nil)

                Button {
                    store.importZipRequested()
                } label: {
                    Label("Import .zip", systemImage: "doc.zipper")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.saveDocument()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!store.isDirty || !store.documentIsEditable)

                Button {
                    store.renderLatexForCurrentFile()
                } label: {
                    Label("Render LaTeX", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!store.selectedFileCanRenderLatex || store.latexRenderState.isRendering)

                Button {
                    store.pullVault()
                } label: {
                    Label("Pull", systemImage: "arrow.down.circle")
                }
                .disabled(!store.gitSnapshot.isRepository)

                Button {
                    store.commitVault()
                } label: {
                    Label("Commit", systemImage: "checkmark.circle")
                }
                .disabled(!store.gitSnapshot.isRepository)

                Button {
                    store.pushVault()
                } label: {
                    Label("Push", systemImage: "arrow.up.circle")
                }
                .disabled(!store.gitSnapshot.isRepository)

                Button {
                    store.inspectorVisible.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.right")
                }
                .help(store.inspectorVisible ? "Hide Details" : "Show Details")
                .accessibilityLabel(store.inspectorVisible ? "Hide Details" : "Show Details")
            }
        }
        .alert("Move file to Trash?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
            Button("Move to Trash", role: .destructive) {
                store.deleteSelectedFile()
            }
        } message: {
            Text(store.currentFile?.name ?? "Selected file")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVaultRequested)) { _ in
            store.chooseVault()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importZipRequested)) { _ in
            store.importZipRequested()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newNoteRequested)) { _ in
            store.createNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveRequested)) { _ in
            store.saveDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshVaultRequested)) { _ in
            store.reloadFiles()
            store.refreshGitStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .renderLatexRequested)) { _ in
            store.renderLatexForCurrentFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitPullRequested)) { _ in
            store.pullVault()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitCommitRequested)) { _ in
            store.commitVault()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitPushRequested)) { _ in
            store.pushVault()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedFileRequested)) { _ in
            if store.currentFile != nil {
                confirmDelete = true
            }
        }
    }

    private var layoutAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.24)
    }

    private var windowTitle: String {
        store.currentFile?.name ?? store.vaultURL?.lastPathComponent ?? AppBrand.displayName
    }
}
