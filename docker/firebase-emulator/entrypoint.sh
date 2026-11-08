#!/bin/sh
# Starts the Auth emulator. Auth state is exported to /data/state on exit and re-imported on the
# next start, so dev users (and their UIDs) survive `docker stop` / `dev-down.sh`.
#
# The export goes to a SUBDIRECTORY of the volume, never /data itself: the CLI replaces the export
# directory wholesale, which fails ("Automatic export failed") when that directory is the volume's
# mount point. Verified empirically in T5.
set -eu

state_dir=/data/state

# --import fails on an empty directory, so only pass it once a previous run has exported.
import_flag=""
if [ -f "$state_dir/firebase-export-metadata.json" ]; then
  import_flag="--import=$state_dir"
fi

# exec so firebase is PID 1's direct replacement and receives SIGTERM, which triggers the export.
# shellcheck disable=SC2086 # import_flag is deliberately unquoted: empty means "no flag".
exec firebase emulators:start --only auth --project demo-orbit-test $import_flag --export-on-exit=$state_dir
