import SwiftUI

/// Centralizes the "may an ambient/repeating animation run right now"
/// decision (design README's Accessibility acceptance criterion: "Reduce
/// Motion: freeze starfield drift, ships, float loops, and scroll-driven 3D
/// — idle spin may stay"). Every CURRENT gated effect (`Figures/
/// MuscleFigure.swift`'s ±7pt float loop, `Components/HourTimeline.swift`'s
/// pulsing "Now" marker) and every FUTURE one `Space/StarfieldView`/
/// `Space/HeroSceneView` (T17/T18) add — starfield drift, ships, and
/// scroll-driven camera moves — must ask this ONE facade the same question
/// rather than each view re-deriving its own `guard !reduceMotion`
/// condition independently (code-standards: route a cross-cutting concern
/// through one facade, not scattered inline checks). This is the "wire the
/// Reduce-Motion gate now, before the animations exist" contract T16
/// establishes for T17/T18 to consume unchanged.
///
/// `@Environment(\.accessibilityReduceMotion)` has no non-View home, so
/// every consumer still reads it itself (in its own `body`/view-lifecycle
/// code) and passes the raw `Bool` in here — this facade owns only the
/// DECISION, not the environment read itself.
///
/// Idle spin is deliberately excluded from this facade's job (the README
/// explicitly allows it to continue under Reduce Motion) — a caller that
/// wants an idle rotation to keep running simply never routes that
/// particular effect through this facade; it is not this type's job to
/// special-case "except idle spin."
enum MotionPreference {
    /// `true` unless Reduce Motion is on. Call this BEFORE starting or
    /// re-triggering any `.repeatForever` animation, ambient drift, ship
    /// movement, or scroll-driven 3D camera transform.
    static func repeatingAnimationsAllowed(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Folds the optional test override in over the system setting.
    ///
    /// Needed because `EnvironmentValues.accessibilityReduceMotion` is
    /// declared `{ get }` — read-only — in the iOS 26.5 SDK, so a snapshot
    /// test can no longer write it with
    /// `.environment(\.accessibilityReduceMotion, true)` the way the suites
    /// were originally authored (that spelling fails to compile now). The
    /// snapshot suites need Reduce Motion forced ON to render deterministically
    /// — otherwise each captured frame depends on exactly when the test host
    /// happened to render it — so the override travels in its own environment
    /// key and every consumer resolves the two through this one facade rather
    /// than re-deriving the precedence itself.
    static func resolvedReduceMotion(system: Bool, override: Bool?) -> Bool {
        override ?? system
    }
}

private struct ReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Test-only override for the system Reduce Motion setting; `nil` (the
    /// default) means "defer to the real device setting", which is always the
    /// case in a shipping build since nothing in the app ever writes it.
    var reduceMotionOverride: Bool? {
        get { self[ReduceMotionOverrideKey.self] }
        set { self[ReduceMotionOverrideKey.self] = newValue }
    }
}
