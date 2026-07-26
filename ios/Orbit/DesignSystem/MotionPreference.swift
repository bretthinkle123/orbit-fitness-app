import Foundation

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
}
