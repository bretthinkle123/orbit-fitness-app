import Foundation

/// Identifies one exercise's one set — the currency `doneSetTags` uses so a
/// screen can ask "is THIS set done?" in O(1) without re-deriving it from
/// `TrainDay.exercises` itself (plan §Frontend: "the derived values...so the
/// cross-screen reactions the design depicts work off one store").
struct SetTag: Hashable, Sendable {
    let exerciseID: Int
    let setIndex: Int
}

/// The one shared, `@MainActor`-confined store holding the fetched day data
/// + settings + derived values every screen reads (plan §Frontend `Core/`:
/// "`AppStore` (`@MainActor @Observable`) holding the fetched day data +
/// settings + `DayState` and the derived values... so the cross-screen
/// reactions the design depicts work off one store"). Screens never call
/// `APIClientProtocol` directly — they read/mutate through this store, so a
/// quick-add on Fuel is reflected in Home's ring, a set toggle is reflected
/// in both Train's score and Body's glow, etc., without each screen
/// separately re-fetching or re-deriving the same numbers.
@MainActor
@Observable
final class AppStore {
    private let apiClient: APIClientProtocol

    private(set) var profile: ProfileOut?
    private(set) var fuelDay: FuelDay?
    private(set) var trainDay: TrainDay?
    private(set) var bodyDay: BodyDay?
    private(set) var weightWindow: WeightWindow?
    /// The global quick-food catalog (T15's `FuelView`) — deliberately NOT
    /// part of `loadEverything()`'s day-scoped `async let` fan-out: it is
    /// global/cacheable (plan §Backend), not per-day data, so it is fetched
    /// once, lazily, on first need rather than on every day-boundary reload.
    private(set) var quickFoods: [QuickFood]?

    private(set) var isLoading = false
    private(set) var lastError: AppError?

    /// The day_key every day-scoped fetch/write uses (plan §Data: the
    /// user's device-tz local date) — recomputed at store construction and
    /// on each `loadEverything()` call, so a day boundary crossed while the
    /// app was backgrounded is picked up on the next foreground load.
    private(set) var dayKey: String

    init(apiClient: APIClientProtocol, dayKey: String = DayKeyFormatting.today()) {
        self.apiClient = apiClient
        self.dayKey = dayKey
    }

    // MARK: - Derived values (design-spec §5 "shared store, cross-screen reactions")

    var macroTotals: MacroTotals? { fuelDay?.totals }
    var macroTargets: MacroTargets? { fuelDay?.targets }
    var remainingKcal: Int? { fuelDay?.remainingKcal }

    var trainScore: Int? { trainDay?.score }
    var weeklyDelta: Int? { trainDay?.weeklyDelta }

    /// Derives the display `Theme` from the caller's own saved palette
    /// preference, defaulting to purple before a profile exists — every
    /// screen's starfield/card tinting (T17) and `SettingsSheet` (T13) all
    /// need this exact expression; centralized here once rather than
    /// re-derived independently at each call site.
    var currentTheme: Theme {
        Theme(preset: PalettePreset(rawValue: profile?.palettePreset ?? "") ?? .default)
    }

    /// Every (exercise, set-index) pair currently marked done, for the
    /// active `dayKey` — Train's set circles and any other screen that
    /// needs to know "is this set on?" read this rather than searching
    /// `trainDay.exercises` themselves.
    var doneSetTags: Set<SetTag> {
        guard let trainDay else { return [] }
        return Set(
            trainDay.exercises.flatMap { exercise in
                exercise.doneSetIndexes.map { SetTag(exerciseID: exercise.id, setIndex: $0) }
            }
        )
    }

    /// Muscle-group names trained on the active `dayKey` (Body's glow +,
    /// per the design, a future Home/Train cross-highlight).
    var trainedMuscleGroupsToday: Set<String> {
        guard let bodyDay else { return [] }
        return Set(bodyDay.muscleLevels.filter(\.trainedToday).map(\.muscleGroup))
    }

    // MARK: - Loading

    /// Bootstraps the profile (idempotent — safe to call every launch) and
    /// fetches every day-scoped resource for `dayKey` concurrently. Screens
    /// render `isLoading`/`lastError`/each `nil` field as the design's
    /// loading/empty/error states (plan §Frontend) rather than this store
    /// picking a UI shape itself.
    func loadEverything() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await apiClient.bootstrapProfile()
            async let fuel = apiClient.fetchFuelDay(dayKey: dayKey)
            async let train = apiClient.fetchTrainDay(dayKey: dayKey)
            async let body = apiClient.fetchBodyDay(dayKey: dayKey)
            async let weight = apiClient.fetchWeightWindow()
            (fuelDay, trainDay, bodyDay, weightWindow) = try await (fuel, train, body, weight)
            lastError = nil
        } catch {
            lastError = Self.asAppError(error)
        }
    }

    /// Re-derives `dayKey` from the device clock and reloads everything —
    /// call when the app returns to foreground, so a day-boundary crossing
    /// while backgrounded is honored (plan §Data: day_key is device-tz
    /// local date, not a value fixed at launch).
    func refreshForCurrentDay() async {
        dayKey = DayKeyFormatting.today()
        await loadEverything()
    }

    /// Fetches the quick-food catalog once and caches it — a no-op on every
    /// subsequent call (the catalog never changes within a session), so
    /// `FuelView` can call this unconditionally from a `.task` without
    /// re-fetching on every appearance.
    func loadQuickFoodsIfNeeded() async {
        guard quickFoods == nil else { return }
        do {
            quickFoods = try await apiClient.fetchQuickFoods()
        } catch {
            lastError = Self.asAppError(error)
        }
    }

    // MARK: - Mutations (each refreshes exactly the screens the design says react)

    /// Quick-add a food entry, then re-fetch Fuel (updates its rings/bars)
    /// — Home's ring/macro bars read the SAME `fuelDay`, so they update too
    /// without a separate fetch (design-spec §5: "Quick-add on Fuel updates
    /// Home's ring + macro bars...").
    func addFoodEntry(_ entry: FoodEntryCreate) async throws {
        _ = try await apiClient.createFoodEntry(entry)
        fuelDay = try await apiClient.fetchFuelDay(dayKey: dayKey)
    }

    /// Marks a set done, then re-fetches BOTH Train and Body (design-spec
    /// §5: "Set toggles on Train update the score everywhere... and light
    /// the corresponding Body muscles").
    func markSetDone(_ toggle: SetToggleCreate) async throws {
        _ = try await apiClient.markSetDone(toggle)
        async let train = apiClient.fetchTrainDay(dayKey: dayKey)
        async let body = apiClient.fetchBodyDay(dayKey: dayKey)
        (trainDay, bodyDay) = try await (train, body)
    }

    func unmarkSet(_ identifier: SetIdentifier) async throws {
        try await apiClient.unmarkSet(identifier)
        async let train = apiClient.fetchTrainDay(dayKey: dayKey)
        async let body = apiClient.fetchBodyDay(dayKey: dayKey)
        (trainDay, bodyDay) = try await (train, body)
    }

    func logWeight(_ entry: WeightEntryCreate) async throws {
        _ = try await apiClient.logWeight(entry)
        weightWindow = try await apiClient.fetchWeightWindow()
    }

    func updateProfile(_ update: ProfileUpdate) async throws {
        profile = try await apiClient.updateProfile(update)
    }

    /// Deletes the account. When the server rejects the attempt with
    /// `.unauthorized` (a stale `auth_time` — ASVS 7.5.1) AND the caller
    /// supplied re-authentication credentials, this re-authenticates once
    /// and retries the delete exactly once more — the concrete "fresh-reauth
    /// reprompt flow" plan §Frontend names for `AuthService`, orchestrated
    /// here since `AppStore` is the layer that already holds both
    /// collaborators. A `nil` `reauthentication` on a 401 rethrows instead
    /// of guessing — the caller (a Settings screen, T13+) is what prompts
    /// the user for their password and calls back in with it.
    func deleteAccount(
        authService: AuthServiceProtocol,
        reauthenticatingWith reauthentication: (email: String, password: String)? = nil
    ) async throws {
        do {
            try await apiClient.deleteAccount()
        } catch AppError.unauthorized {
            guard let reauthentication else { throw AppError.unauthorized(message: "Re-authentication required") }
            try await authService.reauthenticate(email: reauthentication.email, password: reauthentication.password)
            try await apiClient.deleteAccount()
        }
    }

    private static func asAppError(_ error: Error) -> AppError {
        (error as? AppError) ?? .network(message: error.localizedDescription)
    }
}
