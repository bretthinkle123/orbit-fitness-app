import SwiftUI

/// One logged entry rendered in an `HourTimeline` row — a small,
/// presentation-only shape (not `Core/Models.FoodEntry` directly, since the
/// timeline needs a pre-formatted time label the model doesn't carry, and
/// building that string is the caller/screen's day-key-aware job, T15).
struct HourTimelineEntry: Identifiable {
    let id: Int
    let name: String
    let kcal: Int
}

/// CMP-13 — Fuel's By-hour panel: rows 6 AM–9 PM, a lit hour-dot + rail
/// when an hour has entries, a pulsing "Now" marker (NM-9: gated by Reduce
/// Motion). Data-driven — the caller buckets its day's `FoodEntry` rows by
/// hour-of-day into `entriesByHour`; this component owns no clock/date
/// logic of its own beyond the fixed 6...21 row range the design depicts.
struct HourTimeline: View {
    let entriesByHour: [Int: [HourTimelineEntry]]
    /// The current hour (24-hour) if "now" falls within 6...21, else `nil`
    /// — the caller decides this (it owns the device clock), this view
    /// only renders the marker.
    var nowHour: Int?
    var theme = Theme()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private static let displayedHours = Array(6...21)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.displayedHours, id: \.self) { hour in
                row(for: hour)
            }
        }
    }

    private func row(for hour: Int) -> some View {
        let entries = entriesByHour[hour] ?? []
        let isNow = hour == nowHour
        return HStack(alignment: .top, spacing: Metrics.Spacing.cardGap / 2) {
            VStack(spacing: 0) {
                Circle()
                    .fill(entries.isEmpty ? Theme.Neutral.chipFill : theme.secondary)
                    .frame(width: 8, height: 8)
                    .shadow(color: entries.isEmpty ? .clear : theme.ringGlow, radius: Metrics.Shadow.ringGlowRadius)
                Rectangle().fill(Theme.Neutral.cardBorder).frame(width: 1)
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(Self.hourLabel(hour))
                        .font(.orbit(.caption))
                        .foregroundStyle(Theme.Neutral.textMuted)
                    if isNow {
                        Text("Now")
                            .font(.orbit(.micro))
                            .foregroundStyle(theme.secondaryLight)
                            .opacity(isPulsing ? 0.4 : 1)
                            .onAppear(perform: startPulsingIfAllowed)
                    }
                }
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.name)
                            .font(.orbit(.body))
                            .foregroundStyle(Theme.Neutral.textPrimary)
                        Spacer()
                        Text("\(entry.kcal) kcal")
                            .font(.orbit(.caption))
                            .foregroundStyle(Theme.Neutral.textMuted)
                    }
                    .padding(.horizontal, Metrics.Spacing.cardPaddingMin / 2)
                    .padding(.vertical, 4)
                    .background(Theme.Neutral.chipFill)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.chipMin, style: .circular))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// NM-9: repeating pulse loops are gated by Reduce Motion — routed
    /// through the one `MotionPreference` facade (T16), the same gate
    /// `MuscleFigure`'s float loop uses and `Space/`'s starfield/hero
    /// animations (T17/T18) will consume unchanged.
    private func startPulsingIfAllowed() {
        guard MotionPreference.repeatingAnimationsAllowed(reduceMotion: reduceMotion) else { return }
        withAnimation(.easeInOut(duration: Metrics.Motion.pulseDuration).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    /// 24-hour → "6 AM"/"9 PM" formatting — a pure function.
    static func hourLabel(_ hour24: Int) -> String {
        let period = hour24 < 12 ? "AM" : "PM"
        let displayHour = hour24 % 12 == 0 ? 12 : hour24 % 12
        return "\(displayHour) \(period)"
    }
}
