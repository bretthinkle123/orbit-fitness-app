# Run 4 — App Store submission pass

_Pre-launch gate 4 of 4 → LAUNCH. Consumed by requirements-elicitation + planning at run
start. Greenfield already ships the mechanically-gated subset: account deletion
(5.1.1(v)), `PrivacyInfo.xcprivacy` + Required-Reason declarations, ATS on,
`ITSAppUsesNonExemptEncryption`, inert capability stubs — `store-compliance.sh`
critical=0. This run does everything else between a repo and a listing (the
app-store-submission-requirements skill is the checklist authority)._

## Scope
- **Privacy nutrition labels** reconciled against the REAL data map as built after runs
  2–3 (Health & Fitness category for weight/diet data; consent flow described); labels
  must match the privacy manifest and actual collection — mismatch is a rejection class.
- **Signing/capabilities:** distribution cert + profiles, App ID, entitlements (none
  beyond baseline expected pre-HealthKit); CI archive/notarize lane if desired.
- **App Store Connect setup:** app record under the official name **"Orbit Fitness &
  Diet Tracking"** (29 chars, fits the 30 limit; home-screen display name stays "Orbit").
  Name-collision note: multiple "Orbit" fitness apps coexist ("orbit" is a weak/common
  mark) — exact string availability confirmed likely; optional trademark clearance
  (USPTO classes 9/41/44) if budget allows.
- **Listing assets:** screenshots — one 6.9-inch iPhone set (1320×2868; 6.7-inch
  fallback accepted, Apple auto-scales smaller sizes; a 13-inch iPad set only if iPad is
  supported; re-verify exact specs at submission time), description, keywords,
  category (Health & Fitness), **age rating questionnaire**, **privacy policy URL +
  support URL** (must exist and describe the health-data handling from run 2's legal
  review).
- **Review-guideline self-checklist:** 5.1.1 data collection/consent, 5.1.3 health-data
  (no ads use — true by architecture), 4.2 minimum functionality (fine), 2.1 completeness
  (no stub confusion: the four inert log-method buttons must not look broken — decide
  copy/hide state for v1).
- **TestFlight:** internal + small external beta round; crash triage via Sentry/dSYMs
  (wired in run 1) before submitting.
- Export compliance answer (standard encryption exemption — flag already set).

## Key decisions
Stub-button presentation at launch (hide vs "coming soon"); phased release %; launch
markets — if EU is included: GDPR lawful-basis/consent readiness is assumed covered by
run 2's consent work, and the Art. 20 export (run 12) must pull forward ahead of EU
availability; confirm both with counsel.

## Acceptance sketch
`store-compliance.sh` full pass; label ⇄ manifest ⇄ actual-collection three-way match
documented; TestFlight build distributed + beta feedback triaged; submission checklist
signed off; app submitted (approval itself is external — track, don't gate).

## Size
Small-medium; mostly Connect/config/assets work, minimal code (stub presentation, build
settings).
