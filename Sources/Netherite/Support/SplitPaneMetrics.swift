import CoreGraphics

enum SplitPaneMetrics {
    static let primarySidebarMinWidth: CGFloat = 300
    static let primarySidebarIdealWidth: CGFloat = 300
    static let primarySidebarMaxWidth: CGFloat = 310

    static let secondarySidebarMinWidth: CGFloat = 300
    static let secondarySidebarIdealWidth: CGFloat = 320
    static let secondarySidebarMaxWidth: CGFloat = 340

    static let mainContentMinWidth: CGFloat = 420

    static let editorSplitOriginalFraction: CGFloat = 0.5
    static let editorSplitSyncFractionTolerance: CGFloat = 0.01
    static let editorSplitDividerWidth: CGFloat = 1
    static let editorSplitResizeHitWidth: CGFloat = 18
    static let editorOriginalMinWidth: CGFloat = 260
    static let editorPreviewMinWidth: CGFloat = 320
}
