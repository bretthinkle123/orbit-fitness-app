import SwiftUI

/// The 6-segment level bar `MuscleRow` (CMP-21) composes with — the design
/// README's own "Suggested SwiftUI Decomposition" names this as a distinct
/// file (`LevelSegments` + `MuscleRow`) even though it isn't its own CMP
/// id; it's the reusable "how many of the 6 levels are filled" bar shape.
struct LevelSegments: View {
    /// 1...6 — how many of the 6 segments are filled (matches
    /// `Theme.levelScale`'s 6 stops exactly).
    let level: Int
    var theme = Theme()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...6, id: \.self) { segmentIndex in
                Capsule()
                    .fill(segmentIndex <= level ? Color(hex: theme.levelScaleStop(forLevel: segmentIndex).colorHex) : Theme.Neutral.chipFill)
                    .frame(height: 6)
            }
        }
        // The parent `MuscleRow` supplies the spoken level label combining
        // muscle name + level + trained-today; this bar alone has nothing
        // additional to announce.
        .accessibilityHidden(true)
    }

    /// Clamps an out-of-range level into the drawable 0...6 segment count —
    /// a pure function (Swift Testing exercises both bounds + mid-range,
    /// the task's named "LevelSegments mapping" math slice). Used by
    /// callers that need a SAFE level to pass in (this view itself trusts
    /// its `level` input directly, matching `Theme.levelScaleStop`'s own
    /// documented "trap loudly on a real data bug" precondition rather than
    /// silently clamping inside the view).
    static func clampedLevel(_ level: Int) -> Int {
        min(max(level, 0), 6)
    }
}
