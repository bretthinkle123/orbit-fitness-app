import SwiftUI

/// The 120s rest-countdown state machine `TrainView`'s `RestChip` displays —
/// a pure, directly-testable model (no `Timer`/Combine dependency in the
/// type itself) so Swift Testing can drive it deterministically via
/// `tick()` rather than waiting on a real clock. `TrainView` owns one as
/// `@State` and ticks it once per second via a `.task` loop (structured
/// concurrency, `swift-conventions`, rather than `Timer`/Combine).
struct RestTimerState: Equatable {
    private(set) var remainingSeconds: Int = 0

    /// A set turning ON (re)starts the 120s countdown (design-spec §5)
    /// regardless of whatever was already counting down — a (re)start, not
    /// an accumulate.
    mutating func startCountdown(seconds: Int = 120) {
        remainingSeconds = seconds
    }

    /// One second elapsed — never goes below 0 (the chip hides at 0, not a
    /// negative countdown display).
    mutating func tick() {
        remainingSeconds = max(remainingSeconds - 1, 0)
    }

    var isResting: Bool { remainingSeconds > 0 }
}

/// SCREEN-3 Train — strength score, Push Day session with tappable sets,
/// rest timer, week strip. Every set toggle goes through `AppStore.
/// markSetDone`/`unmarkSet` (T12), which already re-fetches BOTH Train and
/// Body so the score-everywhere + Body-glow cross-screen reaction (design-
/// spec §5) happens through the one shared store, never a local mutation
/// here.
struct TrainView: View {
    let store: AppStore

    @State private var restTimer = RestTimerState()
    @State private var actionError: AppError?
    // T18: same scroll-progress facade `HomeView`/`FuelView` use — drives
    // the asteroid's camera-orbit azimuth + the hero layer's own parallax.
    @State private var heroScroll = HeroScrollProgress.zero

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Neutral.screenBackground.ignoresSafeArea()
            // T17: the z0 layer of the shared ZStack recipe (NM-6).
            StarfieldView(seed: StarfieldSeed.train, theme: store.currentTheme)
            // T18: the z1 layer — displaced rocky asteroid + 3 orbiting
            // debris rocks, heating up (emissive glow) as sets complete.
            HeroSceneView(
                kind: .train,
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
                    Color.clear.frame(height: Metrics.HeroSpacer.train)
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
        // 1Hz tick loop for the client-side rest countdown — auto-cancelled
        // when the view disappears (`.task`'s structured-concurrency
        // lifetime, `swift-conventions`), no Timer/Combine needed.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                restTimer.tick()
            }
        }
    }

    private var header: some View {
        HStack {
            HeaderWordmark(text: "TRAIN")
            Spacer()
            if let focus = store.trainDay?.program.focus {
                Text("\(focus) focus")
                    .font(.orbit(.caption))
                    .foregroundStyle(Theme.Neutral.textMuted)
                    .padding(.horizontal, Metrics.Spacing.cardPaddingMin)
                    .frame(minHeight: Metrics.HitTarget.minimum)
                    .background(Theme.Neutral.chipFill)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, Metrics.Spacing.contentSidePadding)
        .padding(.top, Metrics.Spacing.screenPadding)
        .padding(.bottom, Metrics.Spacing.cardGap / 2)
        .background(Theme.Neutral.screenBackground)
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.lastError, store.trainDay == nil {
            ErrorStateView(error: error) { await store.loadEverything() }
        } else if store.trainDay == nil {
            LoadingStateView(message: "Loading today's session\u{2026}")
        } else if let trainDay = store.trainDay, let profile = store.profile {
            let theme = Theme(preset: PalettePreset(rawValue: profile.palettePreset) ?? .default)
            if let actionError {
                Text(actionError.userFacingMessage)
                    .font(.orbit(.caption))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("train-error")
            }
            scoreCard(trainDay: trainDay, profile: profile, theme: theme)
            sessionCard(trainDay: trainDay, theme: theme)
            WeekStrip(filledDays: trainDay.weekStrip, theme: theme)
        }
    }

    // MARK: - Strength-score card

    private func scoreCard(trainDay: TrainDay, profile: ProfileOut, theme: Theme) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap / 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(trainDay.score)")
                        .font(.orbit(.bigStatTrainScore))
                        .foregroundStyle(Theme.Neutral.textPrimary)
                    Text("+\(trainDay.weeklyDelta) this wk")
                        .font(.orbit(.caption))
                        .foregroundStyle(Theme.Neutral.textMuted)
                        .padding(.horizontal, Metrics.Spacing.cardPaddingMin / 2)
                        .background(Theme.Neutral.chipFill)
                        .clipShape(Capsule())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Strength score \(trainDay.score), plus \(trainDay.weeklyDelta) this week")
                // T16 (AC27 smoke chain): a stable identifier the score
                // reads through (its LABEL carries the live number/delta —
                // the smoke test captures the label before/after a set
                // toggle and asserts it changed, rather than hardcoding a
                // score value).
                .accessibilityIdentifier("train-score-value")
                MacroBar(
                    fraction: Double(profile.nextTierPercent) / 100,
                    tint: theme.primary,
                    accessibilityLabel: "\(profile.nextTierPercent) percent to next tier"
                )
            }
        }
    }

    /// The hero's asteroid-heat target (README "emissive heat = .1 +
    /// 1.6*(doneSets/16)") — `16` is Push Day's OWN seeded total (T6:
    /// 4+3+3+3+3), but this derives the denominator from `trainDay.exercises`
    /// itself (the SAME computation `sessionCard` below already does, factored
    /// out here so the two call sites can never silently drift apart) rather
    /// than hardcoding `16`, so a future program with a different set count
    /// still produces the correct ratio. `0` before `trainDay` loads (the
    /// hero still renders, just cold).
    private var heroLiveInputs: HeroSceneLiveInputs {
        guard let trainDay = store.trainDay else { return HeroSceneLiveInputs() }
        let totalSets = Self.totalSetCount(for: trainDay)
        let doneSetFraction = totalSets > 0 ? Double(store.doneSetTags.count) / Double(totalSets) : 0
        return HeroSceneLiveInputs(doneSetFraction: doneSetFraction)
    }

    private static func totalSetCount(for trainDay: TrainDay) -> Int {
        trainDay.exercises.reduce(0) { $0 + $1.sets }
    }

    // MARK: - Session card (Push Day + exercises + set circles)

    private func sessionCard(trainDay: TrainDay, theme: Theme) -> some View {
        let doneCount = store.doneSetTags.count
        let totalSets = Self.totalSetCount(for: trainDay)
        return GlassCard {
            VStack(alignment: .leading, spacing: Metrics.Spacing.cardGap) {
                HStack {
                    Text(trainDay.program.name)
                        .font(.orbit(.cardTitle))
                        .foregroundStyle(Theme.Neutral.textPrimary)
                    Spacer()
                    Text("\(doneCount)/\(totalSets)")
                        .font(.orbit(.caption))
                        .foregroundStyle(Theme.Neutral.textMuted)
                    RestChip(remainingSeconds: restTimer.remainingSeconds, theme: theme)
                }
                MacroBar(
                    fraction: totalSets > 0 ? Double(doneCount) / Double(totalSets) : 0,
                    tint: theme.secondary,
                    accessibilityLabel: "\(doneCount) of \(totalSets) sets done"
                )
                ForEach(trainDay.exercises) { exercise in
                    exerciseBlock(exercise: exercise, dayKey: trainDay.dayKey, theme: theme)
                }
            }
        }
    }

    private func exerciseBlock(exercise: Exercise, dayKey: String, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name)
                .font(.orbit(.body))
                .foregroundStyle(Theme.Neutral.textPrimary)
            Text(ExerciseSchemeFormatting.formatted(sets: exercise.sets, reps: exercise.reps, weight: exercise.weight))
                .font(.orbit(.caption))
                .foregroundStyle(Theme.Neutral.textMuted)
            HStack(spacing: Metrics.Spacing.cardGap / 2) {
                ForEach(0..<exercise.sets, id: \.self) { setIndex in
                    let isDone = store.doneSetTags.contains(SetTag(exerciseID: exercise.id, setIndex: setIndex))
                    SetCircle(
                        setNumber: setIndex + 1,
                        isDone: isDone,
                        theme: theme,
                        action: { Task { await toggleSet(exercise: exercise, setIndex: setIndex, dayKey: dayKey, isCurrentlyDone: isDone) } }
                    )
                    // T16 (AC27 smoke chain): a stable, per-(exercise,set)
                    // identifier built from the exercise's own NAME (not its
                    // DB-assigned id, which is a seed-order accident, not a
                    // stable fact worth a test depending on).
                    .accessibilityIdentifier("train-set-\(AccessibilityIdentifierSlug.slug(exercise.name))-\(setIndex + 1)")
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleSet(exercise: Exercise, setIndex: Int, dayKey: String, isCurrentlyDone: Bool) async {
        do {
            if isCurrentlyDone {
                try await store.unmarkSet(SetIdentifier(exerciseID: exercise.id, setIndex: setIndex, dayKey: dayKey))
            } else {
                try await store.markSetDone(
                    SetToggleCreate(exerciseID: exercise.id, setIndex: setIndex, dayKey: dayKey, doneAt: Date())
                )
                // design-spec §5: turning a set ON (re)starts the 120s rest countdown.
                restTimer.startCountdown()
            }
            actionError = nil
        } catch {
            actionError = (error as? AppError) ?? .network(message: error.localizedDescription)
        }
    }
}
