import SwiftUI

private struct AppThemeViewModifier: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(theme.preferredColorScheme)
            .onAppear {
                theme.applyToApplication()
            }
            .onChange(of: theme) { _, newTheme in
                newTheme.applyToApplication()
            }
    }
}

extension View {
    func appTheme(_ theme: AppTheme) -> some View {
        modifier(AppThemeViewModifier(theme: theme))
    }
}
