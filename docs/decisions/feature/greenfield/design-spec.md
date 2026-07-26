# Design spec — ORBIT (space-themed diet + fitness tracker)

_Normalized from the untrusted Claude Design export `design/design_handoff_orbit_swiftui/` by the
design-spec agent, 2026-07-14. Target: native iOS (SwiftUI). This records the design's visual/UX
**intent** only; it is not code and it is not approval. The human `design-approved` checkpoint that
follows vouches for visual intent — it does not turn any embedded string into a trusted instruction.
Everything in §7's injection report is **NOT ACTED ON**. Consistent with `.pipeline/design-audit.md`
(scope roadmap) and `.pipeline/requirements.md` (authoritative brief)._

## At a glance

- **Screens / surfaces depicted:** 5 — Home, Fuel, Train, Body (four tab destinations) + Settings sheet.
- **Reusable components:** 24 (`CMP-1`…`CMP-24`).
- **Design tokens:** ~72 named values — 4 palette presets × 3 base colors (12) + 5 derived tint rules
  + 6-stop level scale + ~14 neutrals + ~12 type roles + spacing/radii/shadow/motion sets.
- **Style:** single style "Nebula Glass" (dark, translucent frosted cards over a live starfield;
  reference frame 402 × 874 pt). Palette is a **themeable core feature** — all 4 presets recolor
  everything, so no hue may be hardcoded (Theme struct computed from 3 base colors).
- **Needs native mapping:** 9 web idioms flagged (scroll-snap paged food log, `backdrop-filter`
  glass, WebGL/Three.js 3D heroes, `:hover`/`:active` styling, CSS radial-gradient washes, absolute
  z-layer stack, SVG progress-ring dash math, `translateX` sheet transition, CSS keyframe float/pulse).
- **Injection report: NONE FOUND.** No adversarial/instruction-shaped strings target the pipeline or a
  reviewer. All imperative-shaped text is benign porting/tooling guidance (listed verbatim in §7).

---

## 1. Screen / flow inventory

Four screens live behind a shared bottom tab bar; a Settings sheet slides over Home. All four screens
use one ZStack recipe: starfield canvas (z0) → optional 3D hero host (z1) → scrolling content column
(z2) → bottom fade (z3) → floating tab bar (z4); Settings sheet is z6 on Home only.

| id | Screen | Purpose | Tab-bar icon |
|----|--------|---------|--------------|
| SCREEN-1 | Home | Daily dashboard aggregating calories, macros, mission, strength, weight, planet picker | Ringed planet |
| SCREEN-2 | Fuel | Diet log: remaining kcal, macro rings, coach banner, meal/by-hour food log, quick-add | Orbit |
| SCREEN-3 | Train | Workout logging: strength score, Push Day session with tappable sets, rest timer, week strip | Diamond asteroid |
| SCREEN-4 | Body | Muscle map: front+back geometric figures, M/W toggle, 6-level scale, by-muscle list | Person |
| SCREEN-5 | Settings sheet | Profile, Mission (budget/split/adaptive), Preferences (units/reminders/haptics), System (appearance/export/sign-out) | (modal; no tab) |

### Navigation edges (what triggers each transition)

| From | Trigger | To | Notes |
|------|---------|----|-------|
| any | tab-bar item tap | Home / Fuel / Train / Body | Only the active-item highlight moves; markup identical per screen. Prototype renders all 4 as a static gallery row — actual tab switching is an **open item** for the SwiftUI build. |
| SCREEN-1 Home | tap avatar "AK" (30pt, top-right) | SCREEN-5 Settings sheet | Slides in from right (`translateX 102%→0`, .5s); 3D hero keeps animating beneath. |
| SCREEN-5 Settings | tap back chevron (top-left) | SCREEN-1 Home | Slides back out. |
| SCREEN-1 Home | tap "Start Push Day" CTA | (undepicted) | No wired destination in prototype; intent implies Train. **Open item.** |
| SCREEN-1 Home | tap a planet chip (6) | (in place) | Re-textures the 3D hero + sets ring count = chip index; no screen change. |
| SCREEN-2 Fuel | tap a dinner quick-add chip | (in place) | Appends food row, chip flips to "✓ name"; updates rings/bars/budget on ALL screens + pulses matching 3D macro moon. Idempotent per food. |
| SCREEN-2 Fuel | tap "Meals"/"By hour" OR swipe panels | (in place) | Segmented control + horizontal paged panels stay in sync. |
| SCREEN-3 Train | tap a set circle | (in place) | Toggles set done; ON (re)starts 120s rest countdown; score = 512 + done sets everywhere; heats asteroid; lights Body muscles. |
| SCREEN-4 Body | tap M / W | (in place) | Crossfades male/female figures (front + back). |
| SCREEN-2/5 | Metric/Imperial, toggles | (in place) | Settings state changes. |

**Open items (undepicted flows required by scope — designed later per README "Extending the UI"):**
onboarding / sign-in / register / name; account-deletion action (Settings System section); weight-entry
sheet (Home weight card shows data, no input UI); budget & macro-split editor sheets (chevron rows exist,
editors don't); Scan/Photo/Search/Label log-method flows (4 buttons render, no flow depicted); zero-data
states for Home/Train/Body (only Fuel's Dinner-empty is depicted).

---

## 2. Component inventory

| id | Component | Variants | Interactive states | Used on |
|----|-----------|----------|--------------------|---------|
| CMP-1 | GlassCard | standard (r22, fill .32) · small chip (r10–14, fill .38) | static | all screens (every card) |
| CMP-2 | SectionLabel | — | static | all card headers |
| CMP-3 | HeaderWordmark | ORBIT / FUEL / TRAIN / BODY + gradient dot | static | all screen headers |
| CMP-4 | Avatar | 30pt (Home header) · 52pt (Settings profile), initials "AK" | pressed (scale .9) | Home, Settings |
| CMP-5 | ProgressRing | r54 (Home calories, 9pt stroke) · r24 (Fuel macros, 6pt stroke) | default; animates dash-offset .7s | Home, Fuel |
| CMP-6 | MacroBar | 7pt rounded, colors secL/pri/acc | animates width .6s | Home (macros), Fuel (remaining) |
| CMP-7 | GradientPillButton | 46pt, r23, 135° pri→sec gradient + glow | hover (brightness 1.12), pressed (scale .98) | Home ("Start Push Day") |
| CMP-8 | StatChip | Strength score · Burn rate | static | Home |
| CMP-9 | SegmentedToggle | M/W (Body) · Meals/By-hour (Fuel) · Metric/Imperial (Settings) | selected / unselected (bg .14 vs transparent) | Body, Fuel, Settings |
| CMP-10 | PlanetPickerChip | 6 named chips (Ember…Zenith), dot = level color | active (highlight + secL border) / inactive; pressed (scale .94) | Home |
| CMP-11 | QuickAddChip | +name (unadded) / ✓name (added, tinted) | default / added / pressed (scale .95) | Fuel (Dinner) |
| CMP-12 | MealCard | Breakfast / Lunch / Dinner / Meals and Snacks | Dinner has empty state (dashed divider + "Nothing logged — quick add:") | Fuel (Meals tab) |
| CMP-13 | HourTimeline | rows 6 AM–9 PM, hour dot + rail, entry chips, NOW marker | dot lit when hour has entries; pulsing NOW row | Fuel (By-hour tab) |
| CMP-14 | LogMethodButton | Scan / Photo / Search / Label (46pt glass circles) | hover (bg .11); **action stubbed — no flow** | Fuel |
| CMP-15 | CoachBanner | secondary-tinted info banner | static | Fuel ("Mission Control:…") |
| CMP-16 | TipBanner | secondary-tinted tip banner | static | Body ("Tip:…") |
| CMP-17 | SetCircle | 36pt numbered circle | default / done (135° gradient fill + glow) / pressed (scale .9) | Train |
| CMP-18 | RestChip | "REST m:ss" | visible only while rest > 0 (counts down from 2:00) | Train |
| CMP-19 | WeekStrip | 7 dots (4 filled) | static (design shows fixed pattern) | Train |
| CMP-20 | Sparkline | 30-day weight, area fill + line + scatter dots + end dot | static (coordinates are design data) | Home |
| CMP-21 | MuscleRow | color dot + name + 6-segment bar + level label + optional "▲ today" | today-flag when trained | Body (13 rows) |
| CMP-22 | LevelLegend | 6-stop gradient bar, Beginner…World Class | static | Body |
| CMP-23 | MuscleFigure | male/female × front/back (4 SVGs, 220×290 grid) | per-muscle fill = level color; trained-today = secL glow; float ±7pt; M/W crossfade | Body |
| CMP-24 | GlassTabBar | 4 items (Home/Fuel/Train/Body) | active = white 9% pill + #F3E8FF icon/label | all screens |
| CMP-25 | SettingsRow | chevron row (budget, macro split, appearance, export) · toggle row (adaptive, reminders, haptics) · action row (sign-out) | chevron rows tappable (editors undepicted); toggle knob slides `translateX(17px)` | Settings |

_(Design README's "Suggested SwiftUI Decomposition" maps these to `GlassCard`, `SectionLabel`,
`ProgressRing`, `MacroBar`, `GradientPillButton`, `StatChip`, `SegmentedToggle`, `QuickAddChip` +
`MealCard`, `HourTimeline`, `SetCircle`, `LevelSegments` + `MuscleRow`, `Sparkline`, `GlassTabBar`.)_

---

## 3. Design tokens

Single source of visual truth. Every palette-derived value is computed from the active 3-color palette
via linear-RGB blend — **do not hardcode hues** (CLAUDE.md Theme rule). Read from README §"Design
Tokens" and the `<script>` block (`_pal`, `_scale6`, `_setsVals`) and inline styles in the HTML.

### 3.1 Color — palette presets (user picks one of 4; everything recolors)

| Preset | primary | secondary | accent | Source |
|--------|---------|-----------|--------|--------|
| Purple (default) | `#8B5CF6` | `#D946EF` | `#F0ABFC` | README L23; script `data-props.palette.default` |
| Blue | `#3B82F6` | `#22D3EE` | `#93C5FD` | README L24; script options[1] |
| Red | `#EF4444` | `#FB7185` | `#FED7AA` | README L25; script options[2] |
| Green | `#10B981` | `#84CC16` | `#6EE7B7` | README L26; script options[3] |

### 3.2 Color — derived tints & dark washes (per palette)

| Token | Rule | Source |
|-------|------|--------|
| secondaryLight (`cSecL`) | blend(secondary → `#FFFFFF`, 28%) | README L28; `_pal` |
| primaryLight (`cPriL`) | blend(primary → `#FFFFFF`, 30%) | README L29; `_pal` |
| primaryLighter (`cPriLL`) | blend(primary → `#FFFFFF`, 50%) | README L30; `_pal` |
| primaryDark (`rPriD`) | blend(primary → `#000000`, 12%) | `renderVals` |
| primaryDark2 (`rPriD2`) | blend(primary → `#000000`, 28%) — used for the two screen radial washes | README L42; `renderVals` |

### 3.3 Color — 6-stop strength-level scale (Beginner → World Class, per palette)

| Stop | Level name | Rule | Source |
|------|-----------|------|--------|
| 1 | Beginner | blend(primary → `#0B0620`, 55%) | README L33; `_scale6` |
| 2 | Novice | blend(primary → `#0B0620`, 28%) | README L34 |
| 3 | Intermediate | primary | README L35 |
| 4 | Advanced | blend(primary → secondary, 55%) | README L36 |
| 5 | Elite | secondaryLight | README L37 |
| 6 | World Class | blend(accent → `#FFFFFF`, 45%) | README L38 |

_Open item / defect note: the script also carries a **static** array `D.scale =
['#4a3878','#5f42b0','#8b5cf6','#c052e8','#e879f9','#fcd8ff']` (the Purple-computed scale). It is
defined but not read by render (`mList`/legend use the live `_scale6()`); treat `_scale6()` as
canonical and the static array as a dead artifact._

### 3.4 Color — neutrals (constant across palettes)

| Token | Value | Source |
|-------|-------|--------|
| Screen background | `#04050E` + radial wash `rgba(rPriD2,.30)` top-right (150%×70% at 80%,−15%) + `rgba(rPriD2,.35)` bottom-left (120%×55% at 0%,100%) | README L42; inline |
| Card fill | `rgba(23,15,44,0.32)`, backdrop blur 4 | README L43 |
| Card border | `1px rgba(255,255,255,0.10)` | README L43 |
| Small chip fill | `rgba(23,15,44,0.38)` | README L43 |
| Tab-bar fill | `rgba(22,13,42,0.78)`, blur 18 | README L58; inline |
| Tab-bar active pill | `rgba(255,255,255,0.09)`, active icon/label `#F3E8FF` | README L58 |
| Text primary | `#F4F0FF` (rows also use `#F1ECFD`) | README L44 |
| Text muted | `rgba(216,206,238,0.62)` | README L44 |
| Text faint | `rgba(216,206,238,0.45)` (also .55 / .5 / .35 in tiers) | README L44 |
| Figure neutral fill | `rgba(244,240,255,0.13)` (head/neck/hands/pelvis/knees/feet) | figure-paths.md L11 |
| Figure outline | `1px rgba(12,6,26,0.4)` | figure-paths.md L11 |
| Bottom fade | linear-gradient(0°, `#04050E` 25% → transparent), 112pt, non-interactive | README L58; inline |
| Settings profile email | `alex.kepler@orbit.app` (demo copy) | HTML L228 |

### 3.5 Typography

| Role | Family / size / weight | Source |
|------|------------------------|--------|
| Display / numbers / wordmark | **Space Grotesk** (substitute SF Pro Rounded semibold) | README L49 |
| Body / UI | **DM Sans** (substitute SF Pro) | README L50 |
| Wordmark | 14 / 700, tracking .24em | README L50 |
| Greeting / screen title | 25 / 600, tracking −.01em | README L50 |
| Big stat | 34–40 / 700 (Fuel remaining 34; Train score 40; Home calRem 26; Home stat 24) | README L50 |
| Card title | 19 / 600 | README L50 |
| Body | 12–13 | README L50 |
| Captions | 9.5–11 | README L50 |
| Section label | 10.5 / 600, letter-spacing .18em, UPPERCASE, muted | README L45 |
| Micro / today-flag | 8.5–9 | inline |

_JetBrains Mono is loaded in the HTML but used only by gallery chrome (`.dv-*`) — not part of the design.
Fonts are OFL: bundle `.ttf` or substitute SF._

### 3.6 Spacing, radii, elevation, motion

| Group | Values | Source |
|-------|--------|--------|
| Screen / content padding | screen 16; content column 64 / 16 / 140 (top/side/bottom) | README L54; inline |
| Card padding | 16–18; card-to-card gap 12; header side pad 4 | README L54 |
| Hero top spacer | Home 244 · Fuel 224 · Train 214 (reserves the 3D hero, top ~440pt); Body has no hero | README L58 |
| Radii | cards 22 · pill button 23 (46pt tall) · tab bar 26 · chips 10–14 · segmented 8–13 · progress bars 4–7pt | README L53 |
| Shadow / glow | CTA `0 6px 22px rgba(sec,.35)` · ring glow `drop-shadow 0 0 7px rgba(sec,.55)` · set-done `0 0 12px rgba(sec,.45)` · trained-muscle `drop-shadow 0 0 7px secL@.85` | inline; figure-paths.md L20 |
| Progress-ring math | r54 → circumference 339.3; r24 → 150.8; rotate(−90°) to start at 12 o'clock; progress = dash-offset | README L74; inline |
| Motion — fills | color/fill .4s | README L108 |
| Motion — bars/rings | .5–.7s cubic-bezier(.22,1,.36,1) | README L108 |
| Motion — press | chips/sets scale 0.95 (avatar 0.9, CTA 0.98) | README L108 |
| Motion — float | figures ±7pt on ~5.5–6s ease loop (`oFloat`) | figure-paths.md L6; inline |
| Motion — pulse | status/NOW dots 2.4s (`oPulse`) | inline |
| Motion — sheet | Settings slide .5s cubic-bezier(.22,1,.36,1) | inline |
| Global | motionSpeed prop .25–2× time multiplier; parallax hero translateY up to −95pt; ships toggle | script `data-props` |

---

## 4. Layout intent

Fixed reference layout is 402 × 874 pt (iPhone); recreate at reference size then adapt to device sizes.
All screens are a full-bleed dark ZStack; content scrolls over a pinned 3D hero + starfield.

- **SCREEN-1 Home** — header (gradient dot + ORBIT wordmark left · avatar right) pinned above a 244pt
  hero gap → greeting block → vertically stacked cards in order: "Your system" planet picker → calories
  ring card (124pt ring left, Eaten/Burned/Budget column right) → macros card (3 bars) → mission card
  (gradient CTA) → 2 side-by-side stat chips → weight-trend card (sparkline). Single column, 12pt gaps.
- **SCREEN-2 Fuel** — header (FUEL + "Today" chip) → 224pt hero gap → centered macro legend chips →
  remaining card (34pt number + gradient bar) → 3 macro rings in a row → coach banner → food-log header
  (SectionLabel + Meals/By-hour segmented control) → **two horizontally paged panels** (Meals cards /
  By-hour timeline) → 4 log-method buttons in a row.
- **SCREEN-3 Train** — header (TRAIN + "Wk 8 · Block 2" chip) → 214pt hero gap → strength-score card
  (40pt score, delta chip, 68% progress bar) → session card ("Push Day", done/16 counter, RestChip,
  thin progress bar, 5 exercise blocks each with a row of tappable 36pt set circles) → week strip.
- **SCREEN-4 Body** — header (BODY + "Results" chip) → "Body map" title + score subtitle → muscle-levels
  card (M/W toggle top-right; **front figure then, scrolling down, back figure**, each captioned; 6-stop
  legend bar) → "By muscle group" card (13 rows) → tip banner. **No 3D hero — starfield only.**
- **SCREEN-5 Settings sheet** — full-height overlay from the right: back chevron + "Settings" title →
  profile card (52pt avatar, name, email, current-planet chip) → Mission section (Daily budget row ›,
  Macro split row ›, Adaptive-targets toggle) → Preferences (Units segmented, Reminders toggle, Haptics
  toggle) → System (Appearance ›, Export data ›, Sign out) → version footer "ORBIT v0.9 · DAY 12 IN ORBIT".

**Adaptive behavior (intent):** the layout is a fixed single-column phone design; README says recreate
pixel-perfect at reference size then scale to device sizes; if adopting Dynamic Type, scale the whole
type ladder proportionally so card layouts hold. Header pinned; content scrolls; tab bar + bottom fade
pinned. No multi-column / wide-screen variant is depicted (**open item** for iPad/landscape).

---

## 5. Interaction notes

- **Shared store, cross-screen reactions:** one state drives all screens. Quick-add on Fuel updates
  Home's ring + macro bars + Fuel rings + the 3D macro moon (pulse). Set toggles on Train update the
  score everywhere, heat the asteroid, and light the corresponding Body muscles + set "▲ today".
- **Set toggle:** tap a set circle → toggles done (135° gradient fill + glow when on); turning ON
  (re)starts a 120s rest countdown shown as a "REST m:ss" chip that hides at 0. Score = 512 + doneCount;
  weekly delta = "+{4+done} this wk".
- **Quick-add:** idempotent per food; chip flips "+name" → "✓ name" tinted; dinner kcal = sum of added.
- **Food-log paging:** Meals/By-hour is a segmented control **and** horizontally swipeable panels kept in
  sync (scroll-snap paging in the prototype). By-hour is a 6 AM–9 PM timeline; hour dots light when they
  have entries; a pulsing "Now · 7:42 PM" marker sits in the 7 PM row; dinner quick-adds appear there live.
- **M/W toggle:** swaps male/female figures (front + back) with a crossfade.
- **Planet picker:** index 0–5 → 3D texture-seed change + ring count = index (0 rings "Ember" … 5 "Zenith");
  caption uses singular "1 ring" at index 1. Prototype swaps instantly; ≤0.3s crossfade acceptable.
- **Settings sheet:** slides `translateX(102%→0)` over everything incl. tab bar; 3D hero keeps animating
  beneath; back chevron closes. Toggle knobs slide `translateX(17px)`; segmented controls restyle inline.
- **Scroll-driven 3D (per screen, normalized scroll 0–1, smoothed ~8%/frame):** Home planet spins (idle
  0.14 rad/s + 2.6× scroll), rings tilt, camera pulls z 4.6→4.05; Fuel camera descends top-down→edge-on,
  orbit yaw += 1.5× scroll; Train camera orbits azimuth 2.4× scroll around the asteroid; hero layer also
  parallax-translates up to −95pt.
- **Ambient motion:** starfield drifts + parallax-shifts with scroll; shooting star every 3.5–10.5s; tiny
  ship fly-by every 14–40s (toggleable); figures float ±7pt; status/NOW dots pulse.
- **Transitions:** color/fill .4s; bars/rings .5–.7s cubic-bezier(.22,1,.36,1); press scale .95.
- **Accessibility (acceptance criteria per README):** Reduce Motion **freezes** starfield drift, ships,
  float loops, and scroll-driven 3D (idle spin may remain). VoiceOver: rings/bars expose value + target
  ("1,303 of 2,350 kilocalories"); set circles are "Set 2, done/not done" toggles; muscle rows read
  "{group}, {level}, trained today". Hit targets ≥ 44pt even when the glyph is smaller (36pt set circles /
  30pt avatar pad their tappable area).

---

## 6. Needs native mapping (web export → SwiftUI)

REQUIRED. Each web idiom below has no clean 1:1 SwiftUI equivalent; the downstream plan must translate
intent, not port markup. (For an iOS target, `apple-hig-compliance` + `claude-design-to-swiftui` consume
this section.)

| # | Web idiom | Where it appears | Why it needs a native decision |
|---|-----------|------------------|--------------------------------|
| NM-1 | Horizontal **scroll-snap** paged panels + a scroll listener syncing a segmented control | Fuel food log (Meals ⇄ By-hour) | No CSS scroll-snap in SwiftUI. Map to a paged `TabView` (`.tabViewStyle(.page)`) bound to the segmented `SegmentedToggle`; the script's snap/listener workaround is explicitly web-only (comment: "SwiftUI: a plain withAnimation on the paged offset"). |
| NM-2 | `backdrop-filter: blur()` frosted glass (cards blur 4, tab bar blur 18, banners blur 10) | every GlassCard, tab bar, coach/tip banners | Use SwiftUI `Material` (e.g. thin/ultraThin dark) at reduced opacity so the starfield reads through; exact 32% fill + blur radius won't map literally — tune to the "stars read through" intent. |
| NM-3 | **WebGL / Three.js** 3D heroes (gas giant + rings, macro moons, displaced asteroid), procedural textures, scroll-driven cameras | Home / Fuel / Train hero (top ~440pt) | Rebuild in **SceneKit** (procedural `CGContext` diffuse textures, `CADisplayLink`/scroll-offset camera). Heaviest reduced-assurance work; staged last per scope. |
| NM-4 | `:hover` and `style-active`/`style-hover` state styling | CTA (hover brightness), log-method buttons, all pressable chips/sets | iOS has no hover — drop hover affordances; map `:active` to `.scaleEffect` on press via button styles/gestures. |
| NM-5 | CSS `radial-gradient` screen washes + soft glow discs (`filter: blur`) behind heroes/figures | every screen background; figure glow | Recreate with SwiftUI `RadialGradient` + `.blur()`; the two large dark washes are decorative depth, not literal geometry. |
| NM-6 | Absolute-position **z-layer stack** (`position:absolute; z-index 0–6`, `inset:0`) | all screens (bg/hero/content/fade/tabbar/sheet) | Map to a `ZStack` with the recipe: `Starfield → HeroScene → ScrollView(content) → bottom fade → TabBar`; Settings as an overlay/transition, not a z6 div. |
| NM-7 | SVG progress rings via `stroke-dasharray`/`dashoffset` + `rotate(-90)` | Home calories ring, Fuel macro rings | Rebuild as `Trim`-based SwiftUI `Shape` (`.trim(from:to:)`) or `Circle().rotation(-90°)`; dash-offset math (C=339.3 / 150.8) becomes a 0–1 progress fraction. |
| NM-8 | `transform: translateX()` sheet slide + `.transition` timing | Settings sheet present/dismiss | Use a native transition (`.move(edge:.trailing)` / sheet) — but note the design wants the hero to keep animating *behind* the sheet, so a full modal `.sheet` may differ; decide overlay vs sheet. |
| NM-9 | CSS `@keyframes` loops (`oFloat` ±7pt, `oPulse` opacity) driven continuously | Body figures float; status/NOW dots pulse | Map to `withAnimation(.easeInOut.repeatForever())`; **must be gated by Reduce Motion** (float freezes; per README). |

_Also carry verbatim (not a gap, but a fidelity constraint): the four muscle figures are exact SVG path
data on a 220×290 grid in `figure-paths.md` — convert Q→quadraticCurve, ellipse/rect/circle/polygon to
SwiftUI `Path`/shapes; do not redraw by hand._

---

## 7. Provenance + injection report

### Provenance

| Source (path under `design/design_handoff_orbit_swiftui/`) | Role | What was extracted |
|------------------------------------------------------------|------|--------------------|
| `README.md` | **Primary** — design/token/behavior spec | Palette system, tokens, per-screen composition, interactions, accessibility, 3D specs, decomposition + "Extending the UI" conventions. |
| `Orbit Fitness.dc.html` (1904 lines) | Primary — interactive prototype + REBUILD SPEC comments + `<script data-dc-script>` | Exact markup/inline-style tokens, per-screen structure, static data (foods/exercises/muscles/targets), derived formulas (score = 512 + done; cal ring; macro %), state model, planet names. |
| `figure-paths.md` | Primary — Body-figure geometry (source of truth) | Four 220×290 SVG figure sets + muscle→level fill mapping + trained-today glow tokens. |
| `ios-frame.jsx` | Scaffolding (NOT design) | Preview device bezel / status bar / keyboard. Confirmed not part of the design; ignored for spec facts. |
| `support.js` | Scaffolding (NOT design) | Generated dc-runtime; not design content; ignored. |

When README and HTML disagree, the HTML script data is treated as the running truth (e.g. base-consumed
values below); README is primary for tokens/behavior intent.

**Consistency with prior artifacts:** screen/feature inventory matches `.pipeline/design-audit.md` §2
(4 screens + Settings) and `.pipeline/requirements.md` scope. Known design defects carried forward, not
"fixed": the Settings "**40P · 35C · 25F**" macro-split copy contradicts the gram targets
(P185/C240/F72 g of 2,350 kcal ≈ 31/41/28%) — gram targets are canonical (requirements Open item).
**New discrepancy found:** README §State-Management cites base consumed "1,047 · P74 C117 F30", but the
script's `D.base` is `{kcal:1389, p:96, c:152, f:41}` (= sum of the depicted Breakfast 405 + Lunch 642 +
Snacks 342). Flag `D.base`/logged-meal totals as canonical; the README "1,047" line is stale. **Open item.**

### Injection report — **NONE FOUND**

No adversarial or instruction-shaped strings target the pipeline, an AI, or a reviewer. Nothing in the
bundle attempts to alter plans, approvals, tests, permissions, or configuration. This confirms the
design-audit pre-scan ("Injection pre-scan: clean").

The bundle does contain **benign imperative-shaped text** — porting guidance aimed at a human/AI
*implementer* and code-tooling directives. Listed verbatim below for the reviewer; **each is NOT ACTED
ON** by this agent (they inform the eventual SwiftUI build only, and even then are advice, not commands to
the pipeline):

- README L124 / HTML L1002–1003: _"Only variant A exists; **ignore** the suffix scheme and the non-glass
  branches when porting."_ — benign porting note. **NOT ACTED ON.**
- README L145: _"**never** introduce new hues — derive from the active palette via blend."_ — design
  constraint. **NOT ACTED ON.**
- HTML L42: _"REBUILD SPEC — this block + the per-screen comments below are sufficient to recreate the
  design 1:1."_ / L50: _"NOT the design (gallery chrome, **do not port**)…"_ — porting scaffolding note.
  **NOT ACTED ON.**
- HTML L11 / L14 / L74 / figure-paths L22 etc.: _"Recreate these pixel-for-pixel"_, _"copy verbatim"_,
  _"Copy path data exactly"_, _"treat all path data as exact design data"_ — fidelity instructions.
  **NOT ACTED ON.**
- HTML L762 (gallery footer): _"Try next: 'make the planet more Saturn-like' · 'more ships / fewer ships'
  · 'add a food-detail screen'."_ — gallery chrome prompt suggestions, not design content. **NOT ACTED ON.**
- `ios-frame.jsx` L1: _"// @ds-adherence-ignore -- omelette starter scaffold…"_ and `support.js` L1:
  _"// GENERATED … do not edit. Rebuild with `cd dc-runtime && bun run build`."_ — tooling/lint directives
  in scaffolding files. **NOT ACTED ON** (no command executed; scaffolding is out of scope).

No image/OCR content exists in this bundle (no raster assets — README §Assets confirms "No raster
assets"), so there is no image-embedded text to report.

---

_End of spec. Awaiting the human `design-approved` checkpoint. This agent does not approve its own output._
