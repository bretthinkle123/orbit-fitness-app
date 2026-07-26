import SwiftUI

/// SCREEN-2 Fuel — diet log: remaining kcal, macro rings, coach banner,
/// meal/by-hour food log, quick-add. NM-1: the Meals<->By-hour paging is a
/// `TabView(.page)` bound to the SAME `SegmentedToggle` selection binding —
/// `SegmentedToggle` (T14) already wraps its own selection mutation in
/// `withAnimation`, so the page transition animates for free from sharing
/// that one binding (design's own comment: "SwiftUI: a plain withAnimation
/// on the paged offset").
struct FuelView: View {
    let store: AppStore

    /// Fixed display order (`src/orbit/models.py`'s `MEAL_GROUPS` tuple,
    /// verified directly this session) — the backend's `meals` dict has no
    /// JSON ordering of its own, so the client picks the canonical order.
    private static let mealGroupOrder = ["breakfast", "lunch", "snacks", "dinner"]

    private enum LogView: Hashable { case meals, byHour }
    @State private var logView: LogView = .meals
    // T18: same scroll-progress facade `HomeView` uses — drives the fuel
    // planet's yaw/camera descent + the hero layer's own parallax offset.
    @State private var heroScroll = HeroScrollProgress.zero

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Neutral.screenBackground.ignoresSafeArea()
            // T17: the z0 layer of the shared ZStack recipe (NM-6).
            StarfieldView(seed: StarfieldSeed.fuel, theme: store.currentTheme)
            // T18: the z1 layer — small gas planet + 3 orbiting macro moons,
            // each moon's scale live-reacting to its own macro's eaten/target
            // fraction (design: "matching 3D macro moon scales up").
            HeroSceneView(
                kind: .fuel,
                theme: store.currentTheme,
                scrollProgress: heroScroll.normalized,
                liveInputs: heroLiveInputs
            )
            .frame(height: Metrics.Hero.sceneHeight)
            .offset(y: -heroScroll.normalized * Metrics.Hero.parallaxMaxOffset)
            .frame(maxWidth: .infinity, alignment: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap) {
                    HeroScrollAnchor()
                    Color.clear.frame(height: Metrics.HeroSpacer.fuel)
                    content
                }
                .padding(.horizontal, Metrics.Spacing.contentSidePadding)
                .padding(.bottom, Metrics.Spacing.contentBottomPadding)
                .reportHeroScrollContentHeight()
            }
            .trackHeroScrollProgress($heroScroll)
            .refreshable { await store.refreshForCurrentDay() }
        }
        .safeAreaInset(edge: .top) { header }
        .task { await store.loadQuickFoodsIfNeeded() }
    }

    /// Derives the 3 macro fractions the hero's moons scale by — reuses the
    /// SAME `ProgressRing.clampedFraction` the macro-ring row already calls
    /// (`macroRingsRow` below), never a second fraction formula. `0` for
    /// every macro before `fuelDay` loads (the hero still renders, just with
    /// each moon at its base scale).
    private var heroLiveInputs: HeroSceneLiveInputs {
        guard let fuelDay = store.fuelDay else { return HeroSceneLiveInputs() }
        return HeroSceneLiveInputs(
            proteinFraction: ProgressRing.clampedFraction(value: fuelDay.totals.proteinGrams, target: Double(fuelDay.targets.proteinTargetGrams)),
            carbFraction: ProgressRing.clampedFraction(value: fuelDay.totals.carbGrams, target: Double(fuelDay.targets.carbTargetGrams)),
            fatFraction: ProgressRing.clampedFraction(value: fuelDay.totals.fatGrams, target: Double(fuelDay.targets.fatTargetGrams))
        )
    }

    private var header: some View {
        HStack {
            HeaderWordmark(text: "FUEL")
            Spacer()
            Text("Today")
                .font(.orbit(.caption))
                .foregroundStyle(Theme.Neutral.textMuted)
                .padding(.horizontal, Metrics.Spacing.cardPaddingMin)
                .frame(minHeight: Metrics.HitTarget.minimum)
                .background(Theme.Neutral.chipFill)
                .clipShape(Capsule())
        }
        .padding(.horizontal, Metrics.Spacing.contentSidePadding)
        .padding(.top, Metrics.Spacing.screenPadding)
        .padding(.bottom, Metrics.Spacing.cardGap / 2)
        .background(Theme.Neutral.screenBackground)
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.lastError, store.fuelDay == nil {
            ErrorStateView(error: error) { await store.loadEverything() }
        } else if store.fuelDay == nil {
            LoadingStateView(message: "Pulling up today's fuel log\u{2026}")
        } else if let fuelDay = store.fuelDay, let profile = store.profile {
            let theme = Theme(preset: PalettePreset(rawValue: profile.palettePreset) ?? .default)
            macroLegend(theme: theme)
            remainingCard(fuelDay: fuelDay, theme: theme)
            macroRingsRow(fuelDay: fuelDay, theme: theme)
            coachBanner(fuelDay: fuelDay, theme: theme)
            foodLogHeader
            pagedFoodLog(fuelDay: fuelDay)
            logMethodRow
        }
    }

    // MARK: - Macro legend (secL/pri/acc, matching the macro-bar/ring tints)

    private func macroLegend(theme: Theme) -> some View {
        HStack(spacing: Metrics.Spacing.cardGap) {
            legendChip(label: "Protein", tint: theme.secondaryLight)
            legendChip(label: "Carbs", tint: theme.primary)
            legendChip(label: "Fat", tint: theme.accent)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendChip(label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(label).font(.orbit(.micro)).foregroundStyle(Theme.Neutral.textMuted)
        }
    }

    // MARK: - Remaining card (34pt number + gradient bar)

    private func remainingCard(fuelDay: FuelDay, theme: Theme) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
                SectionLabel("Remaining today")
                Text("\(NumberDisplay.formatted(fuelDay.remainingKcal)) kcal")
                    .font(.orbit(.bigStatFuelRemaining))
                    .foregroundStyle(Theme.Neutral.textPrimary)
                    // T16 (AC27 smoke chain): the smoke test captures this
                    // value before a quick-add and asserts it decreased
                    // afterward (totals genuinely react), rather than
                    // hardcoding a remaining-kcal number.
                    .accessibilityIdentifier("fuel-remaining-kcal-value")
                MacroBar(
                    fraction: ProgressRing.clampedFraction(value: Double(fuelDay.totals.kcal), target: Double(fuelDay.targets.kcalBudget)),
                    tint: theme.secondary,
                    accessibilityLabel: "\(NumberDisplay.formatted(fuelDay.totals.kcal)) of \(NumberDisplay.formatted(fuelDay.targets.kcalBudget)) kilocalories"
                )
            }
        }
    }

    // MARK: - 3 macro rings (CMP-5 small)

    private func macroRingsRow(fuelDay: FuelDay, theme: Theme) -> some View {
        HStack(spacing: Metrics.Spacing.cardGap) {
            macroRing(label: "Protein", eaten: fuelDay.totals.proteinGrams, target: fuelDay.targets.proteinTargetGrams, tint: theme.secondaryLight, theme: theme)
            macroRing(label: "Carbs", eaten: fuelDay.totals.carbGrams, target: fuelDay.targets.carbTargetGrams, tint: theme.primary, theme: theme)
            macroRing(label: "Fat", eaten: fuelDay.totals.fatGrams, target: fuelDay.targets.fatTargetGrams, tint: theme.accent, theme: theme)
        }
        .frame(maxWidth: .infinity)
    }

    private func macroRing(label: String, eaten: Double, target: Int, tint: Color, theme: Theme) -> some View {
        VStack(spacing: 4) {
            ProgressRing(
                size: .small,
                fraction: ProgressRing.clampedFraction(value: eaten, target: Double(target)),
                tint: tint,
                glow: theme.ringGlow,
                accessibilityLabel: "\(label), \(Int(eaten)) of \(target) grams"
            )
            Text(label).font(.orbit(.micro)).foregroundStyle(Theme.Neutral.textMuted)
        }
    }

    // MARK: - Coach banner (CMP-15)

    private func coachBanner(fuelDay: FuelDay, theme: Theme) -> some View {
        let split = CoachMessageFormatting.splitLeadIn(fuelDay.coachMessage)
        return CoachBanner(leadIn: split.leadIn, message: split.message, theme: theme)
    }

    // MARK: - Food-log header + paging (NM-1)

    private var foodLogHeader: some View {
        HStack {
            SectionLabel("Food log")
            Spacer()
            SegmentedToggle(options: [LogView.meals, .byHour], selection: $logView) {
                $0 == .meals ? "Meals" : "By hour"
            }
        }
    }

    private func pagedFoodLog(fuelDay: FuelDay) -> some View {
        TabView(selection: $logView) {
            mealsPanel(fuelDay: fuelDay).tag(LogView.meals)
            byHourPanel(fuelDay: fuelDay).tag(LogView.byHour)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(minHeight: 420)
    }

    private func mealsPanel(fuelDay: FuelDay) -> some View {
        VStack(spacing: Metrics.Spacing.cardGap) {
            ForEach(Self.mealGroupOrder, id: \.self) { mealGroup in
                MealCard(
                    title: mealGroup.capitalized,
                    entries: fuelDay.meals[mealGroup] ?? [],
                    emptyStateQuickAdds: store.quickFoods ?? [],
                    onQuickAdd: { food in Task { await quickAdd(food: food, mealGroup: mealGroup) } }
                )
            }
        }
    }

    private func byHourPanel(fuelDay: FuelDay) -> some View {
        let allEntries = Self.mealGroupOrder.flatMap { fuelDay.meals[$0] ?? [] }
        let entriesByHour = Dictionary(grouping: allEntries) { Calendar.current.component(.hour, from: $0.loggedAt) }
            .mapValues { entries in entries.map { HourTimelineEntry(id: $0.id, name: $0.name, kcal: $0.kcal) } }
        let currentHour = Calendar.current.component(.hour, from: Date())
        return ScrollView {
            HourTimeline(entriesByHour: entriesByHour, nowHour: (6...21).contains(currentHour) ? currentHour : nil)
        }
    }

    // MARK: - Log-method row (CMP-14, stubbed)

    private var logMethodRow: some View {
        HStack(spacing: Metrics.Spacing.cardGap) {
            ForEach(LogMethodButton.Method.allCases) { method in
                LogMethodButton(method: method)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func quickAdd(food: QuickFood, mealGroup: String) async {
        try? await store.addFoodEntry(.quickFood(id: food.id, mealGroup: mealGroup, dayKey: store.dayKey, loggedAt: Date()))
    }
}
