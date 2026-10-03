import SwiftUI

/// Static, non-interactive island shown on the lock screen: a notch-sized black
/// pill with a lock icon peeking to the left of the notch. Lives in its own panel
/// (see `NotchController.buildLockWindow`), so it carries no live state.
struct LockIslandView: View {
    let metrics: NotchMetrics

    private var shape: NotchShape {
        NotchShape(topRadius: 0, bottomRadius: metrics.collapsedCornerRadius)
    }

    var body: some View {
        shape
            .fill(Color.black)
            .frame(width: metrics.collapsedWidth, height: metrics.restHeight)
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: metrics.collapsedSidePadding, alignment: .center)
                    Spacer(minLength: metrics.notchWidth)
                    Color.clear.frame(width: metrics.collapsedSidePadding)
                }
                .frame(width: metrics.collapsedWidth, height: metrics.restHeight)
            }
            .clipShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
