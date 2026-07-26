# `migrations/` — Alembic schema + seed migrations

> Per-directory README — diff, don't rewrite on later changes. (`migrations/README` —
> no extension — is Alembic's own generated boilerplate; this file is the project README.)

## Purpose

Owns the PostgreSQL schema (9 tables) and the seed data (quick-food catalog, the "Push
Day" program + exercises, and the per-user template rows `POST /me/bootstrap` copies)
via Alembic. Run with `alembic upgrade head` (`alembic.ini` at the repo root).

## Modules

| File | Responsibility |
|---|---|
| `env.py` | Alembic runtime config — resolves the DB URL through the same secrets facade the app uses (`src/orbit/config`), never a hardcoded connection string. |
| `script.py.mako` | Alembic's revision-file template. |
| `versions/0001_initial_schema.py` | Creates all 9 tables + every CHECK/FK/UNIQUE constraint (`down_revision = None` — the root migration). |
| `versions/0002_seed_catalog_program_levels.py` | Data migration (`down_revision = "0001"`): seeds `quick_foods`, the "Push Day" `programs`/`exercises` rows, and `muscle_level_templates` (the per-user defaults `POST /me/bootstrap` copies). |

## Relationships

`0001` is a pure schema migration (create-migration kind — its round-trip test asserts
schema + constraint reversibility, not row survival, since `downgrade()` drops the
tables). `0002` depends on `0001` and is a **data-only** migration — seeds are inserted
via a dedicated migration rather than app code so `new users start EMPTY` (CLAUDE.md) is
mechanically true: `quick_foods`/`programs`/`exercises`/`muscle_level_templates` are
global reference/template rows with no `owner_uid`; nothing here creates a per-user row.

## Notes

- Both migrations' `upgrade()`/`downgrade()` pairs are exercised by
  `tests/integration/test_migrations.py`'s round-trip test, which re-verifies every
  named constraint still enforces after `up`.
- `muscle_level_templates` was added as a judgment call beyond the plan's literal table
  list, to hold the seeded defaults `POST /me/bootstrap` copies per new user without
  duplicating them inline in application code — see
  `.pipeline/implementation-progress.md` (T2 entry) /
  `docs/decisions/feature/greenfield/` for the retained record.
