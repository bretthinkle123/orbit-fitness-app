import SwiftUI

/// The 13 muscle-group identifiers a figure shape's fill can reference —
/// raw values match `src/orbit/models.py`'s `MUSCLE_GROUPS` tuple exactly
/// (read directly this session), so a shape's fill level / trained-today
/// state can be looked up straight from `GET /body`'s `muscle_group` string
/// with no translation table.
enum MuscleGroupToken: String, CaseIterable, Sendable {
    case chest, shoulders, traps, biceps, forearms, core, quads, calves, lats, triceps
    case lowerBack = "lower_back"
    case glutes, hamstrings

    /// The exact display copy `figure-paths.md`'s / the design's `_D.muscles`
    /// array uses ("Lower back", not "Lower Back") — `MuscleRow`'s visible
    /// label and VoiceOver text read this, never a generic `.capitalized`
    /// transform of the raw backend string (which would wrongly title-case
    /// every word of "lower_back").
    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .traps: return "Traps"
        case .biceps: return "Biceps"
        case .forearms: return "Forearms"
        case .core: return "Core"
        case .quads: return "Quads"
        case .calves: return "Calves"
        case .lats: return "Lats"
        case .triceps: return "Triceps"
        case .lowerBack: return "Lower back"
        case .glutes: return "Glutes"
        case .hamstrings: return "Hamstrings"
        }
    }
}

/// One SVG shape from `figure-paths.md`, converted **verbatim** (CLAUDE.md /
/// design-spec §6: "the four muscle figures are exact SVG path data on a
/// 220x290 grid... convert Q -> quadraticCurve, ellipse/rect/circle/polygon
/// to SwiftUI Path/shapes; do not redraw by hand"). Every coordinate in
/// `FigurePaths`' four shape arrays below was extracted PROGRAMMATICALLY
/// from `figure-paths.md`'s own `<path>`/`<ellipse>`/`<circle>`/`<rect>` tags
/// by a throwaway Python script (never hand-transcribed — the same
/// "generate, don't retype" discipline T2's Alembic migration used against a
/// live database) and cross-checked against a second, independent Python
/// parse for shape counts (33/34/26/27 for male-front/female-front/
/// male-back/female-back) and spot-checked coordinates — the full
/// transcript is recorded in `.pipeline/implementation-progress.md`'s T15
/// entry, mirroring T11's math cross-check pattern.
struct MuscleFigureShape: Sendable, Equatable {
    enum PathSegment: Sendable, Equatable {
        case line(to: CGPoint)
        case quad(control: CGPoint, to: CGPoint)
        case close
    }

    enum Geometry: Sendable, Equatable {
        /// SVG `M`/`L`/`Q`/`Z` commands — `Q` (quadratic Bezier) is the ONLY
        /// curve command `figure-paths.md` uses, converted to SwiftUI's
        /// `addQuadCurve(to:control:)` 1:1 (identical control-point/endpoint
        /// semantics — no reinterpretation needed).
        case path(start: CGPoint, segments: [PathSegment])
        /// SVG `<ellipse>`, optionally with a `transform="rotate(deg cx cy)"`
        /// (the two Female-front chest shapes only) — rotated about its own
        /// center, matching SVG's rotate-about-point semantics.
        case ellipse(center: CGPoint, rx: CGFloat, ry: CGFloat, rotationDegrees: Double)
        case circle(center: CGPoint, radius: CGFloat)
        /// SVG `<rect rx=…>` — `figure-paths.md` never specifies `ry`
        /// independently, so `rx` doubles as the corner radius on both axes
        /// (SVG's own default when `ry` is omitted).
        case roundedRect(origin: CGPoint, size: CGSize, cornerRadius: CGFloat)
    }

    enum Fill: Equatable, Sendable {
        /// A muscle-token shape — filled by the active level-scale color for
        /// that group (`Theme.levelScaleStop`), outlined (figure-paths.md:
        /// "Outline on muscle shapes: 1pt rgba(12,6,26,.4)" —
        /// `Theme.Neutral.figureOutline`), and glow-eligible when trained
        /// today.
        case muscle(MuscleGroupToken)
        /// A body-neutral shape (head, neck, hands, pelvis, knees, feet) —
        /// `Theme.Neutral.figureNeutralFill`, no outline, never glows.
        case neutral
        /// The ellipse ground shadow beneath each figure —
        /// `rgba({{rPri}},.16)` in the source, i.e. the active theme's
        /// primary color at 16% alpha.
        case groundShadow
    }

    let geometry: Geometry
    let fill: Fill
}

extension MuscleFigureShape.Geometry {
    /// Builds the SwiftUI `Path` for this shape — the one place `Q`/ellipse/
    /// rect/circle become concrete drawing calls.
    var path: Path {
        switch self {
        case .path(let start, let segments):
            var path = Path()
            path.move(to: start)
            for segment in segments {
                switch segment {
                case .line(let to):
                    path.addLine(to: to)
                case .quad(let control, let to):
                    path.addQuadCurve(to: to, control: control)
                case .close:
                    path.closeSubpath()
                }
            }
            return path
        case .ellipse(let center, let rx, let ry, let rotationDegrees):
            let rect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
            let basePath = Path(ellipseIn: rect)
            guard rotationDegrees != 0 else { return basePath }
            let radians = rotationDegrees * .pi / 180
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: radians)
                .translatedBy(x: -center.x, y: -center.y)
            return basePath.applying(transform)
        case .circle(let center, let radius):
            return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        case .roundedRect(let origin, let size, let cornerRadius):
            return Path(roundedRect: CGRect(origin: origin, size: size), cornerRadius: cornerRadius, style: .circular)
        }
    }
}

/// The four figures (male/female x front/back), each on `figure-paths.md`'s
/// own `220 x 290` pt grid (`FigurePaths.gridSize`). Static geometry data
/// only — `Figures/MuscleFigure.swift` is the View that renders one.
enum FigurePaths {
    static let gridSize = CGSize(width: 220, height: 290)

    /// Male FRONT — 33 shapes, figure-paths.md verbatim.
    static let maleFront: [MuscleFigureShape] = [
        MuscleFigureShape(geometry: .ellipse(center: CGPoint(x: 110, y: 282), rx: 36, ry: 4.5, rotationDegrees: 0), fill: .groundShadow),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 110, y: 25), radius: 13.5), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 104, y: 37), segments: [.quad(control: CGPoint(x: 110, y: 40), to: CGPoint(x: 116, y: 37)), .line(to: CGPoint(x: 116, y: 47)), .quad(control: CGPoint(x: 110, y: 50), to: CGPoint(x: 104, y: 47)), .close]), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 103, y: 47), segments: [.quad(control: CGPoint(x: 88, y: 50), to: CGPoint(x: 79, y: 58)), .line(to: CGPoint(x: 103, y: 60)), .close]), fill: .muscle(.traps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 117, y: 47), segments: [.quad(control: CGPoint(x: 132, y: 50), to: CGPoint(x: 141, y: 58)), .line(to: CGPoint(x: 117, y: 60)), .close]), fill: .muscle(.traps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 63, y: 58), segments: [.quad(control: CGPoint(x: 72, y: 50), to: CGPoint(x: 83, y: 55)), .quad(control: CGPoint(x: 87, y: 64), to: CGPoint(x: 83, y: 73)), .quad(control: CGPoint(x: 71, y: 76), to: CGPoint(x: 64, y: 69)), .quad(control: CGPoint(x: 61, y: 63), to: CGPoint(x: 63, y: 58)), .close]), fill: .muscle(.shoulders)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 157, y: 58), segments: [.quad(control: CGPoint(x: 148, y: 50), to: CGPoint(x: 137, y: 55)), .quad(control: CGPoint(x: 133, y: 64), to: CGPoint(x: 137, y: 73)), .quad(control: CGPoint(x: 149, y: 76), to: CGPoint(x: 156, y: 69)), .quad(control: CGPoint(x: 159, y: 63), to: CGPoint(x: 157, y: 58)), .close]), fill: .muscle(.shoulders)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 86, y: 58), segments: [.quad(control: CGPoint(x: 97, y: 53), to: CGPoint(x: 108, y: 57)), .line(to: CGPoint(x: 108, y: 79)), .quad(control: CGPoint(x: 96, y: 86), to: CGPoint(x: 87, y: 79)), .quad(control: CGPoint(x: 82, y: 68), to: CGPoint(x: 86, y: 58)), .close]), fill: .muscle(.chest)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 134, y: 58), segments: [.quad(control: CGPoint(x: 123, y: 53), to: CGPoint(x: 112, y: 57)), .line(to: CGPoint(x: 112, y: 79)), .quad(control: CGPoint(x: 124, y: 86), to: CGPoint(x: 133, y: 79)), .quad(control: CGPoint(x: 138, y: 68), to: CGPoint(x: 134, y: 58)), .close]), fill: .muscle(.chest)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 62, y: 80), segments: [.quad(control: CGPoint(x: 70, y: 76), to: CGPoint(x: 75, y: 82)), .quad(control: CGPoint(x: 77, y: 92), to: CGPoint(x: 74, y: 104)), .quad(control: CGPoint(x: 70, y: 111), to: CGPoint(x: 65, y: 108)), .quad(control: CGPoint(x: 59, y: 96), to: CGPoint(x: 62, y: 80)), .close]), fill: .muscle(.biceps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 158, y: 80), segments: [.quad(control: CGPoint(x: 150, y: 76), to: CGPoint(x: 145, y: 82)), .quad(control: CGPoint(x: 143, y: 92), to: CGPoint(x: 146, y: 104)), .quad(control: CGPoint(x: 150, y: 111), to: CGPoint(x: 155, y: 108)), .quad(control: CGPoint(x: 161, y: 96), to: CGPoint(x: 158, y: 80)), .close]), fill: .muscle(.biceps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 52, y: 114), segments: [.quad(control: CGPoint(x: 58, y: 110), to: CGPoint(x: 63, y: 115)), .quad(control: CGPoint(x: 66, y: 126), to: CGPoint(x: 62, y: 140)), .quad(control: CGPoint(x: 59, y: 148), to: CGPoint(x: 54, y: 146)), .quad(control: CGPoint(x: 49, y: 132), to: CGPoint(x: 52, y: 114)), .close]), fill: .muscle(.forearms)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 168, y: 114), segments: [.quad(control: CGPoint(x: 162, y: 110), to: CGPoint(x: 157, y: 115)), .quad(control: CGPoint(x: 154, y: 126), to: CGPoint(x: 158, y: 140)), .quad(control: CGPoint(x: 161, y: 148), to: CGPoint(x: 166, y: 146)), .quad(control: CGPoint(x: 171, y: 132), to: CGPoint(x: 168, y: 114)), .close]), fill: .muscle(.forearms)),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 50, y: 152), radius: 4.8), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 170, y: 152), radius: 4.8), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 88, y: 88), segments: [.quad(control: CGPoint(x: 93, y: 86), to: CGPoint(x: 96, y: 90)), .line(to: CGPoint(x: 96, y: 120)), .quad(control: CGPoint(x: 93, y: 126), to: CGPoint(x: 89, y: 122)), .quad(control: CGPoint(x: 86, y: 105), to: CGPoint(x: 88, y: 88)), .close]), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 132, y: 88), segments: [.quad(control: CGPoint(x: 127, y: 86), to: CGPoint(x: 124, y: 90)), .line(to: CGPoint(x: 124, y: 120)), .quad(control: CGPoint(x: 127, y: 126), to: CGPoint(x: 131, y: 122)), .quad(control: CGPoint(x: 134, y: 105), to: CGPoint(x: 132, y: 88)), .close]), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 99, y: 86), size: CGSize(width: 10, height: 11), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 111, y: 86), size: CGSize(width: 10, height: 11), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 99, y: 99), size: CGSize(width: 10, height: 11), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 111, y: 99), size: CGSize(width: 10, height: 11), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 99, y: 112), size: CGSize(width: 10, height: 11), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 111, y: 112), size: CGSize(width: 10, height: 11), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 99, y: 125), size: CGSize(width: 22, height: 9), cornerRadius: 4.5), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 96, y: 138), segments: [.line(to: CGPoint(x: 124, y: 138)), .quad(control: CGPoint(x: 122, y: 153), to: CGPoint(x: 110, y: 160)), .quad(control: CGPoint(x: 98, y: 153), to: CGPoint(x: 96, y: 138)), .close]), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 90, y: 160), segments: [.quad(control: CGPoint(x: 98, y: 155), to: CGPoint(x: 106, y: 161)), .quad(control: CGPoint(x: 109, y: 182), to: CGPoint(x: 105, y: 204)), .quad(control: CGPoint(x: 101, y: 212), to: CGPoint(x: 95, y: 209)), .quad(control: CGPoint(x: 88, y: 186), to: CGPoint(x: 90, y: 160)), .close]), fill: .muscle(.quads)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 130, y: 160), segments: [.quad(control: CGPoint(x: 122, y: 155), to: CGPoint(x: 114, y: 161)), .quad(control: CGPoint(x: 111, y: 182), to: CGPoint(x: 115, y: 204)), .quad(control: CGPoint(x: 119, y: 212), to: CGPoint(x: 125, y: 209)), .quad(control: CGPoint(x: 132, y: 186), to: CGPoint(x: 130, y: 160)), .close]), fill: .muscle(.quads)),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 99, y: 213), radius: 4.2), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 121, y: 213), radius: 4.2), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 92, y: 222), segments: [.quad(control: CGPoint(x: 99, y: 216), to: CGPoint(x: 105, y: 223)), .quad(control: CGPoint(x: 107, y: 238), to: CGPoint(x: 102, y: 256)), .quad(control: CGPoint(x: 98, y: 262), to: CGPoint(x: 95, y: 258)), .quad(control: CGPoint(x: 90, y: 240), to: CGPoint(x: 92, y: 222)), .close]), fill: .muscle(.calves)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 128, y: 222), segments: [.quad(control: CGPoint(x: 121, y: 216), to: CGPoint(x: 115, y: 223)), .quad(control: CGPoint(x: 113, y: 238), to: CGPoint(x: 118, y: 256)), .quad(control: CGPoint(x: 122, y: 262), to: CGPoint(x: 125, y: 258)), .quad(control: CGPoint(x: 130, y: 240), to: CGPoint(x: 128, y: 222)), .close]), fill: .muscle(.calves)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 87, y: 266), size: CGSize(width: 18, height: 8), cornerRadius: 4), fill: .neutral),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 115, y: 266), size: CGSize(width: 18, height: 8), cornerRadius: 4), fill: .neutral)
    ]

    /// Female FRONT — 34 shapes, figure-paths.md verbatim.
    static let femaleFront: [MuscleFigureShape] = [
        MuscleFigureShape(geometry: .ellipse(center: CGPoint(x: 110, y: 276), rx: 32, ry: 4, rotationDegrees: 0), fill: .groundShadow),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 110, y: 9.5), radius: 4.2), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 110, y: 24), radius: 12.5), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 105, y: 35.5), segments: [.quad(control: CGPoint(x: 110, y: 38), to: CGPoint(x: 115, y: 35.5)), .line(to: CGPoint(x: 115, y: 45)), .quad(control: CGPoint(x: 110, y: 47.5), to: CGPoint(x: 105, y: 45)), .close]), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 104, y: 45.5), segments: [.quad(control: CGPoint(x: 92, y: 48), to: CGPoint(x: 84, y: 54)), .line(to: CGPoint(x: 104, y: 56)), .close]), fill: .muscle(.traps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 116, y: 45.5), segments: [.quad(control: CGPoint(x: 128, y: 48), to: CGPoint(x: 136, y: 54)), .line(to: CGPoint(x: 116, y: 56)), .close]), fill: .muscle(.traps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 70, y: 55), segments: [.quad(control: CGPoint(x: 78, y: 49), to: CGPoint(x: 87, y: 53)), .quad(control: CGPoint(x: 90, y: 60), to: CGPoint(x: 87, y: 68)), .quad(control: CGPoint(x: 77, y: 71), to: CGPoint(x: 71, y: 65)), .quad(control: CGPoint(x: 68, y: 60), to: CGPoint(x: 70, y: 55)), .close]), fill: .muscle(.shoulders)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 150, y: 55), segments: [.quad(control: CGPoint(x: 142, y: 49), to: CGPoint(x: 133, y: 53)), .quad(control: CGPoint(x: 130, y: 60), to: CGPoint(x: 133, y: 68)), .quad(control: CGPoint(x: 143, y: 71), to: CGPoint(x: 149, y: 65)), .quad(control: CGPoint(x: 152, y: 60), to: CGPoint(x: 150, y: 55)), .close]), fill: .muscle(.shoulders)),
        MuscleFigureShape(geometry: .ellipse(center: CGPoint(x: 97, y: 71.5), rx: 11, ry: 10.5, rotationDegrees: -8), fill: .muscle(.chest)),
        MuscleFigureShape(geometry: .ellipse(center: CGPoint(x: 123, y: 71.5), rx: 11, ry: 10.5, rotationDegrees: 8), fill: .muscle(.chest)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 68, y: 76), segments: [.quad(control: CGPoint(x: 75, y: 72), to: CGPoint(x: 79, y: 78)), .quad(control: CGPoint(x: 81, y: 87), to: CGPoint(x: 78, y: 98)), .quad(control: CGPoint(x: 74, y: 104), to: CGPoint(x: 70, y: 101)), .quad(control: CGPoint(x: 65, y: 89), to: CGPoint(x: 68, y: 76)), .close]), fill: .muscle(.biceps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 152, y: 76), segments: [.quad(control: CGPoint(x: 145, y: 72), to: CGPoint(x: 141, y: 78)), .quad(control: CGPoint(x: 139, y: 87), to: CGPoint(x: 142, y: 98)), .quad(control: CGPoint(x: 146, y: 104), to: CGPoint(x: 150, y: 101)), .quad(control: CGPoint(x: 155, y: 89), to: CGPoint(x: 152, y: 76)), .close]), fill: .muscle(.biceps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 59, y: 107), segments: [.quad(control: CGPoint(x: 64, y: 103), to: CGPoint(x: 68, y: 108)), .quad(control: CGPoint(x: 70, y: 118), to: CGPoint(x: 67, y: 131)), .quad(control: CGPoint(x: 64, y: 138), to: CGPoint(x: 60, y: 136)), .quad(control: CGPoint(x: 56, y: 122), to: CGPoint(x: 59, y: 107)), .close]), fill: .muscle(.forearms)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 161, y: 107), segments: [.quad(control: CGPoint(x: 156, y: 103), to: CGPoint(x: 152, y: 108)), .quad(control: CGPoint(x: 150, y: 118), to: CGPoint(x: 153, y: 131)), .quad(control: CGPoint(x: 156, y: 138), to: CGPoint(x: 160, y: 136)), .quad(control: CGPoint(x: 164, y: 122), to: CGPoint(x: 161, y: 107)), .close]), fill: .muscle(.forearms)),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 57, y: 143), radius: 4.4), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 163, y: 143), radius: 4.4), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 90, y: 85), segments: [.quad(control: CGPoint(x: 94, y: 83), to: CGPoint(x: 97, y: 87)), .line(to: CGPoint(x: 97, y: 114)), .quad(control: CGPoint(x: 94, y: 119), to: CGPoint(x: 91, y: 116)), .quad(control: CGPoint(x: 88, y: 100), to: CGPoint(x: 90, y: 85)), .close]), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 130, y: 85), segments: [.quad(control: CGPoint(x: 126, y: 83), to: CGPoint(x: 123, y: 87)), .line(to: CGPoint(x: 123, y: 114)), .quad(control: CGPoint(x: 126, y: 119), to: CGPoint(x: 129, y: 116)), .quad(control: CGPoint(x: 132, y: 100), to: CGPoint(x: 130, y: 85)), .close]), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 100, y: 83), size: CGSize(width: 9.5, height: 10), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 110.5, y: 83), size: CGSize(width: 9.5, height: 10), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 100, y: 95), size: CGSize(width: 9.5, height: 10), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 110.5, y: 95), size: CGSize(width: 9.5, height: 10), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 100, y: 107), size: CGSize(width: 9.5, height: 10), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 110.5, y: 107), size: CGSize(width: 9.5, height: 10), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 100, y: 119), size: CGSize(width: 20, height: 8.5), cornerRadius: 4), fill: .muscle(.core)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 93, y: 131), segments: [.line(to: CGPoint(x: 127, y: 131)), .quad(control: CGPoint(x: 129, y: 150), to: CGPoint(x: 110, y: 161)), .quad(control: CGPoint(x: 91, y: 150), to: CGPoint(x: 93, y: 131)), .close]), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 89, y: 158), segments: [.quad(control: CGPoint(x: 97, y: 152), to: CGPoint(x: 106, y: 159)), .quad(control: CGPoint(x: 109, y: 178), to: CGPoint(x: 105, y: 199)), .quad(control: CGPoint(x: 101, y: 207), to: CGPoint(x: 95, y: 204)), .quad(control: CGPoint(x: 87, y: 182), to: CGPoint(x: 89, y: 158)), .close]), fill: .muscle(.quads)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 131, y: 158), segments: [.quad(control: CGPoint(x: 123, y: 152), to: CGPoint(x: 114, y: 159)), .quad(control: CGPoint(x: 111, y: 178), to: CGPoint(x: 115, y: 199)), .quad(control: CGPoint(x: 119, y: 207), to: CGPoint(x: 125, y: 204)), .quad(control: CGPoint(x: 133, y: 182), to: CGPoint(x: 131, y: 158)), .close]), fill: .muscle(.quads)),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 99, y: 208), radius: 4), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 121, y: 208), radius: 4), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 92, y: 217), segments: [.quad(control: CGPoint(x: 98, y: 211), to: CGPoint(x: 104, y: 218)), .quad(control: CGPoint(x: 106, y: 232), to: CGPoint(x: 101, y: 249)), .quad(control: CGPoint(x: 97, y: 255), to: CGPoint(x: 94, y: 251)), .quad(control: CGPoint(x: 89, y: 234), to: CGPoint(x: 92, y: 217)), .close]), fill: .muscle(.calves)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 128, y: 217), segments: [.quad(control: CGPoint(x: 122, y: 211), to: CGPoint(x: 116, y: 218)), .quad(control: CGPoint(x: 114, y: 232), to: CGPoint(x: 119, y: 249)), .quad(control: CGPoint(x: 123, y: 255), to: CGPoint(x: 126, y: 251)), .quad(control: CGPoint(x: 131, y: 234), to: CGPoint(x: 128, y: 217)), .close]), fill: .muscle(.calves)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 88, y: 259), size: CGSize(width: 17, height: 8), cornerRadius: 4), fill: .neutral),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 115, y: 259), size: CGSize(width: 17, height: 8), cornerRadius: 4), fill: .neutral)
    ]

    /// Male BACK — 26 shapes, figure-paths.md verbatim.
    static let maleBack: [MuscleFigureShape] = [
        MuscleFigureShape(geometry: .ellipse(center: CGPoint(x: 110, y: 282), rx: 36, ry: 4.5, rotationDegrees: 0), fill: .groundShadow),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 110, y: 25), radius: 13.5), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 104, y: 37), segments: [.quad(control: CGPoint(x: 110, y: 40), to: CGPoint(x: 116, y: 37)), .line(to: CGPoint(x: 116, y: 45)), .quad(control: CGPoint(x: 110, y: 48), to: CGPoint(x: 104, y: 45)), .close]), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 110, y: 44), segments: [.quad(control: CGPoint(x: 96, y: 48), to: CGPoint(x: 84, y: 56)), .quad(control: CGPoint(x: 98, y: 60), to: CGPoint(x: 104, y: 64)), .line(to: CGPoint(x: 110, y: 86)), .line(to: CGPoint(x: 116, y: 64)), .quad(control: CGPoint(x: 122, y: 60), to: CGPoint(x: 136, y: 56)), .quad(control: CGPoint(x: 124, y: 48), to: CGPoint(x: 110, y: 44)), .close]), fill: .muscle(.traps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 63, y: 58), segments: [.quad(control: CGPoint(x: 72, y: 50), to: CGPoint(x: 83, y: 55)), .quad(control: CGPoint(x: 87, y: 64), to: CGPoint(x: 83, y: 73)), .quad(control: CGPoint(x: 71, y: 76), to: CGPoint(x: 64, y: 69)), .quad(control: CGPoint(x: 61, y: 63), to: CGPoint(x: 63, y: 58)), .close]), fill: .muscle(.shoulders)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 157, y: 58), segments: [.quad(control: CGPoint(x: 148, y: 50), to: CGPoint(x: 137, y: 55)), .quad(control: CGPoint(x: 133, y: 64), to: CGPoint(x: 137, y: 73)), .quad(control: CGPoint(x: 149, y: 76), to: CGPoint(x: 156, y: 69)), .quad(control: CGPoint(x: 159, y: 63), to: CGPoint(x: 157, y: 58)), .close]), fill: .muscle(.shoulders)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 84, y: 68), segments: [.quad(control: CGPoint(x: 95, y: 64), to: CGPoint(x: 103, y: 70)), .line(to: CGPoint(x: 103, y: 92)), .quad(control: CGPoint(x: 99, y: 116), to: CGPoint(x: 92, y: 124)), .quad(control: CGPoint(x: 84, y: 100), to: CGPoint(x: 84, y: 68)), .close]), fill: .muscle(.lats)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 136, y: 68), segments: [.quad(control: CGPoint(x: 125, y: 64), to: CGPoint(x: 117, y: 70)), .line(to: CGPoint(x: 117, y: 92)), .quad(control: CGPoint(x: 121, y: 116), to: CGPoint(x: 128, y: 124)), .quad(control: CGPoint(x: 136, y: 100), to: CGPoint(x: 136, y: 68)), .close]), fill: .muscle(.lats)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 62, y: 80), segments: [.quad(control: CGPoint(x: 70, y: 76), to: CGPoint(x: 75, y: 82)), .quad(control: CGPoint(x: 77, y: 92), to: CGPoint(x: 74, y: 104)), .quad(control: CGPoint(x: 70, y: 111), to: CGPoint(x: 65, y: 108)), .quad(control: CGPoint(x: 59, y: 96), to: CGPoint(x: 62, y: 80)), .close]), fill: .muscle(.triceps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 158, y: 80), segments: [.quad(control: CGPoint(x: 150, y: 76), to: CGPoint(x: 145, y: 82)), .quad(control: CGPoint(x: 143, y: 92), to: CGPoint(x: 146, y: 104)), .quad(control: CGPoint(x: 150, y: 111), to: CGPoint(x: 155, y: 108)), .quad(control: CGPoint(x: 161, y: 96), to: CGPoint(x: 158, y: 80)), .close]), fill: .muscle(.triceps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 52, y: 114), segments: [.quad(control: CGPoint(x: 58, y: 110), to: CGPoint(x: 63, y: 115)), .quad(control: CGPoint(x: 66, y: 126), to: CGPoint(x: 62, y: 140)), .quad(control: CGPoint(x: 59, y: 148), to: CGPoint(x: 54, y: 146)), .quad(control: CGPoint(x: 49, y: 132), to: CGPoint(x: 52, y: 114)), .close]), fill: .muscle(.forearms)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 168, y: 114), segments: [.quad(control: CGPoint(x: 162, y: 110), to: CGPoint(x: 157, y: 115)), .quad(control: CGPoint(x: 154, y: 126), to: CGPoint(x: 158, y: 140)), .quad(control: CGPoint(x: 161, y: 148), to: CGPoint(x: 166, y: 146)), .quad(control: CGPoint(x: 171, y: 132), to: CGPoint(x: 168, y: 114)), .close]), fill: .muscle(.forearms)),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 50, y: 152), radius: 4.8), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 170, y: 152), radius: 4.8), fill: .neutral),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 102, y: 96), size: CGSize(width: 7, height: 34), cornerRadius: 3.5), fill: .muscle(.lowerBack)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 111, y: 96), size: CGSize(width: 7, height: 34), cornerRadius: 3.5), fill: .muscle(.lowerBack)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 95, y: 136), segments: [.quad(control: CGPoint(x: 107, y: 133), to: CGPoint(x: 108, y: 147)), .quad(control: CGPoint(x: 108, y: 160), to: CGPoint(x: 98, y: 162)), .quad(control: CGPoint(x: 90, y: 155), to: CGPoint(x: 91, y: 145)), .quad(control: CGPoint(x: 92, y: 138), to: CGPoint(x: 95, y: 136)), .close]), fill: .muscle(.glutes)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 125, y: 136), segments: [.quad(control: CGPoint(x: 113, y: 133), to: CGPoint(x: 112, y: 147)), .quad(control: CGPoint(x: 112, y: 160), to: CGPoint(x: 122, y: 162)), .quad(control: CGPoint(x: 130, y: 155), to: CGPoint(x: 129, y: 145)), .quad(control: CGPoint(x: 128, y: 138), to: CGPoint(x: 125, y: 136)), .close]), fill: .muscle(.glutes)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 90, y: 166), segments: [.quad(control: CGPoint(x: 98, y: 161), to: CGPoint(x: 106, y: 167)), .quad(control: CGPoint(x: 109, y: 186), to: CGPoint(x: 105, y: 206)), .quad(control: CGPoint(x: 101, y: 214), to: CGPoint(x: 95, y: 211)), .quad(control: CGPoint(x: 88, y: 190), to: CGPoint(x: 90, y: 166)), .close]), fill: .muscle(.hamstrings)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 130, y: 166), segments: [.quad(control: CGPoint(x: 122, y: 161), to: CGPoint(x: 114, y: 167)), .quad(control: CGPoint(x: 111, y: 186), to: CGPoint(x: 115, y: 206)), .quad(control: CGPoint(x: 119, y: 214), to: CGPoint(x: 125, y: 211)), .quad(control: CGPoint(x: 132, y: 190), to: CGPoint(x: 130, y: 166)), .close]), fill: .muscle(.hamstrings)),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 99, y: 215), radius: 4.2), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 121, y: 215), radius: 4.2), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 92, y: 222), segments: [.quad(control: CGPoint(x: 99, y: 216), to: CGPoint(x: 105, y: 223)), .quad(control: CGPoint(x: 107, y: 238), to: CGPoint(x: 102, y: 256)), .quad(control: CGPoint(x: 98, y: 262), to: CGPoint(x: 95, y: 258)), .quad(control: CGPoint(x: 90, y: 240), to: CGPoint(x: 92, y: 222)), .close]), fill: .muscle(.calves)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 128, y: 222), segments: [.quad(control: CGPoint(x: 121, y: 216), to: CGPoint(x: 115, y: 223)), .quad(control: CGPoint(x: 113, y: 238), to: CGPoint(x: 118, y: 256)), .quad(control: CGPoint(x: 122, y: 262), to: CGPoint(x: 125, y: 258)), .quad(control: CGPoint(x: 130, y: 240), to: CGPoint(x: 128, y: 222)), .close]), fill: .muscle(.calves)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 87, y: 266), size: CGSize(width: 18, height: 8), cornerRadius: 4), fill: .neutral),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 115, y: 266), size: CGSize(width: 18, height: 8), cornerRadius: 4), fill: .neutral)
    ]

    /// Female BACK — 27 shapes, figure-paths.md verbatim.
    static let femaleBack: [MuscleFigureShape] = [
        MuscleFigureShape(geometry: .ellipse(center: CGPoint(x: 110, y: 276), rx: 32, ry: 4, rotationDegrees: 0), fill: .groundShadow),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 110, y: 9.5), radius: 4.2), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 110, y: 24), radius: 12.5), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 105, y: 35.5), segments: [.quad(control: CGPoint(x: 110, y: 38), to: CGPoint(x: 115, y: 35.5)), .line(to: CGPoint(x: 115, y: 43)), .quad(control: CGPoint(x: 110, y: 45.5), to: CGPoint(x: 105, y: 43)), .close]), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 110, y: 42), segments: [.quad(control: CGPoint(x: 99, y: 46), to: CGPoint(x: 88, y: 52)), .quad(control: CGPoint(x: 100, y: 56), to: CGPoint(x: 105, y: 60)), .line(to: CGPoint(x: 110, y: 78)), .line(to: CGPoint(x: 115, y: 60)), .quad(control: CGPoint(x: 120, y: 56), to: CGPoint(x: 132, y: 52)), .quad(control: CGPoint(x: 121, y: 46), to: CGPoint(x: 110, y: 42)), .close]), fill: .muscle(.traps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 70, y: 55), segments: [.quad(control: CGPoint(x: 78, y: 49), to: CGPoint(x: 87, y: 53)), .quad(control: CGPoint(x: 90, y: 60), to: CGPoint(x: 87, y: 68)), .quad(control: CGPoint(x: 77, y: 71), to: CGPoint(x: 71, y: 65)), .quad(control: CGPoint(x: 68, y: 60), to: CGPoint(x: 70, y: 55)), .close]), fill: .muscle(.shoulders)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 150, y: 55), segments: [.quad(control: CGPoint(x: 142, y: 49), to: CGPoint(x: 133, y: 53)), .quad(control: CGPoint(x: 130, y: 60), to: CGPoint(x: 133, y: 68)), .quad(control: CGPoint(x: 143, y: 71), to: CGPoint(x: 149, y: 65)), .quad(control: CGPoint(x: 152, y: 60), to: CGPoint(x: 150, y: 55)), .close]), fill: .muscle(.shoulders)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 88, y: 64), segments: [.quad(control: CGPoint(x: 97, y: 61), to: CGPoint(x: 104, y: 66)), .line(to: CGPoint(x: 104, y: 86)), .quad(control: CGPoint(x: 100, y: 108), to: CGPoint(x: 94, y: 116)), .quad(control: CGPoint(x: 87, y: 94), to: CGPoint(x: 88, y: 64)), .close]), fill: .muscle(.lats)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 132, y: 64), segments: [.quad(control: CGPoint(x: 123, y: 61), to: CGPoint(x: 116, y: 66)), .line(to: CGPoint(x: 116, y: 86)), .quad(control: CGPoint(x: 120, y: 108), to: CGPoint(x: 126, y: 116)), .quad(control: CGPoint(x: 133, y: 94), to: CGPoint(x: 132, y: 64)), .close]), fill: .muscle(.lats)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 68, y: 76), segments: [.quad(control: CGPoint(x: 75, y: 72), to: CGPoint(x: 79, y: 78)), .quad(control: CGPoint(x: 81, y: 87), to: CGPoint(x: 78, y: 98)), .quad(control: CGPoint(x: 74, y: 104), to: CGPoint(x: 70, y: 101)), .quad(control: CGPoint(x: 65, y: 89), to: CGPoint(x: 68, y: 76)), .close]), fill: .muscle(.triceps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 152, y: 76), segments: [.quad(control: CGPoint(x: 145, y: 72), to: CGPoint(x: 141, y: 78)), .quad(control: CGPoint(x: 139, y: 87), to: CGPoint(x: 142, y: 98)), .quad(control: CGPoint(x: 146, y: 104), to: CGPoint(x: 150, y: 101)), .quad(control: CGPoint(x: 155, y: 89), to: CGPoint(x: 152, y: 76)), .close]), fill: .muscle(.triceps)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 59, y: 107), segments: [.quad(control: CGPoint(x: 64, y: 103), to: CGPoint(x: 68, y: 108)), .quad(control: CGPoint(x: 70, y: 118), to: CGPoint(x: 67, y: 131)), .quad(control: CGPoint(x: 64, y: 138), to: CGPoint(x: 60, y: 136)), .quad(control: CGPoint(x: 56, y: 122), to: CGPoint(x: 59, y: 107)), .close]), fill: .muscle(.forearms)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 161, y: 107), segments: [.quad(control: CGPoint(x: 156, y: 103), to: CGPoint(x: 152, y: 108)), .quad(control: CGPoint(x: 150, y: 118), to: CGPoint(x: 153, y: 131)), .quad(control: CGPoint(x: 156, y: 138), to: CGPoint(x: 160, y: 136)), .quad(control: CGPoint(x: 164, y: 122), to: CGPoint(x: 161, y: 107)), .close]), fill: .muscle(.forearms)),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 57, y: 143), radius: 4.4), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 163, y: 143), radius: 4.4), fill: .neutral),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 103, y: 94), size: CGSize(width: 6.5, height: 30), cornerRadius: 3), fill: .muscle(.lowerBack)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 110.5, y: 94), size: CGSize(width: 6.5, height: 30), cornerRadius: 3), fill: .muscle(.lowerBack)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 93, y: 128), segments: [.quad(control: CGPoint(x: 107, y: 125), to: CGPoint(x: 108, y: 139)), .quad(control: CGPoint(x: 108, y: 153), to: CGPoint(x: 97, y: 156)), .quad(control: CGPoint(x: 88, y: 149), to: CGPoint(x: 89, y: 138)), .quad(control: CGPoint(x: 90, y: 131), to: CGPoint(x: 93, y: 128)), .close]), fill: .muscle(.glutes)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 127, y: 128), segments: [.quad(control: CGPoint(x: 113, y: 125), to: CGPoint(x: 112, y: 139)), .quad(control: CGPoint(x: 112, y: 153), to: CGPoint(x: 123, y: 156)), .quad(control: CGPoint(x: 132, y: 149), to: CGPoint(x: 131, y: 138)), .quad(control: CGPoint(x: 130, y: 131), to: CGPoint(x: 127, y: 128)), .close]), fill: .muscle(.glutes)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 89, y: 160), segments: [.quad(control: CGPoint(x: 97, y: 154), to: CGPoint(x: 106, y: 161)), .quad(control: CGPoint(x: 109, y: 178), to: CGPoint(x: 105, y: 198)), .quad(control: CGPoint(x: 101, y: 206), to: CGPoint(x: 95, y: 203)), .quad(control: CGPoint(x: 87, y: 182), to: CGPoint(x: 89, y: 160)), .close]), fill: .muscle(.hamstrings)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 131, y: 160), segments: [.quad(control: CGPoint(x: 123, y: 154), to: CGPoint(x: 114, y: 161)), .quad(control: CGPoint(x: 111, y: 178), to: CGPoint(x: 115, y: 198)), .quad(control: CGPoint(x: 119, y: 206), to: CGPoint(x: 125, y: 203)), .quad(control: CGPoint(x: 133, y: 182), to: CGPoint(x: 131, y: 160)), .close]), fill: .muscle(.hamstrings)),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 99, y: 206), radius: 4), fill: .neutral),
        MuscleFigureShape(geometry: .circle(center: CGPoint(x: 121, y: 206), radius: 4), fill: .neutral),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 92, y: 217), segments: [.quad(control: CGPoint(x: 98, y: 211), to: CGPoint(x: 104, y: 218)), .quad(control: CGPoint(x: 106, y: 232), to: CGPoint(x: 101, y: 249)), .quad(control: CGPoint(x: 97, y: 255), to: CGPoint(x: 94, y: 251)), .quad(control: CGPoint(x: 89, y: 234), to: CGPoint(x: 92, y: 217)), .close]), fill: .muscle(.calves)),
        MuscleFigureShape(geometry: .path(start: CGPoint(x: 128, y: 217), segments: [.quad(control: CGPoint(x: 122, y: 211), to: CGPoint(x: 116, y: 218)), .quad(control: CGPoint(x: 114, y: 232), to: CGPoint(x: 119, y: 249)), .quad(control: CGPoint(x: 123, y: 255), to: CGPoint(x: 126, y: 251)), .quad(control: CGPoint(x: 131, y: 234), to: CGPoint(x: 128, y: 217)), .close]), fill: .muscle(.calves)),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 88, y: 259), size: CGSize(width: 17, height: 8), cornerRadius: 4), fill: .neutral),
        MuscleFigureShape(geometry: .roundedRect(origin: CGPoint(x: 115, y: 259), size: CGSize(width: 17, height: 8), cornerRadius: 4), fill: .neutral)
    ]


    /// `gender` matches `src/orbit/models.py`'s `GENDERS` tuple ("m"/"w") —
    /// the SAME raw values `SettingsSheet`/`BodyView`'s gender control
    /// already read/write via `PATCH /profile`, so `BodyView` needs no
    /// second gender vocabulary. Any value other than "w" renders male
    /// (matches the DB CHECK's closed `("m","w")` set — never reachable in
    /// practice, but a safe default rather than a crash if it ever were).
    static func frontShapes(forGender gender: String) -> [MuscleFigureShape] {
        gender == "w" ? femaleFront : maleFront
    }

    static func backShapes(forGender gender: String) -> [MuscleFigureShape] {
        gender == "w" ? femaleBack : maleBack
    }
}
