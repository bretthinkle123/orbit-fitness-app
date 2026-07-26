import SwiftUI

/// CMP-12 — Fuel's per-meal cards (Breakfast/Lunch/Dinner/Snacks). Takes
/// `Core/Models.swift`'s existing `FoodEntry`/`QuickFood` types directly
/// rather than inventing parallel presentational structs — they're already
/// plain `Codable` value types with exactly the fields this card needs
/// (YAGNI: no reason to duplicate them for a presentational layer that has
/// no different shape to express). Only Dinner is depicted with the
/// zero-data quick-add state (design-spec: dashed divider + "Nothing
/// logged — quick add:" + suggestion chips) — any meal group can render it
/// once `entries` is empty, generalizing the ONE depicted example per
/// plan §Data's day-keyed, all-groups-always-present architecture.
struct MealCard: View {
    let title: String
    let entries: [FoodEntry]
    /// Only meaningful when `entries` is empty — the quick-add suggestions
    /// shown in the empty state.
    var emptyStateQuickAdds: [QuickFood] = []
    var onQuickAdd: ((QuickFood) -> Void)?

    private var totalKcal: Int { entries.reduce(0) { $0 + $1.kcal } }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
                HStack {
                    Text(title)
                        .font(.orbit(.cardTitle))
                        .foregroundStyle(Theme.Neutral.textPrimary)
                    Spacer()
                    Text("\(totalKcal) kcal")
                        .font(.orbit(.caption))
                        .foregroundStyle(Theme.Neutral.textMuted)
                }
                if entries.isEmpty {
                    emptyState
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.name)
                                .font(.orbit(.body))
                                .foregroundStyle(Theme.Neutral.textPrimary)
                            Spacer()
                            Text("\(entry.kcal)")
                                .font(.orbit(.caption))
                                .foregroundStyle(Theme.Neutral.textMuted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
            DashedDivider()
            Text("Nothing logged — quick add:")
                .font(.orbit(.caption))
                .foregroundStyle(Theme.Neutral.textMuted)
            HStack(spacing: Metrics.Spacing.cardGap / 2) {
                ForEach(emptyStateQuickAdds) { food in
                    QuickAddChip(name: food.name, isAdded: false) { onQuickAdd?(food) }
                        // T16 (AC27 smoke chain): a stable, per-(meal,food)
                        // identifier — `title` is already the raw meal-group
                        // key capitalized (`FuelView` passes `mealGroup.
                        // capitalized`), so lowercasing it round-trips to the
                        // same key `AppStore.addFoodEntry` sends server-side.
                        .accessibilityIdentifier("fuel-quickadd-\(title.lowercased())-\(AccessibilityIdentifierSlug.slug(food.name))")
                }
            }
        }
    }
}

/// The design's dashed section divider (empty-state meal cards) — SwiftUI
/// has no built-in dashed `Rectangle`, so this draws a 1pt horizontal
/// `Path` with a dash `StrokeStyle` instead of a solid fill.
private struct DashedDivider: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
            }
            .stroke(Theme.Neutral.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 1)
    }
}
