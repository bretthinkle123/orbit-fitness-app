import SwiftUI

/// CMP-18 — Train's "REST m:ss" chip, visible only while resting. The
/// countdown TICK itself is the caller's responsibility (a `Timer`/`.task`
/// loop owned by `TrainView`'s state, T15) — this component is a dumb,
/// data-driven presentational view that simply renders (or hides itself
/// for) whatever `remainingSeconds` it's given right now.
struct RestChip: View {
    /// The chip renders nothing when this is <= 0 (design-spec: "visible
    /// only while rest > 0").
    let remainingSeconds: Int
    var theme = Theme()

    var body: some View {
        if remainingSeconds > 0 {
            Text("REST \(Self.formatted(remainingSeconds))")
                .font(.orbit(.caption))
                .foregroundStyle(Theme.Neutral.textPrimary)
                .padding(.horizontal, Metrics.Spacing.cardPaddingMin)
                .frame(minHeight: Metrics.HitTarget.minimum)
                .background(theme.secondary.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.chipMax, style: .circular))
                .accessibilityLabel("Resting, \(remainingSeconds) seconds remaining")
        }
    }

    /// `m:ss` formatting (e.g. 125 → "2:05") — a pure function; Swift
    /// Testing exercises the 0/59/60/120 boundaries.
    // `nonisolated`: this is pure math with no view state, but it lives on a
    // `View`, so Swift 6 isolates it to the main actor by inheritance. The
    // Swift Testing cases that exercise it run OFF the main actor, and the
    // isolation check traps at runtime — SIGTRAP, taking the whole test host
    // down rather than failing one test.
    nonisolated static func formatted(_ totalSeconds: Int) -> String {
        let clamped = max(totalSeconds, 0)
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
