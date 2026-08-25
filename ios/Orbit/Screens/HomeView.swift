import SwiftUI

#if DEBUG
private struct GreetingHourOverrideKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// Snapshot-test seam: pin the hour `HomeView`'s greeting is derived from,
    /// instead of reading the wall clock.
    ///
    /// Needed because the greeting is the ONE part of Home that is not a
    /// function of the store's pinned `dayKey`: it reads `Date()` and buckets
    /// it via `GreetingText.timeOfDayGreeting(hour:)` ("Good morning" /
    /// "afternoon" / "evening" / "night"). A recorded baseline therefore only
    /// matches when the suite is re-run inside the SAME time-of-day bucket it
    /// was recorded in — `testHomeViewLoadedState` recorded at 22:40 ("Good
    /// night") failed the next afternoon ("Good afternoon"), which reads as a
    /// visual regression rather than a clock-dependent fixture. The rest of
    /// the screen was already deterministic (`AppStore(dayKey: "2026-07-25")`);
    /// this closes the last gap.
    ///
    /// `#if DEBUG` so no test seam exists in release source (AC32/SC-7), the
    /// same posture as `heroSceneRenderingEnabled` and
    /// `OrbitApp.resetAuthStateIfRequested`.
    var greetingHourOverride: Int? {
        get { self[GreetingHourOverrideKey.self] }
        set { self[GreetingHourOverrideKey.self] = newValue }
    }
}
#endif

/// SCREEN-1 Home — the daily dashboard aggregating profile+fuel+train+weight
/// (plan §Backend "API rationale": "the Home dashboard composes
/// profile+fuel+train+weight with Swift `async let` concurrency (4 parallel
/// requests)"). The 4-parallel fetch itself lives in `AppStore.
/// loadEverything()` (T12) — this view is a pure READER of that already-
/// fetched state, never a second, duplicate fetch path.
struct HomeView: View {
    let store: AppStore
    let authService: AuthServiceProtocol
    /// The avatar tap opens Settings (design-spec §4: "tap avatar 'AK' —
    /// SCREEN-5 Settings sheet") — `AppRouter.presentSettings()`, supplied by
    /// `RootTabView` (the router lives one level up).
    let onOpenSettings: () -> Void
    /// Home's "Start Push Day" CTA has no wired destination in the
    /// prototype (design-spec §1: "Open item... intent implies Train") —
    /// resolved here per the design's own stated intent: switch to the
    /// Train tab.
    let onStartPushDay: () -> Void

    #if DEBUG
    /// Snapshot-test seam — see `EnvironmentValues.greetingHourOverride`.
    @Environment(\.greetingHourOverride) private var greetingHourOverride
    #endif

    @State private var isShowingWeightSheet = false
    // T18: the scroll-progress facade every hero-bearing screen shares
    // (`Space/HeroSceneView.swift`) — drives the planet spin/ring-tilt/
    // camera-pull math AND the hero layer's own −95pt parallax offset below.
    @State private var heroScroll = HeroScrollProgress.zero

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Neutral.screenBackground.ignoresSafeArea()
            // T17: replaces the flat-background placeholder — the z0 layer
            // of the shared ZStack recipe (NM-6).
            StarfieldView(seed: StarfieldSeed.home, theme: store.currentTheme)
            // T18: the z1 layer — gas-giant planet + progression rings
            // (design-spec's "Your system" planet-index selection drives
            // both the texture seed and the ring count). README's own
            // default `planetIndex` (2) covers the brief pre-bootstrap
            // window before `store.profile` loads.
            HeroSceneView(
                kind: .home(planetIndex: store.profile?.planetIndex ?? 2),
                theme: store.currentTheme,
                scrollProgress: heroScroll.normalized
            )
            .frame(height: Metrics.Hero.sceneHeight)
            .offset(y: -heroScroll.normalized * Metrics.Hero.parallaxMaxOffset)
            .frame(maxWidth: .infinity, alignment: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap) {
                    HeroScrollAnchor()
                    // Reserves the Home 3D hero's space (smaller than the
                    // hero's own ~440pt visual height, README, so cards
                    // slide up over its lower portion).
                    Color.clear.frame(height: Metrics.HeroSpacer.home)
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
        .sheet(isPresented: $isShowingWeightSheet) {
            WeightEntrySheet(store: store)
        }
    }

    // MARK: - Header (pinned; design-spec §4: "Header pinned; content scrolls")

    private var header: some View {
        HStack {
            HeaderWordmark(text: "ORBIT")
            Spacer()
            Avatar(
                initials: AvatarInitials.initials(
                    displayName: authService.currentUserDisplayName,
                    email: authService.currentUserEmail
                ),
                size: .small,
                action: onOpenSettings
            )
            // `home-avatar-settings-button` is the identifier T13's
            // `AuthFlowUITests`/`AccountLifecycleUITests` already assert on
            // — preserved verbatim so those XCUITest skeletons keep working
            // now that a real screen replaces `RootTabView`'s placeholder.
            .accessibilityIdentifier("home-avatar-settings-button")
        }
        .padding(.horizontal, Metrics.Spacing.contentSidePadding)
        .padding(.top, Metrics.Spacing.screenPadding)
        .padding(.bottom, Metrics.Spacing.cardGap / 2)
        .background(Theme.Neutral.screenBackground)
    }

    // MARK: - Content states (plan §Frontend: loading / empty / error)

    @ViewBuilder
    private var content: some View {
        if let error = store.lastError, store.profile == nil {
            ErrorStateView(error: error) { await store.loadEverything() }
        } else if store.profile == nil {
            LoadingStateView(message: "Charting your orbit\u{2026}")
        } else if let profile = store.profile {
            let theme = Theme(preset: PalettePreset(rawValue: profile.palettePreset) ?? .default)
            greeting
            planetPickerCard(profile: profile, theme: theme)
            caloriesRingCard(profile: profile, theme: theme)
            macrosCard(profile: profile, theme: theme)
            missionCard(theme: theme)
            statChipsRow(profile: profile)
            weightTrendCard(profile: profile)
        }
    }

    private var greeting: some View {
        var hour = Calendar.current.component(.hour, from: Date())
        #if DEBUG
        hour = greetingHourOverride ?? hour
        #endif
        return Text(GreetingText.timeOfDayGreeting(hour: hour))
            .font(.orbit(.screenTitle))
            .foregroundStyle(Theme.Neutral.textPrimary)
    }

    // MARK: - "Your system" planet picker (CMP-10 x6)

    private static let planetNames = ["Ember", "Dune", "Titan", "Aurora", "Nova", "Zenith"]

    private func planetPickerCard(profile: ProfileOut, theme: Theme) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
                SectionLabel("Your system")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.Spacing.cardGap / 2) {
                        ForEach(Array(Self.planetNames.enumerated()), id: \.offset) { index, name in
                            PlanetPickerChip(
                                name: name,
                                levelIndex: index + 1, // theme.levelScaleStop is 1...6
                                isActive: profile.planetIndex == index,
                                theme: theme,
                                action: { Task { await updateProfile(ProfileUpdate(planetIndex: index)) } }
                            )
                        }
                    }
                }
                Text(PlanetRingCaption.caption(forIndex: profile.planetIndex))
                    .font(.orbit(.micro))
                    .foregroundStyle(Theme.Neutral.textFaint)
            }
        }
    }

    // MARK: - Calories ring card (CMP-5 large)

    private func caloriesRingCard(profile: ProfileOut, theme: Theme) -> some View {
        let eaten = store.macroTotals?.kcal ?? 0
        let budget = profile.kcalBudget
        let burned = profile.burnedKcal
        return GlassCard {
            HStack(spacing: Metrics.Spacing.cardGap) {
                ProgressRing(
                    size: .large,
                    fraction: ProgressRing.clampedFraction(value: Double(eaten), target: Double(budget)),
                    tint: theme.primary,
                    glow: theme.ringGlow,
                    accessibilityLabel: "\(NumberDisplay.formatted(eaten)) of \(NumberDisplay.formatted(budget)) kilocalories"
                )
                // T16 (AC27 smoke chain): a stable identifier over the
                // ring's LIVE value+target label — the smoke test captures
                // this label before a Fuel quick-add and asserts it changed
                // afterward (the shared-store cross-screen reaction, plan
                // §Frontend), rather than hardcoding an eaten/budget number.
                .accessibilityIdentifier("home-calorie-ring")
                VStack(alignment: .leading, spacing: 6) {
                    statRow(label: "Eaten", value: NumberDisplay.formatted(eaten), identifier: "home-stat-eaten-value")
                    statRow(label: "Burned", value: NumberDisplay.formatted(burned))
                    statRow(label: "Budget", value: NumberDisplay.formatted(budget))
                }
            }
        }
    }

    /// `identifier` is optional (default `nil`) so only the ONE stat row the
    /// smoke test needs to read (`"Eaten"`, T16/AC27) carries a stable
    /// identifier — "Burned"/"Budget" don't need one and shouldn't be forced
    /// to invent one just to keep this signature uniform.
    @ViewBuilder
    private func statRow(label: String, value: String, identifier: String? = nil) -> some View {
        HStack {
            Text(label).font(.orbit(.caption)).foregroundStyle(Theme.Neutral.textMuted)
            Spacer(minLength: Metrics.Spacing.cardGap)
            let valueText = Text(value).font(.orbit(.body)).foregroundStyle(Theme.Neutral.textPrimary)
            if let identifier {
                valueText.accessibilityIdentifier(identifier)
            } else {
                valueText
            }
        }
    }

    // MARK: - Macros card (CMP-6 x3)

    private func macrosCard(profile: ProfileOut, theme: Theme) -> some View {
        let totals = store.macroTotals
        return GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
                SectionLabel("Macros")
                macroBarRow(
                    label: "Protein", eaten: totals?.proteinGrams ?? 0, target: profile.proteinTargetGrams, tint: theme.secondaryLight
                )
                macroBarRow(
                    label: "Carbs", eaten: totals?.carbGrams ?? 0, target: profile.carbTargetGrams, tint: theme.primary
                )
                macroBarRow(
                    label: "Fat", eaten: totals?.fatGrams ?? 0, target: profile.fatTargetGrams, tint: theme.accent
                )
            }
        }
    }

    private func macroBarRow(label: String, eaten: Double, target: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label) \u{00b7} \(Int(eaten))/\(target) g")
                .font(.orbit(.caption))
                .foregroundStyle(Theme.Neutral.textMuted)
            MacroBar(
                fraction: ProgressRing.clampedFraction(value: eaten, target: Double(target)),
                tint: tint,
                accessibilityLabel: "\(label), \(Int(eaten)) of \(target) grams"
            )
        }
    }

    // MARK: - Mission card (CMP-7)

    private func missionCard(theme: Theme) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
                SectionLabel("Mission")
                GradientPillButton(title: "Start Push Day", theme: theme, action: onStartPushDay)
            }
        }
    }

    // MARK: - Stat chips row (CMP-8 x2)

    private func statChipsRow(profile: ProfileOut) -> some View {
        HStack(spacing: Metrics.Spacing.cardGap) {
            StatChip(
                label: "Strength score",
                value: store.trainScore.map(String.init) ?? "\u{2014}",
                caption: store.weeklyDelta.map { "+\($0) this wk \u{00b7} \(profile.tierLabel)" }
            )
            StatChip(label: "Burn rate", value: "\(NumberDisplay.formatted(profile.burnedKcal)) kcal")
        }
    }

    // MARK: - Weight-trend card (CMP-20)

    private func weightTrendCard(profile: ProfileOut) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
                HStack {
                    SectionLabel("Weight")
                    Spacer()
                    Button("Log", action: { isShowingWeightSheet = true })
                        .font(.orbit(.caption))
                        .foregroundStyle(Theme.Neutral.textPrimary)
                        .frame(minWidth: Metrics.HitTarget.minimum, minHeight: Metrics.HitTarget.minimum)
                        .accessibilityIdentifier("home-log-weight-button")
                }
                if let window = store.weightWindow, let latest = window.latest {
                    Sparkline(values: window.entries.map(\.weightKilograms))
                        .frame(height: 60)
                    let trendText = window.weeklyDeltaKilograms.map { delta -> String in
                        let displayDelta = WeightUnitFormatting.displayValue(kilograms: abs(delta), units: profile.units)
                        let direction = delta < 0 ? "down" : "up"
                        return "\(WeightUnitFormatting.formatted(kilograms: latest.weightKilograms, units: profile.units)), \(direction) \(String(format: "%.1f", displayDelta)) \(WeightUnitFormatting.unitLabel(units: profile.units)) / wk"
                    } ?? WeightUnitFormatting.formatted(kilograms: latest.weightKilograms, units: profile.units)
                    Text(trendText)
                        .font(.orbit(.caption))
                        .foregroundStyle(Theme.Neutral.textMuted)
                        // T16 (AC27 smoke chain): lets the smoke test assert
                        // the empty-state prompt was replaced by a real
                        // trend line after logging a weight entry.
                        .accessibilityIdentifier("home-weight-trend-value")
                } else {
                    EmptyStatePrompt(
                        message: "No weigh-ins yet \u{2014} log one to start your trend.",
                        actionTitle: "Log weight",
                        action: { isShowingWeightSheet = true }
                    )
                    .accessibilityIdentifier("home-weight-empty-state")
                }
            }
        }
    }

    // MARK: - Actions

    private func updateProfile(_ update: ProfileUpdate) async {
        try? await store.updateProfile(update)
    }
}
