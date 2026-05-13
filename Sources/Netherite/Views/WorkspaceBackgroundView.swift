import SwiftUI

struct WorkspaceBackgroundView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("workspaceTint") private var workspaceTintRaw = WorkspaceTint.none.rawValue

    private var tint: WorkspaceTint {
        WorkspaceTint(rawValue: workspaceTintRaw) ?? .none
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if tint != .none {
                tint.color
                    .opacity(reduceTransparency ? min(tint.opacity, 0.06) : tint.opacity)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: tint.rawValue)
    }
}
