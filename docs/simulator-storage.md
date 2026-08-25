# Simulator storage budget — monitoring the Mac across testing runs

_Owner: the operator's Mac (`plans/00-mac-pipeline-readiness.md` Phase 5). Check with
`scripts/check_simulator_storage.sh` before and after every simulator-backed testing run;
append the result to the [run log](#run-log) at the bottom of this file._

## Why this file exists

On **2026-08-12**, the first Mac testing run after the greenfield merge filled the data
volume to **99% (3.6 GB free)**. The failure did not present as a disk problem. Under that
space pressure iCloud Drive evicted the Python venv's files to the cloud — they show
`dataless` in `ls -lO` — so every `import` blocked on a network fetch. `import pytest`
took over **75 seconds** and looked exactly like a hung test suite. Time was spent chasing
a `subprocess.stdout.read()` deadlock in `tests/conftest.py` before the real cause
surfaced.

**The cost of a full disk here is a misdiagnosis, not an error message.** That is what this
budget is designed to prevent.

## The one distinction that matters

Storage on this machine splits into two categories that behave completely differently.

**Fixed costs do not grow with the app's feature set.** A simulator runtime is a full copy
of iOS — every system framework, the dyld shared cache, the whole root filesystem — so the
device can execute real iPhone binaries. iOS 26.5 is ~20 GB expanded (from an 8.52 GB
download) and would be exactly the same size if Orbit had 5 screens or 500. None of the
runs in `docs/roadmap.md` change this number.

**Growing costs accumulate across testing runs.** Simulator device data, DerivedData,
SwiftPM caches, and Docker images grow every time you build and run. All of them are safely
deletable and regenerate on the next run. These are what the default check watches.

The practical consequence: **adding features is not what fills this disk.** The repo is
19 MB of source. What fills it is (a) a new simulator runtime at each Xcode upgrade, and
(b) build artifacts nobody pruned.

## Measured baseline — 2026-08-12

First full accounting, taken on the operator's MacBook Air after the iOS 26.5 runtime
download. Data volume: **228 GB capacity, 178 GB used, 3.6 GB free**.

| Item | Size | Category |
|---|---|---|
| `/Applications` (all apps; Xcode is 4 GB of it) | 45 GB | Fixed |
| `/Library/Developer/CoreSimulator` — total | 27 GB | Fixed |
| — mounted runtime volumes (iOS 26.5) | 20 GB | Fixed |
| — runtime disk images (incl. watchOS 9.4, dated 2023) | 3.3 GB | Fixed, prunable |
| `~/Library` (caches, iCloud local cache, app support) | 25 GB | Mixed |
| `~/anaconda3` | 6.1 GB | Unrelated to this project |
| `~/Library/Caches/org.swift.swiftpm` | 628 MB | Growing |
| `~/Library/Developer/CoreSimulator` (device data) | 324 MB | Growing |
| `~/Library/Developer/Xcode/DerivedData` | 88 MB | Growing |
| **Orbit repo — all source, design export, git history** | **19 MB** | Negligible |

No Time Machine local snapshots existed to purge, so that common reclaim path was not
available.

## Thresholds

| Free space | Status | Meaning |
|---|---|---|
| ≥ 15 GB | OK | Safe to start a simulator run and pull Docker images. |
| 8–15 GB | WARN | Reclaim before adding a runtime or new Docker images. |
| < 8 GB | FAIL | **Do not start a simulator testing run.** Reclaim first. |

The floor is sized so a simulator run and a Docker-backed backend suite both fit without
pushing the volume into the iCloud eviction behavior described above. Override per-machine
with `ORBIT_STORAGE_MIN_FREE_GB` / `ORBIT_STORAGE_WARN_FREE_GB`.

## How to run the check

```sh
# Fast — the growing costs only. Run before and after each testing run.
scripts/check_simulator_storage.sh

# Fast check + append a row to the run log at the bottom of this file
scripts/check_simulator_storage.sh --log --label="before AC27 walk"

# Also measure the fixed costs (slow: du over ~27 GB of runtimes)
scripts/check_simulator_storage.sh --full
```

Exit codes let a run gate on the result: `0` within budget, `1` below warn, `2` below the
hard floor. If the run passes `-derivedDataPath` to a scratch directory (as the pipeline
does), point the check at it with `ORBIT_DERIVED_DATA_PATH` or that build output is
invisible to the totals.

## Reclaim playbook

In the order to try them — cheapest and least destructive first.

```sh
# 1. Unused simulator devices (keeps runtimes; deletes accumulated device data)
xcrun simctl delete unavailable

# 2. Build artifacts — always safe, always regenerate
rm -rf ~/Library/Developer/Xcode/DerivedData/*
rm -rf ~/Library/Caches/org.swift.swiftpm

# 3. Old simulator runtimes — the big one, ~20 GB each.
#    List first, then delete only what no target needs. Orbit is iOS-only:
#    a watchOS or tvOS runtime here is pure dead weight.
xcrun simctl runtime list
xcrun simctl runtime delete <identifier>

# 4. Docker images from the backend suite (re-pulled on next run)
docker system prune -a
```

**Check `df -h /System/Volumes/Data`, never `df -h /`.** On APFS the `/` mount is the
sealed read-only system snapshot; it reported 17 GB used / 3.6 GB free on a machine whose
real data volume was 178 GB used. Reading the wrong volume was itself a wrong turn during
the 2026-08-12 run.

## Standing rules

1. **Prune runtimes at every Xcode upgrade.** This is the only cost that grows without
   bound. Each new iOS version adds ~20 GB and old runtimes do not remove themselves — the
   watchOS 9.4 image from September 2023 in the baseline above is the proof.
2. **Keep the repo outside iCloud-synced folders.** A checkout under `~/Desktop` or
   `~/Documents` gets evicted under space pressure, which breaks builds and test runs in
   ways that look like application bugs. `~/repos/` is safe.
3. **Run the check on both sides of a testing run** and log the result, so growth is
   visible as a trend rather than discovered at 99% full.
4. **Never store a Python venv inside a synced checkout.** Create it outside the tree; the
   eviction failure mode above is specifically what this prevents.

## Run log

_Appended by `scripts/check_simulator_storage.sh --log` (newest last). This table is the
last thing in the file by construction — the script appends rows to the end._

| Date | Label | Free | Reclaimable | Status | Host |
|---|---|---|---|---|---|
| 2026-08-12 | baseline after iOS 26.5 runtime download | 3.6 GB | 1.0 GB | FAIL | operator MacBook Air |
