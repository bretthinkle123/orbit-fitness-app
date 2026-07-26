# Fonts — TODO for the Mac phase

**Status: not yet bundled.** This Linux build host has no network path this session was
authorized to use for fetching font binaries, and no Swift/Xcode toolchain to embed or
verify them anyway (`.pipeline/implementation-progress.md`'s T11 entry). Per plan.md's
Open Question 6 default, the app runs correctly without these files: `DesignSystem/
Font+Theme.swift`'s `OrbitFontFamily.isEmbedded` checks at runtime whether each family's
`.ttf` is actually registered and falls back automatically to the recorded SF substitute
(SF Pro Rounded for the display/numbers family, SF Pro for body/UI) when it is not. Nothing
in this task is blocked on the fonts landing — this file exists so the Mac-phase operator
(`plans/00-mac-pipeline-readiness.md` Phase 5) knows exactly what to fetch and where it goes.

## What to fetch

Both are Google Fonts, OFL-1.1 licensed (free to bundle in the app), named verbatim in the
design export (`design/design_handoff_orbit_swiftui/README.md` lines 48–50, 164):

| Family | Role | Google Fonts page |
|---|---|---|
| Space Grotesk | Display / numbers / wordmark | https://fonts.google.com/specimen/Space+Grotesk |
| DM Sans | Body / UI | https://fonts.google.com/specimen/DM+Sans |

Download each family's static `.ttf` files (not the variable-font build — `UIAppFonts`
wants one concrete weight per file) and place them directly in this directory
(`ios/Orbit/Resources/Fonts/`):

| Exact filename | PostScript name `Font+Theme.swift` expects |
|---|---|
| `SpaceGrotesk-Regular.ttf` | `SpaceGrotesk-Regular` |
| `SpaceGrotesk-Medium.ttf` | (loaded for completeness; `Font+Theme.swift` maps `.medium`/`.semibold` weights to the SemiBold file) |
| `SpaceGrotesk-SemiBold.ttf` | `SpaceGrotesk-SemiBold` |
| `SpaceGrotesk-Bold.ttf` | `SpaceGrotesk-Bold` |
| `DMSans-Regular.ttf` | `DMSans-Regular` |
| `DMSans-Medium.ttf` | `DMSans-Medium` |
| `DMSans-Bold.ttf` | `DMSans-Bold` |

Verify each file's actual PostScript name after adding it (Font Book, or `fc-scan
--format '%{postscriptname}\n' <file>`) — Google Fonts' shipped PostScript names have
matched the table above historically, but confirm rather than assume before wiring
`UIAppFonts`, since a mismatch here means `OrbitFontFamily.isEmbedded` silently stays
`false` and the app quietly keeps using the SF substitute instead of erroring.

Also copy the OFL license text (`OFL.txt`, included in each Google Fonts download zip)
into this directory — both faces require redistributing the license alongside the files.

## Wiring (do this once the `.ttf` files are in this directory)

1. Add all seven `.ttf` files (this directory) to the `Orbit` target's **Copy Bundle
   Resources** build phase (XcodeGen: add a `resources:` entry for
   `Resources/Fonts` in `ios/Orbit/project.yml` — see that file's own `# TODO(fonts)`
   comment).
2. In `Resources/Info.plist` (created by T13 — `App/{OrbitApp,...}` task), add a
   `UIAppFonts` array listing each of the seven filenames above.
3. Rebuild and confirm `OrbitFontFamily.isEmbedded` flips to `true` for both families
   (`ThemeTests.swift` doesn't assert this directly — it tests the color/percentage math,
   not font embedding — but a manual Font Book / `po UIFont.familyNames` check in the
   debugger is a quick confirmation).

Until all three steps above are done, the app is fully functional and faithful to the
design's *type ramp* (sizes/weights/tracking) — only the specific typeface differs
(SF Pro Rounded / SF Pro instead of Space Grotesk / DM Sans), which is the explicitly
recorded, plan-approved fallback, not a defect.
