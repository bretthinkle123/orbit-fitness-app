import Foundation

/// `Codable` request/response models for every endpoint `APIClient` calls.
/// Field names/optionality/wire formats are derived from the SERVED contract,
/// not memory: `src/orbit/schemas/*.py` was read directly, and the running
/// backend's `/openapi.json` plus real captured JSON from each live endpoint
/// (via the Firebase Auth emulator + a throwaway Postgres, this session) were
/// used to confirm exact wire shapes — in particular that `logged_at`/
/// `done_at` serialize as `"yyyy-MM-dd'T'HH:mm:ss'Z'"` (no fractional
/// seconds) and `day_key`/`weight_kg` etc. match the schema exactly. See
/// `.pipeline/implementation-progress.md`'s T12 entry for the capture
/// transcript. `day_key` stays a validated `String` (a calendar date has no
/// single unambiguous `Date` representation without also fixing a timezone);
/// every timestamp (`logged_at`/`done_at`) is a genuine `Date`, decoded/
/// encoded via `APIClient`'s shared ISO-8601 `JSONDecoder`/`JSONEncoder`.

// MARK: - Profile (`GET /profile`, `POST /me/bootstrap`, `PATCH /profile`)

/// One muscle group's base level as `GET /profile`/`POST /me/bootstrap`
/// report it — distinct from `BodyMuscleLevel` (which also carries
/// `trained_today`) because the backend serves two distinct schema classes
/// for these two endpoints, not one shared shape with an optional field.
struct ProfileMuscleLevel: Codable, Equatable, Sendable {
    let muscleGroup: String
    let level: Int

    enum CodingKeys: String, CodingKey {
        case muscleGroup = "muscle_group"
        case level
    }
}

struct ProfileOut: Codable, Equatable, Sendable {
    let kcalBudget: Int
    let proteinTargetGrams: Int
    let carbTargetGrams: Int
    let fatTargetGrams: Int
    let proteinPercent: Int
    let carbPercent: Int
    let fatPercent: Int
    let scoreBase: Int
    let tierLabel: String
    let percentileLabel: String
    let nextTierPercent: Int
    let palettePreset: String
    let units: String
    let gender: String
    let planetIndex: Int
    let burnedKcal: Int
    let muscleLevels: [ProfileMuscleLevel]

    enum CodingKeys: String, CodingKey {
        case kcalBudget = "kcal_budget"
        case proteinTargetGrams = "protein_target_g"
        case carbTargetGrams = "carb_target_g"
        case fatTargetGrams = "fat_target_g"
        case proteinPercent = "protein_pct"
        case carbPercent = "carb_pct"
        case fatPercent = "fat_pct"
        case scoreBase = "score_base"
        case tierLabel = "tier_label"
        case percentileLabel = "percentile_label"
        case nextTierPercent = "next_tier_pct"
        case palettePreset = "palette_preset"
        case units
        case gender
        case planetIndex = "planet_index"
        case burnedKcal = "burned_kcal"
        case muscleLevels = "muscle_levels"
    }
}

/// `PATCH /profile` request — mirrors `schemas.profile.ProfileUpdate`'s
/// writable-field allowlist exactly (every field optional, partial update);
/// there is deliberately no `Encodable` field this client can set beyond
/// what the server itself accepts (ASVS 15.3.3 mass-assignment defense holds
/// even though the enforcement lives server-side — the client has no way to
/// even CONSTRUCT a request naming an extra field).
struct ProfileUpdate: Encodable, Equatable, Sendable {
    var palettePreset: String?
    var units: String?
    var gender: String?
    var planetIndex: Int?
    var kcalBudget: Int?
    var proteinTargetGrams: Int?
    var carbTargetGrams: Int?
    var fatTargetGrams: Int?

    enum CodingKeys: String, CodingKey {
        case palettePreset = "palette_preset"
        case units
        case gender
        case planetIndex = "planet_index"
        case kcalBudget = "kcal_budget"
        case proteinTargetGrams = "protein_target_g"
        case carbTargetGrams = "carb_target_g"
        case fatTargetGrams = "fat_target_g"
    }
}

// MARK: - Fuel (`/catalog/quick-foods`, `/fuel/entries`, `/fuel`)

struct QuickFood: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let kcal: Int
    let proteinGrams: Double
    let carbGrams: Double
    let fatGrams: Double

    enum CodingKeys: String, CodingKey {
        case id, name, kcal
        case proteinGrams = "protein_g"
        case carbGrams = "carb_g"
        case fatGrams = "fat_g"
    }
}

/// `POST /fuel/entries` request — mirrors `schemas.fuel.FoodEntryCreate`'s
/// quick-food-XOR-explicit-macros contract. The server enforces the XOR at
/// its schema boundary; this initializer enforces the SAME choice at
/// construction time so a caller can never even build an invalid request
/// (Liskov-safe narrowing: two named constructors, no raw memberwise init).
struct FoodEntryCreate: Encodable, Equatable, Sendable {
    let mealGroup: String
    let dayKey: String
    let loggedAt: Date
    let quickFoodID: Int?
    let name: String?
    let kcal: Int?
    let proteinGrams: Double?
    let carbGrams: Double?
    let fatGrams: Double?

    private init(
        mealGroup: String, dayKey: String, loggedAt: Date, quickFoodID: Int?,
        name: String?, kcal: Int?, proteinGrams: Double?, carbGrams: Double?, fatGrams: Double?
    ) {
        self.mealGroup = mealGroup
        self.dayKey = dayKey
        self.loggedAt = loggedAt
        self.quickFoodID = quickFoodID
        self.name = name
        self.kcal = kcal
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
        self.fatGrams = fatGrams
    }

    static func quickFood(id: Int, mealGroup: String, dayKey: String, loggedAt: Date) -> FoodEntryCreate {
        FoodEntryCreate(
            mealGroup: mealGroup, dayKey: dayKey, loggedAt: loggedAt, quickFoodID: id,
            name: nil, kcal: nil, proteinGrams: nil, carbGrams: nil, fatGrams: nil
        )
    }

    static func explicitMacros(
        name: String, kcal: Int, proteinGrams: Double, carbGrams: Double, fatGrams: Double,
        mealGroup: String, dayKey: String, loggedAt: Date
    ) -> FoodEntryCreate {
        FoodEntryCreate(
            mealGroup: mealGroup, dayKey: dayKey, loggedAt: loggedAt, quickFoodID: nil,
            name: name, kcal: kcal, proteinGrams: proteinGrams, carbGrams: carbGrams, fatGrams: fatGrams
        )
    }

    enum CodingKeys: String, CodingKey {
        case mealGroup = "meal_group"
        case dayKey = "day_key"
        case loggedAt = "logged_at"
        case quickFoodID = "quick_food_id"
        case name, kcal
        case proteinGrams = "protein_g"
        case carbGrams = "carb_g"
        case fatGrams = "fat_g"
    }
}

struct FoodEntry: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let kcal: Int
    let proteinGrams: Double
    let carbGrams: Double
    let fatGrams: Double
    let mealGroup: String
    let loggedAt: Date
    let dayKey: String

    enum CodingKeys: String, CodingKey {
        case id, name, kcal
        case proteinGrams = "protein_g"
        case carbGrams = "carb_g"
        case fatGrams = "fat_g"
        case mealGroup = "meal_group"
        case loggedAt = "logged_at"
        case dayKey = "day_key"
    }
}

struct MacroTotals: Codable, Equatable, Sendable {
    let kcal: Int
    let proteinGrams: Double
    let carbGrams: Double
    let fatGrams: Double

    enum CodingKeys: String, CodingKey {
        case kcal
        case proteinGrams = "protein_g"
        case carbGrams = "carb_g"
        case fatGrams = "fat_g"
    }
}

struct MacroTargets: Codable, Equatable, Sendable {
    let kcalBudget: Int
    let proteinTargetGrams: Int
    let carbTargetGrams: Int
    let fatTargetGrams: Int

    enum CodingKeys: String, CodingKey {
        case kcalBudget = "kcal_budget"
        case proteinTargetGrams = "protein_target_g"
        case carbTargetGrams = "carb_target_g"
        case fatTargetGrams = "fat_target_g"
    }
}

/// `GET /fuel?day_key=` response. `meals` is keyed by meal-group name with
/// ALL FOUR groups always present (even empty) — the design's "Dinner starts
/// empty" pattern, verified against a real captured response this session
/// (an account with only breakfast/dinner entries still served `lunch: []`
/// and `snacks: []`), not assumed from the schema alone.
struct FuelDay: Codable, Equatable, Sendable {
    let dayKey: String
    let meals: [String: [FoodEntry]]
    let totals: MacroTotals
    let targets: MacroTargets
    let remainingKcal: Int
    let coachMessage: String

    enum CodingKeys: String, CodingKey {
        case dayKey = "day_key"
        case meals, totals, targets
        case remainingKcal = "remaining_kcal"
        case coachMessage = "coach_message"
    }
}

// MARK: - Train (`/train`, `/train/sets`)

struct Program: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let focus: String
    let estimatedMinutes: Int

    enum CodingKeys: String, CodingKey {
        case id, name, focus
        case estimatedMinutes = "est_minutes"
    }
}

struct Exercise: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let sets: Int
    let reps: Int
    let weight: Double
    let muscleTag: String
    let doneSetIndexes: [Int]

    enum CodingKeys: String, CodingKey {
        case id, name, sets, reps, weight
        case muscleTag = "muscle_tag"
        case doneSetIndexes = "done_set_indexes"
    }
}

struct TrainDay: Codable, Equatable, Sendable {
    let dayKey: String
    let program: Program
    let exercises: [Exercise]
    let score: Int
    let weekStrip: [Bool]
    let sessionCount: Int
    let weeklyDelta: Int

    enum CodingKeys: String, CodingKey {
        case dayKey = "day_key"
        case program, exercises, score
        case weekStrip = "week_strip"
        case sessionCount = "session_count"
        case weeklyDelta = "weekly_delta"
    }
}

/// The four fields identifying one set — shared by `POST` and `DELETE
/// /train/sets` (mirrors `schemas.train.SetIdentifier`).
struct SetIdentifier: Encodable, Equatable, Sendable {
    let exerciseID: Int
    let setIndex: Int
    let dayKey: String

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case setIndex = "set_index"
        case dayKey = "day_key"
    }
}

/// `POST /train/sets` request (mirrors `schemas.train.SetToggleCreate`).
struct SetToggleCreate: Encodable, Equatable, Sendable {
    let exerciseID: Int
    let setIndex: Int
    let dayKey: String
    let doneAt: Date

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case setIndex = "set_index"
        case dayKey = "day_key"
        case doneAt = "done_at"
    }
}

struct SetEvent: Codable, Equatable, Sendable {
    let exerciseID: Int
    let setIndex: Int
    let dayKey: String
    let doneAt: Date

    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case setIndex = "set_index"
        case dayKey = "day_key"
        case doneAt = "done_at"
    }
}

// MARK: - Body (`/body`)

/// One muscle group's base level + today's trained flag — distinct from
/// `ProfileMuscleLevel` (see that type's docstring for why these aren't one
/// shared shape).
struct BodyMuscleLevel: Codable, Equatable, Sendable {
    let muscleGroup: String
    let level: Int
    let trainedToday: Bool

    enum CodingKeys: String, CodingKey {
        case muscleGroup = "muscle_group"
        case level
        case trainedToday = "trained_today"
    }
}

struct BodyDay: Codable, Equatable, Sendable {
    let dayKey: String
    let muscleLevels: [BodyMuscleLevel]

    enum CodingKeys: String, CodingKey {
        case dayKey = "day_key"
        case muscleLevels = "muscle_levels"
    }
}

// MARK: - Weight (`/weight`)

/// `POST /weight` request (mirrors `schemas.weight.WeightEntryCreate`) —
/// canonical kg; the app's units-display conversion happens at render time,
/// never here (plan §Data: "Weight stored canonical metric (kg)").
struct WeightEntryCreate: Encodable, Equatable, Sendable {
    let weightKilograms: Double
    let dayKey: String
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case weightKilograms = "weight_kg"
        case dayKey = "day_key"
        case loggedAt = "logged_at"
    }
}

struct WeightEntry: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let weightKilograms: Double
    let dayKey: String
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case weightKilograms = "weight_kg"
        case dayKey = "day_key"
        case loggedAt = "logged_at"
    }
}

/// `GET /weight` response — `latest`/`weeklyDeltaKilograms` are genuinely
/// `nil` for a brand-new account or when the 30-day window doesn't yet span
/// 7 days, never a fabricated zero (verified against a real captured
/// brand-new-account response this session: `{"entries":[],"latest":null,
/// "weekly_delta_kg":null}`).
struct WeightWindow: Codable, Equatable, Sendable {
    let entries: [WeightEntry]
    let latest: WeightEntry?
    let weeklyDeltaKilograms: Double?

    enum CodingKeys: String, CodingKey {
        case entries, latest
        case weeklyDeltaKilograms = "weekly_delta_kg"
    }
}

// MARK: - Day-key formatting (the one place a `day_key` string is built)

/// Builds the `day_key` string every day-scoped request needs — the user's
/// device-timezone local calendar date (plan §Data: "`day_key` = user's
/// device-tz local date; client sends tz" — the tz is implicit in which
/// calendar date this produces, matching `schemas.common.DayKey`'s
/// `YYYY-MM-DD` pattern exactly).
enum DayKeyFormatting {
    static func today(calendar: Calendar = .current, now: Date = Date()) -> String {
        string(from: now, calendar: calendar)
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX") // fixed, non-localized digits
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
