# ios/Orbit/Config/

## Purpose

Per-configuration build settings for the Orbit app target.

## Modules

| File | Role |
|---|---|
| `Debug.xcconfig` | `ORBIT_API_BASE_URL` = `http://localhost:8080` and `ORBIT_FIREBASE_AUTH_EMULATOR_HOST` = `localhost:9100` (the compose stack) |
| `Release.xcconfig` | Pre-existing placeholder `http://localhost:8001` (owed to E1/E3) and an empty emulator host |

## How they relate

`ios/Orbit/project.yml` attaches each file to its configuration. Values reach the app through
`Info.plist`; the emulator wiring in `OrbitApp.swift` is compiled into Debug only. The `$()`
inside the URLs keeps `//` from starting an xcconfig comment. See `docs/local-development.md`.
