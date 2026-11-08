# docker/firebase-emulator/

## Purpose

Builds the Firebase Auth emulator image used by the compose stack. No official image exists,
so it is built in-repo from a digest-pinned `node` base and a pinned `firebase-tools`. The
Auth emulator is a Node process; the image has no JRE (evidence: `docs/local-development.md`,
"The Firebase emulator image: no JDK").

## Modules

| File | Role |
|---|---|
| `Dockerfile` | Pinned base, installs `firebase-tools` (`FIREBASE_TOOLS_VERSION` must match `.github/workflows/pipeline-ci.yml`; asserted by `tests/unit/test_local_stack_config.py`) |
| `firebase.json` | Enables only the `auth` emulator on port 9099, host `0.0.0.0`, UI off |
| `entrypoint.sh` | Starts the emulator, imports prior state if present, exports to `/data/state` on exit so users survive a graceful stop |

## How they relate

The `Dockerfile` copies `firebase.json` and `entrypoint.sh` into `/app`. The entrypoint
exports to a subdirectory of the `/data` volume because the CLI replaces its export
directory wholesale, which fails on a mount point.
