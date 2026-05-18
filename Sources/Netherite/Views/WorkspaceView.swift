import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var confirmDelete: Bool
    @State private var markdownPreviewScrollTargetID: Int?
    @State private var sourceScrollTargetOffset: Int?

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 780

            ZStack {
                WorkspaceBackgroundView()

                if store.vaultURL == nil {
                    EmptyVaultView()
                        .transition(.opacity)
                } else if store.workspaceSection == .changes {
                    GitChangesView(isCompact: isCompact)
                        .transition(.opacity)
                } else if store.workspaceSection == .references {
                    ReferenceWorkspaceView(isCompact: isCompact)
                        .transition(.opacity)
                } else if isCompact {
                    workspaceContent(
                        isCompact: true,
                        content: compactContent(windowHeight: proxy.size.height)
                    )
                } else {
                    workspaceContent(isCompact: false, content: regularContent)
                }
            }
            .animation(layoutAnimation, value: isCompact)
            .animation(layoutAnimation, value: store.inspectorVisible)
            .animation(layoutAnimation, value: store.workspaceSection)
            .animation(layoutAnimation, value: store.selectedFileID)
            .animation(layoutAnimation, value: store.openFileTabIDs)
        }
    }

    private func workspaceContent<Content: View>(isCompact: Bool, content: Content) -> some View {
        VStack(spacing: 0) {
            if store.currentFile == nil {
                EmptySelectionView()
                    .transition(.opacity)
            } else {
                content
                    .transition(.opacity)
            }
        }
        .transition(.opacity)
    }

    private func compactContent(windowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            EditorWorkspaceView(
                confirmDelete: $confirmDelete,
                isCompact: true,
                markdownScrollTargetID: $markdownPreviewScrollTargetID,
                sourceScrollTargetOffset: $sourceScrollTargetOffset
            )

            if store.inspectorVisible {
                Divider()
                InspectorView(
                    markdownScrollTargetID: $markdownPreviewScrollTargetID,
                    sourceScrollTargetOffset: $sourceScrollTargetOffset
                )
                    .frame(height: compactInspectorHeight(for: windowHeight))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var regularContent: some View {
        HSplitView {
            EditorWorkspaceView(
                confirmDelete: $confirmDelete,
                isCompact: false,
                markdownScrollTargetID: $markdownPreviewScrollTargetID,
                sourceScrollTargetOffset: $sourceScrollTargetOffset
            )
            .frame(minWidth: SplitPaneMetrics.mainContentMinWidth, maxWidth: .infinity)
            .layoutPriority(1)

            if store.inspectorVisible {
                InspectorView(
                    markdownScrollTargetID: $markdownPreviewScrollTargetID,
                    sourceScrollTargetOffset: $sourceScrollTargetOffset
                )
                    .frame(
                        minWidth: SplitPaneMetrics.secondarySidebarMinWidth,
                        idealWidth: SplitPaneMetrics.secondarySidebarIdealWidth,
                        maxWidth: SplitPaneMetrics.secondarySidebarMaxWidth
                    )
            }
        }
    }

    private func compactInspectorHeight(for windowHeight: CGFloat) -> CGFloat {
        min(260, max(170, windowHeight * 0.32))
    }

    private var layoutAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.24)
    }
}

private struct EmptyVaultView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        VStack(spacing: 18) {
            BrandLogoView(size: 82)

            VStack(spacing: 6) {
                Text(AppBrand.displayName)
                    .font(.largeTitle.weight(.semibold))
                Text("Open a vault")
                    .font(.headline)
                Text("Choose a folder that contains your notes and project files.")
                    .foregroundStyle(.secondary)
            }

            Button {
                store.chooseVault()
            } label: {
                Label("Choose Folder", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptySelectionView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        VStack(spacing: 16) {
            BrandLogoView(size: 48)

            Text("Select or create a note")
                .font(.title3.weight(.semibold))

            Button {
                store.createNote()
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
