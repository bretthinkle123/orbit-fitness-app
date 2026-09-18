# C2 — Food logging integrations (Search · Scan · Label)

_Phase C (features, local + Simulator), run 2 of 8. Likely three sub-runs in this order:
(a) text search + food database, (b) barcode scan, (c) nutrition-label OCR. Un-stubs
three of the four `LogMethodButton`s greenfield ships inert; **Photo** stays stubbed
(meal-photo recognition is deferred — see Out of scope). Consumed by
requirements-elicitation + planning at run start._

## Goal
Logging real-world foods without manual macro entry. This is the single biggest
daily-utility upgrade and retention driver.

## Decisions already made (owner, 2026-09-18)
- **Food-data source: USDA FoodData Central (FDC)**, the only provider this run.
  - Free, with a free API key from api.data.gov.
  - Data is public domain (CC0). Confirm the licence and current rate limits in-run; the
    default api.data.gov limit has been 1,000 requests/hour per key.
  - Barcode coverage comes via the Branded Foods `gtinUpc` field; it is US-skewed.
  - It works for local development: the **backend** calls FDC over the internet, and the
    Simulator only ever talks to the local API. The key never ships in the app.
- **Barcode miss → manual entry**, pre-filled with the scanned barcode. **Open Food Facts
  is not integrated.** It stays a documented later option (better international coverage;
  ODbL attribution/share-alike obligations to review if ever adopted).
- **Meal-photo recognition is out of scope.** The server-side ML option costs money per
  call and sends images off the device. Only on-device label OCR is built.
- _Options considered before the decision_: FDC vs Open Food Facts (free/ODbL, variable
  quality) vs commercial APIs (Nutritionix/FatSecret: cost, licensing, uptime SLA).

## Sub-run (a) — Search + food database
- **New endpoint `GET /catalog/search?q=`** — **a new free-text input surface**:
  - Length-bound, pattern-sane query validation
  - Tier-2 uid-keyed rate limit (search is the abuse magnet)
  - Bounded results (LIMIT, no pagination yet)
- **Outbound FDC calls** go through a provider facade with timeout, retry and circuit
  breaker (api-edge-conventions). A cache layer controls call volume and latency and
  keeps usage well inside the FDC rate limit: Redis, or a local `foods_cache` table.
- **FDC API key**: stored via the secrets facade — locally, a LocalStack secret seeded
  from A1's gitignored `.env.local`. Never hardcoded, never in the iOS app.
- **Tests never call FDC.** The provider facade is exercised against recorded fixture
  responses, so tests and CI are deterministic and offline. One opt-in live smoke check
  may exist for manual use.
- **`food_entries` gains two columns** (an additive migration):
  - `source` — `manual|quick|search|scan|label`, nullable. Existing rows stay NULL
    (pre-integration legacy); greenfield's explicit-macros path maps to `manual`,
    quick-add to `quick`.
  - `external_food_id` — the FDC id, nullable.
  - Both get classification rows (roadmap standing rule 2). Food-entry values are already
    B2-encrypted.

## Sub-run (b) — Barcode scan
- **Camera permission**: `NSCameraUsageDescription` + privacy manifest. The nutrition
  label update rides the E3 submission. The camera is used on-device only; if frames
  never leave the device, the label impact is the usage string + manifest, not data
  collection.
- **VisionKit/AVFoundation scanner** → barcode → FDC `gtinUpc` lookup via the backend;
  a miss goes to prefilled manual entry.
- **Simulator limitation:** the Simulator has no camera, and the live scanner reports
  itself unsupported there. Local verification therefore:
  - Feeds a barcode value in through a **DEBUG-only injection path**, compiled out of
    Release builds and asserted absent from them.
  - Runs the lookup/miss flows end-to-end from there.
  - Real-camera scanning is verified later, on a physical device (E3's TestFlight round).

## Sub-run (c) — Nutrition-label OCR
- **On-device Vision text recognition** reads the label; extracted values go to a
  confirm-and-edit screen before saving (never saved blind). Free and privacy-friendly:
  images never leave the device and are never uploaded.
- Works in the Simulator on still images — sample label photos added to the Simulator's
  library, plus fixture images for unit tests of the parsing logic.

## Security / compliance notes
- SSRF n/a: fixed FDC host allowlist.
- Provider API key via the secrets facade.
- Search queries are user content: log length/shape only, never the text.
- New entries emit B1 audit events.
- Provider ToS/licence recorded in docs.

## Out of scope
- Meal-photo recognition (deferred; see roadmap "Deferred beyond go-live")
- Open Food Facts or any second provider
- Commercial food APIs

## Acceptance sketch
- Search returns bounded, cached results within the perf budget.
- An entry created from search carries correct macros + `source` + `external_food_id`.
- Rate limit proven.
- Provider outage (fixture-simulated) degrades to quick-add, never a 5xx.
- Barcode hit/miss flows pass XCUITest via the DEBUG injection path.
- The DEBUG path is absent from the Release build.
- Label OCR parses the fixture labels correctly, and confirm-before-save holds.
- Permission strings/manifest updated; licence recorded.

## Size
(a) medium; (b) small-medium; (c) medium. Keep them as separate PR trains.
