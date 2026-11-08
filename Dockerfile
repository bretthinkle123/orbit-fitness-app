# Orbit API image: plain uvicorn, no Lambda adapter (that is A2's concern).
#
# The image bakes in NO secret, emulator host or AWS endpoint. Its default behaviour is real
# Firebase verification and real AWS endpoints; only docker-compose supplies local overrides.
#
# Both stages use the same multi-arch INDEX digest, the newest one at least 14 days old:
# python:3.12.15-slim-bookworm, re-pushed 2026-10-21T11:07Z (registry re-checked 2026-11-08T04:35Z).
# Bump the digest, never ignore a fixable CVE.

FROM python:3.12-slim-bookworm@sha256:6a0e06f5ba0b373d051aabd3fffb9b873f27f9a2a3a14bcbe37dee6f0e3bbc70 AS builder

# Same Poetry pin as CI, so the lock is resolved identically in both places.
ENV POETRY_VIRTUALENVS_IN_PROJECT=true \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
RUN pip install --no-cache-dir poetry==2.4.1

# Dependencies first: this layer is rebuilt only when pyproject.toml or poetry.lock change.
COPY pyproject.toml poetry.lock ./
RUN poetry check --lock \
    && poetry install --only main --no-root --no-interaction

COPY src/ ./src/
RUN poetry install --only main --no-interaction \
    # The runtime never installs packages. pip bundles its own (older) urllib3/msgpack, which
    # scanners report as vulnerable copies of libraries the app does not use, and removing
    # pip also takes the package installer out of an attacker's hands.
    && /app/.venv/bin/python -m pip uninstall --yes pip


FROM python:3.12-slim-bookworm@sha256:6a0e06f5ba0b373d051aabd3fffb9b873f27f9a2a3a14bcbe37dee6f0e3bbc70 AS runtime

# Fixed uid/gid so file ownership is predictable and the user is never root.
RUN groupadd --gid 10001 orbit \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin orbit \
    # Same reasoning as the builder: no package installer (and no bundled copies of
    # libraries it vendors) in the runtime image. Runs on the system interpreter.
    && python -m pip uninstall --yes pip setuptools wheel

WORKDIR /app
# The venv must live at the same path as in the builder: its scripts embed that path.
COPY --from=builder --chown=10001:10001 /app/.venv /app/.venv
COPY --chown=10001:10001 src/ /app/src/
COPY --chown=10001:10001 migrations/ /app/migrations/
COPY --chown=10001:10001 alembic.ini /app/alembic.ini

ENV PATH=/app/.venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER 10001:10001
EXPOSE 8000

# stdlib probe: slim images have no curl and adding one widens the attack surface.
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=2).status==200 else 1)"]

CMD ["uvicorn", "orbit.main:app", "--host", "0.0.0.0", "--port", "8000"]
