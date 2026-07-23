# `$PMS_HOME` suite layout

Unified data root for PMS toolchains. Default: **`~/.pms`**. Override with
**`PMS_HOME`**.

```text
$PMS_HOME/
  auth/
    session.db              # clerk-zig session (0600, DELETE journal)
  toolchains/
    manifest.toml           # clerk-zig registry v1 ([[tool]] schema)
  bin/                      # optional: unified PATH shims (later)
  rusty/                    # migrates from ~/.rusty (per-PM data)
    toolchains/
    store/
    …
  hasky/                    # migrates from ~/.hasky
  scripty/
  deploy/
  …
```

## Ownership

| Path | Owner package |
|------|----------------|
| `$PMS_HOME` resolution | **clerk-zig** `paths` (shared) |
| `$PMS_HOME/auth/**` | **clerk-zig** only |
| `$PMS_HOME/toolchains/manifest.toml` | **clerk-zig** registry API (v1 schema with `[[tool]]`) |
| `$PMS_HOME/<pm>/**` | that PM’s own paths module |

### Toolchains manifest (registry v1)

Owned by **clerk-zig** `registry` module. Header comment and tables:

```toml
# clerk-zig registry v1

[[tool]]
name = "rusty"
version = "0.1.0"
path = "/path/to/install"
updated_at = 1721600000
```

API: `clerk.registry.Registry.load` / `put` / `save` / `get` / `remove`; list via
`reg.entries`. See `docs/CONSUMING.md`.

## Migration notes

- Today rusty uses `$RUSTY_HOME` / `~/.rusty` and `auth.db` at its root.
- After cutover: session is only at `$PMS_HOME/auth/session.db`.
- One-time migrate: if old `$RUSTY_HOME/auth.db` exists and new session empty,
  copy or import (implementation plan Task: rusty cutover).
- Per-PM toolchains/stores move under `$PMS_HOME/<pm>/` in follow-up PRs per
  PM; auth does not block that migration.

## Security

- `auth/session.db` mode **0600**
- `toolchains/manifest.toml` mode **0600** (no secrets; install metadata only)
- No world-readable tokens
- Prefer `PRAGMA journal_mode=DELETE` (no WAL sidecars)
