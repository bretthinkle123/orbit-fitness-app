import Foundation
import Testing
@testable import Orbit

/// T18's pure-logic slice: `GasGiantTextureMath`'s recipe determinism +
/// per-layer parameter bounds, `IcosahedronMeshBuilder`/`AsteroidDisplacement`'s
/// mesh-generation determinism + displacement bounds, and `HeroCameraMath`'s
/// per-scene camera-position-from-scroll-offset formulas — every numeric
/// bound below copied directly from `Space/Textures.swift`/`HeroSceneView.swift`'s
/// own doc comments (which themselves cite the exact `Orbit Fitness.dc.html`
/// formula each mirrors), the same discipline `Tests/SpaceTests.swift` (T17)
/// established for the starfield's own pure-logic half.
///
/// **Authored, not compiled, on this host** (`.pipeline/implementation-
/// progress.md` T11-T17): no Swift toolchain exists here. Genuine `swift
/// test` execution is the operator's Mac phase.
@Suite("GasGiantTextureRNG — the design's own LCG, replicated exactly")
struct GasGiantTextureRNGTests {
    @Test("Same seed produces the exact same sequence of values")
    func sameSeedIsDeterministic() {
        var first = GasGiantTextureRNG(seed: 3)
        var second = GasGiantTextureRNG(seed: 3)
        let firstSequence = (0..<20).map { _ in first.next() }
        let secondSequence = (0..<20).map { _ in second.next() }
        #expect(firstSequence == secondSequence)
    }

    @Test("Different seeds produce different sequences", arguments: [(3, 12), (11, 19), (5, 7)])
    func differentSeedsDiffer(seeds: (Int, Int)) {
        var first = GasGiantTextureRNG(seed: seeds.0)
        var second = GasGiantTextureRNG(seed: seeds.1)
        let firstSequence = (0..<10).map { _ in first.next() }
        let secondSequence = (0..<10).map { _ in second.next() }
        #expect(firstSequence != secondSequence)
    }

    @Test("Every value stays within 0..<1", arguments: [3, 7, 11, 12, 19, 21])
    func valuesStayInUnitRange(seed: Int) {
        var rng = GasGiantTextureRNG(seed: seed)
        for _ in 0..<500 {
            let value = rng.next()
            #expect(value >= 0 && value < 1)
        }
    }

    @Test("A DIFFERENT sequence than StarfieldRNG for the same seed (two distinct generators, not one shared)")
    func differsFromStarfieldRNGForTheSameSeed() {
        var gasGiantRNG = GasGiantTextureRNG(seed: 5)
        var starfieldRNG = StarfieldRNG(seed: 5)
        let gasGiantSequence = (0..<5).map { _ in gasGiantRNG.next() }
        let starfieldSequence = (0..<5).map { _ in starfieldRNG.next() }
        #expect(gasGiantSequence != starfieldSequence)
    }
}

@Suite("GasGiantTextureMath — recipe determinism + layer parameter bounds")
struct GasGiantTextureMathTests {
    @Test("Same seed → identical band+storm recipe (byte-for-byte)")
    func sameSeedProducesIdenticalRecipe() {
        let first = GasGiantTextureMath.generateRecipe(seed: 5)
        let second = GasGiantTextureMath.generateRecipe(seed: 5)
        #expect(first.bands == second.bands)
        #expect(first.storms == second.storms)
    }

    @Test("Different planet-index seeds produce different recipes", arguments: [
        (GasGiantTextureMath.homePlanetSeed(planetIndex: 0), GasGiantTextureMath.homePlanetSeed(planetIndex: 1)),
        (GasGiantTextureMath.homePlanetSeed(planetIndex: 2), GasGiantTextureMath.fuelPlanetSeed),
    ])
    func differentSeedsProduceDifferentRecipes(seeds: (Int, Int)) {
        let first = GasGiantTextureMath.generateRecipe(seed: seeds.0)
        let second = GasGiantTextureMath.generateRecipe(seed: seeds.1)
        #expect(first.bands != second.bands)
    }

    @Test("Exactly 4 storms, matching _gasTex's own fixed loop count")
    func fixedStormCount() {
        let recipe = GasGiantTextureMath.generateRecipe(seed: 5)
        #expect(recipe.storms.count == GasGiantTextureMath.stormCount)
        #expect(recipe.storms.count == 4)
    }

    @Test("Storm highlight tint alternates by index parity (i % 2)")
    func stormHighlightAlternatesByParity() {
        let recipe = GasGiantTextureMath.generateRecipe(seed: 5)
        for (index, storm) in recipe.storms.enumerated() {
            #expect(storm.usesAccentHighlight == (index % 2 == 1))
        }
    }

    @Test("Band height/alpha/colorIndex stay within the design's own numeric ranges", arguments: [3, 5, 7, 11, 12, 19])
    func bandParametersStayInBounds(seed: Int) {
        let recipe = GasGiantTextureMath.generateRecipe(seed: seed)
        #expect(!recipe.bands.isEmpty)
        for band in recipe.bands {
            #expect(band.fillHeight >= 7.5 && band.fillHeight <= 31.5, "fillHeight \(band.fillHeight) out of bounds")
            #expect(band.alpha >= 0.5 && band.alpha <= 1.0, "alpha \(band.alpha) out of bounds")
            #expect(band.colorIndex >= 0 && band.colorIndex < GasGiantTextureMath.bandColorCount, "colorIndex \(band.colorIndex) out of bounds")
        }
    }

    @Test("Storm center/radius/highlightAlpha stay within the design's own numeric ranges", arguments: [3, 5, 7, 11])
    func stormParametersStayInBounds(seed: Int) {
        let recipe = GasGiantTextureMath.generateRecipe(seed: seed)
        for storm in recipe.storms {
            #expect(storm.centerX >= 80 && storm.centerX <= 430, "centerX \(storm.centerX) out of bounds")
            #expect(storm.centerY >= 60 && storm.centerY <= 200, "centerY \(storm.centerY) out of bounds")
            #expect(storm.radiusX >= 15 && storm.radiusX <= 39, "radiusX \(storm.radiusX) out of bounds")
            #expect(storm.radiusY >= 6 && storm.radiusY <= 16, "radiusY \(storm.radiusY) out of bounds")
            #expect(storm.highlightAlpha >= 0.4 && storm.highlightAlpha <= 0.7, "highlightAlpha \(storm.highlightAlpha) out of bounds")
        }
    }

    @Test("Row-shear offset stays within ±36 (10+26) at every row, for every seed", arguments: [3, 5, 7, 11])
    func rowShearOffsetStaysInBounds(seed: Int) {
        for row in stride(from: 0, to: GasGiantTextureMath.textureHeight, by: 7) {
            let offset = GasGiantTextureMath.rowShearOffset(row: row, seed: seed)
            #expect(offset >= -36 && offset <= 36, "row \(row) offset \(offset) out of bounds")
        }
    }

    @Test("Home planet seed formula: 5 + 9*planetIndex")
    func homePlanetSeedFormula() {
        #expect(GasGiantTextureMath.homePlanetSeed(planetIndex: 0) == 5)
        #expect(GasGiantTextureMath.homePlanetSeed(planetIndex: 2) == 23)
        #expect(GasGiantTextureMath.homePlanetSeed(planetIndex: 5) == 50)
    }

    @Test("Fuel planet always uses the fixed seed 11, never the home formula")
    func fuelPlanetSeedIsFixed() {
        #expect(GasGiantTextureMath.fuelPlanetSeed == 11)
    }
}

@Suite("IcosahedronMeshBuilder — base shape + subdivision")
struct IcosahedronMeshBuilderTests {
    @Test("The base icosahedron has exactly 12 vertices and 20 faces (60 indices)")
    func baseIcosahedronHasStandardCounts() {
        let mesh = IcosahedronMeshBuilder.makeBaseIcosahedron()
        #expect(mesh.positions.count == 12)
        #expect(mesh.indices.count == 60) // 20 faces * 3
    }

    @Test("Every base vertex lies on the unit sphere (length 1)")
    func baseVerticesAreUnitLength() {
        let mesh = IcosahedronMeshBuilder.makeBaseIcosahedron()
        for vertex in mesh.positions {
            let length = (vertex.x * vertex.x + vertex.y * vertex.y + vertex.z * vertex.z).squareRoot()
            #expect(abs(length - 1) < 0.0001, "vertex length \(length) not unit")
        }
    }

    @Test("Subdividing 0 times returns the mesh unchanged")
    func zeroIterationsIsANoOp() {
        let base = IcosahedronMeshBuilder.makeBaseIcosahedron()
        let subdivided = IcosahedronMeshBuilder.subdivided(base, iterations: 0)
        #expect(subdivided == base)
    }

    @Test("Each subdivision round quadruples the face count and every new vertex stays on the unit sphere")
    func subdivisionQuadruplesFacesAndStaysUnitLength() {
        let base = IcosahedronMeshBuilder.makeBaseIcosahedron()
        let onceSubdivided = IcosahedronMeshBuilder.subdivided(base, iterations: 1)
        #expect(onceSubdivided.indices.count == base.indices.count * 4)
        for vertex in onceSubdivided.positions {
            let length = (vertex.x * vertex.x + vertex.y * vertex.y + vertex.z * vertex.z).squareRoot()
            #expect(abs(length - 1) < 0.0001, "vertex length \(length) not unit")
        }
    }

    @Test("Subdividing 4 times (Train's asteroid, README) produces the expected face count with no seams (shared edge vertices deduplicated)")
    func fourSubdivisionsMatchesDesignSpec() {
        let base = IcosahedronMeshBuilder.makeBaseIcosahedron()
        let subdivided = IcosahedronMeshBuilder.subdivided(base, iterations: 4)
        // 20 faces * 4^4 = 5120 faces = 15360 indices.
        #expect(subdivided.indices.count == 15360)
        // A seamless icosphere at subdivision N has exactly 10*4^N + 2 vertices
        // (Euler's formula for a closed triangulated sphere) — asserting this
        // exact count is the strongest possible proof the edge-midpoint cache
        // is deduplicating correctly (a seam bug would inflate this count).
        #expect(subdivided.positions.count == 10 * 4 * 4 * 4 * 4 + 2)
    }
}

@Suite("AsteroidDisplacement — the design's own ridged-noise formula")
struct AsteroidDisplacementTests {
    @Test("Displacement magnitude stays within the formula's own analytic bounds [1-0.17-0.05, 1+0.17+0.05]", arguments: [
        SIMD3<Double>(1, 0, 0), SIMD3<Double>(0, 1, 0), SIMD3<Double>(0, 0, 1),
        SIMD3<Double>(0.577, 0.577, 0.577), SIMD3<Double>(-0.577, 0.577, -0.577),
    ])
    func magnitudeStaysInBounds(unit: SIMD3<Double>) {
        let magnitude = AsteroidDisplacement.magnitude(unit: unit)
        #expect(magnitude >= 0.78 && magnitude <= 1.22, "magnitude \(magnitude) out of bounds")
    }

    @Test("Displacing a mesh keeps every vertex's DIRECTION but scales its length by magnitude(unit:)")
    func displacementPreservesDirectionAndScalesLength() {
        let base = IcosahedronMeshBuilder.makeBaseIcosahedron()
        let displaced = AsteroidDisplacement.displaced(base)
        #expect(displaced.indices == base.indices)
        for (original, result) in zip(base.positions, displaced.positions) {
            let expectedMagnitude = AsteroidDisplacement.magnitude(unit: original)
            let resultLength = (result.x * result.x + result.y * result.y + result.z * result.z).squareRoot()
            #expect(abs(resultLength - expectedMagnitude) < 0.0001)
        }
    }
}

@Suite("RingMeshBuilder — flat annulus geometry")
struct RingMeshBuilderTests {
    @Test("Every vertex lies at either the inner or the outer radius (a flat ring, no vertex in between)")
    func verticesLieOnInnerOrOuterRadius() {
        let mesh = RingMeshBuilder.makeAnnulus(innerRadius: 1.5, outerRadius: 1.66, segments: 8)
        for vertex in mesh.positions {
            let radius = (vertex.x * vertex.x + vertex.z * vertex.z).squareRoot()
            let matchesInner = abs(radius - 1.5) < 0.0001
            let matchesOuter = abs(radius - 1.66) < 0.0001
            #expect(matchesInner || matchesOuter, "radius \(radius) matches neither inner nor outer")
            #expect(vertex.y == 0, "ring must lie flat in the XZ plane")
        }
    }
}

@Suite("HeroCameraMath — per-scene scroll/time-driven camera formulas, ported verbatim from _loop()")
struct HeroCameraMathTests {
    // MARK: Home

    @Test("Home camera pulls in z (4.6 -> 4.05) and rises in y as scroll goes 0 -> 1")
    func homeCameraPullsInAndRisesWithScroll() {
        let atTop = HeroCameraMath.homeCameraPosition(scrollProgress: 0)
        let atBottom = HeroCameraMath.homeCameraPosition(scrollProgress: 1)
        #expect(atTop.z == 4.6)
        #expect(abs(atBottom.z - 4.05) < 0.0001)
        #expect(atTop.y == 0.3)
        #expect(abs(atBottom.y - 0.65) < 0.0001)
    }

    @Test("Home planet spin advances with BOTH elapsed time and scroll")
    func homePlanetSpinAdvancesWithTimeAndScroll() {
        let atStart = HeroCameraMath.homePlanetSpinAngle(elapsedTime: 0, scrollProgress: 0)
        let afterTime = HeroCameraMath.homePlanetSpinAngle(elapsedTime: 10, scrollProgress: 0)
        let afterScroll = HeroCameraMath.homePlanetSpinAngle(elapsedTime: 0, scrollProgress: 1)
        #expect(atStart == 0)
        #expect(afterTime > atStart)
        #expect(afterScroll > atStart)
    }

    @Test("Home ring-group tilt eases from .42/.16 toward .08/.46 as scroll goes 0 -> 1")
    func homeRingGroupTiltEasesWithScroll() {
        let atTop = HeroCameraMath.homeRingGroupRotation(scrollProgress: 0)
        let atBottom = HeroCameraMath.homeRingGroupRotation(scrollProgress: 1)
        #expect(abs(atTop.x - 0.42) < 0.0001)
        #expect(abs(atBottom.x - 0.08) < 0.0001)
        #expect(abs(atTop.z - 0.16) < 0.0001)
        #expect(abs(atBottom.z - 0.46) < 0.0001)
    }

    // MARK: Fuel

    @Test("Fuel camera descends from top-down (y 1.6) toward edge-on (y 0.2) as scroll goes 0 -> 1")
    func fuelCameraDescendsWithScroll() {
        let atTop = HeroCameraMath.fuelCameraPosition(elapsedTime: 0, scrollProgress: 0)
        let atBottom = HeroCameraMath.fuelCameraPosition(elapsedTime: 0, scrollProgress: 1)
        #expect(atTop.y == 1.6)
        #expect(abs(atBottom.y - 0.2) < 0.0001)
    }

    @Test("Fuel moon scale increases monotonically with macro fraction (0...1) at pulse 0")
    func fuelMoonScaleIncreasesWithMacroFraction() {
        let empty = HeroCameraMath.fuelMoonScale(baseScale: 1, macroFraction: 0)
        let full = HeroCameraMath.fuelMoonScale(baseScale: 1, macroFraction: 1)
        #expect(abs(empty - 0.78) < 0.0001)
        #expect(abs(full - 1.28) < 0.0001)
        #expect(full > empty)
    }

    // MARK: Train

    @Test("Train camera orbits azimuth on a fixed radius (4.5) as scroll goes 0 -> 1")
    func trainCameraOrbitsAtFixedRadius() {
        for scrollProgress in stride(from: 0.0, through: 1.0, by: 0.1) {
            let position = HeroCameraMath.trainCameraPosition(scrollProgress: scrollProgress)
            let radius = (position.x * position.x + position.z * position.z).squareRoot()
            #expect(abs(radius - 4.5) < 0.0001, "radius \(radius) at scroll \(scrollProgress)")
        }
    }

    @Test("Train asteroid target emissive intensity rises from .1 (no sets done) toward 1.7 (all 16 done)")
    func trainTargetEmissiveIntensityFormula() {
        #expect(HeroCameraMath.trainAsteroidTargetEmissiveIntensity(doneSetFraction: 0) == 0.1)
        #expect(abs(HeroCameraMath.trainAsteroidTargetEmissiveIntensity(doneSetFraction: 1) - 1.7) < 0.0001)
    }
}

@Suite("HeroScrollProgress — normalized 0...1 derivation + guard against not-yet-scrollable content")
struct HeroScrollProgressTests {
    @Test("Not-yet-scrollable content (content <= viewport) always normalizes to 0")
    func notYetScrollableNormalizesToZero() {
        var progress = HeroScrollProgress.zero
        progress.viewportHeight = 800
        progress.contentHeight = 800
        progress.offsetFromTop = 50 // should never happen physically, but must not divide-by-zero/negative
        #expect(progress.normalized == 0)
    }

    @Test("Halfway-scrolled content normalizes to 0.5")
    func halfwayScrolledNormalizesToHalf() {
        var progress = HeroScrollProgress.zero
        progress.viewportHeight = 800
        progress.contentHeight = 1600
        progress.offsetFromTop = 400
        #expect(abs(progress.normalized - 0.5) < 0.0001)
    }

    @Test("Normalized value is clamped to 1 even if offset overshoots the scrollable extent")
    func normalizedClampsToOne() {
        var progress = HeroScrollProgress.zero
        progress.viewportHeight = 800
        progress.contentHeight = 1600
        progress.offsetFromTop = 5000
        #expect(progress.normalized == 1)
    }
}

@Suite("HeroScrollMotionGate — Reduce Motion freezes the scroll TARGET, not elapsed time")
struct HeroScrollMotionGateTests {
    @Test("Motion allowed: returns the LIVE target")
    func motionAllowedReturnsLiveTarget() {
        let result = HeroScrollMotionGate.effectiveScrollTarget(liveTarget: 0.8, lastAllowedTarget: 0.2, motionAllowed: true)
        #expect(result == 0.8)
    }

    @Test("Motion NOT allowed: returns the LAST allowed target (frozen in place, never reset to 0)")
    func motionNotAllowedReturnsLastAllowedTarget() {
        let result = HeroScrollMotionGate.effectiveScrollTarget(liveTarget: 0.9, lastAllowedTarget: 0.35, motionAllowed: false)
        #expect(result == 0.35)
        #expect(result != 0)
    }
}
