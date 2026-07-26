import SwiftUI

/// CMP-21 — Body's 13 "by muscle group" rows: color dot + name +
/// `LevelSegments` 6-segment bar + level label + optional "▲ today".
struct MuscleRow: View {
    let muscleGroupName: String
    /// 1...6, matching `muscle_base_levels.level`'s DB range (T2) exactly.
    let level: Int
    let isTrainedToday: Bool
    var theme = Theme()

    private var levelStop: LevelScaleStop { theme.levelScaleStop(forLevel: level) }

    var body: some View {
        HStack(spacing: Metrics.Spacing.cardGap / 2) {
            Circle()
                .fill(Color(hex: levelStop.colorHex))
                .frame(width: 8, height: 8)
            Text(muscleGroupName)
                .font(.orbit(.body))
                .foregroundStyle(Theme.Neutral.textPrimary)
                .frame(width: 78, alignment: .leading)
            LevelSegments(level: level, theme: theme)
                .frame(width: 70)
            Text(levelStop.name)
                .font(.orbit(.caption))
                .foregroundStyle(Theme.Neutral.textMuted)
            if isTrainedToday {
                Text("▲ today")
                    .font(.orbit(.micro))
                    .foregroundStyle(theme.secondaryLight)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        // README's VoiceOver acceptance criterion, verbatim shape:
        // "{group}, {level}, trained today".
        .accessibilityLabel("\(muscleGroupName), \(levelStop.name)\(isTrainedToday ? ", trained today" : "")")
    }
}
