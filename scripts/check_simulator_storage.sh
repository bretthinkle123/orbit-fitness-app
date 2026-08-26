#!/usr/bin/env bash
# Storage budget check for the iOS Simulator + build caches on the operator's
# Mac (`plans/00-mac-pipeline-readiness.md` Phase 5). Run it BEFORE and AFTER
# every simulator-backed testing run; see `docs/simulator-storage.md` for the
# budget, the reclaim playbook, and the per-run log this script appends to.
#
# Why this exists: on 2026-08-12 the first Mac test run after the greenfield
# merge filled the data volume to 99% (3.6 GB free). Under that pressure iCloud
# Drive evicted the Python venv's files to the cloud (`dataless` in `ls -lO`),
# so every `import` blocked on a network fetch — `import pytest` took over 75
# seconds and presented as a hung test suite, not as a disk problem. The cost
# of a full disk here is a misdiagnosis, which is why this check is cheap and
# runs on both sides of a testing run.
#
# What it measures, and why the split matters:
#   - FIXED costs (simulator runtimes, Xcode) are one-time and do NOT grow with
#     the app's feature set. A runtime is a full copy of iOS (~20 GB for
#     iOS 26.5), identical whether Orbit has 5 screens or 500. These are only
#     re-measured under `--full` because `du` over them is slow.
#   - GROWING costs (simulator device data, DerivedData, SPM caches, Docker
#     images) accumulate across testing runs and are what this check watches by
#     default. All are safely deletable; they regenerate.
#
# macOS portability (the engine's two real risk classes, per the runbook):
# bash 3.2 compatible — no `mapfile`, no `declare -A`, no `${var^^}`; and no
# GNU-only tools — no `stat -c`, `timeout`, `sha256sum`, or `date -d`.
#
# Exit codes (so a run can gate on this): 0 = within budget, 1 = below the warn
# threshold, 2 = below the hard floor (do not start a simulator run).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORAGE_DOC="${REPO_ROOT}/docs/simulator-storage.md"

# Thresholds in GB, overridable per-machine. The floor is sized so that a
# simulator run plus a Docker-backed backend suite both fit without pushing the
# volume into the eviction behavior described above.
WARN_FREE_GB="${ORBIT_STORAGE_WARN_FREE_GB:-15}"
MIN_FREE_GB="${ORBIT_STORAGE_MIN_FREE_GB:-8}"

FULL=0
APPEND_LOG=0
LABEL=""
for arg in "$@"; do
    case "${arg}" in
        --full) FULL=1 ;;
        --log) APPEND_LOG=1 ;;
        --label=*) LABEL="${arg#--label=}" ;;
        -h|--help)
            echo "usage: $(basename "$0") [--full] [--log] [--label=<text>]"
            echo "  --full   also measure the fixed costs (simulator runtimes); slow"
            echo "  --log    append a row to docs/simulator-storage.md"
            echo "  --label  text for the log row (e.g. 'before AC27 walk')"
            exit 0
            ;;
        *) echo "unknown argument: ${arg}" >&2; exit 64 ;;
    esac
done

# Prints a whole number of MB for a path, or 0 if it does not exist.
#
# `du` exits non-zero when it cannot walk a subdirectory — which is guaranteed
# here: /Library/Developer/CoreSimulator holds root-owned runtime internals
# (e.g. .../RuntimeRoot/private/var/db/modelmanagerd) that deny access even to
# an admin user. It still prints a correct grand total on its last line, so the
# non-zero exit must be swallowed explicitly: under `set -euo pipefail` a bare
# `du ... | awk ...` would abort the whole script mid-report.
dir_mb() {
    if [ ! -e "$1" ]; then
        echo "0"
        return 0
    fi
    local kb
    kb="$( { du -sk "$1" 2>/dev/null || true; } | tail -1 | awk '{ print $1 }')"
    if [ -z "${kb}" ]; then
        kb=0
    fi
    awk -v kb="${kb}" 'BEGIN { printf "%d", kb / 1024 }'
}

human_gb() {
    awk -v mb="$1" 'BEGIN { printf "%.1f", mb / 1024 }'
}

# IMPORTANT: measure /System/Volumes/Data, NOT `/`. On APFS `df -h /` reports
# the sealed read-only system snapshot (it showed 17 GB used / 3.6 GB free on a
# machine whose real data volume was 178 GB used) — reading `/` here would
# quietly report the wrong volume.
DATA_VOLUME="/System/Volumes/Data"
if [ ! -d "${DATA_VOLUME}" ]; then
    DATA_VOLUME="/"
fi
FREE_KB="$(df -k "${DATA_VOLUME}" | awk 'NR==2 { print $4 }')"
USED_KB="$(df -k "${DATA_VOLUME}" | awk 'NR==2 { print $3 }')"
CAPACITY="$(df -k "${DATA_VOLUME}" | awk 'NR==2 { print $5 }')"
FREE_GB="$(awk -v kb="${FREE_KB}" 'BEGIN { printf "%.1f", kb / 1048576 }')"
USED_GB="$(awk -v kb="${USED_KB}" 'BEGIN { printf "%.1f", kb / 1048576 }')"

# Growing costs — the ones that accumulate across testing runs.
DEVICES_MB="$(dir_mb "${HOME}/Library/Developer/CoreSimulator/Devices")"
CACHES_MB="$(dir_mb "${HOME}/Library/Developer/CoreSimulator/Caches")"
DERIVED_MB="$(dir_mb "${HOME}/Library/Developer/Xcode/DerivedData")"
SPM_MB="$(dir_mb "${HOME}/Library/Caches/org.swift.swiftpm")"
# A run that passes -derivedDataPath elsewhere (the pipeline uses a scratch dir)
# is invisible to the line above, so allow it to be pointed at explicitly.
EXTRA_DERIVED_MB=0
if [ -n "${ORBIT_DERIVED_DATA_PATH:-}" ]; then
    EXTRA_DERIVED_MB="$(dir_mb "${ORBIT_DERIVED_DATA_PATH}")"
fi
GROWING_MB=$(( DEVICES_MB + CACHES_MB + DERIVED_MB + SPM_MB + EXTRA_DERIVED_MB ))

echo "=== Orbit simulator storage check ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
echo
printf "Data volume (%s): %s GB free, %s GB used, %s full\n" \
    "${DATA_VOLUME}" "${FREE_GB}" "${USED_GB}" "${CAPACITY}"
echo
echo "Growing costs (safe to delete; regenerate on next run):"
printf "  %-34s %8s GB\n" "Simulator device data" "$(human_gb "${DEVICES_MB}")"
printf "  %-34s %8s GB\n" "Simulator caches" "$(human_gb "${CACHES_MB}")"
printf "  %-34s %8s GB\n" "DerivedData (default path)" "$(human_gb "${DERIVED_MB}")"
if [ -n "${ORBIT_DERIVED_DATA_PATH:-}" ]; then
    printf "  %-34s %8s GB\n" "DerivedData (ORBIT_DERIVED_DATA_PATH)" "$(human_gb "${EXTRA_DERIVED_MB}")"
fi
printf "  %-34s %8s GB\n" "SwiftPM cache" "$(human_gb "${SPM_MB}")"
printf "  %-34s %8s GB\n" "TOTAL RECLAIMABLE" "$(human_gb "${GROWING_MB}")"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo
    echo "Docker (testcontainers images for the backend suite):"
    docker system df 2>/dev/null | sed 's/^/  /'
fi

FIXED_MB=0
if [ "${FULL}" -eq 1 ]; then
    echo
    echo "Fixed costs (one-time; do NOT grow with the app's feature set):"
    IMAGES_MB="$(dir_mb "/Library/Developer/CoreSimulator/Images")"
    VOLUMES_MB="$(dir_mb "/Library/Developer/CoreSimulator/Volumes")"
    XCODE_MB="$(dir_mb "/Applications/Xcode.app")"
    FIXED_MB=$(( IMAGES_MB + VOLUMES_MB + XCODE_MB ))
    printf "  %-34s %8s GB\n" "Runtime disk images" "$(human_gb "${IMAGES_MB}")"
    printf "  %-34s %8s GB\n" "Mounted runtime volumes" "$(human_gb "${VOLUMES_MB}")"
    printf "  %-34s %8s GB\n" "Xcode.app" "$(human_gb "${XCODE_MB}")"
    echo
    echo "Installed runtimes (each new iOS version is ~20 GB — prune old ones):"
    xcrun simctl runtime list 2>/dev/null | grep -E "^(iOS|watchOS|tvOS|visionOS)" | sed 's/^/  /' || true
fi

echo
STATUS="OK"
RC=0
if awk -v f="${FREE_GB}" -v m="${MIN_FREE_GB}" 'BEGIN { exit !(f < m) }'; then
    STATUS="FAIL"
    RC=2
    echo "FAIL: ${FREE_GB} GB free is below the ${MIN_FREE_GB} GB hard floor."
    echo "Do not start a simulator testing run — reclaim space first."
    echo "See the reclaim playbook: docs/simulator-storage.md"
elif awk -v f="${FREE_GB}" -v w="${WARN_FREE_GB}" 'BEGIN { exit !(f < w) }'; then
    STATUS="WARN"
    RC=1
    echo "WARN: ${FREE_GB} GB free is below the ${WARN_FREE_GB} GB warn threshold."
    echo "Reclaim before adding another simulator runtime or Docker images."
else
    echo "OK: ${FREE_GB} GB free is within budget."
fi

if [ "${APPEND_LOG}" -eq 1 ]; then
    if [ ! -f "${STORAGE_DOC}" ]; then
        echo "cannot append: ${STORAGE_DOC} not found" >&2
        exit 66
    fi
    # The log table is the LAST thing in the doc by construction, so a new row
    # is a plain append — no in-place rewrite, nothing for a `sed -i` BSD/GNU
    # difference to break.
    printf '| %s | %s | %s GB | %s GB | %s | %s |\n' \
        "$(date -u +%Y-%m-%d)" \
        "${LABEL:-unlabeled}" \
        "${FREE_GB}" \
        "$(human_gb "${GROWING_MB}")" \
        "${STATUS}" \
        "$(hostname -s 2>/dev/null || echo unknown)" \
        >> "${STORAGE_DOC}"
    echo "Logged to docs/simulator-storage.md"
fi

exit "${RC}"
