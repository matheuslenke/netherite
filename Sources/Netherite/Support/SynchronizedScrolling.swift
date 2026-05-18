import CoreGraphics

enum ScrollSyncSource: Equatable {
    case editor
    case preview
}

struct ScrollSyncState: Equatable {
    let source: ScrollSyncSource
    let progress: CGFloat
    let revision: Int

    static let initial = ScrollSyncState(source: .editor, progress: 0, revision: 0)
}

struct ScrollSyncMetrics: Equatable {
    let offset: CGFloat
    let maxOffset: CGFloat
    let progress: CGFloat

    static let zero = ScrollSyncMetrics(offset: 0, maxOffset: 0, progress: 0)
}

enum SynchronizedScrolling {
    static let progressTolerance: CGFloat = 0.002
    static let offsetTolerance: CGFloat = 0.5

    static func metrics(offset: CGFloat, contentLength: CGFloat, viewportLength: CGFloat) -> ScrollSyncMetrics {
        let maxOffset = max(contentLength - viewportLength, 0)
        let clampedOffset = min(max(offset, 0), maxOffset)
        let progress = maxOffset > 0 ? clampedOffset / maxOffset : 0

        return ScrollSyncMetrics(
            offset: clampedOffset,
            maxOffset: maxOffset,
            progress: min(max(progress, 0), 1)
        )
    }

    static func nextState(from current: ScrollSyncState, source: ScrollSyncSource, progress: CGFloat) -> ScrollSyncState {
        ScrollSyncState(
            source: source,
            progress: min(max(progress, 0), 1),
            revision: current.revision + 1
        )
    }
}
