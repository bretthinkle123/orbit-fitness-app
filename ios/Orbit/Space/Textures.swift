import CoreGraphics
import Foundation
import SceneKit
import simd
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Gas-giant procedural texture (T18, README "3D & Animated
// Background" §, `Orbit Fitness.dc.html`'s `_gasTex(seed)` ported verbatim —
// same "port the design's own formula bit-for-bit" discipline
// `Space/StarfieldView.swift` (T17) established for `_makeBg`.)

/// The LCG `_gasTex` seeds and steps — DELIBERATELY a separate type from
/// `StarfieldRNG` (`Space/StarfieldView.swift`): the design itself uses two
/// distinct seed transforms for its two distinct generators (`_makeBg`'s own
/// `sd = seed*7919+133`; `_gasTex`'s own `sd = seed*4241+97` — same
/// recurrence step, `(sd*9301+49297)%233280`, different seed formula), so
/// unifying them into one type would silently change which sequence a given
/// seed produces relative to the design's own two independent generators.
struct GasGiantTextureRNG {
    private var state: Int

    init(seed: Int) {
        state = seed * 4241 + 97
    }

    /// Returns the next value in `0..<1`, advancing the generator's state.
    mutating func next() -> Double {
        state = (state * 9301 + 49297) % 233280
        return Double(state) / 233280.0
    }
}

/// One horizontal band of the base (pre-shear) texture fill — `_gasTex`'s
/// `while (y < 256) { h = 6+rnd()*24; ... }` loop, one iteration per band.
struct GasGiantBand: Equatable, Sendable {
    let yStart: Double
    /// `_gasTex` fills `h + 1.5` tall (a slight overlap so no seam ever shows
    /// between consecutive bands) — kept separate from the loop's own `y`
    /// step size (plain `h`) so the renderer reproduces both numbers exactly.
    let fillHeight: Double
    /// Index into `Theme.gasGiantBandPalette` (`Math.floor(rnd()*cols.length)`).
    let colorIndex: Int
    let alpha: Double
}

/// One of the 4 storm ellipses `_gasTex` draws after shearing — a shadow
/// ellipse (fixed alpha `.3`, offset +3,+2, larger) plus a highlight ellipse
/// at the same center (random alpha, alternating tint by index parity).
struct GasGiantStorm: Equatable, Sendable {
    let centerX: Double
    let centerY: Double
    let radiusX: Double
    let radiusY: Double
    let highlightAlpha: Double
    /// `i % 2` — `true` selects `Theme.gasGiantStormHighlightAccentHex`,
    /// `false` selects `Theme.secondaryLightHex` (`_gasTex`: `i % 2 ? ... :
    /// GP.secL`).
    let usesAccentHighlight: Bool
}

/// One seed's complete, deterministic band+storm recipe — generated once per
/// texture build, never regenerated (mirrors `StarfieldFieldGenerator`'s own
/// "generate once from the seed, pure function" shape, T17).
struct GasGiantTextureRecipe: Equatable, Sendable {
    let bands: [GasGiantBand]
    let storms: [GasGiantStorm]
}

enum GasGiantTextureMath {
    static let textureWidth = 512
    static let textureHeight = 256
    static let bandColorCount = 11
    static let stormCount = 4

    /// Generates the deterministic band+storm recipe for `seed` — RNG call
    /// order matches `_gasTex` exactly: all bands first (the `while
    /// (y<256)` loop consumes 3 calls/band: height, alpha, colorIndex), THEN
    /// all 4 storms (5 calls/storm: ex, ey, rw, rh, highlight-alpha —
    /// `_gasTex`'s own storm loop order; the shadow ellipse's own alpha,
    /// `.3`, is a FIXED constant in the source, never an `rnd()` draw).
    static func generateRecipe(seed: Int) -> GasGiantTextureRecipe {
        var rng = GasGiantTextureRNG(seed: seed)
        var bands: [GasGiantBand] = []
        var y = 0.0
        while y < Double(textureHeight) {
            let height = 6 + rng.next() * 24
            let alpha = 0.5 + rng.next() * 0.5
            let colorIndex = Int(rng.next() * Double(bandColorCount))
            bands.append(GasGiantBand(yStart: y, fillHeight: height + 1.5, colorIndex: colorIndex, alpha: alpha))
            y += height
        }

        var storms: [GasGiantStorm] = []
        for index in 0..<stormCount {
            let centerX = 80 + rng.next() * 350
            let centerY = 60 + rng.next() * 140
            let radiusX = 15 + rng.next() * 24
            let radiusY = 6 + rng.next() * 10
            let highlightAlpha = 0.4 + rng.next() * 0.3
            storms.append(
                GasGiantStorm(
                    centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY,
                    highlightAlpha: highlightAlpha, usesAccentHighlight: index % 2 == 1
                )
            )
        }

        return GasGiantTextureRecipe(bands: bands, storms: storms)
    }

    /// `_gasTex`'s per-row horizontal shear (`Math.round(Math.sin(yy*.085+seed)*10
    /// + Math.sin(yy*.021+seed*2.7)*26)`) — bounded to roughly ±36 (10+26), so
    /// the renderer's 3x-wrapped blit (`off-width`, `off`, `off+width`) always
    /// fully covers the canvas with no gap regardless of the row's offset sign.
    static func rowShearOffset(row: Int, seed: Int) -> Double {
        (sin(Double(row) * 0.085 + Double(seed)) * 10 + sin(Double(row) * 0.021 + Double(seed) * 2.7) * 26).rounded()
    }

    /// The Home planet's texture seed (`5 + 9*planetIndex`, README "Home
    /// planet seed = 5 + 9·planetIndex"); the Fuel planet uses the FIXED seed
    /// `11` (README) — never this formula.
    static func homePlanetSeed(planetIndex: Int) -> Int {
        5 + 9 * planetIndex
    }

    /// README "Fuel planet uses fixed seed 11" — named rather than a bare
    /// literal at the call site, matching `homePlanetSeed`'s own treatment.
    static let fuelPlanetSeed = 11
}

#if canImport(UIKit)
/// Renders `GasGiantTextureMath.generateRecipe(seed:)`'s recipe into a
/// 512×256 `UIImage` for `SCNMaterial.diffuse.contents` — every drawing step
/// mirrors `_gasTex` in the SAME order: base fill, bands (into an offscreen
/// buffer), the sheared 3x-wrapped blit, storms, then the pole-darkening
/// gradient overlay. Every color comes from `Theme`'s `gasGiant*` facade
/// properties (never a hex literal here — `check_no_inline_hex.sh`'s
/// grep polices this file too, `Space/` is not exempt).
enum GasGiantTextureRenderer {
    static func makeImage(seed: Int, theme: Theme) -> UIImage {
        let recipe = GasGiantTextureMath.generateRecipe(seed: seed)
        let width = GasGiantTextureMath.textureWidth
        let height = GasGiantTextureMath.textureHeight
        let size = CGSize(width: width, height: height)

        // Step 1: the unsheared bands, drawn to an offscreen buffer first —
        // `_gasTex` does this via its own second `tmp` canvas so the shear
        // step below always samples undistorted rows.
        let unshearedImage = UIGraphicsImageRenderer(size: size).image { rendererContext in
            let context = rendererContext.cgContext
            fillColor(theme.gasGiantBaseFillHex, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for band in recipe.bands {
                let hex = theme.gasGiantBandPalette[band.colorIndex]
                fillColor(hex, alpha: band.alpha).setFill()
                context.fill(CGRect(x: 0, y: CGFloat(band.yStart), width: CGFloat(width), height: CGFloat(band.fillHeight)))
            }
        }
        guard let unshearedCGImage = unshearedImage.cgImage else { return unshearedImage }

        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            let context = rendererContext.cgContext

            // Step 2: per-row horizontal shear, wrapped 3x so no gap ever
            // shows regardless of the row's own offset direction.
            for row in 0..<height {
                let offset = GasGiantTextureMath.rowShearOffset(row: row, seed: seed)
                guard let rowSlice = unshearedCGImage.cropping(to: CGRect(x: 0, y: row, width: width, height: 1)) else { continue }
                for wrapMultiple in [-1, 0, 1] {
                    let x = offset + Double(wrapMultiple * width)
                    context.draw(rowSlice, in: CGRect(x: CGFloat(x), y: CGFloat(row), width: CGFloat(width), height: 1))
                }
            }

            // Step 3: storms — a shadow ellipse (fixed alpha `.3`), then a
            // tinted highlight ellipse at the same center.
            for storm in recipe.storms {
                fillColor(theme.gasGiantStormShadowHex, alpha: 0.3).setFill()
                context.fillEllipse(in: CGRect(
                    x: CGFloat(storm.centerX + 3 - storm.radiusX * 1.2), y: CGFloat(storm.centerY + 2 - storm.radiusY * 1.25),
                    width: CGFloat(storm.radiusX * 2.4), height: CGFloat(storm.radiusY * 2.5)
                ))

                let highlightHex = storm.usesAccentHighlight ? theme.gasGiantStormHighlightAccentHex : theme.secondaryLightHex
                fillColor(highlightHex, alpha: storm.highlightAlpha).setFill()
                context.fillEllipse(in: CGRect(
                    x: CGFloat(storm.centerX - storm.radiusX), y: CGFloat(storm.centerY - storm.radiusY),
                    width: CGFloat(storm.radiusX * 2), height: CGFloat(storm.radiusY * 2)
                ))
            }

            // Step 4: pole-darkening vertical gradient overlay
            // (`rgba(10,4,30,.6)` at the poles fading to `0` at the equator band).
            let poleShadow = UIColor(Theme.Neutral.gasGiantPoleShadow)
            let gradientColors = [
                poleShadow.withAlphaComponent(0.6).cgColor,
                poleShadow.withAlphaComponent(0).cgColor,
                poleShadow.withAlphaComponent(0).cgColor,
                poleShadow.withAlphaComponent(0.6).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0, 0.16, 0.84, 1]) else { return }
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
    }

    /// Turns an already-blended hex string from `Theme` into a `UIColor` —
    /// reuses `OrbitColorMath.rgbComponents(of:)` (widened `internal` this
    /// task) rather than a second hex parser (`code-standards` "don't
    /// reinvent"). Never called with a literal — always a `Theme` property.
    private static func fillColor(_ hex: String, alpha: Double) -> UIColor {
        let components = OrbitColorMath.rgbComponents(of: hex)
        return UIColor(
            red: CGFloat(components.red) / 255, green: CGFloat(components.green) / 255,
            blue: CGFloat(components.blue) / 255, alpha: CGFloat(alpha)
        )
    }
}
#endif

// MARK: - Mesh builders (icosahedron/asteroid/ring — the "mesh builders" half
// of this file's own task-row name)

/// A plain triangle-list mesh — vertex positions + a flat triangle index
/// list (3 indices per face) — the shared currency every builder below
/// produces/consumes before `SCNGeometryBuilder` turns it into a real
/// `SCNGeometry`.
struct TriangleMesh: Equatable, Sendable {
    let positions: [SIMD3<Double>]
    let indices: [Int32]
}

/// Builds a subdivided icosahedron (an "icosphere") — Train's rocky asteroid
/// base shape (README "icosahedron subdiv 4") before `AsteroidDisplacement`
/// roughens it, and the small, subdiv-0 debris rocks.
enum IcosahedronMeshBuilder {
    /// The 12-vertex, 20-face base icosahedron (unit sphere) — the same
    /// golden-ratio vertex layout Three.js's own `IcosahedronGeometry`
    /// starts from; a standard construction, not design-specific.
    static func makeBaseIcosahedron() -> TriangleMesh {
        let goldenRatio = (1 + sqrt(5.0)) / 2
        let rawVertices: [SIMD3<Double>] = [
            SIMD3(-1, goldenRatio, 0), SIMD3(1, goldenRatio, 0), SIMD3(-1, -goldenRatio, 0), SIMD3(1, -goldenRatio, 0),
            SIMD3(0, -1, goldenRatio), SIMD3(0, 1, goldenRatio), SIMD3(0, -1, -goldenRatio), SIMD3(0, 1, -goldenRatio),
            SIMD3(goldenRatio, 0, -1), SIMD3(goldenRatio, 0, 1), SIMD3(-goldenRatio, 0, -1), SIMD3(-goldenRatio, 0, 1),
        ]
        let positions = rawVertices.map(normalized)
        let indices: [Int32] = [
            0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
            1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
            3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
            4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
        ]
        return TriangleMesh(positions: positions, indices: indices)
    }

    /// One (or more) rounds of midpoint subdivision (each triangle → 4),
    /// with an edge-midpoint cache so shared edges between adjacent faces
    /// produce exactly ONE shared vertex (never a seam-causing duplicate).
    /// `iterations: 0` returns the mesh unchanged (the debris rocks' own
    /// "subdiv 0" case, README).
    static func subdivided(_ mesh: TriangleMesh, iterations: Int) -> TriangleMesh {
        var current = mesh
        for _ in 0..<max(iterations, 0) {
            current = subdivideOnce(current)
        }
        return current
    }

    private static func subdivideOnce(_ mesh: TriangleMesh) -> TriangleMesh {
        var positions = mesh.positions
        var midpointCache: [UInt64: Int32] = [:]

        func midpointIndex(_ indexA: Int32, _ indexB: Int32) -> Int32 {
            let key = edgeKey(indexA, indexB)
            if let cached = midpointCache[key] { return cached }
            let midpoint = normalized((positions[Int(indexA)] + positions[Int(indexB)]) * 0.5)
            positions.append(midpoint)
            let newIndex = Int32(positions.count - 1)
            midpointCache[key] = newIndex
            return newIndex
        }

        var newIndices: [Int32] = []
        var triangleStart = 0
        while triangleStart + 2 < mesh.indices.count {
            let a = mesh.indices[triangleStart]
            let b = mesh.indices[triangleStart + 1]
            let c = mesh.indices[triangleStart + 2]
            let ab = midpointIndex(a, b)
            let bc = midpointIndex(b, c)
            let ca = midpointIndex(c, a)
            newIndices.append(contentsOf: [a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
            triangleStart += 3
        }

        return TriangleMesh(positions: positions, indices: newIndices)
    }

    /// A stable, order-independent key for an undirected edge — guarantees
    /// the SAME midpoint vertex is reused whether a triangle visits the edge
    /// as (a,b) or a neighbor visits it as (b,a).
    private static func edgeKey(_ indexA: Int32, _ indexB: Int32) -> UInt64 {
        let low = UInt64(min(indexA, indexB))
        let high = UInt64(max(indexA, indexB))
        return (low << 32) | high
    }

    private static func normalized(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        let length = simd_length(vector)
        guard length > 0 else { return vector }
        return vector / length
    }
}

/// Train's rocky-asteroid surface displacement — README "vertices displaced
/// by `1 + 0.17·sin(3.1x)sin(2.7y+1.7)sin(3.7z+0.6) + 0.05·sin(8y+5x)`",
/// verbatim from `_makeScene`'s train branch.
enum AsteroidDisplacement {
    /// The radial displacement magnitude for a UNIT-sphere vertex (`x,y,z`
    /// each already normalized) — a pure function, directly Swift-Testing-
    /// covered for its numeric bounds (`[1-0.17-0.05, 1+0.17+0.05]`).
    static func magnitude(unit: SIMD3<Double>) -> Double {
        let ridged = 0.17 * sin(unit.x * 3.1) * sin(unit.y * 2.7 + 1.7) * sin(unit.z * 3.7 + 0.6)
        let fineNoise = 0.05 * sin(unit.y * 8 + unit.x * 5)
        return 1 + ridged + fineNoise
    }

    /// Displaces every vertex of an already-subdivided unit icosahedron
    /// radially by `magnitude(unit:)` — `_makeScene`'s own
    /// `vv.normalize().multiplyScalar(m)` per vertex.
    static func displaced(_ mesh: TriangleMesh) -> TriangleMesh {
        let displacedPositions = mesh.positions.map { vertex -> SIMD3<Double> in
            let unit = simd_length(vertex) > 0 ? simd_normalize(vertex) : vertex
            return unit * magnitude(unit: unit)
        }
        return TriangleMesh(positions: displacedPositions, indices: mesh.indices)
    }
}

/// A flat annulus (inner radius → outer radius) lying flat in the XZ plane —
/// Home's progression rings (Three.js `RingGeometry` rotated `rotation.x =
/// PI/2`; built directly in the ring's own plane here instead, so
/// `HeroSceneView` never needs a per-ring node rotation for it).
enum RingMeshBuilder {
    static func makeAnnulus(innerRadius: Double, outerRadius: Double, segments: Int = 90) -> TriangleMesh {
        var positions: [SIMD3<Double>] = []
        for segment in 0...segments {
            let angle = Double(segment) / Double(segments) * 2 * Double.pi
            let cosine = cos(angle)
            let sine = sin(angle)
            positions.append(SIMD3(cosine * innerRadius, 0, sine * innerRadius))
            positions.append(SIMD3(cosine * outerRadius, 0, sine * outerRadius))
        }
        var indices: [Int32] = []
        for segment in 0..<segments {
            let innerCurrent = Int32(segment * 2)
            let outerCurrent = Int32(segment * 2 + 1)
            let innerNext = Int32((segment + 1) * 2)
            let outerNext = Int32((segment + 1) * 2 + 1)
            indices.append(contentsOf: [innerCurrent, outerCurrent, innerNext, outerCurrent, outerNext, innerNext])
        }
        return TriangleMesh(positions: positions, indices: indices)
    }
}

/// Turns a pure `TriangleMesh` into a real `SCNGeometry` — the one place
/// this file bridges into SceneKit's own geometry-source types.
enum SCNGeometryBuilder {
    /// One DISTINCT vertex per triangle corner, each carrying its own face's
    /// flat normal — matches Three.js's `flatShading: true` (the design's
    /// asteroid/debris material), the visually "faceted" rock look, unlike
    /// the smooth-shaded rings/moons (`smoothShaded(_:)` below).
    static func flatShaded(_ mesh: TriangleMesh) -> SCNGeometry {
        var expandedPositions: [SCNVector3] = []
        var expandedNormals: [SCNVector3] = []
        expandedPositions.reserveCapacity(mesh.indices.count)
        expandedNormals.reserveCapacity(mesh.indices.count)

        var triangleStart = 0
        while triangleStart + 2 < mesh.indices.count {
            let a = mesh.positions[Int(mesh.indices[triangleStart])]
            let b = mesh.positions[Int(mesh.indices[triangleStart + 1])]
            let c = mesh.positions[Int(mesh.indices[triangleStart + 2])]
            let crossProduct = simd_cross(b - a, c - a)
            let faceNormal = simd_length(crossProduct) > 0 ? simd_normalize(crossProduct) : SIMD3<Double>(0, 1, 0)
            for vertex in [a, b, c] {
                expandedPositions.append(SCNVector3(Float(vertex.x), Float(vertex.y), Float(vertex.z)))
                expandedNormals.append(SCNVector3(Float(faceNormal.x), Float(faceNormal.y), Float(faceNormal.z)))
            }
            triangleStart += 3
        }

        let indices = Array(Int32(0)..<Int32(expandedPositions.count))
        let positionSource = SCNGeometrySource(vertices: expandedPositions)
        let normalSource = SCNGeometrySource(normals: expandedNormals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [positionSource, normalSource], elements: [element])
    }

    /// Shared, per-vertex averaged normals — used for the Home progression
    /// rings and any other shape that should NOT read as faceted.
    static func smoothShaded(_ mesh: TriangleMesh) -> SCNGeometry {
        var normalAccumulators = [SIMD3<Double>](repeating: SIMD3<Double>(repeating: 0), count: mesh.positions.count)
        var triangleStart = 0
        while triangleStart + 2 < mesh.indices.count {
            let indexA = Int(mesh.indices[triangleStart])
            let indexB = Int(mesh.indices[triangleStart + 1])
            let indexC = Int(mesh.indices[triangleStart + 2])
            let a = mesh.positions[indexA]
            let b = mesh.positions[indexB]
            let c = mesh.positions[indexC]
            let faceNormal = simd_cross(b - a, c - a)
            normalAccumulators[indexA] += faceNormal
            normalAccumulators[indexB] += faceNormal
            normalAccumulators[indexC] += faceNormal
            triangleStart += 3
        }

        let positions = mesh.positions.map { SCNVector3(Float($0.x), Float($0.y), Float($0.z)) }
        let normals = normalAccumulators.map { accumulator -> SCNVector3 in
            let resolved = simd_length(accumulator) > 0 ? simd_normalize(accumulator) : SIMD3<Double>(0, 1, 0)
            return SCNVector3(Float(resolved.x), Float(resolved.y), Float(resolved.z))
        }
        let positionSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        return SCNGeometry(sources: [positionSource, normalSource], elements: [element])
    }
}
