import SwiftUI

/// The page's scroll position and full height, measured in the page's own
/// coordinate space. Used by the slim custom thumb in the trailing gutter.
struct PageScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
}

struct PageScrollMetricsKey: PreferenceKey {
    static var defaultValue = PageScrollMetrics()

    static func reduce(value: inout PageScrollMetrics, nextValue: () -> PageScrollMetrics) {
        let next = nextValue()
        if next.contentHeight > 0 { value = next }
    }
}

/// Placed in the background of the scrolling content. It reports how far the page
/// has travelled and how tall it is, without touching the scroll view itself.
struct PageScrollMeasure: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: PageScrollMetricsKey.self,
                value: PageScrollMetrics(
                    offset: -proxy.frame(in: .named("pageScroll")).minY,
                    contentHeight: proxy.size.height
                )
            )
        }
    }
}

/// The only scroll affordance of the page: a 3 pt thumb in the trailing gutter.
/// The system's legacy rail is hidden (`.scrollIndicators(.never)`); this thumb keeps
/// the exact cream margin, follows the palette in both appearances and never draws a
/// white track over the paper. It disappears when the page fits the window.
struct PageScrollThumb: View {
    let metrics: PageScrollMetrics
    let viewport: CGFloat

    var body: some View {
        if metrics.contentHeight > viewport + 1, viewport > 1 {
            let track = max(0, viewport - 16)
            let height = min(track, max(40, track * viewport / metrics.contentHeight))
            let maxScroll = max(1, metrics.contentHeight - viewport)
            let progress = min(max(metrics.offset / maxScroll, 0), 1)

            Capsule()
                .fill(Mock.ink3.opacity(0.55))
                .frame(width: 3, height: height)
                .offset(y: 8 + progress * (track - height))
                .padding(.trailing, 6)
                .accessibilityHidden(true)
        }
    }
}
