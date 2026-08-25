import SwiftUI

/// CMP-19 — Train's 7-dot week strip + "N sessions" caption. Data-driven
/// from `GET /train`'s `week_strip: [Bool]` (T6) — this component invents
/// no day-of-week semantics of its own (no assumption about which index is
/// "today" or whether the array starts Sunday/Monday); it renders exactly
/// the 7-length boolean array it's given, in order.
struct WeekStrip: View {
    let filledDays: [Bool]
    var theme = Theme()

    var body: some View {
        HStack(spacing: Metrics.Spacing.cardGap / 2) {
            ForEach(Array(filledDays.enumerated()), id: \.offset) { _, isFilled in
                Circle()
                    .fill(isFilled ? theme.primary : Theme.Neutral.chipFill)
                    .frame(width: 10, height: 10)
            }
            Spacer()
            Text("\(Self.sessionCount(in: filledDays)) sessions")
                .font(.orbit(.caption))
                .foregroundStyle(Theme.Neutral.textMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.sessionCount(in: filledDays)) sessions this week")
    }

    /// Counts the trained days in a week-strip array — a pure function
    /// (Swift Testing exercises all-false/all-true/partial-fill and a
    /// non-7-length input, the task's named "WeekStrip day computation"
    /// math slice).
    // `nonisolated`: this is pure math with no view state, but it lives on a
    // `View`, so Swift 6 isolates it to the main actor by inheritance. The
    // Swift Testing cases that exercise it run OFF the main actor, and the
    // isolation check traps at runtime — SIGTRAP, taking the whole test host
    // down rather than failing one test.
    nonisolated static func sessionCount(in filledDays: [Bool]) -> Int {
        filledDays.filter { $0 }.count
    }
}
