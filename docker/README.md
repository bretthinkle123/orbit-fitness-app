# docker/

## Purpose

Container build contexts for images the local stack needs that no trustworthy upstream
publishes. The API image's `Dockerfile` is at the repo root; compose wiring is in
`docker-compose.yml`. Local-environment narrative: `docs/local-development.md`.

## Modules

| Path | What it is |
|---|---|
| `firebase-emulator/` | Firebase Auth emulator image (see its README) |

## How they relate

`docker-compose.yml` builds `firebase-emulator/` as the `firebase-emulator` service.
