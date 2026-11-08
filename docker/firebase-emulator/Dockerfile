# Firebase Auth emulator for the local stack. Built in-repo from a pinned base and a pinned
# firebase-tools: no official image exists and a community one would be an unvetted dependency.
#
# No JRE on purpose. The Auth emulator runs inside the firebase-tools Node process; Java is only
# needed by the Firestore, Realtime Database and Storage emulators, none of which run here
# (evidence: docs/local-development.md, "Firebase emulator: no JDK").
#
# Base: node:24.20.0-trixie-slim, multi-arch index digest pushed 2026-08-27. 24.21.0 (2026-10-06)
# was not yet 14 days old when this was written, so it is not eligible.
FROM node:24.20.0-trixie-slim@sha256:50c3b2f6988dfc307b86e5301d69611af31f4789bdf232863b07d3b02fe55ae0

# Must equal FIREBASE_TOOLS_VERSION in .github/workflows/pipeline-ci.yml so the emulator behaves
# the same locally, in CI's test job and here (asserted by tests/unit/test_local_stack_config.py).
ARG FIREBASE_TOOLS_VERSION=15.18.0
RUN npm install -g firebase-tools@${FIREBASE_TOOLS_VERSION} \
    && npm cache clean --force

# Caps the V8 heap so the emulator cannot crowd the other containers in the 3 GB Colima VM.
ENV NODE_OPTIONS=--max-old-space-size=192

# The CLI writes its debug log next to firebase.json, and /data holds the exported auth state.
WORKDIR /app
COPY --chown=node:node firebase.json entrypoint.sh /app/
RUN chmod 0755 /app/entrypoint.sh \
    && mkdir /data \
    && chown node:node /app /data

# `node` (uid 1000) is the unprivileged account the official Node base image ships; naming it keeps
# the intent readable, so the numeric-user advice (DL3066) is deliberately waived here.
# hadolint ignore=DL3066
USER node
EXPOSE 9099

# Node 24 has a global fetch, and the slim image has no curl.
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=6 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:9099/emulator/v1/projects/demo-orbit-test/config').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]

ENTRYPOINT ["/app/entrypoint.sh"]
