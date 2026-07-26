import SwiftUI

/// SCREEN-4 Body — muscle map: front+back geometric figures, M/W toggle,
/// 6-level scale, by-muscle list. **No 3D hero — starfield only**
/// (design-spec §4), so this screen uses the generic `Metrics.Spacing.
/// contentTopPadding`, not a `HeroSpacer` value.
struct BodyView: View {
    let store: AppStore

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Neutral.screenBackground.ignoresSafeArea()
            // T17: the z0 layer of the shared ZStack recipe (NM-6) — Body
            // has "no 3D hero — starfield only" (design-spec §4), so this
            // IS the whole background here, not just a base layer under a
            // future hero.
            StarfieldView(seed: StarfieldSeed.body, theme: store.currentTheme)
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap) {
                    content
                }
                .padding(.top, Metrics.Spacing.contentTopPadding)
                .padding(.horizontal, Metrics.Spacing.contentSidePadding)
                .padding(.bottom, Metrics.Spacing.contentBottomPadding)
            }
            .refreshable { await store.refreshForCurrentDay() }
        }
        .safeAreaInset(edge: .top) { header }
    }

    private var header: some View {
        HStack {
            HeaderWordmark(text: "BODY")
            Spacer()
            Text("Results")
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
        if let error = store.lastError, store.bodyDay == nil {
            ErrorStateView(error: error) { await store.loadEverything() }
        } else if store.bodyDay == nil {
            LoadingStateView(message: "Mapping your body\u{2026}")
        } else if let bodyDay = store.bodyDay, let profile = store.profile {
            let theme = Theme(preset: PalettePreset(rawValue: profile.palettePreset) ?? .default)
            titleBlock
            muscleLevelsCard(bodyDay: bodyDay, profile: profile, theme: theme)
            byMuscleGroupCard(bodyDay: bodyDay, theme: theme)
            TipBanner(leadIn: "Tip:", message: "log sets on Train and trained muscles glow here.", theme: theme)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Body map")
                .font(.orbit(.screenTitle))
                .foregroundStyle(Theme.Neutral.textPrimary)
            Text("Score \(store.trainScore ?? store.profile?.scoreBase ?? 0)")
                .font(.orbit(.caption))
                .foregroundStyle(Theme.Neutral.textMuted)
        }
    }

    // MARK: - Muscle-levels card (M/W toggle + front/back figures + legend)

    private func muscleLevelsCard(bodyDay: BodyDay, profile: ProfileOut, theme: Theme) -> some View {
        let levelLookup = Dictionary(uniqueKeysWithValues: bodyDay.muscleLevels.map { ($0.muscleGroup, $0) })

        func level(for token: MuscleGroupToken) -> Int {
            levelLookup[token.rawValue]?.level ?? 1
        }
        func trainedToday(for token: MuscleGroupToken) -> Bool {
            levelLookup[token.rawValue]?.trainedToday ?? false
        }

        return GlassCard {
            VStack(spacing: Metrics.Spacing.cardGap) {
                HStack {
                    SectionLabel("Muscle map")
                    Spacer()
                    SegmentedToggle(options: ["m", "w"], selection: genderBinding) {
                        $0 == "m" ? "M" : "W"
                    }
                }
                VStack(spacing: 4) {
                    Text("Front").font(.orbit(.micro)).foregroundStyle(Theme.Neutral.textFaint)
                    MuscleFigure(
                        shapes: FigurePaths.frontShapes(forGender: profile.gender),
                        levelForGroup: level,
                        isTrainedToday: trainedToday,
                        theme: theme
                    )
                    .frame(height: 240)
                }
                VStack(spacing: 4) {
                    Text("Back").font(.orbit(.micro)).foregroundStyle(Theme.Neutral.textFaint)
                    MuscleFigure(
                        shapes: FigurePaths.backShapes(forGender: profile.gender),
                        levelForGroup: level,
                        isTrainedToday: trainedToday,
                        theme: theme
                    )
                    .frame(height: 240)
                }
                LevelLegend(theme: theme)
            }
        }
    }

    private var genderBinding: Binding<String> {
        Binding(
            get: { store.profile?.gender ?? "m" },
            set: { newValue in Task { try? await store.updateProfile(ProfileUpdate(gender: newValue)) } }
        )
    }

    // MARK: - By-muscle-group card (13 rows, backend's own declared order)

    private func byMuscleGroupCard(bodyDay: BodyDay, theme: Theme) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
                SectionLabel("By muscle group")
                ForEach(bodyDay.muscleLevels, id: \.muscleGroup) { level in
                    MuscleRow(
                        muscleGroupName: MuscleGroupToken(rawValue: level.muscleGroup)?.displayName ?? level.muscleGroup.capitalized,
                        level: level.level,
                        isTrainedToday: level.trainedToday,
                        theme: theme
                    )
                    // T16 (AC27 smoke chain): keyed on the backend's own raw
                    // muscle-group token (`"chest"`, not the display name),
                    // so the smoke test can assert "Body glows" after
                    // toggling a known Push Day set (chest, via Barbell
                    // Bench Press) without depending on display-string
                    // formatting.
                    .accessibilityIdentifier("body-muscle-row-\(level.muscleGroup)")
                }
            }
        }
    }
}
