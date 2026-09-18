# E3 — App Store submission pass (go live)

_Phase E (going live), run 3 of 3 → LAUNCH. **Parked until the owner decides to go live,
and only after every Phase A–D feature works locally in the Simulator** (owner rule,
2026-09-17). Requires E1 (a live API) and E2. Consumed by requirements-elicitation +
planning at run start. Greenfield already ships the mechanically-gated subset: account
deletion (5.1.1(v)), `PrivacyInfo.xcprivacy` + Required-Reason declarations, ATS on,
`ITSAppUsesNonExemptEncryption`, inert capability stubs — `store-compliance.sh`
critical=0. This run does everything else between a repo and a listing (the
app-store-submission-requirements skill is the checklist authority)._

## Scope
- **Privacy nutrition labels** reconciled against the REAL data map as built through
  Phases B–D (Health & Fitness category for weight/diet data and HealthKit activity; B2
  consent flow described; camera used on-device only by C2's scanner); labels
  must match the privacy manifest and actual collection — mismatch is a rejection class.
- **Signing/capabilities:** distribution cert + profiles, App ID, entitlements (the
  HealthKit entitlement from C6 is now expected, plus the camera usage string from C2);
  CI archive/notarize lane if desired. Requires the **Apple Developer Program ($99/yr)**.
- **App Store Connect setup:** app record under the official name **"Orbit Fitness &
  Diet Tracking"** (29 chars, fits the 30 limit; home-screen display name stays "Orbit").
  Name-collision note: multiple "Orbit" fitness apps coexist ("orbit" is a weak/common
  mark) — exact string availability confirmed likely; optional trademark clearance
  (USPTO classes 9/41/44) if budget allows.
- **Listing assets:** screenshots — one 6.9-inch iPhone set (1320×2868; 6.7-inch
  fallback accepted, Apple auto-scales smaller sizes; a 13-inch iPad set only if iPad is
  supported; re-verify exact specs at submission time), description, keywords,
  category (Health & Fitness), **age rating questionnaire**, **privacy policy URL +
  support URL** (must exist and describe the health-data handling; free hosting such as
  GitHub Pages is fine). **Legal/counsel review of the privacy policy** happens here — it
  moved from the old SOC brief when its data-hardening part became B1/B2, and B2 drafted
  the text.
- **Review-guideline self-checklist:** 5.1.1 data collection/consent, 5.1.3 health-data
  (no ads use — true by architecture), 4.2 minimum functionality (fine), 2.1 completeness
  (no stub confusion: after C2 only the **Photo** log-method button is still inert —
  meal-photo recognition is deferred — so decide its copy/hide state for v1).
- **TestFlight:** internal + small external beta round; crash triage via Sentry/dSYMs
  (wired in E1) before submitting. The TestFlight round is also where the **real-device
  checks the Simulator couldn't do** are discharged: C2's live camera barcode scanning
  and C6's HealthKit with real Watch/iPhone-motion data.
- Export compliance answer (standard encryption exemption — flag already set).

## Key decisions
- **Monetization: free vs freemium, decided before this run.** It was deferred from the
  coach run (C7, note-only). If freemium: plan the StoreKit + entitlement + webhook run
  before submission, and gate the coach via C7's entitlement shape.
- Photo-button presentation at launch (hide vs "coming soon")
- Phased release %
- Launch markets. If EU is included: GDPR lawful-basis/consent readiness is covered by
  B2's consent work, and the Art. 20 export already exists (D1); confirm both with
  counsel.

## Acceptance sketch
`store-compliance.sh` full pass; label ⇄ manifest ⇄ actual-collection three-way match
documented; TestFlight build distributed + beta feedback triaged; submission checklist
signed off; app submitted (approval itself is external — track, don't gate).

## Size
Small-medium; mostly Connect/config/assets work, minimal code (stub presentation, build
settings).
