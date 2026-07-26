import Foundation

/// Small, pure display-formatting helpers shared by the data-backed screens
/// (Home/Fuel/Train/Body) — centralized here rather than scattered ad hoc
/// per-screen number/string formatting, so e.g. "en-US thousands separators
/// for every displayed number" (`Orbit Fitness.dc.html`'s own `fmt()` helper)
/// is applied in exactly one place. Every function here is pure and directly
/// tested (`Tests/ScreensTests.swift`).
enum NumberDisplay {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// e.g. 2350 -> "2,350" — matches the design's own `fmt(n)` convention.
    static func formatted(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Converts a canonical kilogram weight (plan §Data: "Weight stored
/// canonical metric (kg)") to/from the profile's own display unit, rounded
/// to 0.1 (CLAUDE.md: "display converts per units setting (round 0.1)").
enum WeightUnitFormatting {
    private static let kilogramsPerPound = 0.45359237

    static func displayValue(kilograms: Double, units: String) -> Double {
        let raw = units == "imperial" ? kilograms / kilogramsPerPound : kilograms
        return (raw * 10).rounded() / 10
    }

    static func kilograms(fromDisplayValue value: Double, units: String) -> Double {
        units == "imperial" ? value * kilogramsPerPound : value
    }

    static func unitLabel(units: String) -> String {
        units == "imperial" ? "lb" : "kg"
    }

    static func formatted(kilograms: Double, units: String) -> String {
        String(format: "%.1f %@", displayValue(kilograms: kilograms, units: units), unitLabel(units: units))
    }
}

/// Splits the server's single static coach string
/// (`schemas.fuel.STATIC_COACH_MESSAGE`, e.g. "Mission Control: log
/// consistently...") into `CoachBanner`'s separate bold lead-in + message —
/// falls back to an empty lead-in (never crashes) if the server copy ever
/// loses its colon.
enum CoachMessageFormatting {
    static func splitLeadIn(_ raw: String) -> (leadIn: String, message: String) {
        guard let colonIndex = raw.firstIndex(of: ":") else { return ("", raw) }
        let leadIn = String(raw[raw.startIndex...colonIndex])
        let message = raw[raw.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
        return (leadIn, message)
    }
}

/// Derives a 1-2 letter avatar monogram from the Firebase user's own
/// display name (client-side-only, `AuthService.register`), falling back to
/// the email's local-part, then a generic glyph — the backend stores
/// neither field (CLAUDE.md: "no local PII beyond the UID"), so this is a
/// purely client-side presentational derivation, never a server round trip.
enum AvatarInitials {
    static func initials(displayName: String?, email: String?) -> String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
            if !letters.isEmpty { return String(letters).uppercased() }
        }
        if let email, let localPart = email.split(separator: "@").first, !localPart.isEmpty {
            return String(localPart.prefix(2)).uppercased()
        }
        return "?"
    }
}

/// Home's planet-picker ring-count caption (design-spec §5: "ring count =
/// index (0 rings 'Ember' ... 5 'Zenith'); caption uses singular '1 ring' at
/// index 1"). The 3D ring visualization itself is `Space/` (T17-18, LAST),
/// but this caption is real, data-driven UI text independent of whether the
/// hero has landed yet.
enum PlanetRingCaption {
    static func caption(forIndex index: Int) -> String {
        index == 1 ? "1 ring" : "\(index) rings"
    }
}

/// Formats one exercise's sets/reps/weight into the design's "4 x 8 . 185
/// lb" shape. **Judgment call**: `exercises.weight` (`src/orbit/models.py`)
/// has no declared canonical unit in plan.md (unlike `weight_entries.
/// weight_kg`, which is explicitly canonical-kg) — the 5 seeded Push Day
/// values are the design's own lb figures verbatim (`migrations/versions/
/// 0002_seed_catalog_program_levels.py`), so this always labels "lb" rather
/// than converting per the profile's units setting, which would silently
/// invent a conversion the backend never declared.
enum ExerciseSchemeFormatting {
    static func formatted(sets: Int, reps: Int, weight: Double) -> String {
        let weightText = weight == weight.rounded() ? String(Int(weight)) : String(weight)
        return "\(sets) \u{00d7} \(reps) \u{00b7} \(weightText) lb"
    }
}

/// A time-of-day greeting for Home's greeting block — pure so it's testable
/// without a device clock dependency in the test itself.
enum GreetingText {
    static func timeOfDayGreeting(hour: Int) -> String {
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}
