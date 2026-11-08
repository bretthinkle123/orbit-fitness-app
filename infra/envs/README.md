# infra/envs/

## Purpose

Environment-specific Terraform roots that compose the shared modules in `infra/modules/`.

## Modules

| Path | What it is |
|---|---|
| `local/` | The local root, applied to moto (see its README) |

## How they relate

Roots reuse the modules unchanged; differences are module variables or provider configuration,
never a forked module copy. The production root remains `infra/` itself.
