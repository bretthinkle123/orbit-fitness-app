# Handoff: ORBIT — Space-Themed Fitness + Diet Tracker (SwiftUI port)

## Overview
ORBIT is a mobile app concept fusing a strength-training tracker (Stronger-style: strength score, set logging, muscle-level map) with an adaptive diet coach (MacroFactor-style: calorie/macro budget, fast food logging, weekly coach adjustments), wrapped in an outer-space/nebula theme. Four screens: **Home** (combined daily dashboard), **Fuel** (diet log), **Train** (workout logging), **Body** (results — geometric human muscle map, front + back).

**Target: native iPhone app in SwiftUI.**

## About the Design Files
The files in this bundle are **design references created in HTML** — interactive prototypes showing intended look and behavior. They are NOT production code to copy directly. The task is to **recreate these designs in SwiftUI** using native patterns (SwiftUI views, SceneKit/RealityKit for 3D, TimelineView+Canvas for the animated background).

`Orbit Fitness.dc.html` shows the single style — "Nebula Glass" (screens labeled 1a, 1b, 1c, 1d). Per design direction, planets have **no wireframe/triangle mesh overlays** — smooth textured spheres only. Cards are highly translucent (32% fill, blur 4) so the starfield shows through.

## Fidelity
**High-fidelity.** Colors, spacing, typography, copy, and interactions are final intent. Recreate pixel-perfectly at the reference size, then adapt to device sizes (reference frame: 402 × 874 pt, iPhone bezel).

## Design Tokens

### Palette system (themeable — this is a core feature)
Every color in the app derives from a 3-color palette `[primary, secondary, accent]`. The user picks one of 4 presets; EVERYTHING recolors (UI, charts, 3D planets, nebula, stars, ship):

- Purple (default): `#8B5CF6`, `#D946EF`, `#F0ABFC`
- Blue: `#3B82F6`, `#22D3EE`, `#93C5FD`
- Red: `#EF4444`, `#FB7185`, `#FED7AA`
- Green: `#10B981`, `#84CC16`, `#6EE7B7`

Derived tints (blend = linear RGB interpolation toward target):
- `secondaryLight` = blend(secondary → white, 28%)
- `primaryLight` = blend(primary → white, 30%)
- `primaryLighter` = blend(primary → white, 50%)

Strength-level scale (6 stops, Beginner → World Class), derived per palette:
1. blend(primary → #0B0620, 55%)
2. blend(primary → #0B0620, 28%)
3. primary
4. blend(primary → secondary, 55%)
5. secondaryLight
6. blend(accent → white, 45%)

Implement as a `Theme` struct computed from the 3 base colors.

### Neutrals (constant across palettes)
- Screen background: `#04050E` + two large dark radial washes of `primaryDark2` = blend(primary → black, 28%): 30% alpha at top-right (150%×70% ellipse at 80%,−15%), 35% alpha at bottom-left (120%×55% at 0%,100%)
- Card fill: `rgba(23,15,44,0.32)` with background blur 4 — very translucent, stars must read through (SwiftUI: thin dark material at reduced opacity) — border 1pt `rgba(255,255,255,0.10)`, corner radius 22. Small chips use `rgba(23,15,44,0.38)`.
- Text: `#F4F0FF`; muted: `rgba(216,206,238,0.62)`; faint: `rgba(216,206,238,0.45)`
- Section label style: 10.5pt, weight 600, letter-spacing 0.18em, UPPERCASE, muted color

### Typography
- Display / numbers / wordmark: **Space Grotesk** (Google Font — bundle it, or substitute SF Pro Rounded semibold)
- Body / UI: **DM Sans** (or SF Pro)
- Key sizes: wordmark 14/700 tracking .24em; greeting 25/600; big stat 34–40/700; card title 19/600; body 12–13; captions 9.5–11

### Radii & spacing
- Cards 22 · pill button 23 (46pt tall) · chips 12–14 · progress bars 4–7pt tall, rounded
- Screen padding 16; card padding 16–18; card gap 12

## Screens (variant A)

All four share: full-screen animated space background (see below), a 3D hero in the top ~440pt (Home/Fuel/Train; Body has none), content scrolling over it, a bottom fade (112pt, `#04050E` at 25% → transparent), and a floating glass tab bar (inset 14pt sides / 16pt bottom; fill `rgba(22,13,42,0.78)`, blur 18, radius 26; active tab = `rgba(255,255,255,0.09)` pill highlight; icons: ringed planet / orbit / diamond asteroid / person). The content column's top spacer reserves the hero: Home 244pt · Fuel 224pt · Train 214pt.

### 1a Home — daily dashboard
- Header row: gradient dot + "ORBIT" wordmark; avatar circle "AK" (30pt)
- 3D hero: gas-giant planet with progression rings (see 3D spec)
- "Your system" card: 6 planet chips — Ember, Dune, Titan, Aurora, Nova, Zenith — dot colored by level-scale stop; active chip highlighted; caption `{Level} · {n} rings`; footer "Orbiting {Planet} · rank up to travel further". Tapping a chip re-textures the hero planet and sets ring count = chip index.
- Greeting: "Good evening, Alex" + pulsing dot + "Tue 7 Jul · Day 12 in orbit"
- Calories card: 124pt ring (9pt stroke, secondary color, glow shadow, round cap; progress = eaten/2350) with center "{remaining}" + "KCAL LEFT"; right column rows: Eaten {n} / Burned +412 / Budget 2,350
- Macros card: 3 rows (Protein/Carbs/Fat) — label, 7pt progress bar (colors: secondaryLight / primary / accent), "{n} / {target} g"
- Today's mission card: "Push Day", "5 exercises · ~52 min · Chest focus", full-width gradient pill button "Start Push Day" (135° gradient primary→secondary, glow shadow)
- Two stat chips: Strength score {512+setsDone} (+{4+done} this wk · Intermediate II) · Burn rate 2,847 (↑ 32 · kcal / day est.)
- Weight trend card: "182.4 lb" + "↓ 0.4 lb / wk", 30-day sparkline (secondaryLight line, soft area fill, scattered scale-weight dots, accent end dot)

### 1b Fuel — diet tracking
- Header: "FUEL" wordmark + "Today" chip
- 3D hero: small gas planet with 3 orbiting macro moons on tilted rings; legend chips ● Protein ● Carbs ● Fat
- Remaining card: "{remaining} / 2,350 kcal", gradient progress bar, "Eaten {n}" / "Coach adjusts Mon"
- Macro rings row: three 58pt rings (P/C/F) "{n}/{target}g"
- Coach banner (secondary-tinted): "**Mission Control:** burn rate trending ↑ 2,847 kcal — carbs +15 g from Monday."
- Food log: Breakfast (405 kcal: Greek Yogurt + Granola 342 · Blueberries 57 · Espresso 6), Lunch (642 kcal: Chicken Burrito Bowl 642 · Sparkling Water 0), Dinner (starts empty: "Nothing logged — quick add:" + 3 chips: Salmon & Rice Bowl 612 · Whey Shake 178 · Chicken Stir-fry 524). Tapping a chip appends the row, chip flips to "✓ {name}" tinted state, all rings/bars/budgets update app-wide, and the matching 3D macro moon scales up with a pulse.
- Food log views: the section header carries a Meals / By hour segmented toggle, and the two panels below it swipe horizontally (scroll-snap paging; tab taps and swipes stay in sync — SwiftUI: paged TabView + segmented control). **By hour** is a MacroFactor-style hourly timeline, 6 AM–9 PM: hour labels + a 1pt vertical rail on the left, the hour dot lights up (secondary + glow) when it has entries, each entry is a small glass chip (name / "time · meal" / kcal), a pulsing "Now · 7:42 PM" marker sits in the 7 PM row, and dinner quick-adds appear there live at 7:05/7:12/7:18 PM. Logged times: Espresso 6:45 AM · Greek Yogurt + Granola 7:20 AM · Blueberries 7:25 AM · Apple + PB 10:30 AM · Burrito Bowl 12:40 PM · Sparkling Water 12:45 PM · Cottage Cheese 3:30 PM.
- Log-method buttons: Scan · Photo · Search · Label (46pt glass circles, line icons)

### 1c Train — workout logging
- Header: "TRAIN" + "Wk 8 · Block 2" chip
- 3D hero: displaced rocky asteroid + 3 orbiting debris rocks; heats (emissive glow up) as sets are completed; camera orbits on scroll
- Strength score card: {512+done} + "+{4+done} this wk" chip, "Intermediate II", 68% bar to Advanced, "Top 22% @ 183 lb"
- Session card: "Push Day", "{done} / 16 sets · tap to log", thin progress bar; when a set is checked a "REST {m:ss}" chip appears counting down from 2:00
  - Exercises (name · scheme · tag · tappable 36pt set circles; done = gradient fill + glow):
    1. Barbell Bench Press — 4 × 8 · 185 lb (Chest)
    2. Incline DB Press — 3 × 10 · 60 lb (Chest)
    3. Seated Overhead Press — 3 × 10 · 95 lb (Delts)
    4. Cable Fly — 3 × 12 · 42.5 lb (Chest)
    5. Triceps Pushdown — 3 × 12 · 57.5 lb (Triceps)
- Week strip: 7 dots (4 filled) · "4 sessions"

### 1d Body — results (muscle map)
- Header: "BODY" + "Results" chip; title "Body map", subtitle "Levels from your logged lifts · Score {n}"
- Muscle levels card: M / W segmented toggle (top-right); **front figure**, caption "Front"; scroll down to **back figure** standing below, caption "Back"; both float gently (±7pt, ~6s ease). Level legend gradient bar (6-stop scale) with "Beginner … World class".
- Figures: geometric humans built from curved vector paths on a 220 × 290 grid — **use the exact SVG path/shape data in the HTML as SwiftUI `Path` sources**. Muscle fills = level-scale color; neutral parts (head, neck, hands, pelvis, knees, feet) `rgba(244,240,255,0.13)`; 1pt dark outline `rgba(12,6,26,0.4)`; soft radial glow behind. Muscles trained today (any set logged for that tag) get a secondary-colored glow (drop shadow) and "▲ today" in the list.
- "By muscle group" card, 13 rows: Chest Advanced · Shoulders Int · Traps Int · Biceps Int · Forearms Novice · Core Int · Quads Novice · Calves Beginner · Lats Advanced · Triceps Int · Lower back Int · Glutes Novice · Hamstrings Novice. Row = color dot + name + 6-segment level bar + label (+ optional "▲ today").
- Tip banner: "**Tip:** log sets on Train and trained muscles glow here."

## Interactions & Behavior
- Shared store: logging food on Fuel updates Home (ring, macros); logging sets on Train updates score everywhere and lights muscles on Body.
- Set toggle: tap toggles done; turning ON starts/restarts 120s rest countdown; score = 512 + doneCount.
- Quick-add: idempotent per food; dinner kcal = sum of added.
- M/W toggle swaps male/female figures (front + back) with a crossfade.
- Planet picker: index 0–5 → texture seed changes + ring count = index (0 rings for Beginner "Ember" up to 5 for "Zenith"); caption uses singular "1 ring". Prototype swaps instantly; a ≤0.3s crossfade is acceptable.
- Scroll-driven 3D (per screen, driven by normalized scroll 0–1, smoothed ~8%/frame): Home — planet spins (idle 0.14 rad/s + 2.6×scroll), ring tilt eases, camera pulls z 4.6→4.05 and rises; Fuel — camera descends from top-down (y 1.6) toward edge-on (y 0.2), orbit group yaw += 1.5×scroll; Train — camera orbits azimuth 2.4×scroll around the asteroid. Hero layer also parallax-translates up to −95pt.
- Transitions: color/fill changes 0.4s; bars/rings 0.5–0.7s cubic-bezier(.22,1,.36,1); chips/sets scale 0.95 on press.
- Respect Reduce Motion: freeze background drift, ships, and float animations.

## State Management
```swift
struct DayState {
  var loggedExtras: [Int] = []          // indices into quickFoods
  var setsDone: Set<String> = []        // "exerciseIndex-setIndex"
  var restSeconds: Int = 0              // counts down each second
  var gender: Gender = .male
  var planetIndex: Int = 2              // 0...5
  var foodLogTab: Int = 0               // Fuel food log: 0 = Meals, 1 = By hour
}
```
Static data: targets (2,350 kcal · P185 C240 F72), base consumed (1,047 · P74 C117 F30), meals, quick foods (with macros), exercises (with set counts + muscle tag), muscle levels (1–6 per group). Derived: totals, remaining, per-macro %, done fraction, level colors. No networking.

Note: the HTML logic keys per-screen values with an `A` suffix and branches on a `glass` flag — remnants of a removed second variant. Only variant A exists; ignore the suffix scheme and the non-glass branches when porting.

## Suggested SwiftUI Decomposition
One workable module layout for the greenfield build (naming free; the split matters):

- `Theme.swift` — palette presets, blend/tint math, 6-stop level scale, neutrals, type styles (all values in "Design Tokens")
- `AppStore.swift` — `@Observable` store: `DayState` + static data + derived values (totals, remaining, score, doneTags)
- `Screens/` — `HomeView` · `FuelView` · `TrainView` · `BodyView` · `SettingsSheet`; each screen is the shared ZStack recipe (starfield → optional hero → scrolling content with top spacer → bottom fade → tab bar)
- `Components/` — reusable views and where they recur:
  - `GlassCard` (every card, all screens) · `SectionLabel` (every section header)
  - `ProgressRing` (Home calories r54 · Fuel macros r24) · `MacroBar` (Home macros, Fuel remaining)
  - `GradientPillButton` (Home CTA) · `StatChip` (Home score/burn pair)
  - `SegmentedToggle` — ONE component, three uses: M/W (Body), Meals/By hour (Fuel), Metric/Imperial (Settings)
  - `QuickAddChip` + `MealCard` (Fuel meals) · `HourTimeline` (Fuel by-hour) · `SetCircle` (Train) · `LevelSegments` + `MuscleRow` (Body) · `Sparkline` (Home weight) · `GlassTabBar` (all screens)
- `Space/` — `StarfieldView` (TimelineView + Canvas), `HeroSceneView` (SceneKit; home/fuel/train configurations), procedural texture + mesh builders
- `Figures/` — the four Body figures as `Path` collections from `figure-paths.md`

## Extending the UI (conventions for future features)
Follow these so new UI reads as the same app:
- **New screen** = the shared ZStack recipe with a fresh deterministic starfield seed; content column padding 64/16/140; add a tab-bar item as a simple line glyph (active = white 9% pill + `#F3E8FF`).
- **New card** = GlassCard tokens verbatim (fill `rgba(23,15,44,0.32)`, blur 4, border white 10%, radius 22, padding 16–18, 12pt gap below the SectionLabel).
- **Colors**: never introduce new hues — derive from the active palette via blend (as Theme does). Neutrals only from the constants list. Every new surface must recolor correctly under all 4 presets.
- **Type**: numbers/wordmarks Space Grotesk, body DM Sans; respect the size ladder (captions 9.5–11, body 12–13, titles 19, stats 34–40).
- **State**: hang new interactions off the shared store so cross-screen reactions keep working; transitions 0.4–0.7s with the `(.22,1,.36,1)` curve; pressed elements scale 0.95.
- **Hit targets** ≥ 44pt even when the glyph is smaller (pad the tappable area — e.g. 36pt set circles, 30pt avatar).

## Accessibility
- Reduce Motion: freeze starfield drift, ships, float loops, and scroll-driven 3D (idle spin may stay).
- VoiceOver: rings/bars expose value + target ("1,303 of 2,350 kilocalories"); set circles expose "Set 2, done/not done" toggles; muscle rows read "{group}, {level}, trained today".
- Text uses fixed reference sizes; if adopting Dynamic Type, scale the whole ladder proportionally so card layouts hold.

## 3D & Animated Background (SceneKit / SpriteKit / Canvas)
- **Gas-giant texture (procedural, 512×256)**: fill horizontal bands (heights 6–30px) with random palette blends at 50–100% alpha; then shear each pixel row horizontally by `sin(y·0.085+seed)·10 + sin(y·0.021+seed·2.7)·26` (wrap); add 4 storm ellipses (light accent/secondary over dark offset shadow); darken poles with a vertical gradient. Home planet seed = 5 + 9·planetIndex; Fuel planet uses fixed seed 11.
- **Home planet**: sphere r 1.12 (scene scaled ×0.62), soft back-lit atmosphere shell (primary-light, ~13% alpha), accent-colored moonlet (r 0.11, secondary emissive) orbiting r 2.5; rings: flat annuli, count = planetIndex, radius 1.5+0.26i, width 0.16, alternating secondaryLight/accent/primary at opacity .34−.04i. **No wireframe overlays.**
- **Fuel scene**: planet r 0.66; 3 thin tori r 1.15/1.55/1.95 (tilts z 0 / +0.3 / −0.25); moons r 0.13/0.16/0.105, angular speeds 0.5/0.36/0.27 rad/s; moon scale = 0.78 + 0.5×macroPct (+pulse on log).
- **Train asteroid**: icosahedron subdiv 4, vertices displaced by `1 + 0.17·sin(3.1x)sin(2.7y+1.7)sin(3.7z+0.6) + 0.05·sin(8y+5x)`, flat shading, base #5B4D7D, emissive = secondary at intensity 0.1 + 1.6×(setsDone/16); 3 small orbiting debris rocks.
- Lighting: ambient #9A8CC9 0.6 + white directional 1.15 from (3,4,5) + secondary point light 1.3 from (−3.5,−2,3).
- **Background layer (every screen)**: 155–220 stars — 5 gaussian clusters (20–33 each; cluster stars brighter, alpha 0.5–1.0, ~22% accent-tinted) + 55 loose (alpha 0.3–0.85); deterministic seed per screen (home 5 · fuel 6 · train 7 · body 8) so layouts are stable; big stars get a 2.7× halo at 25% alpha; pre-rendered nebula blobs behind clusters (primary/secondary radial gradients ~26%→0, plus small accent core); layers shift with scroll (offset = scroll·150·depth, depths 0.14–0.42) and drift slowly. **Shooting star** every 3.5–10.5s: 0.75s white streak with secondary fade tail. **Tiny ship** every 14–40s: dart-shaped hull (10×9pt path), primary cockpit dot, secondary engine glow + 25pt fading trail, crosses horizontally at 44–74 pt/s with a gentle sine bob. Ships toggleable.

## Assets
No raster assets. Fonts: Space Grotesk + DM Sans (Google Fonts — bundle .ttf or substitute SF). All icons are simple line/geometric shapes (recreate as SF Symbols or paths). Muscle-figure geometry is extracted verbatim into `figure-paths.md` (four 220×290 SVGs + fill-mapping table); sparkline points and tab icons remain in the HTML — copy coordinates directly.

## Files
- `figure-paths.md` — the four muscle-figure SVGs (male/female × front/back, 220×290 grid) with muscle-fill mapping — the source of truth for Body-figure geometry.
- `Orbit Fitness.dc.html` — the full interactive prototype (open in a browser; variant A = left/top row, screens 1a–1d). Logic (data, palette math, 3D parameters) is in the `<script data-dc-script>` block at the bottom — fully commented with a SwiftUI porting map (state → @Observable store, palette → Theme struct, 3D scenes → SceneKit, starfield → TimelineView+Canvas). The HTML template is annotated too: a REBUILD SPEC header comment (design vs scaffolding, layer stack, recurring tokens, template-hole conventions) plus per-screen and per-card structural comments.
- `ios-frame.jsx`, `support.js` — preview scaffolding only (device bezel + runtime). Not part of the design.
