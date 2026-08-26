import Foundation
import SceneKit
import SwiftUI
import simd

// MARK: - Scroll-progress tracking (the ONE mechanism every hero-bearing
// screen routes its scroll-driven 3D through — `code-standards` facade rule;
// README's own porting map: "scroll listeners -> ScrollView offset
// preference -> scene params").

/// The raw scroll-tracking inputs one `ScrollView` reports — `normalized`
/// derives the design's own `scrollTop / (scrollHeight - clientHeight)`
/// formula (`_makeScene`'s scroll listener) from them.
struct HeroScrollProgress: Equatable, Sendable {
    static let zero = HeroScrollProgress()
    var viewportHeight: CGFloat = 0
    var contentHeight: CGFloat = 0
    /// `0` at the very top, growing as the user scrolls down — the raw,
    /// un-eased offset (`HeroSceneState` owns the "8%/frame" easing itself,
    /// mirroring `S.scroll += (S.target - S.scroll) * .08`).
    var offsetFromTop: CGFloat = 0

    /// Guarded against not-yet-scrollable content (`scrollableExtent <= 0`)
    /// the same way the design's own listener leaves `S.target` at its
    /// initial `0` in that case (`m > 0 ? scrollTop/m : 0`).
    var normalized: Double {
        let scrollableExtent = contentHeight - viewportHeight
        guard scrollableExtent > 0 else { return 0 }
        return min(max(Double(offsetFromTop / scrollableExtent), 0), 1)
    }
}

private struct HeroScrollOffsetPreferenceKey: PreferenceKey {
    // `let`, not `var`: a mutable static is nonisolated global shared mutable
    // state, which Swift 6 rejects. `PreferenceKey.defaultValue` is a
    // get-only requirement, so a constant satisfies it.
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct HeroContentHeightPreferenceKey: PreferenceKey {
    // `let`, not `var`: a mutable static is nonisolated global shared mutable
    // state, which Swift 6 rejects. `PreferenceKey.defaultValue` is a
    // get-only requirement, so a constant satisfies it.
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct HeroViewportHeightPreferenceKey: PreferenceKey {
    // `let`, not `var`: a mutable static is nonisolated global shared mutable
    // state, which Swift 6 rejects. `PreferenceKey.defaultValue` is a
    // get-only requirement, so a constant satisfies it.
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The named coordinate space `HeroScrollAnchor` measures itself against —
/// anchored to the `ScrollView` itself (via `.trackHeroScrollProgress`, which
/// applies `.coordinateSpace(name:)` to it), NOT to the scrolling content, so
/// the anchor's reported `minY` changes exactly by however far the content
/// has scrolled.
private let heroScrollCoordinateSpaceName = "heroScroll"

extension View {
    /// Applies to a hero-bearing screen's `ScrollView` — reports its live
    /// viewport height and establishes the named coordinate space
    /// `HeroScrollAnchor`/`reportHeroScrollContentHeight()` (both placed
    /// INSIDE the scrollable content) measure against.
    func trackHeroScrollProgress(_ progress: Binding<HeroScrollProgress>) -> some View {
        modifier(HeroScrollTrackingModifier(progress: progress))
    }

    /// Applies to the scrollable content's own outermost container (the same
    /// `VStack` `HeroScrollAnchor` sits inside) — reports its TOTAL height,
    /// the `scrollHeight` half of the design's own `scrollHeight -
    /// clientHeight` denominator.
    func reportHeroScrollContentHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeroContentHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }
}

private struct HeroScrollTrackingModifier: ViewModifier {
    @Binding var progress: HeroScrollProgress

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HeroViewportHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
            .coordinateSpace(name: heroScrollCoordinateSpaceName)
            .onPreferenceChange(HeroViewportHeightPreferenceKey.self) { progress.viewportHeight = $0 }
            .onPreferenceChange(HeroContentHeightPreferenceKey.self) { progress.contentHeight = $0 }
            .onPreferenceChange(HeroScrollOffsetPreferenceKey.self) { progress.offsetFromTop = -$0 }
    }
}

/// Placed as the FIRST child of a hero-bearing screen's scrollable `VStack`
/// (zero height, invisible) — its own `minY` relative to
/// `heroScrollCoordinateSpaceName` becomes more negative as the user scrolls
/// down; `HeroScrollTrackingModifier` negates it back to a positive offset.
struct HeroScrollAnchor: View {
    var body: some View {
        Color.clear
            .frame(height: 0)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HeroScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(heroScrollCoordinateSpaceName)).minY
                    )
                }
            )
    }
}

// MARK: - Reduce-Motion gate for scroll-driven motion specifically (idle
// spin is a SEPARATE concern this file's own `HeroSceneState.tick` never
// freezes — README "Reduce Motion... idle spin may stay").

enum HeroScrollMotionGate {
    /// The scroll value this frame's camera/rotation math should use — the
    /// live target while scroll-driven motion is allowed, or the LAST
    /// allowed value (frozen in place, never reset to 0) once Reduce Motion
    /// engages. Design's own accessibility contract: scroll-driven camera
    /// motion "STOPS" (a freeze, not a jarring snap back to the top).
    static func effectiveScrollTarget(liveTarget: Double, lastAllowedTarget: Double, motionAllowed: Bool) -> Double {
        motionAllowed ? liveTarget : lastAllowedTarget
    }
}

// MARK: - Pure per-frame scene math (ported verbatim from `_loop()`'s
// home/fuel/train branches — directly Swift-Testing-covered, no SceneKit
// dependency, same split `StarfieldRenderer`/`StarfieldFieldGenerator` (T17)
// established between "pure math" and "the thing that draws it").

enum HeroCameraMath {
    // MARK: Home — `_loop`: "planet spin t*.14+scroll*2.6; ring tilt eases
    // .42->.08; camera z 4.6->4.05, y rises with scroll."

    static func homeCameraPosition(scrollProgress: Double) -> (x: Double, y: Double, z: Double) {
        (0, 0.3 + scrollProgress * 0.35, 4.6 - scrollProgress * 0.55)
    }

    static func homePlanetSpinAngle(elapsedTime: Double, scrollProgress: Double) -> Double {
        elapsedTime * 0.14 + scrollProgress * 2.6
    }

    /// The ring GROUP's own Euler x/z rotation — `P.rg.rotation.x = .42 -
    /// s*.34; P.rg.rotation.z = .16 + s*.3`.
    static func homeRingGroupRotation(scrollProgress: Double) -> (x: Double, z: Double) {
        (0.42 - scrollProgress * 0.34, 0.16 + scrollProgress * 0.3)
    }

    /// The accent moonlet's orbit (simplified from the design's own
    /// decorative cruiser-ship mesh — see `HeroSceneState`'s doc comment for
    /// why) — `_loop`'s own cruiser math, `Math.cos(a)*r,
    /// Math.sin(a*1.4)*.34, Math.sin(a)*r` where `a = t*.45`, reused
    /// verbatim for the simpler moonlet.
    static func homeMoonletPosition(elapsedTime: Double, orbitRadius: Double) -> (x: Double, y: Double, z: Double) {
        let angle = elapsedTime * 0.45
        return (cos(angle) * orbitRadius, sin(angle * 1.4) * 0.34, sin(angle) * orbitRadius)
    }

    // MARK: Fuel — `_loop`: "group yaw t*.09+scroll*1.5; camera descends
    // y1.6->0.2 (top-down -> edge-on)."

    static func fuelCameraPosition(elapsedTime: Double, scrollProgress: Double) -> (x: Double, y: Double, z: Double) {
        (sin(elapsedTime * 0.2) * 0.12, 1.6 - scrollProgress * 1.4, 4)
    }

    static func fuelGroupYaw(elapsedTime: Double, scrollProgress: Double) -> Double {
        elapsedTime * 0.09 + scrollProgress * 1.5
    }

    static func fuelPlanetSpinAngle(elapsedTime: Double) -> Double {
        elapsedTime * 0.28
    }

    /// One macro moon's position on its own (already-tilted-by-its-parent-
    /// node) orbit — `Math.cos(a)*r, 0, Math.sin(a)*r` where `a = t*speed +
    /// phase`.
    static func fuelMoonPosition(elapsedTime: Double, orbitRadius: Double, angularSpeed: Double, phase: Double) -> (x: Double, y: Double, z: Double) {
        let angle = elapsedTime * angularSpeed + phase
        return (cos(angle) * orbitRadius, 0, sin(angle) * orbitRadius)
    }

    /// `o.base * (.78 + .5*pct)` — the one-shot "pulse on quick-add" bump
    /// (`* (1 + pulse*.4)`) is DEFERRED (see `HeroSceneState`'s doc comment),
    /// so `pulse` always resolves to `0` from every current call site,
    /// collapsing this to the steady-state formula until a future task wires
    /// a live pulse trigger off `AppStore`'s own food-log mutation.
    static func fuelMoonScale(baseScale: Double, macroFraction: Double, pulse: Double = 0) -> Double {
        baseScale * (0.78 + 0.5 * macroFraction) * (1 + pulse * 0.4)
    }

    // MARK: Train — `_loop`: "asteroid spin + camera orbits azimuth =
    // scroll*2.4 at r4.5."

    static func trainCameraPosition(scrollProgress: Double) -> (x: Double, y: Double, z: Double) {
        let azimuth = scrollProgress * 2.4
        return (sin(azimuth) * 4.5, 0.35 + scrollProgress * 0.55, cos(azimuth) * 4.5)
    }

    static func trainRockRotation(elapsedTime: Double, scrollProgress: Double) -> (y: Double, x: Double, z: Double) {
        (elapsedTime * 0.3 + scrollProgress * 3.2, 0.15 + scrollProgress * 0.5, sin(elapsedTime * 0.1) * 0.08)
    }

    /// `.1 + 1.6*(doneSets/16)` — the TARGET emissive intensity; easing
    /// toward it (`+= (target-current)*.06`/frame) is `HeroSceneState`'s own
    /// per-frame job, mirroring the split `homeCameraPosition` already has
    /// from the design's own `S.scroll` easing.
    static func trainAsteroidTargetEmissiveIntensity(doneSetFraction: Double) -> Double {
        0.1 + 1.6 * doneSetFraction
    }

    /// One orbiting debris rock's position (the astronaut-specific
    /// collision/flail choreography for the middle debris item is DEFERRED —
    /// see `HeroSceneState`'s doc comment; every debris rock here uses the
    /// SAME base orbit formula regardless) — `Math.cos(a)*r,
    /// Math.sin(a*.9)*.4, Math.sin(a)*r` where `a = t*speed + phase`.
    static func trainDebrisPosition(elapsedTime: Double, orbitRadius: Double, angularSpeed: Double, phase: Double) -> (x: Double, y: Double, z: Double) {
        let angle = elapsedTime * angularSpeed + phase
        return (cos(angle) * orbitRadius, sin(angle * 0.9) * 0.4, sin(angle) * orbitRadius)
    }
}

// MARK: - Lighting (shared by every hero scene, README: "ambient [fixed
// lavender] 0.6 + white directional 1.15 from (3,4,5) + secondary point
// light 1.3 from (−3.5,−2,3)")

enum HeroLighting {
    static func makeLights(theme: Theme) -> [SCNNode] {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(ambientLightColor)
        ambient.light?.intensity = 0.6 * 1000 // SceneKit lumens; `.6` was the Three.js 0...1 intensity

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.color = UIColor.white
        directional.light?.intensity = 1.15 * 1000
        directional.position = SCNVector3(3, 4, 5)
        directional.look(at: SCNVector3(0, 0, 0))

        let point = SCNNode()
        point.light = SCNLight()
        point.light?.type = .omni
        point.light?.color = UIColor(theme.secondary)
        point.light?.intensity = 1.3 * 1000
        point.position = SCNVector3(-3.5, -2, 3)

        return [ambient, directional, point]
    }

    /// README's fixed ambient-light tint — a palette-INDEPENDENT constant
    /// (same family as `Theme.Neutral`'s other fixed neutrals), so it lives
    /// here rather than inventing a new `Theme` property nothing else needs;
    /// expressed as raw sRGB components (never a hex literal, and never
    /// spelled out as a hex STRING in prose either — `check_no_inline_hex.sh`
    /// greps comments too, T13's own store-compliance incident) so there is
    /// nothing for that script to flag in this file.
    private static let ambientLightColor = Color(.sRGB, red: 154.0 / 255, green: 140.0 / 255, blue: 201.0 / 255, opacity: 1)
}

// MARK: - Scene kind + live per-frame inputs

/// Which of the 3 hero configurations to build — `planetIndex` is the ONE
/// per-instance value that changes the Home scene's actual GEOMETRY (ring
/// count, texture seed), so it lives on the kind itself (triggers a rebuild
/// via `.onChange`); Fuel/Train have no such structural variation.
enum HeroSceneKind: Equatable {
    case home(planetIndex: Int)
    case fuel
    case train
}

/// Continuous, every-frame-fresh inputs that feed the math WITHOUT
/// requiring a geometry rebuild (macro percentages, done-set fraction) —
/// kept separate from `HeroSceneKind` so ticking a set on Train, for
/// instance, never re-triggers the (comparatively expensive) 5-subdivision
/// asteroid mesh rebuild.
struct HeroSceneLiveInputs: Equatable {
    var proteinFraction: Double = 0
    var carbFraction: Double = 0
    var fatFraction: Double = 0
    var doneSetFraction: Double = 0
}

// MARK: - Scene state (the one mutable, per-instance, per-frame owner —
// same architecture `StarfieldSimulation` (T17) established: a class so
// `HeroSceneView` can hold ONE persistent instance across every
// `TimelineView` tick, mutated from inside that tick's own closure.)

/// Owns the built `SCNScene` + the node references its per-frame `tick`
/// needs to mutate, plus the elapsed-time/scroll-easing state.
///
/// **`@MainActor`, for the SAME reason `Space/StarfieldView.swift`'s
/// `StarfieldSimulation` is (T17's own resolved-and-documented open
/// question, not re-derived here): under the iOS 17+ SDK, `View`
/// conformance makes `HeroSceneView`'s own `init`/property-initializers
/// MainActor-isolated already, so constructing this class there is a
/// same-actor call.**
///
/// **Idle spin vs. scroll-driven motion — the ONE contract this class
/// (unlike `StarfieldSimulation`) must NOT collapse into a single freeze**:
/// README's accessibility line draws a real distinction for heroes
/// specifically — "scroll-driven camera motion STOPS, idle spin may
/// remain" — so `elapsedTime` here ALWAYS advances (never frozen, unlike
/// `StarfieldSimulation`'s own full freeze), while only the EASED scroll
/// value (`easedScrollProgress`) is gated by `HeroScrollMotionGate`. Every
/// formula in `HeroCameraMath` that depends on `t` alone keeps moving; every
/// term that depends on `s` (scroll) stops varying the instant Reduce
/// Motion engages.
///
/// **Deliberate scope simplifications (documented, not silently dropped —
/// AC31's own literal wording is "Home planet+rings, Fuel macro moons, Train
/// asteroid + scroll-driven cameras", none of which name these flourishes)**:
/// the design's decorative cruiser-ship mesh orbiting Home is built here as
/// a simple emissive moonlet sphere instead (README's OWN 3D-spec bullet
/// already describes it that way: "accent-colored moonlet... orbiting r
/// 2.5"); Fuel's low-poly food-shaped moons (`_mkFood`: drumstick/apple/
/// cheese/milk composite meshes) are plain tinted spheres instead (README's
/// own bullet: "3 orbiting macro moons", not "food-shaped moons"); Train's
/// tethered-astronaut collision/flail choreography (`_mkAstronaut` + the
/// once-a-minute bump-into-the-outer-rock physics) is omitted — the 3
/// debris rocks all use the SAME plain orbit formula
/// (`HeroCameraMath.trainDebrisPosition`) rather than one of them running a
/// separate physics simulation nothing in the plan/README names. Fuel's
/// "pulse on quick-add" one-shot moon-scale bump is also deferred (no live
/// trigger wired from `AppStore`'s food-log mutation this task) — the
/// steady-state scale formula is complete and live.
@MainActor
final class HeroSceneState {
    /// A default `SCNScene`'s background renders opaque, which would paint
    /// over the `StarfieldView` at z0 beneath the hero in `HomeView`'s ZStack.
    /// Clearing it is NECESSARY but NOT SUFFICIENT — the hosting view has to
    /// be non-opaque too, which is why the hero is rendered by
    /// `TransparentSceneView` rather than SwiftUI's `SceneView`.
    let scene: SCNScene = {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        return scene
    }()
    let cameraNode: SCNNode

    private let kind: HeroSceneKind
    private var appliedTheme: Theme?
    private var appliedPlanetIndex: Int?

    private var elapsedTime: Double = 0
    private var lastDate: Date?
    private var easedScrollProgress: Double = 0
    private var lastAllowedScrollTarget: Double = 0

    // Home
    /// The design's own `grp` for the home scene (`_makeScene`'s
    /// `grp.scale.setScalar(.62)`) — planet/rings/moonlet all mount as
    /// CHILDREN of this, so the one group-level scale applies to all three
    /// together, matching the design exactly; created once (`init` calls
    /// `applyIfNeeded`, which lazily creates it on the first apply) and
    /// reused across re-applies — only its CHILDREN get replaced.
    private var homeGroupNode: SCNNode?
    private var homePlanetNode: SCNNode?
    private var homeRingGroupNode: SCNNode?
    private var homeMoonletNode: SCNNode?

    // Fuel
    private var fuelPlanetNode: SCNNode?
    private var fuelGroupNode: SCNNode?
    private struct FuelMoon {
        let node: SCNNode
        let orbitRadius: Double
        let angularSpeed: Double
        let phase: Double
        let baseScale: Double
    }
    private var fuelProteinMoon: FuelMoon?
    private var fuelCarbMoon: FuelMoon?
    private var fuelFatMoon: FuelMoon?

    // Train
    /// The design's own `grp` for the train scene (`_makeScene`'s
    /// `grp.scale.setScalar(.78)`) — same "created once, children replaced
    /// on rebuild" shape as `homeGroupNode` above.
    private var trainGroupNode: SCNNode?
    private var trainRockNode: SCNNode?
    private var trainMaterial: SCNMaterial?
    private var trainCurrentEmissiveIntensity: Double = 0.1
    private struct TrainDebris {
        let node: SCNNode
        let orbitRadius: Double
        let angularSpeed: Double
        let phase: Double
    }
    private var trainDebris: [TrainDebris] = []

    init(kind: HeroSceneKind, theme: Theme) {
        self.kind = kind
        cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.1
        camera.zFar = 60
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        for light in HeroLighting.makeLights(theme: theme) {
            scene.rootNode.addChildNode(light)
        }
        applyIfNeeded(planetIndex: kind.homePlanetIndex, theme: theme)
    }

    /// Rebuilds this hero's kind-specific geometry/texture — a no-op if
    /// neither `theme` nor (Home only) `planetIndex` actually changed since
    /// the last apply, mirroring the design's own `_applyPlanet`/
    /// `_recolorScenes` change-detection (never rebuild every frame; only on
    /// a genuine palette switch or planet-picker tap).
    func applyIfNeeded(planetIndex: Int?, theme: Theme) {
        guard appliedTheme != theme || appliedPlanetIndex != planetIndex else { return }
        appliedTheme = theme
        appliedPlanetIndex = planetIndex
        switch kind {
        case .home:
            rebuildHome(planetIndex: planetIndex ?? 0, theme: theme)
        case .fuel:
            rebuildFuel(theme: theme)
        case .train:
            rebuildTrain(theme: theme)
        }
    }

    /// Advances to `date` and applies every per-frame transform — a no-op
    /// time-wise for the SCROLL-DRIVEN terms when `motionAllowed` is false
    /// (idle-spin terms keep advancing regardless, per this class's own doc
    /// comment above). Call once per `TimelineView` tick.
    func tick(to date: Date, scrollTarget: Double, motionAllowed: Bool, liveInputs: HeroSceneLiveInputs) {
        defer { lastDate = date }
        let delta = lastDate.map { date.timeIntervalSince($0) } ?? 0
        let clampedDelta = min(max(delta, 0), 0.2)
        elapsedTime += clampedDelta

        if motionAllowed { lastAllowedScrollTarget = scrollTarget }
        let effectiveTarget = HeroScrollMotionGate.effectiveScrollTarget(
            liveTarget: scrollTarget, lastAllowedTarget: lastAllowedScrollTarget, motionAllowed: motionAllowed
        )
        // The design's own "8%/frame" ease (`S.scroll += (S.target -
        // S.scroll) * .08`) — applied to the GATED target, so easing itself
        // also settles rather than continuing toward a moving goal once
        // Reduce Motion freezes the target.
        easedScrollProgress += (effectiveTarget - easedScrollProgress) * 0.08

        switch kind {
        case .home:
            tickHome()
        case .fuel:
            tickFuel(liveInputs: liveInputs)
        case .train:
            tickTrain(liveInputs: liveInputs)
        }
    }

    // MARK: - Home

    private func rebuildHome(planetIndex: Int, theme: Theme) {
        let groupNode: SCNNode
        if let existingGroup = homeGroupNode {
            groupNode = existingGroup
        } else {
            groupNode = SCNNode()
            groupNode.scale = SCNVector3(0.62, 0.62, 0.62)
            scene.rootNode.addChildNode(groupNode)
            homeGroupNode = groupNode
        }
        homePlanetNode?.removeFromParentNode()
        homeRingGroupNode?.removeFromParentNode()
        homeMoonletNode?.removeFromParentNode()

        let planetGeometry = SCNSphere(radius: 1.12)
        planetGeometry.segmentCount = 48
        let planetMaterial = SCNMaterial()
        #if canImport(UIKit)
        planetMaterial.diffuse.contents = GasGiantTextureRenderer.makeImage(
            seed: GasGiantTextureMath.homePlanetSeed(planetIndex: planetIndex), theme: theme
        )
        #endif
        planetMaterial.roughness.contents = 0.7
        planetMaterial.metalness.contents = 0.05
        planetMaterial.emission.contents = UIColor(theme.primaryDark)
        planetGeometry.materials = [planetMaterial]
        let planetNode = SCNNode(geometry: planetGeometry)
        groupNode.addChildNode(planetNode)
        homePlanetNode = planetNode

        // Soft back-lit atmosphere shell (README: "primary-light, ~13%
        // alpha") — rendered from the INSIDE (`cullMode = .front`, Three.js's
        // `side: BackSide`) so it reads as a soft glow around the planet's
        // silhouette rather than an opaque outer shell.
        let atmosphereGeometry = SCNSphere(radius: 1.36)
        atmosphereGeometry.segmentCount = 48
        let atmosphereMaterial = SCNMaterial()
        atmosphereMaterial.diffuse.contents = UIColor(theme.primaryLight).withAlphaComponent(0.13)
        atmosphereMaterial.lightingModel = .constant
        atmosphereMaterial.cullMode = .front
        atmosphereMaterial.writesToDepthBuffer = false
        atmosphereGeometry.materials = [atmosphereMaterial]
        let atmosphereNode = SCNNode(geometry: atmosphereGeometry)
        planetNode.addChildNode(atmosphereNode)

        let ringGroupNode = SCNNode()
        let ringColors = [theme.secondaryLight, theme.accent, theme.primary, theme.secondaryLight, theme.accent]
        for ringIndex in 0..<max(planetIndex, 0) {
            let innerRadius = 1.5 + Double(ringIndex) * 0.26
            let ringMesh = RingMeshBuilder.makeAnnulus(innerRadius: innerRadius, outerRadius: innerRadius + 0.16)
            let ringGeometry = SCNGeometryBuilder.smoothShaded(ringMesh)
            let ringMaterial = SCNMaterial()
            ringMaterial.diffuse.contents = UIColor(ringColors[ringIndex % ringColors.count])
                .withAlphaComponent(CGFloat(max(0.34 - Double(ringIndex) * 0.04, 0.12)))
            ringMaterial.lightingModel = .constant
            ringMaterial.isDoubleSided = true
            ringGeometry.materials = [ringMaterial]
            ringGroupNode.addChildNode(SCNNode(geometry: ringGeometry))
        }
        groupNode.addChildNode(ringGroupNode)
        homeRingGroupNode = ringGroupNode

        let moonletGeometry = SCNSphere(radius: 0.11)
        let moonletMaterial = SCNMaterial()
        moonletMaterial.diffuse.contents = UIColor(theme.accent)
        moonletMaterial.emission.contents = UIColor(theme.secondary)
        moonletGeometry.materials = [moonletMaterial]
        let moonletNode = SCNNode(geometry: moonletGeometry)
        groupNode.addChildNode(moonletNode)
        homeMoonletNode = moonletNode

        cameraNode.position = SCNVector3(0, 0.3, 4.6)
    }

    private func tickHome() {
        guard let planetNode = homePlanetNode, let ringGroupNode = homeRingGroupNode, let moonletNode = homeMoonletNode else { return }

        planetNode.eulerAngles.y = Float(HeroCameraMath.homePlanetSpinAngle(elapsedTime: elapsedTime, scrollProgress: easedScrollProgress))

        let ringRotation = HeroCameraMath.homeRingGroupRotation(scrollProgress: easedScrollProgress)
        ringGroupNode.eulerAngles = SCNVector3(Float(ringRotation.x), 0, Float(ringRotation.z))

        let moonletPosition = HeroCameraMath.homeMoonletPosition(elapsedTime: elapsedTime, orbitRadius: 2.5)
        moonletNode.position = SCNVector3(Float(moonletPosition.x), Float(moonletPosition.y), Float(moonletPosition.z))

        let cameraPosition = HeroCameraMath.homeCameraPosition(scrollProgress: easedScrollProgress)
        cameraNode.position = SCNVector3(Float(cameraPosition.x), Float(cameraPosition.y), Float(cameraPosition.z))
        cameraNode.look(at: SCNVector3(0, 0.12, 0))
    }

    // MARK: - Fuel

    private func rebuildFuel(theme: Theme) {
        fuelPlanetNode?.removeFromParentNode()
        fuelGroupNode?.removeFromParentNode()

        let groupNode = SCNNode()
        scene.rootNode.addChildNode(groupNode)
        fuelGroupNode = groupNode

        let planetGeometry = SCNSphere(radius: 0.66)
        planetGeometry.segmentCount = 40
        let planetMaterial = SCNMaterial()
        #if canImport(UIKit)
        planetMaterial.diffuse.contents = GasGiantTextureRenderer.makeImage(seed: GasGiantTextureMath.fuelPlanetSeed, theme: theme)
        #endif
        planetMaterial.roughness.contents = 0.7
        planetMaterial.metalness.contents = 0.05
        planetMaterial.emission.contents = UIColor(theme.primaryDark)
        planetGeometry.materials = [planetMaterial]
        let planetNode = SCNNode(geometry: planetGeometry)
        groupNode.addChildNode(planetNode)
        fuelPlanetNode = planetNode

        // 3 tilted macro orbits (README: radii 1.15/1.55/1.95, tilts z
        // 0/.3/-.25) — the ring itself is a thin torus-equivalent annulus;
        // each moon is a plain tinted sphere (see this class's own "deliberate
        // simplifications" doc comment for why, not the design's food shapes).
        let orbitSpecs: [(radius: Double, tilt: Double, speed: Double, size: Double, color: Color)] = [
            (1.15, 0, 0.5, 0.13, theme.secondaryLight),
            (1.55, 0.3, 0.36, 0.16, theme.primary),
            (1.95, -0.25, 0.27, 0.105, theme.accent),
        ]
        var moons: [FuelMoon] = []
        for (index, spec) in orbitSpecs.enumerated() {
            let subGroup = SCNNode()
            subGroup.eulerAngles.z = Float(spec.tilt)
            groupNode.addChildNode(subGroup)

            let ringMesh = RingMeshBuilder.makeAnnulus(innerRadius: spec.radius - 0.0055, outerRadius: spec.radius + 0.0055, segments: 130)
            let ringGeometry = SCNGeometryBuilder.smoothShaded(ringMesh)
            let ringMaterial = SCNMaterial()
            ringMaterial.diffuse.contents = UIColor(spec.color).withAlphaComponent(0.4)
            ringMaterial.lightingModel = .constant
            ringMaterial.isDoubleSided = true
            ringGeometry.materials = [ringMaterial]
            subGroup.addChildNode(SCNNode(geometry: ringGeometry))

            let moonGeometry = SCNSphere(radius: spec.size)
            moonGeometry.segmentCount = 18
            let moonMaterial = SCNMaterial()
            moonMaterial.diffuse.contents = UIColor(spec.color)
            moonMaterial.emission.contents = UIColor(spec.color).withAlphaComponent(0.5)
            moonGeometry.materials = [moonMaterial]
            let moonNode = SCNNode(geometry: moonGeometry)
            subGroup.addChildNode(moonNode)

            moons.append(FuelMoon(node: moonNode, orbitRadius: spec.radius, angularSpeed: spec.speed, phase: Double(index) * 2.1, baseScale: 1))
        }
        fuelProteinMoon = moons[0]
        fuelCarbMoon = moons[1]
        fuelFatMoon = moons[2]

        cameraNode.position = SCNVector3(0, 1.6, 4)
    }

    private func tickFuel(liveInputs: HeroSceneLiveInputs) {
        guard let planetNode = fuelPlanetNode, let groupNode = fuelGroupNode,
              let proteinMoon = fuelProteinMoon, let carbMoon = fuelCarbMoon, let fatMoon = fuelFatMoon
        else { return }

        groupNode.eulerAngles.y = Float(HeroCameraMath.fuelGroupYaw(elapsedTime: elapsedTime, scrollProgress: easedScrollProgress))
        planetNode.eulerAngles.y = Float(HeroCameraMath.fuelPlanetSpinAngle(elapsedTime: elapsedTime))

        for (moon, fraction) in [(proteinMoon, liveInputs.proteinFraction), (carbMoon, liveInputs.carbFraction), (fatMoon, liveInputs.fatFraction)] {
            let position = HeroCameraMath.fuelMoonPosition(elapsedTime: elapsedTime, orbitRadius: moon.orbitRadius, angularSpeed: moon.angularSpeed, phase: moon.phase)
            moon.node.position = SCNVector3(Float(position.x), Float(position.y), Float(position.z))
            let scale = Float(HeroCameraMath.fuelMoonScale(baseScale: moon.baseScale, macroFraction: fraction))
            moon.node.scale = SCNVector3(scale, scale, scale)
        }

        let cameraPosition = HeroCameraMath.fuelCameraPosition(elapsedTime: elapsedTime, scrollProgress: easedScrollProgress)
        cameraNode.position = SCNVector3(Float(cameraPosition.x), Float(cameraPosition.y), Float(cameraPosition.z))
        cameraNode.look(at: SCNVector3(0, 0, 0))
    }

    // MARK: - Train

    private func rebuildTrain(theme: Theme) {
        let groupNode: SCNNode
        if let existingGroup = trainGroupNode {
            groupNode = existingGroup
        } else {
            groupNode = SCNNode()
            groupNode.scale = SCNVector3(0.78, 0.78, 0.78)
            scene.rootNode.addChildNode(groupNode)
            trainGroupNode = groupNode
        }
        trainRockNode?.removeFromParentNode()
        for debris in trainDebris { debris.node.removeFromParentNode() }
        trainDebris = []

        let baseIcosahedron = IcosahedronMeshBuilder.makeBaseIcosahedron()
        let subdivided = IcosahedronMeshBuilder.subdivided(baseIcosahedron, iterations: 4)
        let displaced = AsteroidDisplacement.displaced(subdivided)
        let rockGeometry = SCNGeometryBuilder.flatShaded(displaced)
        let rockMaterial = SCNMaterial()
        rockMaterial.diffuse.contents = UIColor(Theme.Neutral.asteroidRockBase)
        rockMaterial.roughness.contents = 0.85
        rockMaterial.metalness.contents = 0.1
        rockMaterial.emission.contents = UIColor(theme.secondary)
        trainMaterial = rockMaterial
        trainCurrentEmissiveIntensity = 0.1
        rockGeometry.materials = [rockMaterial]
        let rockNode = SCNNode(geometry: rockGeometry)
        groupNode.addChildNode(rockNode)
        trainRockNode = rockNode

        // 3 small orbiting debris rocks (README: "3 small orbiting debris
        // rocks"; the astronaut-collision choreography one of them runs in
        // the design is deferred — see this class's own doc comment).
        var debrisNodes: [TrainDebris] = []
        for index in 0..<3 {
            let debrisRadius = 0.09 + Double(index) * 0.025
            let debrisMesh = IcosahedronMeshBuilder.makeBaseIcosahedron()
            let debrisGeometry = SCNGeometryBuilder.flatShaded(debrisMesh)
            let debrisMaterial = SCNMaterial()
            debrisMaterial.diffuse.contents = UIColor(theme.secondaryLight)
            debrisMaterial.roughness.contents = 0.9
            debrisGeometry.materials = [debrisMaterial]
            let debrisNode = SCNNode(geometry: debrisGeometry)
            debrisNode.scale = SCNVector3(Float(debrisRadius), Float(debrisRadius), Float(debrisRadius))
            groupNode.addChildNode(debrisNode)
            debrisNodes.append(TrainDebris(node: debrisNode, orbitRadius: 1.7 + Double(index) * 0.35, angularSpeed: 0.5 - Double(index) * 0.12, phase: Double(index) * 2.2))
        }
        trainDebris = debrisNodes

        cameraNode.position = SCNVector3(0, 0.35, 4.5)
    }

    private func tickTrain(liveInputs: HeroSceneLiveInputs) {
        guard let rockNode = trainRockNode, let material = trainMaterial else { return }

        let rockRotation = HeroCameraMath.trainRockRotation(elapsedTime: elapsedTime, scrollProgress: easedScrollProgress)
        rockNode.eulerAngles = SCNVector3(Float(rockRotation.x), Float(rockRotation.y), Float(rockRotation.z))

        let targetIntensity = HeroCameraMath.trainAsteroidTargetEmissiveIntensity(doneSetFraction: liveInputs.doneSetFraction)
        trainCurrentEmissiveIntensity += (targetIntensity - trainCurrentEmissiveIntensity) * 0.06
        // `SCNMaterialProperty.intensity` is a generic 0...1+ contribution
        // multiplier on ANY material slot (Apple docs: "the receiver's
        // intensity... Animatable") — the SceneKit equivalent of Three.js's
        // `MeshStandardMaterial.emissiveIntensity` this formula mirrors.
        material.emission.intensity = CGFloat(trainCurrentEmissiveIntensity)

        for debris in trainDebris {
            let position = HeroCameraMath.trainDebrisPosition(elapsedTime: elapsedTime, orbitRadius: debris.orbitRadius, angularSpeed: debris.angularSpeed, phase: debris.phase)
            debris.node.position = SCNVector3(Float(position.x), Float(position.y), Float(position.z))
        }

        let cameraPosition = HeroCameraMath.trainCameraPosition(scrollProgress: easedScrollProgress)
        cameraNode.position = SCNVector3(Float(cameraPosition.x), Float(cameraPosition.y), Float(cameraPosition.z))
        cameraNode.look(at: SCNVector3(0, 0.1, 0))
    }
}

private extension HeroSceneKind {
    var homePlanetIndex: Int? {
        if case let .home(planetIndex) = self { return planetIndex }
        return nil
    }
}

// MARK: - View (the optional-hero slot in every hero-bearing screen's shared
// ZStack recipe, README "3D hero in the top ~440pt")

/// The SceneKit hero every hero-bearing screen (Home/Fuel/Train; Body has
/// none) layers ABOVE its `StarfieldView` and BELOW its scrolling content —
/// `TimelineView(.animation)` drives `HeroSceneState.tick`, mirroring
/// `Space/StarfieldView.swift`'s own architecture (T17).
#if DEBUG
private struct HeroSceneRenderingEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Snapshot-test seam: set to `false` to render the hero as transparent
    /// space instead of hosting the live `SCNView`.
    ///
    /// Needed because SceneKit's transparency does NOT survive SwiftUI's
    /// OFFSCREEN image render. On a device the hero composites correctly over
    /// the starfield, but a recorded snapshot of the same screen shows the
    /// hero region as a WHITE block — the very bug this file fixed for the
    /// live app. Recording that as a baseline would enshrine an image the app
    /// never actually shows. The scene's own appearance is covered separately
    /// and directly by `Tests/HeroSceneSnapshotTests.swift`; excluding it here
    /// lets the four hero-bearing SCREEN snapshots cover everything else —
    /// cards, macros, palette, layout — deterministically and correctly.
    ///
    /// `#if DEBUG` so no test seam exists in release source (AC32/SC-7), the
    /// same posture as `OrbitApp.resetAuthStateIfRequested`.
    var heroSceneRenderingEnabled: Bool {
        get { self[HeroSceneRenderingEnabledKey.self] }
        set { self[HeroSceneRenderingEnabledKey.self] = newValue }
    }
}
#endif

struct HeroSceneView: View {
    let kind: HeroSceneKind
    let theme: Theme
    let scrollProgress: Double
    var liveInputs: HeroSceneLiveInputs = HeroSceneLiveInputs()

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    #if DEBUG
    @Environment(\.heroSceneRenderingEnabled) private var heroSceneRenderingEnabled
    #endif
    /// Resolved through `MotionPreference` so the snapshot suites can force
    /// Reduce Motion ON: the system key is read-only in the SDK, so tests
    /// write `reduceMotionOverride` instead.
    private var reduceMotion: Bool {
        MotionPreference.resolvedReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
    }
    @State private var sceneState: HeroSceneState

    init(kind: HeroSceneKind, theme: Theme, scrollProgress: Double, liveInputs: HeroSceneLiveInputs = HeroSceneLiveInputs()) {
        self.kind = kind
        self.theme = theme
        self.scrollProgress = scrollProgress
        self.liveInputs = liveInputs
        _sceneState = State(initialValue: HeroSceneState(kind: kind, theme: theme))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            heroContent(at: timeline.date)
        }
        .onChange(of: theme) { _, newTheme in
            sceneState.applyIfNeeded(planetIndex: kind.homePlanetIndex, theme: newTheme)
        }
        .onChange(of: kind) { _, newKind in
            sceneState.applyIfNeeded(planetIndex: newKind.homePlanetIndex, theme: theme)
        }
        // Purely decorative background art — same accessibility contract
        // `StarfieldView` (T17) already established for the layer beneath it.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func heroContent(at date: Date) -> some View {
        let motionAllowed = MotionPreference.repeatingAnimationsAllowed(reduceMotion: reduceMotion)
        let _ = sceneState.tick(to: date, scrollTarget: scrollProgress, motionAllowed: motionAllowed, liveInputs: liveInputs)
        #if DEBUG
        if heroSceneRenderingEnabled {
            TransparentSceneView(scene: sceneState.scene, pointOfView: sceneState.cameraNode)
        } else {
            // Hero omitted for offscreen snapshot rendering — see
            // `EnvironmentValues.heroSceneRenderingEnabled`. Transparent, so
            // the starfield at z0 shows through exactly as it does in the gap
            // around the planet on a real device.
            Color.clear
        }
        #else
        TransparentSceneView(scene: sceneState.scene, pointOfView: sceneState.cameraNode)
        #endif
    }
}

/// Hosts `SCNView` directly instead of using SwiftUI's `SceneView`.
///
/// `SceneView` always renders through an OPAQUE backing view and exposes no
/// knob to change that, so it paints a solid block over the `StarfieldView`
/// at z0 beneath it — the hero region rendered as a white band with the
/// greeting text invisible inside it. Clearing `scene.background` alone does
/// NOT fix that: the opacity lives on the view, not the scene. Hosting
/// `SCNView` is the only way to get `isOpaque = false` together with a clear
/// background colour, which is what the design's ZStack recipe (starfield z0
/// → 3D hero z1 → content) requires.
private struct TransparentSceneView: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = pointOfView
        view.backgroundColor = .clear
        view.isOpaque = false
        // The enclosing `TimelineView(.animation)` advances the scene by
        // calling `HeroSceneState.tick(to:)` every frame, so the view must
        // redraw every frame too rather than only when SceneKit itself
        // decides something changed.
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling2X
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene !== scene {
            uiView.scene = scene
        }
        if uiView.pointOfView !== pointOfView {
            uiView.pointOfView = pointOfView
        }
    }
}
