import SwiftUI

/// UI state shared with the window controller (so it can resize the window when
/// the island expands).
@MainActor
final class IslandState: ObservableObject {
    @Published var metrics: NotchMetrics

    /// Battery %, shown briefly as a "charging" flourish after plugging in.
    @Published var chargingFlourish: Int?

    /// Hide the music pop-out while the playing app is already frontmost.
    @Published var suppressedForFrontmost = false

    /// Clicking the music pop-out switches to the playing app.
    var onTapIsland: (() -> Void)?

    /// Whether a non-music activity currently wants the island popped out.
    var hasCollapsedActivity: Bool { chargingFlourish != nil }

    init(metrics: NotchMetrics) { self.metrics = metrics }
}
