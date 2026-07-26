import Foundation

/// Builds stable, human-readable XCUITest `accessibilityIdentifier` suffixes
/// from server-provided display strings (quick-food names, exercise names)
/// that are seeded data, not literal Swift constants — so a per-instance
/// identifier (`"fuel-quickadd-breakfast-salmon-rice-bowl"`,
/// `"train-set-barbell-bench-press-1"`) can be built once, consistently,
/// from any screen/component that loops over server data, rather than each
/// call site inventing its own slugging rule (code-standards: one facade
/// for a cross-cutting concern, not scattered inline string munging).
///
/// This is pure, testable string logic with no view/SwiftUI dependency of
/// its own — it lives in `DesignSystem/` alongside `Metrics`/`Theme`
/// because, like those, it's a small shared fact every layer (`Components/`,
/// `Screens/`) is free to depend on.
enum AccessibilityIdentifierSlug {
    /// Lowercases, treats every non-alphanumeric run (spaces, `&`, `-`, …)
    /// as a single word boundary, then joins with `-` — e.g.
    /// `"Salmon & Rice Bowl"` → `"salmon-rice-bowl"`, `"Chicken Stir-fry"` →
    /// `"chicken-stir-fry"`, `"Barbell Bench Press"` →
    /// `"barbell-bench-press"`. Idempotent on an already-slugged string
    /// (a hyphen is itself a word boundary, so re-slugging is a no-op).
    /// Deterministic and stable across runs — no dependency on a
    /// database-assigned numeric id, which can vary between fresh seed
    /// loads.
    static func slug(_ text: String) -> String {
        let normalized = text.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined()
        return normalized
            .split(whereSeparator: { $0 == " " })
            .joined(separator: "-")
    }
}
