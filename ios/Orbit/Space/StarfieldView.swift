import SwiftUI

// MARK: - Deterministic seeds (design-spec §5 "Ambient motion" / `_scan()`'s own map)

/// The per-screen starfield seeds — home/fuel/train/body verbatim from the
/// design prototype's own `_scan()` (`Orbit Fitness.dc.html`:
/// `{ home: 5, fuel: 6, train: 7, body: 8 }`). `signIn`/`register` have no
/// depicted seed (the design names no starfield for its undepicted
/// pre-auth screens) — **documented judgment call**: 9/10, simply the next
/// two integers in the same sequence, giving each its own distinct
/// deterministic sky rather than reusing a depicted screen's exact field
/// (the same "a fresh deterministic seed per screen" instruction T13's own
/// `AuthScreenBackdrop` doc comment already recorded as this task's job).
enum StarfieldSeed {
    static let home = 5
    static let fuel = 6
    static let train = 7
    static let body = 8
    static let signIn = 9
    static let register = 10
}

// MARK: - RNG (verbatim port of the design's own generator)

/// The EXACT linear-congruential generator `_makeBg` uses (`Orbit
/// Fitness.dc.html`: `let sd = seed*7919+133; rnd = () => { sd =
/// (sd*9301+49297) % 233280; return sd/233280 }`) — replicated bit-for-bit
/// so a given seed produces the SAME star field the design intended, the
/// same "verbatim conversion" discipline `Figures/FigurePaths.swift` (T15)
/// already established for the muscle-figure geometry. `Int` (64-bit on
/// every iOS target) never overflows here: the post-modulo state is always
/// `0..<233280`, so `state * 9301` never exceeds ~2.2 billion.
struct StarfieldRNG {
    private var state: Int

    init(seed: Int) {
        state = seed * 7919 + 133
    }

    /// Returns the next value in `0..<1`, advancing the generator's state.
    mutating func next() -> Double {
        state = (state * 9301 + 49297) % 233280
        return Double(state) / 233280.0
    }
}

// MARK: - Field data (generated once per seed, never regenerated)

/// One star's fixed (seed-derived) properties — position/size/brightness/
/// twinkle are all generated once; only the PER-FRAME render position/alpha
/// (drift + twinkle phase) changes, computed fresh each frame from these.
struct StarfieldStar: Equatable, Sendable {
    let x: Double
    let y: Double
    let radius: Double
    let baseAlpha: Double
    let twinkleSpeed: Double
    let twinklePhase: Double
    /// Parallax depth (`0.12...0.42`) — how strongly this star's drift/
    /// (deferred) scroll-parallax term is scaled, matching `_makeBg`'s own
    /// per-cluster/per-loose-star depth ranges exactly.
    let depth: Double
    /// The design's `pink` flag — tints this star with the active
    /// palette's ACCENT color instead of the fixed neutral star-white.
    let isAccentTinted: Bool
}

/// One nebula haze blob behind the stars (`_paintNeb`'s per-cluster
/// gradient pair) — generated once per seed, at the SAME cluster center
/// every one of that cluster's stars orbits.
struct StarfieldNebulaCluster: Equatable, Sendable {
    let centerX: Double
    let centerY: Double
    let radius: Double
    /// `pink` flag (design's own name) — tints the OUTER haze blob with the
    /// active palette's SECONDARY color instead of PRIMARY. The inner
    /// "core" highlight always uses ACCENT regardless of this flag
    /// (`_paintNeb`'s `g2` gradient has no pink conditional at all).
    let isAccentTinted: Bool
}

/// Generates one seed's complete, deterministic star/nebula field — a pure
/// function (no view/animation state), directly Swift-Testing-covered for
/// both determinism ("same seed → same star positions") and per-field
/// parameter bounds.
enum StarfieldFieldGenerator {
    /// The 5 fixed cluster depths, verbatim from `_makeBg`'s own
    /// `[.14, .2, .28, .34, .42]` array (index = cluster order, not random).
    static let clusterDepths: [Double] = [0.14, 0.2, 0.28, 0.34, 0.42]
    static let clusterCount = 5
    static let looseStarCount = 55

    /// Generates the field for `seed`, constructing its own RNG — the
    /// common case (a fresh `StarfieldView`/test). `StarfieldSimulation`
    /// uses the `using:` overload instead, since it needs the SAME shared
    /// RNG to continue on afterward for the shooting-star/ship spawn timers
    /// (`_makeBg`'s `shootAt`/`shipAt` are computed on the SAME `rnd`
    /// instance, immediately after every star is generated).
    static func generate(seed: Int, size: CGSize) -> (stars: [StarfieldStar], clusters: [StarfieldNebulaCluster]) {
        var rng = StarfieldRNG(seed: seed)
        return generate(using: &rng, size: size)
    }

    static func generate(using rng: inout StarfieldRNG, size: CGSize) -> (stars: [StarfieldStar], clusters: [StarfieldNebulaCluster]) {
        let width = max(Double(size.width), 1)
        let height = max(Double(size.height), 1)

        var stars: [StarfieldStar] = []
        var clusters: [StarfieldNebulaCluster] = []

        // 5 gaussian-ish clusters (20-33 stars each), the design's own
        // "brighter, some accent-tinted" foreground clumps. RNG call order
        // below matches `_makeBg`'s object-literal evaluation order EXACTLY
        // (cx, cy, spread, n, clusterRadius-factor, clusterPink; then per
        // star: x's two calls, y's two calls, r, a, tw, ph, pink).
        for clusterIndex in 0..<clusterCount {
            let centerX = 30 + rng.next() * (width - 60)
            let centerY = 40 + rng.next() * (height - 80)
            let depth = clusterDepths[clusterIndex]
            let spread = 34 + rng.next() * 36
            let starCount = 20 + Int(rng.next() * 14)
            let clusterRadius = spread * (2.2 + rng.next() * 1.2)
            let clusterIsAccentTinted = rng.next() < 0.4
            clusters.append(
                StarfieldNebulaCluster(centerX: centerX, centerY: centerY, radius: clusterRadius, isAccentTinted: clusterIsAccentTinted)
            )

            for _ in 0..<starCount {
                let x = centerX + (rng.next() + rng.next() - 1) * spread
                let y = centerY + (rng.next() + rng.next() - 1) * spread
                let radius = 0.5 + rng.next() * 1.9
                let baseAlpha = 0.5 + rng.next() * 0.5
                let twinkleSpeed = 0.8 + rng.next() * 2.4
                let twinklePhase = rng.next() * 6.28
                let isAccentTinted = rng.next() < 0.22
                stars.append(
                    StarfieldStar(
                        x: x, y: y, radius: radius, baseAlpha: baseAlpha, twinkleSpeed: twinkleSpeed,
                        twinklePhase: twinklePhase, depth: depth, isAccentTinted: isAccentTinted
                    )
                )
            }
        }

        // 55 loose background stars, spread across the whole canvas
        // (`_makeBg`'s second loop) — call order: x, y, r, a, tw, ph, d,
        // pink (8 calls/star; unlike cluster stars, `d` ITSELF consumes an
        // rng call here, since loose stars have no fixed per-cluster depth).
        for _ in 0..<looseStarCount {
            let x = rng.next() * width
            let y = rng.next() * height
            let radius = 0.3 + rng.next() * 1.1
            let baseAlpha = 0.3 + rng.next() * 0.55
            let twinkleSpeed = 1 + rng.next() * 2
            let twinklePhase = rng.next() * 6.28
            let depth = 0.12 + rng.next() * 0.3
            let isAccentTinted = rng.next() < 0.12
            stars.append(
                StarfieldStar(
                    x: x, y: y, radius: radius, baseAlpha: baseAlpha, twinkleSpeed: twinkleSpeed,
                    twinklePhase: twinklePhase, depth: depth, isAccentTinted: isAccentTinted
                )
            )
        }

        return (stars, clusters)
    }
}

// MARK: - Shooting star (transient, `_drawBg`'s `B.shoot` state machine)

struct StarfieldShootingStar: Equatable, Sendable {
    var x: Double
    var y: Double
    let velocityX: Double
    let velocityY: Double
    var remainingLife: Double
    let maxLife: Double

    /// Spawns one shooting star (`_drawBg`'s spawn block) — RNG call order:
    /// direction, x, y, velocityX-magnitude, velocityY (5 calls, matching
    /// `_drawBg` exactly).
    static func spawn(using rng: inout StarfieldRNG, size: CGSize) -> StarfieldShootingStar {
        let direction: Double = rng.next() < 0.5 ? 1 : -1
        let width = Double(size.width)
        let height = Double(size.height)
        let x = 30 + rng.next() * (width - 60)
        let y = 20 + rng.next() * height * 0.45
        let velocityX = (240 + rng.next() * 170) * direction
        let velocityY = 130 + rng.next() * 90
        return StarfieldShootingStar(x: x, y: y, velocityX: velocityX, velocityY: velocityY, remainingLife: 0.75, maxLife: 0.75)
    }

    /// Advances by `deltaTime`; `nil` once life expires or it exits the
    /// canvas bounds (`_drawBg`'s own despawn condition, verbatim).
    func advanced(deltaTime: Double, size: CGSize) -> StarfieldShootingStar? {
        let newX = x + velocityX * deltaTime
        let newY = y + velocityY * deltaTime
        let newLife = remainingLife - deltaTime
        let width = Double(size.width)
        let height = Double(size.height)
        guard newLife > 0, newX >= -40, newX <= width + 40, newY <= height + 40 else { return nil }
        return StarfieldShootingStar(x: newX, y: newY, velocityX: velocityX, velocityY: velocityY, remainingLife: newLife, maxLife: maxLife)
    }
}

// MARK: - Ship (transient, toggleable, `_drawBg`'s `B.ship` state machine)

struct StarfieldShip: Equatable, Sendable {
    /// `+1` (left-to-right) or `-1` (right-to-left) — also the sign baked
    /// into `speed`, matching `_drawBg`'s own `dir`.
    let direction: Double
    var x: Double
    let y: Double
    let speed: Double
    let bobPhase: Double

    /// Spawns one ship (`_drawBg`'s spawn block) — RNG call order:
    /// direction, y, speed-magnitude, bobPhase (4 calls; `x` itself is
    /// deterministic from `direction`/canvas width, no RNG call, matching
    /// `_drawBg` exactly).
    static func spawn(using rng: inout StarfieldRNG, size: CGSize) -> StarfieldShip {
        let direction: Double = rng.next() < 0.5 ? 1 : -1
        let width = Double(size.width)
        let height = Double(size.height)
        let x = direction > 0 ? -26.0 : width + 26.0
        let y = 70 + rng.next() * (height - 240)
        let speed = (44 + rng.next() * 30) * direction
        let bobPhase = rng.next() * 6.28
        return StarfieldShip(direction: direction, x: x, y: y, speed: speed, bobPhase: bobPhase)
    }

    /// Advances by `deltaTime`; `nil` once the ship has crossed fully past
    /// the OPPOSITE edge from where it entered (`_drawBg`'s own despawn
    /// condition, verbatim).
    func advanced(deltaTime: Double, size: CGSize) -> StarfieldShip? {
        let width = Double(size.width)
        let newX = x + speed * deltaTime
        if (direction > 0 && newX > width + 30) || (direction < 0 && newX < -30) {
            return nil
        }
        return StarfieldShip(direction: direction, x: newX, y: y, speed: speed, bobPhase: bobPhase)
    }
}

// MARK: - Frame (what one `Canvas` tick draws — a pure snapshot)

struct StarfieldFrame {
    let stars: [StarfieldStar]
    let clusters: [StarfieldNebulaCluster]
    let elapsedTime: Double
    /// Normalized scroll position (`0...1`, design's own `B.scroll`).
    /// **Deferred, documented**: this task's own scope (`.pipeline/
    /// tasks.md` T17: "star layers with drift, shooting stars, toggleable
    /// ships") names ambient drift, not scroll-linked parallax — wiring a
    /// real per-screen scroll-offset tracker into all 6 screens'
    /// `ScrollView`s is a distinct, larger unit of work than this task's
    /// scope. The render math below already carries the scroll term
    /// faithfully (`StarfieldRenderer`), so a future task can drive this
    /// value with NO change to the rendering itself; it is always `0` from
    /// every current call site.
    let scrollProgress: Double
    let shootingStar: StarfieldShootingStar?
    let ship: StarfieldShip?
}

// MARK: - Simulation (the one mutable, per-instance, per-frame state machine)

/// Owns the MUTABLE per-frame state (elapsed time, current shooting star/
/// ship, their spawn countdowns) for one starfield instance — a reference
/// type so `StarfieldView` can hold ONE persistent instance across every
/// `TimelineView` tick (`@State` needs stable identity across renders, and
/// mutating a class's OWN internal properties from a `Canvas` content
/// closure is the standard, safe SwiftUI pattern for canvas-driven
/// animation — unlike writing to a tracked `@State`/`@Observable` property
/// during a render pass, which SwiftUI disallows). The star/nebula FIELD
/// itself is generated once, at `init`, from the deterministic seed, and
/// never regenerated.
///
/// **`@MainActor`, deliberately — resolved, not deferred (T17 close-out).**
/// The open question this class left behind was whether marking it
/// `@MainActor` even makes sense given it's constructed from `StarfieldView`'s
/// own plain `struct` `init(seed:theme:shipsEnabled:)` below, not from an
/// already-`@MainActor`-annotated function. It resolves cleanly: under the
/// iOS 17+ SDKs this project targets (`project.yml`'s `deploymentTarget.iOS:
/// "17.0"`), SwiftUI's `View` protocol is ITSELF a globally-`@MainActor`-
/// isolated protocol (not merely its `body` requirement) — every conforming
/// type is therefore wholly MainActor-isolated, including member-wise/custom
/// `init`s that are no part of the protocol's own requirement list. That
/// makes `StarfieldView.init` MainActor-isolated already, so constructing an
/// explicitly-`@MainActor` `StarfieldSimulation` there is a same-actor call,
/// not a cross-actor one — no `await`, no isolation violation, nothing
/// implicit to get wrong. This is also the SAME pattern this codebase already
/// relies on elsewhere without incident: `App/RootTabView.swift`'s `@State
/// private var router = AppRouter()` constructs an `@MainActor @Observable`
/// class directly in a `View`'s stored-property initializer the identical
/// way, and `App/AppRouter.swift`/`Core/AppStore.swift` are both `@MainActor`
/// for the same reason (owning per-frame/per-session mutable reference state
/// a `View` mutates outside `body`).
///
/// The alternative — leaving this class actor-non-isolated and relying on
/// "well, it's only ever called from a View" as an unenforced convention —
/// is exactly the shortcut `swift-conventions`' non-negotiables reject
/// (`"@MainActor correctness over @unchecked Sendable shortcuts"`): explicit
/// `@MainActor` here turns "only ever touched from the main actor" into a
/// COMPILE-TIME guarantee that survives this file growing a second call site
/// later (e.g. a future preview harness or a background pre-warm path) rather
/// than silently permitting one to mutate this class off-main with no
/// diagnostic. Kept as-is from the prior session's draft — this comment is
/// the missing justification, not a code change.
@MainActor
final class StarfieldSimulation {
    let stars: [StarfieldStar]
    let clusters: [StarfieldNebulaCluster]
    private let size: CGSize

    private var rng: StarfieldRNG
    private var elapsedTime: Double = 0
    private var lastDate: Date?
    private var shootingStarCountdown: Double
    private var shootingStar: StarfieldShootingStar?
    private var shipCountdown: Double
    private var ship: StarfieldShip?

    init(seed: Int, size: CGSize) {
        var generatorRNG = StarfieldRNG(seed: seed)
        let field = StarfieldFieldGenerator.generate(using: &generatorRNG, size: size)
        stars = field.stars
        clusters = field.clusters
        // Matches `_makeBg`'s own post-generation calls, on the SAME shared
        // `rnd` instance: `shootAt: 2 + rnd()*6`, `shipAt: 6 + rnd()*22`.
        shootingStarCountdown = 2 + generatorRNG.next() * 6
        shipCountdown = 6 + generatorRNG.next() * 22
        rng = generatorRNG
        self.size = size
    }

    /// Advances the simulation to `date` — a no-op time-wise when `animate`
    /// is false, so repeated calls render the exact same static frame
    /// (Reduce Motion's "idle static field remains" contract, `T16`'s
    /// `MotionPreference` facade). Call once per `TimelineView` tick, from
    /// inside the `Canvas` content closure (safe — see this class's own doc
    /// comment on why mutating a class's internal state there is fine).
    func tick(to date: Date, shipsEnabled: Bool, animate: Bool) {
        defer { lastDate = date }
        guard animate else { return }
        let delta = lastDate.map { date.timeIntervalSince($0) } ?? 0
        // Guards a huge delta after the view was backgrounded/paused —
        // without this, resuming would "catch up" the whole elapsed
        // background duration in one jump (a shooting star could otherwise
        // teleport clean across the screen on the very next frame).
        let clampedDelta = min(max(delta, 0), 0.2)
        elapsedTime += clampedDelta
        advanceShootingStar(deltaTime: clampedDelta)
        if shipsEnabled {
            advanceShip(deltaTime: clampedDelta)
        } else {
            ship = nil
        }
    }

    /// The current frame to draw — a pure read, no mutation. `animate` also
    /// gates whether an in-flight shooting star/ship is shown AT ALL
    /// (Reduce Motion's "idle STATIC field" — no transient decoration,
    /// not merely a paused one).
    func currentFrame(animate: Bool) -> StarfieldFrame {
        StarfieldFrame(
            stars: stars,
            clusters: clusters,
            elapsedTime: elapsedTime,
            scrollProgress: 0,
            shootingStar: animate ? shootingStar : nil,
            ship: animate ? ship : nil
        )
    }

    private func advanceShootingStar(deltaTime: Double) {
        if let current = shootingStar {
            shootingStar = current.advanced(deltaTime: deltaTime, size: size)
            if shootingStar == nil {
                shootingStarCountdown = 3.5 + rng.next() * 7
            }
        } else {
            shootingStarCountdown -= deltaTime
            if shootingStarCountdown <= 0 {
                shootingStar = StarfieldShootingStar.spawn(using: &rng, size: size)
            }
        }
    }

    private func advanceShip(deltaTime: Double) {
        if let current = ship {
            ship = current.advanced(deltaTime: deltaTime, size: size)
            if ship == nil {
                shipCountdown = 14 + rng.next() * 26
            }
        } else {
            shipCountdown -= deltaTime
            if shipCountdown <= 0 {
                ship = StarfieldShip.spawn(using: &rng, size: size)
            }
        }
    }
}

// MARK: - Renderer (per-frame draw — the only place `GraphicsContext` appears)

/// Draws one `StarfieldFrame` into a `Canvas`'s `GraphicsContext` — every
/// formula ported from `_drawBg`/`_paintNeb` (`Orbit Fitness.dc.html`),
/// noted per-section below. A pure function (no state of its own).
enum StarfieldRenderer {
    static func draw(_ frame: StarfieldFrame, into context: inout GraphicsContext, size: CGSize, theme: Theme) {
        drawNebula(frame, into: &context, size: size, theme: theme)
        drawStars(frame, into: &context, size: size, theme: theme)
        if let shootingStar = frame.shootingStar {
            drawShootingStar(shootingStar, into: &context, theme: theme)
        }
        if let ship = frame.ship {
            drawShip(ship, elapsedTime: frame.elapsedTime, into: &context, theme: theme)
        }
    }

    /// `_paintNeb`'s two-gradient-per-cluster haze, minus the offscreen-
    /// bitmap caching (redrawing ~5 clusters' gradients per frame is cheap;
    /// `Canvas` has no persistent bitmap layer the way `<canvas>` does, so
    /// this recomputes rather than re-blitting a cached image — same visual
    /// result). The `-40`/`+40` terms in `_drawBg`'s
    /// `drawImage(neb, 0, -40 - scroll*26 + sin(t*.05)*5)` cancel exactly
    /// against `_paintNeb`'s own `cy + 40` baseline when `scroll` is 0 and
    /// `sin` is 0 — the surviving dynamic term is `-scroll*26 +
    /// sin(t*.05)*5`, applied here as a Y offset on every cluster.
    private static func drawNebula(_ frame: StarfieldFrame, into context: inout GraphicsContext, size: CGSize, theme: Theme) {
        let yOffset = -frame.scrollProgress * 26 + sin(frame.elapsedTime * 0.05) * 5
        for cluster in frame.clusters {
            let center = CGPoint(x: cluster.centerX, y: cluster.centerY + yOffset)
            let outerColor = cluster.isAccentTinted ? theme.secondary : theme.primary
            let outerGradient = Gradient(stops: [
                .init(color: outerColor.opacity(0.26), location: 0),
                .init(color: outerColor.opacity(0.10), location: 0.55),
                .init(color: outerColor.opacity(0), location: 1),
            ])
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - cluster.radius, y: center.y - cluster.radius, width: cluster.radius * 2, height: cluster.radius * 2)),
                with: .radialGradient(outerGradient, center: center, startRadius: 0, endRadius: cluster.radius)
            )

            // The inner "core" highlight always uses ACCENT, regardless of
            // `isAccentTinted` — `_paintNeb`'s `g2` gradient has no pink
            // conditional at all.
            let coreRadius = cluster.radius * 0.4
            let coreGradient = Gradient(stops: [
                .init(color: theme.accent.opacity(0.14), location: 0),
                .init(color: theme.accent.opacity(0), location: 1),
            ])
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
                with: .radialGradient(coreGradient, center: center, startRadius: 0, endRadius: coreRadius)
            )
        }
    }

    /// `_drawBg`'s per-star loop: sine/cosine ambient drift + twinkle
    /// alpha, a 2.7x soft halo behind stars larger than `1.25`pt, wrapped
    /// vertically into the canvas height so the (deferred, always-0) scroll
    /// term can never carry a star permanently off-screen once it's wired.
    private static func drawStars(_ frame: StarfieldFrame, into context: inout GraphicsContext, size: CGSize, theme: Theme) {
        let height = Double(size.height)
        let wrapHeight = height + 30

        for star in frame.stars {
            let driftY = sin(frame.elapsedTime * 0.06 + star.twinklePhase) * 10 * star.depth
            let rawY = star.y - frame.scrollProgress * 150 * star.depth + driftY
            let wrappedY = (rawY.truncatingRemainder(dividingBy: wrapHeight) + wrapHeight).truncatingRemainder(dividingBy: wrapHeight) - 15
            let x = star.x + cos(frame.elapsedTime * 0.045 + star.twinklePhase) * 7 * star.depth

            var alpha = star.baseAlpha * (0.68 + 0.32 * sin(frame.elapsedTime * star.twinkleSpeed + star.twinklePhase))
            alpha = min(max(alpha, 0), 1)
            let color = star.isAccentTinted ? theme.accent : Theme.Neutral.starfieldStarWhite

            if star.radius > 1.25 {
                let haloRadius = star.radius * 2.7
                context.fill(
                    Path(ellipseIn: CGRect(x: x - haloRadius, y: wrappedY - haloRadius, width: haloRadius * 2, height: haloRadius * 2)),
                    with: .color(color.opacity(alpha * 0.25))
                )
            }
            context.fill(
                Path(ellipseIn: CGRect(x: x - star.radius, y: wrappedY - star.radius, width: star.radius * 2, height: star.radius * 2)),
                with: .color(color.opacity(alpha))
            )
        }
    }

    /// `_drawBg`'s shooting-star streak: a white-to-transparent gradient
    /// stroke from the current position back along its own velocity vector,
    /// fading out as `life` runs down (`k = life/max` mirrors the design's
    /// own `globalAlpha` term, baked directly into the gradient stops here
    /// since `GraphicsContext` has no canvas-style `globalAlpha`).
    private static func drawShootingStar(_ shootingStar: StarfieldShootingStar, into context: inout GraphicsContext, theme: Theme) {
        let progress = shootingStar.remainingLife / shootingStar.maxLife
        guard progress > 0 else { return }
        let head = CGPoint(x: shootingStar.x, y: shootingStar.y)
        let tail = CGPoint(x: shootingStar.x - shootingStar.velocityX * 0.09, y: shootingStar.y - shootingStar.velocityY * 0.09)
        var path = Path()
        path.move(to: head)
        path.addLine(to: tail)
        let gradient = Gradient(colors: [Color.white.opacity(progress * 0.9), theme.secondaryLight.opacity(0)])
        context.stroke(
            path,
            with: .linearGradient(gradient, startPoint: head, endPoint: tail),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
        )
    }

    /// `_drawBg`'s ship: an engine-trail gradient stroke, a 4-point hull
    /// wedge, and 2 tiny cockpit/engine dots — all mirrored on the x-axis by
    /// `direction` (replaces the design's `ctx.scale(dir,1)` context
    /// transform by mirroring each point's own x-offset directly, avoiding
    /// any `GraphicsContext` transform-state bookkeeping). Every element
    /// here shares the design's own `0.92` alpha (`_drawBg`'s `globalAlpha =
    /// .92` persists from the hull fill through both dots, until `restore`).
    private static func drawShip(_ ship: StarfieldShip, elapsedTime: Double, into context: inout GraphicsContext, theme: Theme) {
        let bobY = ship.y + sin(elapsedTime * 1.4 + ship.bobPhase) * 3

        var trailPath = Path()
        let trailStart = CGPoint(x: ship.x - 9 * ship.direction, y: bobY)
        let trailEnd = CGPoint(x: ship.x - 34 * ship.direction, y: bobY)
        trailPath.move(to: trailStart)
        trailPath.addLine(to: trailEnd)
        let trailGradient = Gradient(colors: [theme.secondaryLight.opacity(0.3), theme.secondaryLight.opacity(0)])
        context.stroke(
            trailPath,
            with: .linearGradient(trailGradient, startPoint: trailStart, endPoint: trailEnd),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )

        let hullPoints: [(x: Double, y: Double)] = [(10, 0), (-6, -4.4), (-3, 0), (-6, 4.4)]
        let mirroredHull = hullPoints.map { CGPoint(x: ship.x + $0.x * ship.direction, y: bobY + $0.y) }
        var hullPath = Path()
        hullPath.move(to: mirroredHull[0])
        for point in mirroredHull.dropFirst() { hullPath.addLine(to: point) }
        hullPath.closeSubpath()
        context.fill(hullPath, with: .color(Theme.Neutral.starfieldShipHull.opacity(0.92)))

        let cockpitCenter = CGPoint(x: ship.x + 2.6 * ship.direction, y: bobY)
        context.fill(
            Path(ellipseIn: CGRect(x: cockpitCenter.x - 1.5, y: cockpitCenter.y - 1.5, width: 3, height: 3)),
            with: .color(theme.primary.opacity(0.92))
        )
        let engineCenter = CGPoint(x: ship.x - 7.5 * ship.direction, y: bobY)
        context.fill(
            Path(ellipseIn: CGRect(x: engineCenter.x - 1.9, y: engineCenter.y - 1.9, width: 3.8, height: 3.8)),
            with: .color(theme.secondaryLight.opacity(0.92))
        )
    }
}

// MARK: - View (the z0 layer of every screen's shared ZStack recipe, NM-6)

/// The starfield canvas every screen's ZStack recipe puts behind its
/// content (`Starfield → HeroScene → ScrollView(content) → bottom fade →
/// TabBar`, design-spec NM-6) — `TimelineView(.animation)` + `Canvas` per
/// plan §Frontend. Deterministic per-screen seed (`StarfieldSeed`); Reduce
/// Motion freezes drift/twinkle/shooting-stars/ships via the `T16`
/// `MotionPreference` facade (idle STATIC field remains, not a blank one).
struct StarfieldView: View {
    let seed: Int
    var theme = Theme()
    var shipsEnabled = true

    /// The design's own fixed reference layout (design-spec §4: "Fixed
    /// reference layout is 402 × 874 pt (iPhone)"; this app's
    /// `TARGETED_DEVICE_FAMILY` is iPhone-only, no iPad/landscape variant,
    /// `project.yml`) — the star FIELD is generated once against this fixed
    /// size rather than the device's actual (near-identical, always-portrait-
    /// phone) frame, avoiding a `GeometryReader`-driven regeneration/resize
    /// path the app's own fixed-layout architecture doesn't need.
    ///
    /// `nonisolated` because `StarfieldView` is a `View`, and therefore
    /// `@MainActor`-isolated under Swift 6 — which would otherwise isolate this
    /// constant too, making it unusable as the default value of a `static let`
    /// in the nonisolated test cases that measure against it
    /// (`Tests/StarfieldSnapshotTests.swift`, `Tests/SpaceTests.swift`). It is
    /// an immutable `Sendable` constant, so there is nothing here for an actor
    /// to protect.
    nonisolated static let referenceSize = CGSize(width: 402, height: 874)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var simulation: StarfieldSimulation

    init(seed: Int, theme: Theme = Theme(), shipsEnabled: Bool = true) {
        self.seed = seed
        self.theme = theme
        self.shipsEnabled = shipsEnabled
        _simulation = State(initialValue: StarfieldSimulation(seed: seed, size: Self.referenceSize))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let motionAllowed = MotionPreference.repeatingAnimationsAllowed(reduceMotion: reduceMotion)
                simulation.tick(to: timeline.date, shipsEnabled: shipsEnabled, animate: motionAllowed)
                let frame = simulation.currentFrame(animate: motionAllowed)
                StarfieldRenderer.draw(frame, into: &context, size: Self.referenceSize, theme: theme)
            }
        }
        // Purely decorative background art — VoiceOver has nothing useful
        // to read here, and it must never intercept a touch meant for a
        // card/button drawn above it.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}
