# Run 5 — Food-logging integrations (Search · Scan · Photo · Label)

_Post-launch run; likely 2–3 sub-runs in this order: (a) text search + food DB,
(b) barcode scan, (c) photo recognition + label OCR. Un-stubs the four `LogMethodButton`s
greenfield ships inert. Consumed by requirements-elicitation + planning at run start._

## Goal
Logging real-world foods without manual macro entry — the single biggest daily-utility
upgrade and retention driver.

## Sub-run (a) — Search + food database
- **The decision that shapes everything: the food-data source.** USDA FoodData Central
  (free; US-skewed; barcode coverage exists via the Branded Foods `gtinUpc` field) vs
  Open Food Facts (free/ODbL, stronger international barcode coverage, variable quality
  — check attribution/share-alike obligations) vs commercial API
  (Nutritionix/FatSecret — cost, licensing, uptime SLA). Licensing review is part of the
  run.
- New endpoint `GET /catalog/search?q=` — **a new free-text input surface**: length-bound
  + pattern-sane query validation, Tier-2 uid-keyed rate limit (search is the abuse
  magnet), bounded results (LIMIT + no pagination yet), outbound calls through a
  timeout/retry/circuit facade (api-edge-conventions); cache layer (Redis or a local
  `foods_cache` table) to control cost/latency.
- `food_entries` gains `source` (`manual|quick|search|scan|photo|label`, nullable —
  existing rows stay NULL = pre-integration legacy; greenfield's explicit-macros path
  maps to `manual`, quick-add to `quick`) + `external_food_id` (nullable) — additive
  migration.

## Sub-run (b) — Barcode scan
- Camera permission: `NSCameraUsageDescription` + privacy-manifest + **nutrition-label
  update at next submission** (new data type collected? camera is on-device only — label
  impact is usage-string + manifest, not collection, if frames never leave device).
- VisionKit/AVFoundation scanner → barcode → food-DB lookup (source must have barcode
  coverage — feeds decision (a)).

## Sub-run (c) — Photo recognition + label OCR
- Highest cost/complexity: on-device Vision OCR for labels (privacy-friendly, free) vs
  server-side ML API for meal photos (cost per call, images-leave-device ⇒ major privacy
  label + consent change — **photos of food are still user content**; if server-side,
  images must be transient, never stored). Lean: label OCR on-device first; meal-photo
  recognition last or dropped if economics don't work.

## Security / compliance notes
SSRF n/a (fixed API host allowlist); provider API key via Secrets Manager facade; search
queries are user content — log length/shape only, never the text; provider ToS review.

## Acceptance sketch
Search returns bounded, cached results within perf budget; entry-from-search carries
correct macros + source; rate limit proven; provider outage degrades to quick-add (no
5xx); scan happy-path XCUITest; permission strings/manifest updated; licensing recorded.

## Size
(a) medium; (b) small-medium; (c) medium-large. Keep as separate PR trains.
