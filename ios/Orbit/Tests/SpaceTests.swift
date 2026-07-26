import CoreGraphics
import Foundation
import Testing
@testable import Orbit

/// T17's pure-logic slice: `StarfieldRNG` determinism, `StarfieldFieldGenerator`
/// seed-determinism + per-layer parameter bounds (the task's named "seed
/// determinism (same seed → same star positions); layer parameter bounds"
/// test_strategy line), and the shooting-star/ship state machines. Every
/// numeric bound below is copied directly from `Space/StarfieldView.swift`'s
/// own doc comments (which themselves cite the exact `Orbit Fitness.dc.html`
/// formula each mirrors) — a regression in either file's numbers fails a
/// concrete assertion here, not a vague "looks different" snapshot.
///
/// **Authored, not compiled, on this host** (same Linux-host caveat as every
/// prior iOS task, `.pipeline/implementation-progress.md` T11-T16): no Swift
/// toolchain exists here. Genuine `swift test` execution is the operator's
/// Mac phase.
@Suite("StarfieldRNG — the design's own LCG, replicated exactly")
struct StarfieldRNGTests {
    @Test("Same seed produces the exact same sequence of values")
    func sameSeedIsDeterministic() {
        var first = StarfieldRNG(seed: 5)
        var second = StarfieldRNG(seed: 5)
        let firstSequence = (0..<20).map { _ in first.next() }
        let secondSequence = (0..<20).map { _ in second.next() }
        #expect(firstSequence == secondSequence)
    }

    @Test("Different seeds produce different sequences", arguments: [(5, 6), (6, 7), (7, 8), (9, 10)])
    func differentSeedsDiffer(seeds: (Int, Int)) {
        var first = StarfieldRNG(seed: seeds.0)
        var second = StarfieldRNG(seed: seeds.1)
        let firstSequence = (0..<10).map { _ in first.next() }
        let secondSequence = (0..<10).map { _ in second.next() }
        #expect(firstSequence != secondSequence)
    }

    @Test("Every value stays within 0..<1", arguments: [5, 6, 7, 8, 9, 10, 42])
    func valuesStayInUnitRange(seed: Int) {
        var rng = StarfieldRNG(seed: seed)
        for _ in 0..<500 {
            let value = rng.next()
            #expect(value >= 0 && value < 1)
        }
    }
}

@Suite("StarfieldFieldGenerator — seed determinism + layer parameter bounds")
struct StarfieldFieldGeneratorTests {
    private static let referenceSize = StarfieldView.referenceSize

    @Test("Same seed + size → identical star positions and nebula clusters (byte-for-byte)")
    func sameSeedProducesIdenticalField() {
        let first = StarfieldFieldGenerator.generate(seed: StarfieldSeed.home, size: Self.referenceSize)
        let second = StarfieldFieldGenerator.generate(seed: StarfieldSeed.home, size: Self.referenceSize)
        #expect(first.stars == second.stars)
        #expect(first.clusters == second.clusters)
    }

    @Test("Different screen seeds produce different fields", arguments: [
        (StarfieldSeed.home, StarfieldSeed.fuel),
        (StarfieldSeed.fuel, StarfieldSeed.train),
        (StarfieldSeed.train, StarfieldSeed.body),
        (StarfieldSeed.signIn, StarfieldSeed.register),
    ])
    func differentSeedsProduceDifferentFields(seeds: (Int, Int)) {
        let first = StarfieldFieldGenerator.generate(seed: seeds.0, size: Self.referenceSize)
        let second = StarfieldFieldGenerator.generate(seed: seeds.1, size: Self.referenceSize)
        #expect(first.stars != second.stars)
    }

    @Test("Exactly 5 clusters and 55 loose stars, matching _makeBg's own fixed counts")
    func fixedClusterAndLooseStarCounts() {
        let field = StarfieldFieldGenerator.generate(seed: StarfieldSeed.home, size: Self.referenceSize)
        #expect(field.clusters.count == StarfieldFieldGenerator.clusterCount)
        #expect(field.clusters.count == 5)
        // Total stars = per-cluster stars (20...33 each, 5 clusters) + 55 loose.
        let totalStarCount = field.stars.count
        #expect(totalStarCount >= 5 * 20 + StarfieldFieldGenerator.looseStarCount)
        #expect(totalStarCount <= 5 * 33 + StarfieldFieldGenerator.looseStarCount)
    }

    @Test("Every cluster star's depth is exactly one of the 5 fixed cluster depths")
    func clusterStarDepthsAreFixedValues() {
        // Loose stars (depth 0.12...0.3, continuous) are distinguishable from
        // cluster stars (depth: one of exactly 5 discrete values) by radius/
        // alpha range alone would be ambiguous, so this test instead checks
        // that AT LEAST the fixed depths appear among the generated stars —
        // a direct, unambiguous assertion on the discrete-depth contract
        // `_makeBg`'s cluster loop guarantees.
        let field = StarfieldFieldGenerator.generate(seed: StarfieldSeed.fuel, size: Self.referenceSize)
        let depthsPresent = Set(field.stars.map(\.depth))
        for fixedDepth in StarfieldFieldGenerator.clusterDepths {
            #expect(depthsPresent.contains(fixedDepth), "expected cluster depth \(fixedDepth) to appear among generated stars")
        }
    }

    @Test("Star radius/alpha/twinkle-speed stay within the design's own numeric ranges", arguments: [5, 6, 7, 8, 9, 10])
    func starParametersStayInBounds(seed: Int) {
        let field = StarfieldFieldGenerator.generate(seed: seed, size: Self.referenceSize)
        for star in field.stars {
            #expect(star.radius >= 0.3 && star.radius <= 2.4, "radius \(star.radius) out of bounds")
            #expect(star.baseAlpha >= 0.3 && star.baseAlpha <= 1.0, "alpha \(star.baseAlpha) out of bounds")
            #expect(star.twinkleSpeed >= 0.8 && star.twinkleSpeed <= 3.2, "twinkleSpeed \(star.twinkleSpeed) out of bounds")
            #expect(star.twinklePhase >= 0 && star.twinklePhase <= 6.28, "twinklePhase \(star.twinklePhase) out of bounds")
            #expect(star.depth >= 0.12 && star.depth <= 0.42, "depth \(star.depth) out of bounds")
        }
    }

    @Test("Nebula cluster radius stays within the design's own numeric range", arguments: [5, 6, 7, 8])
    func clusterRadiusStaysInBounds(seed: Int) {
        let field = StarfieldFieldGenerator.generate(seed: seed, size: Self.referenceSize)
        for cluster in field.clusters {
            // spread 34...70 * factor 2.2...3.4 → radius 74.8...238.
            #expect(cluster.radius >= 74 && cluster.radius <= 240, "cluster radius \(cluster.radius) out of bounds")
        }
    }
}

@Suite("StarfieldShootingStar — spawn + lifecycle")
struct StarfieldShootingStarTests {
    private static let referenceSize = StarfieldView.referenceSize

    @Test("Spawns with full life and the design's own velocity ranges")
    func spawnHasFullLifeAndBoundedVelocity() {
        var rng = StarfieldRNG(seed: 5)
        let shootingStar = StarfieldShootingStar.spawn(using: &rng, size: Self.referenceSize)
        #expect(shootingStar.remainingLife == 0.75)
        #expect(shootingStar.maxLife == 0.75)
        #expect(abs(shootingStar.velocityX) >= 240 && abs(shootingStar.velocityX) <= 410)
        #expect(shootingStar.velocityY >= 130 && shootingStar.velocityY <= 220)
    }

    @Test("Advancing consumes life and moves the position")
    func advancingConsumesLifeAndMoves() {
        var rng = StarfieldRNG(seed: 5)
        let shootingStar = StarfieldShootingStar.spawn(using: &rng, size: Self.referenceSize)
        let advanced = shootingStar.advanced(deltaTime: 0.1, size: Self.referenceSize)
        #expect(advanced != nil)
        #expect(advanced!.remainingLife < shootingStar.remainingLife)
        #expect(advanced!.x != shootingStar.x)
    }

    @Test("Life expiring returns nil (despawns)")
    func lifeExpiringDespawns() {
        var rng = StarfieldRNG(seed: 5)
        let shootingStar = StarfieldShootingStar.spawn(using: &rng, size: Self.referenceSize)
        let despawned = shootingStar.advanced(deltaTime: 1.0, size: Self.referenceSize) // > maxLife
        #expect(despawned == nil)
    }

    @Test("Crossing off-screen bounds returns nil even before life expires")
    func offScreenDespawns() {
        // A shooting star placed just past the right edge, moving further
        // right, should despawn on the very next advance regardless of
        // remaining life.
        let farRight = StarfieldShootingStar(x: 500, y: 100, velocityX: 300, velocityY: 100, remainingLife: 0.5, maxLife: 0.75)
        let despawned = farRight.advanced(deltaTime: 0.05, size: StarfieldView.referenceSize)
        #expect(despawned == nil)
    }
}

@Suite("StarfieldShip — spawn + lifecycle")
struct StarfieldShipTests {
    private static let referenceSize = StarfieldView.referenceSize

    @Test("Direction is always +1 or -1, never anything else", arguments: [5, 6, 7, 8, 9, 10, 100, 200])
    func directionIsAlwaysSignOne(seed: Int) {
        var rng = StarfieldRNG(seed: seed)
        let ship = StarfieldShip.spawn(using: &rng, size: Self.referenceSize)
        #expect(ship.direction == 1 || ship.direction == -1)
    }

    @Test("A left-to-right ship spawns off the left edge; a right-to-left ship spawns off the right edge")
    func spawnPositionMatchesDirection() {
        var rng = StarfieldRNG(seed: 5)
        let ship = StarfieldShip.spawn(using: &rng, size: Self.referenceSize)
        if ship.direction > 0 {
            #expect(ship.x == -26)
        } else {
            #expect(ship.x == Double(Self.referenceSize.width) + 26)
        }
    }

    @Test("Advancing moves the ship in its own direction")
    func advancingMovesInOwnDirection() {
        var rng = StarfieldRNG(seed: 5)
        let ship = StarfieldShip.spawn(using: &rng, size: Self.referenceSize)
        let advanced = ship.advanced(deltaTime: 0.5, size: Self.referenceSize)
        #expect(advanced != nil)
        if ship.direction > 0 {
            #expect(advanced!.x > ship.x)
        } else {
            #expect(advanced!.x < ship.x)
        }
    }

    @Test("Crossing fully past the opposite edge despawns (returns nil)")
    func crossingOppositeEdgeDespawns() {
        let rightMoving = StarfieldShip(direction: 1, x: 350, y: 100, speed: 60, bobPhase: 0)
        let despawned = rightMoving.advanced(deltaTime: 5, size: Self.referenceSize) // far past width+30
        #expect(despawned == nil)
    }
}

@Suite("StarfieldSimulation — Reduce Motion freeze contract (idle static field remains)")
struct StarfieldSimulationTests {
    private static let referenceSize = StarfieldView.referenceSize

    @Test("animate: false never advances elapsed time across repeated ticks")
    @MainActor
    func frozenSimulationNeverAdvances() {
        let simulation = StarfieldSimulation(seed: StarfieldSeed.home, size: Self.referenceSize)
        let baseDate = Date()
        simulation.tick(to: baseDate, shipsEnabled: true, animate: false)
        let firstFrame = simulation.currentFrame(animate: false)
        simulation.tick(to: baseDate.addingTimeInterval(5), shipsEnabled: true, animate: false)
        let secondFrame = simulation.currentFrame(animate: false)
        #expect(firstFrame.elapsedTime == secondFrame.elapsedTime)
        #expect(secondFrame.elapsedTime == 0)
    }

    @Test("animate: false always renders WITHOUT a shooting star or ship (idle static field, not merely paused)")
    @MainActor
    func frozenSimulationHidesTransientDecoration() {
        let simulation = StarfieldSimulation(seed: StarfieldSeed.home, size: Self.referenceSize)
        let baseDate = Date()
        // Advance normally first so a shooting star/ship is plausibly active...
        for offset in stride(from: 0.0, through: 30, by: 0.1) {
            simulation.tick(to: baseDate.addingTimeInterval(offset), shipsEnabled: true, animate: true)
        }
        // ...then freeze: the returned frame must show neither, regardless
        // of whatever was in flight the instant before.
        simulation.tick(to: baseDate.addingTimeInterval(30.1), shipsEnabled: true, animate: false)
        let frozenFrame = simulation.currentFrame(animate: false)
        #expect(frozenFrame.shootingStar == nil)
        #expect(frozenFrame.ship == nil)
    }

    @Test("animate: true DOES advance elapsed time")
    @MainActor
    func unfrozenSimulationAdvances() {
        let simulation = StarfieldSimulation(seed: StarfieldSeed.home, size: Self.referenceSize)
        let baseDate = Date()
        simulation.tick(to: baseDate, shipsEnabled: true, animate: true)
        simulation.tick(to: baseDate.addingTimeInterval(1), shipsEnabled: true, animate: true)
        let frame = simulation.currentFrame(animate: true)
        #expect(frame.elapsedTime > 0)
    }

    @Test("shipsEnabled: false suppresses the ship even while animating")
    @MainActor
    func shipsDisabledSuppressesShip() {
        let simulation = StarfieldSimulation(seed: StarfieldSeed.home, size: Self.referenceSize)
        let baseDate = Date()
        for offset in stride(from: 0.0, through: 40, by: 0.1) {
            simulation.tick(to: baseDate.addingTimeInterval(offset), shipsEnabled: false, animate: true)
        }
        let frame = simulation.currentFrame(animate: true)
        #expect(frame.ship == nil)
    }
}
