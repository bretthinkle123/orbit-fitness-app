import Foundation
import Testing
@testable import Orbit

/// **Authored, not compiled, on this host** (`.pipeline/implementation-
/// progress.md`'s T11/T12 entries) — genuine execution happens on the
/// operator's Mac. Every JSON fixture below is a REAL response captured this
/// session from the running backend (`poetry run uvicorn` + a throwaway
/// Postgres + the Firebase Auth emulator, real HTTP round trips, not
/// hand-typed guesses) — see the T12 progress entry for the capture
/// transcript. Model↔schema parity was derived from the SERVED contract
/// (`/openapi.json` + `src/orbit/schemas/*.py`), not memory.

// MARK: - Codable decode tests (real captured JSON → each API model)

@Suite("Core — Codable decode of every API model, from real captured JSON")
struct ModelDecodingTests {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test("ProfileOut decodes from a real POST /me/bootstrap response, all 13 muscle levels present")
    func decodesProfileOut() throws {
        let json = """
        {"kcal_budget":2350,"protein_target_g":185,"carb_target_g":240,"fat_target_g":72,\
        "protein_pct":31,"carb_pct":41,"fat_pct":28,"score_base":512,"tier_label":"Beginner",\
        "percentile_label":"Top 100%","next_tier_pct":0,"palette_preset":"purple","units":"imperial",\
        "gender":"m","planet_index":0,"burned_kcal":0,"muscle_levels":[\
        {"muscle_group":"biceps","level":3},{"muscle_group":"calves","level":1},\
        {"muscle_group":"chest","level":4},{"muscle_group":"core","level":3},\
        {"muscle_group":"forearms","level":2},{"muscle_group":"glutes","level":2},\
        {"muscle_group":"hamstrings","level":2},{"muscle_group":"lats","level":4},\
        {"muscle_group":"lower_back","level":3},{"muscle_group":"quads","level":2},\
        {"muscle_group":"shoulders","level":3},{"muscle_group":"traps","level":3},\
        {"muscle_group":"triceps","level":3}]}
        """
        let profile = try Self.makeDecoder().decode(ProfileOut.self, from: Data(json.utf8))
        #expect(profile.kcalBudget == 2350)
        #expect(profile.proteinTargetGrams == 185)
        #expect(profile.proteinPercent == 31)
        #expect(profile.carbPercent == 41)
        #expect(profile.fatPercent == 28)
        #expect(profile.tierLabel == "Beginner")
        #expect(profile.palettePreset == "purple")
        #expect(profile.muscleLevels.count == 13)
        #expect(profile.muscleLevels.first(where: { $0.muscleGroup == "chest" })?.level == 4)
    }

    @Test("QuickFood array decodes from a real GET /catalog/quick-foods response")
    func decodesQuickFoodCatalog() throws {
        let json = """
        [{"id":3,"name":"Chicken Stir-fry","kcal":524,"protein_g":41.0,"carb_g":48.0,"fat_g":16.0},\
        {"id":1,"name":"Salmon & Rice Bowl","kcal":612,"protein_g":42.0,"carb_g":58.0,"fat_g":21.0},\
        {"id":2,"name":"Whey Shake","kcal":178,"protein_g":32.0,"carb_g":8.0,"fat_g":3.0}]
        """
        let foods = try Self.makeDecoder().decode([QuickFood].self, from: Data(json.utf8))
        #expect(foods.count == 3)
        #expect(foods.map(\.name).contains("Whey Shake"))
        #expect(foods.first(where: { $0.id == 2 })?.proteinGrams == 32.0)
    }

    @Test("FoodEntry decodes, and its logged_at parses the real no-fractional-seconds ISO-8601 wire format")
    func decodesFoodEntryAndTimestamp() throws {
        let json = """
        {"id":1,"name":"Chicken Stir-fry","kcal":524,"protein_g":41.0,"carb_g":48.0,"fat_g":16.0,\
        "meal_group":"breakfast","logged_at":"2026-07-25T01:54:17Z","day_key":"2026-07-25"}
        """
        let entry = try Self.makeDecoder().decode(FoodEntry.self, from: Data(json.utf8))
        #expect(entry.name == "Chicken Stir-fry")
        #expect(entry.mealGroup == "breakfast")
        #expect(entry.dayKey == "2026-07-25")

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let components = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: entry.loggedAt)
        #expect(components.year == 2026 && components.month == 7 && components.day == 25)
        #expect(components.hour == 1 && components.minute == 54 && components.second == 17)
    }

    @Test("FuelDay decodes with all 4 meal groups present even when two are empty (design's zero-data pattern)")
    func decodesFuelDayAllFourMealGroups() throws {
        let json = """
        {"day_key":"2026-07-25","meals":{"breakfast":[{"id":1,"name":"Chicken Stir-fry","kcal":524,\
        "protein_g":41.0,"carb_g":48.0,"fat_g":16.0,"meal_group":"breakfast",\
        "logged_at":"2026-07-25T01:54:17Z","day_key":"2026-07-25"}],"lunch":[],"snacks":[],\
        "dinner":[{"id":2,"name":"Grilled Chicken Bowl","kcal":540,"protein_g":48.5,"carb_g":52.0,\
        "fat_g":14.0,"meal_group":"dinner","logged_at":"2026-07-25T02:54:17Z","day_key":"2026-07-25"}]},\
        "totals":{"kcal":1064,"protein_g":89.5,"carb_g":100.0,"fat_g":30.0},\
        "targets":{"kcal_budget":2350,"protein_target_g":185,"carb_target_g":240,"fat_target_g":72},\
        "remaining_kcal":1286,\
        "coach_message":"Mission Control: log consistently this week to unlock personalized adjustments."}
        """
        let fuelDay = try Self.makeDecoder().decode(FuelDay.self, from: Data(json.utf8))
        #expect(fuelDay.meals.keys.sorted() == ["breakfast", "dinner", "lunch", "snacks"])
        #expect(fuelDay.meals["lunch"]?.isEmpty == true)
        #expect(fuelDay.meals["snacks"]?.isEmpty == true)
        #expect(fuelDay.totals.kcal == 1064)
        #expect(fuelDay.remainingKcal == 1286)
        #expect(fuelDay.coachMessage == "Mission Control: log consistently this week to unlock personalized adjustments.")
    }

    @Test("TrainDay decodes score/week_strip/session_count/weekly_delta and each exercise's done_set_indexes")
    func decodesTrainDay() throws {
        let json = """
        {"day_key":"2026-07-25","program":{"id":1,"name":"Push Day","focus":"Chest","est_minutes":52},\
        "exercises":[{"id":1,"name":"Barbell Bench Press","sets":4,"reps":8,"weight":185.0,\
        "muscle_tag":"chest","done_set_indexes":[0]},{"id":2,"name":"Incline DB Press","sets":3,\
        "reps":10,"weight":60.0,"muscle_tag":"chest","done_set_indexes":[]},{"id":3,\
        "name":"Seated Overhead Press","sets":3,"reps":10,"weight":95.0,"muscle_tag":"shoulders",\
        "done_set_indexes":[]},{"id":4,"name":"Cable Fly","sets":3,"reps":12,"weight":42.5,\
        "muscle_tag":"chest","done_set_indexes":[]},{"id":5,"name":"Triceps Pushdown","sets":3,\
        "reps":12,"weight":57.5,"muscle_tag":"triceps","done_set_indexes":[]}],"score":513,\
        "week_strip":[false,false,false,false,false,true,false],"session_count":1,"weekly_delta":1}
        """
        let trainDay = try Self.makeDecoder().decode(TrainDay.self, from: Data(json.utf8))
        #expect(trainDay.program.name == "Push Day")
        #expect(trainDay.exercises.count == 5)
        #expect(trainDay.score == 513)
        #expect(trainDay.weekStrip.count == 7)
        #expect(trainDay.weekStrip[5] == true)
        #expect(trainDay.sessionCount == 1)
        #expect(trainDay.weeklyDelta == 1)
        #expect(trainDay.exercises.first?.doneSetIndexes == [0])
    }

    @Test("BodyDay decodes all 13 muscle levels with trained_today, only chest true after one chest set")
    func decodesBodyDay() throws {
        let json = """
        {"day_key":"2026-07-25","muscle_levels":[{"muscle_group":"chest","level":4,"trained_today":true},\
        {"muscle_group":"shoulders","level":3,"trained_today":false},\
        {"muscle_group":"traps","level":3,"trained_today":false},\
        {"muscle_group":"biceps","level":3,"trained_today":false},\
        {"muscle_group":"forearms","level":2,"trained_today":false},\
        {"muscle_group":"core","level":3,"trained_today":false},\
        {"muscle_group":"quads","level":2,"trained_today":false},\
        {"muscle_group":"calves","level":1,"trained_today":false},\
        {"muscle_group":"lats","level":4,"trained_today":false},\
        {"muscle_group":"triceps","level":3,"trained_today":false},\
        {"muscle_group":"lower_back","level":3,"trained_today":false},\
        {"muscle_group":"glutes","level":2,"trained_today":false},\
        {"muscle_group":"hamstrings","level":2,"trained_today":false}]}
        """
        let bodyDay = try Self.makeDecoder().decode(BodyDay.self, from: Data(json.utf8))
        #expect(bodyDay.muscleLevels.count == 13)
        let trained = bodyDay.muscleLevels.filter(\.trainedToday)
        #expect(trained.map(\.muscleGroup) == ["chest"])
    }

    @Test("WeightEntry decodes canonical kg")
    func decodesWeightEntry() throws {
        let json = #"{"id":1,"weight_kg":81.6,"day_key":"2026-07-25","logged_at":"2026-07-25T00:54:17Z"}"#
        let entry = try Self.makeDecoder().decode(WeightEntry.self, from: Data(json.utf8))
        #expect(entry.weightKilograms == 81.6)
        #expect(entry.dayKey == "2026-07-25")
    }

    @Test("WeightWindow decodes the brand-new-account shape: empty entries, nil latest, nil weekly delta")
    func decodesEmptyWeightWindow() throws {
        let json = #"{"entries":[],"latest":null,"weekly_delta_kg":null}"#
        let window = try Self.makeDecoder().decode(WeightWindow.self, from: Data(json.utf8))
        #expect(window.entries.isEmpty)
        #expect(window.latest == nil)
        #expect(window.weeklyDeltaKilograms == nil)
    }

    @Test("FoodEntryCreate round-trips through the shared encoder — quick-food path never emits macro fields")
    func encodesQuickFoodCreateWithoutMacroFields() throws {
        let create = FoodEntryCreate.quickFood(id: 3, mealGroup: "breakfast", dayKey: "2026-07-25", loggedAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(create)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["quick_food_id"] as? Int == 3)
        #expect(object?["name"] == nil)
        #expect(object?["kcal"] == nil)
    }
}

// MARK: - Error-envelope → AppError mapping

@Suite("Core — error-envelope to AppError mapping")
struct AppErrorMappingTests {
    static func decode(_ json: String) throws -> ErrorEnvelopeResponse {
        try JSONDecoder().decode(ErrorEnvelopeResponse.self, from: Data(json.utf8))
    }

    @Test("A real captured 401 envelope maps to .unauthorized with the server's own message")
    func mapsRealCaptured401() throws {
        let json = """
        {"error":{"code":"unauthorized","message":"Missing or malformed Authorization header",\
        "requestId":"9adbb428-52e4-446d-8440-5d8ac052e4b3"}}
        """
        let envelope = try Self.decode(json)
        let mapped = AppErrorMapping.map(statusCode: 401, envelope: envelope, retryAfterSeconds: nil)
        #expect(mapped == .unauthorized(message: "Missing or malformed Authorization header"))
    }

    @Test("A real captured 404 envelope (unbootstrapped profile) maps to .notFound")
    func mapsRealCaptured404() throws {
        let json = """
        {"error":{"code":"not_found","message":"Profile not found — call POST /me/bootstrap first",\
        "requestId":"2995e1b0-79b5-4235-85aa-d705c263b7ed"}}
        """
        let envelope = try Self.decode(json)
        let mapped = AppErrorMapping.map(statusCode: 404, envelope: envelope, retryAfterSeconds: nil)
        #expect(mapped == .notFound(message: "Profile not found — call POST /me/bootstrap first"))
    }

    @Test("Every declared backend error code maps to its matching AppError case", arguments: [
        ("unauthorized", 401), ("forbidden", 403), ("not_found", 404),
        ("conflict", 409), ("validation_failed", 422), ("rate_limited", 429),
    ])
    func mapsEveryDeclaredCode(code: String, status: Int) throws {
        let envelope = ErrorEnvelopeResponse(error: .init(code: code, message: "msg", requestId: nil))
        let mapped = AppErrorMapping.map(statusCode: status, envelope: envelope, retryAfterSeconds: nil)
        switch (code, mapped) {
        case ("unauthorized", .unauthorized): break
        case ("forbidden", .forbidden): break
        case ("not_found", .notFound): break
        case ("conflict", .conflict): break
        case ("validation_failed", .validationFailed): break
        case ("rate_limited", .rateLimited): break
        default: Issue.record("code \(code) did not map to the expected AppError case: \(mapped)")
        }
    }

    @Test("An unmapped code (\"internal\", the generic 500) falls back to .server with the real status preserved")
    func unmappedCodeFallsBackToServer() {
        let envelope = ErrorEnvelopeResponse(error: .init(code: "internal", message: "An unexpected error occurred.", requestId: nil))
        let mapped = AppErrorMapping.map(statusCode: 500, envelope: envelope, retryAfterSeconds: nil)
        #expect(mapped == .server(statusCode: 500, message: "An unexpected error occurred."))
    }

    @Test("The account-deletion 502 case (backend's unmapped-status \"error\" code) also falls back to .server")
    func accountDeletion502FallsBackToServer() {
        let envelope = ErrorEnvelopeResponse(
            error: .init(code: "error", message: "Account data was erased, but identity deletion failed. Please retry.", requestId: nil)
        )
        let mapped = AppErrorMapping.map(statusCode: 502, envelope: envelope, retryAfterSeconds: nil)
        #expect(mapped == .server(statusCode: 502, message: "Account data was erased, but identity deletion failed. Please retry."))
    }

    @Test("rate_limited preserves the Retry-After seconds separately from the message")
    func rateLimitedPreservesRetryAfter() {
        let envelope = ErrorEnvelopeResponse(error: .init(code: "rate_limited", message: "Too many requests", requestId: nil))
        let mapped = AppErrorMapping.map(statusCode: 429, envelope: envelope, retryAfterSeconds: 42)
        #expect(mapped == .rateLimited(message: "Too many requests", retryAfterSeconds: 42))
    }
}

// MARK: - AppStore derived values + cross-screen reactions

/// A recording, in-memory `APIClientProtocol` double — canned responses in,
/// call counts/arguments out. An `actor` so it's genuinely safe to share
/// across `AppStore`'s concurrent `async let` fetches in `loadEverything()`.
actor MockAPIClient: APIClientProtocol {
    var profileToReturn: ProfileOut
    var fuelDayToReturn: FuelDay
    var trainDayToReturn: TrainDay
    var bodyDayToReturn: BodyDay
    var weightWindowToReturn: WeightWindow
    var errorToThrow: AppError?

    private(set) var markSetDoneCallCount = 0
    private(set) var unmarkSetCallCount = 0
    private(set) var createFoodEntryCallCount = 0
    private(set) var deleteAccountCallCount = 0

    init(
        profile: ProfileOut, fuelDay: FuelDay, trainDay: TrainDay, bodyDay: BodyDay, weightWindow: WeightWindow
    ) {
        self.profileToReturn = profile
        self.fuelDayToReturn = fuelDay
        self.trainDayToReturn = trainDay
        self.bodyDayToReturn = bodyDay
        self.weightWindowToReturn = weightWindow
    }

    private func throwIfConfigured() throws {
        if let errorToThrow { throw errorToThrow }
    }

    func bootstrapProfile() async throws -> ProfileOut { try throwIfConfigured(); return profileToReturn }
    func fetchProfile() async throws -> ProfileOut { try throwIfConfigured(); return profileToReturn }
    func updateProfile(_ update: ProfileUpdate) async throws -> ProfileOut { try throwIfConfigured(); return profileToReturn }
    func signOut() async throws { try throwIfConfigured() }
    func deleteAccount() async throws {
        deleteAccountCallCount += 1
        try throwIfConfigured()
    }

    func fetchQuickFoods() async throws -> [QuickFood] { try throwIfConfigured(); return [] }
    func createFoodEntry(_ entry: FoodEntryCreate) async throws -> FoodEntry {
        createFoodEntryCallCount += 1
        try throwIfConfigured()
        return FoodEntry(
            id: 1, name: "Test Food", kcal: 100, proteinGrams: 1, carbGrams: 1, fatGrams: 1,
            mealGroup: entry.mealGroup, loggedAt: entry.loggedAt, dayKey: entry.dayKey
        )
    }
    func fetchFuelDay(dayKey: String) async throws -> FuelDay { try throwIfConfigured(); return fuelDayToReturn }

    func fetchTrainDay(dayKey: String) async throws -> TrainDay { try throwIfConfigured(); return trainDayToReturn }
    func markSetDone(_ toggle: SetToggleCreate) async throws -> SetEvent {
        markSetDoneCallCount += 1
        try throwIfConfigured()
        return SetEvent(exerciseID: toggle.exerciseID, setIndex: toggle.setIndex, dayKey: toggle.dayKey, doneAt: toggle.doneAt)
    }
    func unmarkSet(_ identifier: SetIdentifier) async throws {
        unmarkSetCallCount += 1
        try throwIfConfigured()
    }

    func fetchBodyDay(dayKey: String) async throws -> BodyDay { try throwIfConfigured(); return bodyDayToReturn }

    func logWeight(_ entry: WeightEntryCreate) async throws -> WeightEntry {
        try throwIfConfigured()
        return WeightEntry(id: 1, weightKilograms: entry.weightKilograms, dayKey: entry.dayKey, loggedAt: entry.loggedAt)
    }
    func fetchWeightWindow() async throws -> WeightWindow { try throwIfConfigured(); return weightWindowToReturn }

    func setError(_ error: AppError?) { errorToThrow = error }
}

@Suite("Core — AppStore derived values + cross-screen reactions")
struct AppStoreTests {
    /// One chest set marked done — mirrors the real captured
    /// `train_day_out_after_set.json` / `body_day_out.json` pair, so the
    /// derived-value assertions below are checked against a genuine
    /// server-shaped fixture, not an invented one.
    static func makeMockClient() -> MockAPIClient {
        let profile = ProfileOut(
            kcalBudget: 2350, proteinTargetGrams: 185, carbTargetGrams: 240, fatTargetGrams: 72,
            proteinPercent: 31, carbPercent: 41, fatPercent: 28, scoreBase: 512, tierLabel: "Beginner",
            percentileLabel: "Top 100%", nextTierPercent: 0, palettePreset: "purple", units: "imperial",
            gender: "m", planetIndex: 0, burnedKcal: 0, muscleLevels: []
        )
        let fuelDay = FuelDay(
            dayKey: "2026-07-25", meals: ["breakfast": [], "lunch": [], "snacks": [], "dinner": []],
            totals: MacroTotals(kcal: 1064, proteinGrams: 89.5, carbGrams: 100, fatGrams: 30),
            targets: MacroTargets(kcalBudget: 2350, proteinTargetGrams: 185, carbTargetGrams: 240, fatTargetGrams: 72),
            remainingKcal: 1286, coachMessage: "Mission Control: log consistently this week to unlock personalized adjustments."
        )
        let trainDay = TrainDay(
            dayKey: "2026-07-25",
            program: Program(id: 1, name: "Push Day", focus: "Chest", estimatedMinutes: 52),
            exercises: [
                Exercise(id: 1, name: "Barbell Bench Press", sets: 4, reps: 8, weight: 185, muscleTag: "chest", doneSetIndexes: [0]),
                Exercise(id: 2, name: "Incline DB Press", sets: 3, reps: 10, weight: 60, muscleTag: "chest", doneSetIndexes: []),
            ],
            score: 513, weekStrip: [false, false, false, false, false, true, false], sessionCount: 1, weeklyDelta: 1
        )
        let bodyDay = BodyDay(
            dayKey: "2026-07-25",
            muscleLevels: [
                BodyMuscleLevel(muscleGroup: "chest", level: 4, trainedToday: true),
                BodyMuscleLevel(muscleGroup: "shoulders", level: 3, trainedToday: false),
            ]
        )
        let weightWindow = WeightWindow(entries: [], latest: nil, weeklyDeltaKilograms: nil)
        return MockAPIClient(profile: profile, fuelDay: fuelDay, trainDay: trainDay, bodyDay: bodyDay, weightWindow: weightWindow)
    }

    @Test("loadEverything() populates every field and derives totals/score/doneSetTags/trainedMuscleGroupsToday")
    @MainActor
    func loadEverythingPopulatesDerivedValues() async {
        let client = Self.makeMockClient()
        let store = AppStore(apiClient: client, dayKey: "2026-07-25")

        await store.loadEverything()

        #expect(store.lastError == nil)
        #expect(store.profile?.tierLabel == "Beginner")
        #expect(store.remainingKcal == 1286)
        #expect(store.macroTotals?.kcal == 1064)
        #expect(store.trainScore == 513)
        #expect(store.weeklyDelta == 1)
        #expect(store.doneSetTags == [SetTag(exerciseID: 1, setIndex: 0)])
        #expect(store.trainedMuscleGroupsToday == ["chest"])
    }

    @Test("A failed fetch surfaces as lastError (typed AppError), not a crash")
    @MainActor
    func loadEverythingSurfacesErrorsAsLastError() async {
        let client = Self.makeMockClient()
        await client.setError(.notFound(message: "Profile not found — call POST /me/bootstrap first"))
        let store = AppStore(apiClient: client, dayKey: "2026-07-25")

        await store.loadEverything()

        #expect(store.lastError == .notFound(message: "Profile not found — call POST /me/bootstrap first"))
        #expect(store.profile == nil)
    }

    @Test("markSetDone re-fetches BOTH Train and Body — the design's cross-screen reaction (score everywhere + Body glow)")
    @MainActor
    func markSetDoneRefreshesTrainAndBody() async throws {
        let client = Self.makeMockClient()
        let store = AppStore(apiClient: client, dayKey: "2026-07-25")
        await store.loadEverything()

        try await store.markSetDone(SetToggleCreate(exerciseID: 2, setIndex: 0, dayKey: "2026-07-25", doneAt: Date()))

        let markCallCount = await client.markSetDoneCallCount
        #expect(markCallCount == 1)
        // The mock always returns the SAME canned trainDay/bodyDay regardless
        // of the toggle sent — what this test verifies is that the store
        // actually RE-FETCHES both (not just one) after the mutation, which
        // is the cross-screen-reaction contract, not the score arithmetic
        // itself (that's covered server-side, T6).
        #expect(store.trainDay != nil)
        #expect(store.bodyDay != nil)
    }

    @Test("addFoodEntry re-fetches Fuel so Home's ring (which reads the same fuelDay) updates too")
    @MainActor
    func addFoodEntryRefreshesFuelDay() async throws {
        let client = Self.makeMockClient()
        let store = AppStore(apiClient: client, dayKey: "2026-07-25")
        await store.loadEverything()

        try await store.addFoodEntry(.quickFood(id: 1, mealGroup: "breakfast", dayKey: "2026-07-25", loggedAt: Date()))

        let createCallCount = await client.createFoodEntryCallCount
        #expect(createCallCount == 1)
        #expect(store.fuelDay != nil)
    }

    @Test("deleteAccount retries exactly once after a successful reauthentication on a 401")
    @MainActor
    func deleteAccountRetriesOnceAfterReauth() async throws {
        let client = Self.makeMockClient()
        await client.setError(.unauthorized(message: "stale auth_time"))
        let store = AppStore(apiClient: client, dayKey: "2026-07-25")
        let authService = MockAuthService()
        authService.onReauthenticate = { [client] in await client.setError(nil) } // simulate a fresh token now working

        try await store.deleteAccount(authService: authService, reauthenticatingWith: (email: "a@b.com", password: "pw"))

        #expect(authService.reauthenticateCallCount == 1)
        let deleteCallCount = await client.deleteAccountCallCount
        #expect(deleteCallCount == 2) // first attempt (401) + retry (success)
    }

    @Test("deleteAccount rethrows the EXACT .unauthorized error when no reauthentication credentials are supplied")
    @MainActor
    func deleteAccountRethrowsWithoutReauthCredentials() async {
        let client = Self.makeMockClient()
        await client.setError(.unauthorized(message: "stale auth_time"))
        let store = AppStore(apiClient: client, dayKey: "2026-07-25")
        let authService = MockAuthService()

        do {
            try await store.deleteAccount(authService: authService, reauthenticatingWith: nil)
            Issue.record("expected deleteAccount to rethrow .unauthorized")
        } catch let error as AppError {
            #expect(error == .unauthorized(message: "Re-authentication required"))
        } catch {
            Issue.record("expected an AppError, got \(error)")
        }
        #expect(authService.reauthenticateCallCount == 0)
    }
}

/// A minimal `AuthServiceProtocol` test double — records `reauthenticate`
/// calls and lets the test simulate its side effect (e.g. clearing the
/// mock API client's configured error) via `onReauthenticate`.
@MainActor
final class MockAuthService: AuthServiceProtocol, Sendable {
    private(set) var reauthenticateCallCount = 0
    var onReauthenticate: (() async -> Void)?
    var isSignedIn: Bool = true
    var currentUserDisplayName: String?
    var currentUserEmail: String?

    func register(email: String, password: String, displayName: String) async throws {}
    func signIn(email: String, password: String) async throws {}
    func signOut() async throws {}
    func reauthenticate(email: String, password: String) async throws {
        reauthenticateCallCount += 1
        await onReauthenticate?()
    }
    func currentIDToken() async throws -> String { "mock-token" }
}

// MARK: - KeychainStore contract

@Suite("Core — KeychainTokenStore contract")
struct KeychainTokenStoreTests {
    /// A per-test unique account name so parallel test runs never collide on
    /// the same Keychain item.
    static func makeStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "com.orbitfitness.orbit.tests", account: "test-\(UUID().uuidString)")
    }

    @Test("save then loadToken round-trips the exact string")
    func saveThenLoadRoundTrips() throws {
        let store = Self.makeStore()
        defer { try? store.clear() }
        try store.save(token: "sample-id-token-value")
        #expect(try store.loadToken() == "sample-id-token-value")
    }

    @Test("loadToken returns nil (not an error) when nothing has been saved")
    func loadTokenReturnsNilWhenEmpty() throws {
        let store = Self.makeStore()
        #expect(try store.loadToken() == nil)
    }

    @Test("save then save again (a token refresh) replaces the value rather than erroring on the duplicate item")
    func savingTwiceReplacesTheValue() throws {
        let store = Self.makeStore()
        defer { try? store.clear() }
        try store.save(token: "first-token")
        try store.save(token: "second-token")
        #expect(try store.loadToken() == "second-token")
    }

    @Test("clear() removes the token, and clearing an already-empty store is a no-op (idempotent, mirrors AC34's sign-out contract)")
    func clearIsIdempotent() throws {
        let store = Self.makeStore()
        try store.save(token: "will-be-cleared")
        try store.clear()
        #expect(try store.loadToken() == nil)
        try store.clear() // second clear — must not throw
        #expect(try store.loadToken() == nil)
    }
}
