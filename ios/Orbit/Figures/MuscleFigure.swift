import SwiftUI

/// CMP-23 — one of the four muscle-figure SVGs (`figure-paths.md`), rendered
/// as native `Path` shapes from `FigurePaths`' verbatim geometry (never
/// redrawn by hand — see that file's header comment for the conversion
/// discipline). One `MuscleFigure` instance renders ONE figure (a given
/// gender's front OR back view); `Screens/BodyView.swift` stacks a front +
/// back instance per the design's "front figure then, scrolling down, back
/// figure" layout (design-spec §4) and swaps which shape array each shows
/// when the M/W toggle changes.
struct MuscleFigure: View {
    let shapes: [MuscleFigureShape]
    /// Looks up a muscle group's current level (1...6) — supplied by the
    /// caller from `GET /body`'s `muscle_levels`, never invented here.
    let levelForGroup: (MuscleGroupToken) -> Int
    /// Whether a group has a logged set today. figure-paths.md only names a
    /// glow filter token (`fxChestA`/`fxDeltsA`/`fxTriA`) for the three
    /// muscle shapes Push Day can ever train (AC11) — **generalized here to
    /// every muscle group** rather than hardcoding the glow to only those
    /// three shapes, the same "generalize the one depicted example to the
    /// architecture" call `Components/MealCard.swift` (T14) already made for
    /// Dinner's empty state. Functionally identical today (only chest/
    /// shoulders/triceps can ever be `true`), architecturally correct if a
    /// future program trains another group.
    let isTrainedToday: (MuscleGroupToken) -> Bool
    var theme = Theme()

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    /// Resolved through `MotionPreference` so the snapshot suites can force
    /// Reduce Motion ON: the system key is read-only in the SDK, so tests
    /// write `reduceMotionOverride` instead.
    private var reduceMotion: Bool {
        MotionPreference.resolvedReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
    }
    @State private var floatOffset: CGFloat = 0

    /// Midpoint of the design's "~5.5-6s" float-loop range (design-spec
    /// §3.6 Motion — float) — a single fixed duration rather than a
    /// randomized per-instance value, since the design names a range (an
    /// approximate feel), not a literal per-instance random seed to
    /// reproduce.
    private static let floatDuration = (Metrics.Motion.floatDurationMin + Metrics.Motion.floatDurationMax) / 2

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / FigurePaths.gridSize.width,
                geometry.size.height / FigurePaths.gridSize.height
            )
            ZStack {
                ForEach(Array(shapes.enumerated()), id: \.offset) { _, shape in
                    shapeView(for: shape)
                }
            }
            .frame(width: FigurePaths.gridSize.width, height: FigurePaths.gridSize.height)
            .scaleEffect(scale)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(FigurePaths.gridSize.width / FigurePaths.gridSize.height, contentMode: .fit)
        .offset(y: floatOffset)
        .onAppear(perform: startFloatingIfAllowed)
        // Decorative artwork — `MuscleRow` (built off the SAME `GET /body`
        // data, one row per group) is what VoiceOver reads for per-muscle
        // detail; duplicating that here would double-announce it.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func shapeView(for shape: MuscleFigureShape) -> some View {
        let path = shape.geometry.path
        switch shape.fill {
        case .muscle(let group):
            let color = Color(hex: theme.levelScaleStop(forLevel: levelForGroup(group)).colorHex)
            path
                .fill(color)
                .overlay(path.stroke(Theme.Neutral.figureOutline, lineWidth: 1))
                .shadow(
                    color: isTrainedToday(group) ? theme.trainedMuscleGlow : .clear,
                    radius: Metrics.Shadow.trainedMuscleGlowRadius
                )
        case .neutral:
            path.fill(Theme.Neutral.figureNeutralFill)
        case .groundShadow:
            path.fill(theme.primary.opacity(0.16))
        }
    }

    /// NM-9: the float loop is gated by Reduce Motion (mirrors
    /// `HourTimeline`'s pulsing-NOW-marker pattern, T14) — both route
    /// through the one `MotionPreference` facade (T16) so `Space/`'s
    /// starfield drift/ships and scroll-driven 3D (T17/T18) ask the SAME
    /// question rather than each view re-deriving its own condition.
    private func startFloatingIfAllowed() {
        guard MotionPreference.repeatingAnimationsAllowed(reduceMotion: reduceMotion) else { return }
        withAnimation(.easeInOut(duration: Self.floatDuration).repeatForever(autoreverses: true)) {
            floatOffset = -Metrics.Motion.floatAmplitude
        }
    }
}
