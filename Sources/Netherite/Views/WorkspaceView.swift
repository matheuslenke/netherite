import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var confirmDelete: Bool

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 780

            ZStack {
                WorkspaceBackgroundView()

                if store.vaultURL == nil {
                    EmptyVaultView()
                        .transition(.opacity)
                } else if store.currentFile == nil {
                    EmptySelectionView()
                        .transition(.opacity)
                } else if isCompact {
                    VStack(spacing: 0) {
                        EditorWorkspaceView(confirmDelete: $confirmDelete, isCompact: true)

                        if store.inspectorVisible {
                            Divider()
                            InspectorView()
                                .frame(height: compactInspectorHeight(for: proxy.size.height))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .transition(.opacity)
                } else {
                    HSplitView {
                        EditorWorkspaceView(confirmDelete: $confirmDelete, isCompact: false)
                            .frame(minWidth: 360)

                        if store.inspectorVisible {
                            InspectorView()
                                .frame(minWidth: 230, idealWidth: 300, maxWidth: 420)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(layoutAnimation, value: isCompact)
            .animation(layoutAnimation, value: store.inspectorVisible)
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
                    .font(AppBrand.monoFont(size: 28, weight: .bold))
                Text("Open a vault")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(0.8)
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
                .font(AppBrand.monoFont(size: 17, weight: .semibold))

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
