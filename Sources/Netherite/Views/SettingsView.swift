import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("launchReopensLastVault") private var launchReopensLastVault = true
    @AppStorage("workspaceTint") private var workspaceTintRaw = WorkspaceTint.none.rawValue
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.system.rawValue

    var body: some View {
        Form {
            Toggle("Reopen last vault at launch", isOn: $launchReopensLastVault)
            Toggle("Hot reload vault changes", isOn: $store.hotReloadEnabled)

            Picker("Appearance", selection: $appThemeRaw) {
                ForEach(AppTheme.allCases) { theme in
                    Label(theme.title, systemImage: theme.systemImage).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Picker("Default editor mode", selection: $store.editorMode) {
                ForEach(EditorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Background tint", selection: $workspaceTintRaw) {
                ForEach(WorkspaceTint.allCases) { tint in
                    Text(tint.title).tag(tint.rawValue)
                }
            }

            HStack(spacing: 10) {
                ForEach(WorkspaceTint.allCases) { tint in
                    Button {
                        withAnimation(selectionAnimation) {
                            workspaceTintRaw = tint.rawValue
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(tint == .none ? Color(nsColor: .separatorColor) : tint.color)
                                .frame(width: 22, height: 22)

                            if workspaceTintRaw == tint.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(tint.title)
                    .accessibilityLabel("Background tint: \(tint.title)")
                    .accessibilityAddTraits(workspaceTintRaw == tint.rawValue ? .isSelected : [])
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }
}
