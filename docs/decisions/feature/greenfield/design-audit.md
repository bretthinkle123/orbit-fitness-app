# Design audit — ORBIT (Diet + Fitness tracker)

_Scope-level audit of `design/design_handoff_orbit_swiftui/` (Claude Design export),
rewritten 2026-07-14 after verifying the README's claims against the prototype template
and script (`Orbit Fitness.dc.html`, 1904 lines; script block from line 765). This is the
ROADMAP layer that feeds planning. The component/token-level normalization + the gated
injection report are still produced by the **design-spec agent** (`.pipeline/design-spec.md`)
— this audit does not replace that stage._

**Injection pre-scan: clean.** No adversarial imperatives in the bundle; the only "ignore"
is a benign porting note (ignore a removed variant's key-suffix scheme). `ios-frame.jsx` /
`support.js` are preview scaffolding, not design content.

**Operator scope ruling (2026-07-14):** the greenfield run includes the **full depicted
feature set** — all four screens + Settings, backed by the real backend — not a thin
slice. Inclusion test used throughout: **a feature is in scope iff its flow is depicted in
the design (or is required and designable from the README's "Extending the UI"
conventions); a feature whose flow is undepicted (button/label only, or algorithm behind a
number) ships as a stub/default and is deferred to a named future run.**

## 1. What the bundle is

Native-iOS (SwiftUI) **diet + strength-training tracker**, space-themed ("Nebula Glass"),
high-fidelity (colors/spacing/copy/interactions are final intent; reference frame
402×874pt). Prototype is **client-only ("No networking")** on static data — so it fully
specifies the frontend and is silent on backend/API/algorithms. Files: `README.md`
(thorough handoff spec), `Orbit Fitness.dc.html` (interactive prototype + commented
porting map), `figure-paths.md` (muscle-figure geometry, source of truth).

## 2. Verified feature inventory (depicted)

**Home — daily dashboard:** ORBIT header + avatar; greeting + date + "Day 12 in orbit";
calories ring (remaining/eaten/burned/budget); macro bars (P/C/F vs targets); "Today's
mission" card (Push Day + CTA); strength-score + burn-rate stat chips; weight trend card
(182.4 lb, ↓0.4 lb/wk, 30-day sparkline); "Your system" planet picker (6 chips, re-textures
hero, ring count = level).

**Fuel — diet log:** remaining-today card + gradient bar; 3 macro rings; coach banner
("Mission Control: … carbs +15 g from Monday"); food log grouped by meal (Breakfast 405 ·
Lunch 642 · Snacks 342 · Dinner starts empty) with **Meals ⇄ By-hour** paged toggle
(hourly timeline 6AM–9PM, now-marker, live-appearing quick-adds); quick-add chips (3
dinner foods, idempotent per food, flip to ✓); log-method buttons **Scan · Photo · Search
· Label** (buttons only — no flow depicted).

**Train — workout logging:** strength-score card (score, +wk delta, "Intermediate II",
68% bar to Advanced, "Top 22% @ 183 lb"); session card "Push Day" (5 exercises, name ·
sets×reps · weight · muscle tag, tappable set circles, done = gradient fill); **rest
timer** (REST m:ss, 120s countdown on set completion); week strip (7 dots, 4 filled).
Depicted score formula: `score = 512 + setsDoneToday`; delta `+{4+done} this wk`.

**Body — results:** muscle map, front + back figures, **M/W toggle** (crossfade);
13 muscle groups on a 6-level scale (Beginner→World Class); level legend; "trained today"
glow derived from today's logged sets (depicted logic); by-muscle list (13 rows, level
bars, "▲ today"). Figure geometry supplied verbatim in `figure-paths.md` (four 220×290
SVG sets → SwiftUI `Path`).

**Settings sheet (README under-sells this — verified in template):** profile block
(avatar "AK", "Alex Kepler"); **Mission section: editable calorie budget row ("2,350 kcal ›")
and macro split row ("40P · 35C · 25F ›")** (chevron rows — editors themselves undepicted;
NB the split copy contradicts the P185/C240/F72 g day targets, which compute to ≈31/41/28%
— prototype inconsistency; gram targets canonical, see requirements Open);
Preferences: **Metric/Imperial** segmented toggle; System section incl. **Sign out**.
Palette picker (4 presets) and ships toggle per README/props.

**Cross-cutting:** 4-preset themeable palette (everything recolors — core feature); shared
store (Fuel logs ⇄ Home ring; Train sets ⇄ score everywhere ⇄ Body glow); animated
starfield (deterministic per-screen seeds, shooting stars, occasional ships, toggleable);
3D SceneKit heroes (Home gas giant + rings; Fuel planet + 3 macro moons that scale with
macro %; Train displaced asteroid that heats with sets) with scroll-driven cameras;
Reduce Motion + VoiceOver behavior specified; fonts Space Grotesk + DM Sans (OFL —
bundle or substitute SF).

## 3. Key audit finding — the depicted/undepicted line

The design depicts **flows** for: food quick-add logging, meal + by-hour views, set
toggling + rest timer, planet picking, M/W + units + palette settings, sign-out, and all
dashboard displays. The design does **not** depict (button/label/number only):

1. **Onboarding / sign-in / registration** — no auth screens at all (avatar implies an
   account). Required anyway (Firebase auth) → design per README "Extending the UI".
2. **Account deletion UI** — required (App Store 5.1.1(v), prior requirement) → Settings
   System section, per conventions.
3. **Weight entry flow** — trend card shows data; no input UI → minimal entry sheet, per
   conventions.
4. **Budget / macro-split editors** — chevron rows exist; editor screens don't → simple
   edit sheets, per conventions.
5. **Scan / Photo / Search / Label** — 4 buttons, zero flow → stubs this run; each is a
   real integration (barcode DB, photo recognition, label OCR, food-search DB) = future runs.
6. **Adaptive coach algorithm** — banner copy only ("Coach adjusts Mon") → banner renders
   a server-supplied message (static default); TDEE/adjustment engine = future run.
7. **Strength tier / percentile formulas** — labels only → stored profile defaults
   ("Intermediate II", "Top 22% @ 183 lb", 68%); real algorithms = future run.
8. **Muscle-level derivation from lift history** — Body says "Levels from your logged
   lifts" but prototype levels are static defaults; only the **trained-today glow** has
   depicted logic → static per-user base levels + trained-today derivation now; history
   engine = future run.
9. **Program builder / periodization** — "Wk 8 · Block 2" chip only → one seeded Push Day
   program; builder = future run.
10. **Rank progression** — "rank up to travel further" caption; no rule → planet picker =
    persisted cosmetic choice; progression mechanics = future run.
11. **Burned kcal / burn rate source** — static "+412" / "2,847"; no activity input exists
    anywhere in the app → optional server field defaulting to 0/absent; real source
    (wearables) = future run.
12. **Empty / first-run states** — only Dinner-empty is depicted → planning defines
    zero-data states for Home/Train/Body per conventions.
13. **Day rollover / timezone, multi-day history** — everything shown is "today" (+30-day
    weight, week strip) → day-keyed data model; day = user's device-timezone local date
    (default; open item).
14. **Error / loading states** — prototype has no networking → prior requirement stands:
    error state + manual retry, no offline.

## 4. Backend surface implied (design is silent — must be designed)

Entities: user profile/settings (palette, units, gender, planet index, kcal budget, macro
gram targets (P/C/F), score base, tier/percentile placeholders, muscle base levels); food entries
(day-keyed: name, kcal, P/C/F, meal group, logged-at); quick-food catalog (global seed,
with macros); program + exercises (seeded Push Day: scheme, weight, muscle tag); set
events (day-keyed: exercise, set index, done-at — toggleable); weight entries (day-keyed,
canonical metric storage, display converts per units). Derived server- or client-side per
depicted formulas: totals, remaining, per-macro %, score, trained-today tags, weekly
delta. **All list queries day-/window-scoped AND hard-capped (LIMIT) — no unbounded
SELECT (carried F4-05 lesson).** Row-level ownership by Firebase UID everywhere; account
deletion cascades all of it.

## 5. Risks / directives for planning

- **Run size is the #1 risk.** This is a full app: planning MUST emit `tasks.md`
  (well over the ≥8-file threshold) and implementation runs per-task segments.
- **Stage fidelity inside the run:** early tasks = backend + functional UI on flat/simple
  backgrounds; later tasks = starfield → animations → 3D SceneKit → scroll-driven
  cameras. A cap must land after function exists, not before.
- **Reduced assurance (Swift):** the heaviest work (3D, theme math, figures, animation)
  is exactly what the deterministic gates can't analyze. Surface the stamp at the diff
  checkpoint; backend keeps full gate coverage. Perf budget (p95<300ms @ ~10 conc)
  applies to the API.
- **Adopt the README's "Suggested SwiftUI Decomposition"** (Theme / AppStore / Screens /
  Components / Space / Figures) and its "Extending the UI" conventions for all undepicted
  screens (auth, deletion, weight entry, editors) so extensions read as the same app.
- **Accessibility acceptance criteria** come straight from the README: Reduce Motion
  freezes drift/ships/float/scroll-3D; VoiceOver values for rings/bars/sets/muscle rows.
- **Seed/demo split:** new users start empty (design's Dinner-empty pattern); the
  prototype's demo day (meals, 4 filled week dots, weight series) lives in previews/tests
  only. Quick-food catalog + Push Day program are real seed data.
- Fonts are OFL — bundle `.ttf` or substitute SF per README.

## 6. Future feature-runs (named deferrals)

1. Food logging integrations: barcode Scan, Photo recognition, nutrition-Label OCR,
   food-Search database.
2. Adaptive diet coach (TDEE / weekly macro adjustments) — replaces static banner.
3. Muscle-level derivation from lift history (+ level-up events).
4. Strength tiers/percentiles engine; program builder / periodization.
5. Activity/burn source (wearables / Apple Health) — replaces burned-kcal placeholder.
6. Rank-progression mechanics (planets earn rings).
7. export-my-data (GDPR portability); retention automation.
8. App Store submission pass (privacy labels, signing, review checklist).
