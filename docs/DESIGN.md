# clerk-zig design

**Status:** Approved approach **B** (extract library + shared `~/.pms` auth root).  
**Date:** 2026-07-22  
**Suite:** PMS (rusty, scripty, hasky, deploy, …)

## Problem

Product CLI auth (Clerk OAuth PKCE + local session) lives only in
`rusty/src/auth/` (~1.1k LOC). Other PMs need the same solved.gg / iResolved
identity without copying OAuth, PKCE, and SQLite session code. Homes are also
split (`~/.rusty`, `~/.hasky`, …), so sessions cannot be shared.

## Goals

1. One Zig package **`clerk-zig`** owns Clerk CLI auth for the suite.
2. One session store under **`$PMS_HOME/auth/session.db`** (default root `~/.pms`).
3. **rusty** depends on clerk-zig and **deletes** in-tree `src/auth/` implementation.
4. Other PMs add thin `auth` CLIs later against the same package.
5. Linux-only; integrity and token hygiene non-negotiable.

## Non-goals (v1)

- Clerk Backend API (secret key)
- JWKS / session JWT verification middleware
- Webhooks
- Full multi-PM path migration of every store/toolchain tree (documented contract only; migrate per PM over time)
- Non-Linux hosts

## Approach B (selected)

Extract OAuth/PKCE/store/login from rusty into clerk-zig. Session + env keys use
the shared suite root. Toolchain data remains per-PM under `$PMS_HOME/<pm>/`
(migration from `~/.rusty` etc. is follow-up). Optional install registry:
`$PMS_HOME/toolchains/manifest.toml`.

## Architecture

```text
┌─────────────────────────────────────────────────────────┐
│  rusty / scripty / hasky CLI  (`auth login|…`)          │
└───────────────────────────┬─────────────────────────────┘
                            │ @import("clerk_zig")
┌───────────────────────────▼─────────────────────────────┐
│  clerk-zig                                              │
│  config → pkce → oauth ⇄ Clerk (https issuer)           │
│           callback + browser                            │
│           login orchestration                           │
│           store ──► zig-libsql                          │
│           paths ($PMS_HOME)                             │
│           registry (optional: toolchains manifest)      │
└───────────────────────────┬─────────────────────────────┘
                            │
              $PMS_HOME/auth/session.db
```

### Public surface

| Symbol area | Responsibility |
|-------------|----------------|
| `paths` | `$PMS_HOME`, `authDir`, `sessionDbPath` |
| `config` | Issuer, client_id, scopes from env |
| `pkce` | Verifier/challenge/state |
| `oauth` | authorize URL, exchange, refresh, revoke, userinfo |
| `callback` | Localhost OAuth redirect listener |
| `browser` | Open system browser |
| `store` | Single-row session CRUD |
| `login` | Interactive login, logout helpers, token refresh |
| `registry` | List/register PM installs under suite home (phase 6) |

### Config env

Primary: `PMS_AUTH_CLIENT_ID`, `PMS_AUTH_ISSUER`, `PMS_AUTH_SCOPES`, `PMS_HOME`.  
Legacy (deprecation): `RUSTY_AUTH_*` when PMS unset.

### Session schema

Port rusty’s single active session (`id = 1`):

- `clerk_user_id`, `email`, `access_token`, `refresh_token`, `expires_at`, `scopes`, `updated_at`
- File mode 0600; `PRAGMA journal_mode=DELETE`

### Dependency graph

```text
zig-libsql
    ↑
clerk-zig
    ↑
rusty, scripty, hasky, …
```

## rusty cutover

1. Path-dep `clerk_zig` in rusty `build.zig.zon`.
2. CLI `src/cli/auth_cmd.zig` calls clerk-zig; remove `src/auth/*.zig` impl.
3. One-time migrate: copy `$RUSTY_HOME/auth.db` → `$PMS_HOME/auth/session.db` if new empty.
4. Document `PMS_AUTH_*` in rusty README/ROADMAP; keep `RUSTY_AUTH_*` aliases temporarily.

## Security

- Public OAuth client only
- HTTPS issuer required
- State mismatch fails closed
- Never log tokens
- Atomic/safe file modes on session DB

## Testing strategy

- Unit tests ported from rusty (pkce, config, paths, store openPath with temp DB)
- oauth/login: mock or skip live HTTP in default CI; optional offline fixtures
- `zig build test` is the gate

## Phases

| Phase | Outcome |
|-------|---------|
| 0 | Scaffold, design, plan, git (this tree) |
| 1 | paths + config + pkce |
| 2 | oauth + callback + browser |
| 3 | store on `$PMS_HOME/auth/session.db` |
| 4 | login orchestration |
| 5 | rusty consumer cutover |
| 6 | registry + thin other-PM CLIs |

## Success criteria

- [x] `zig build` / `zig build test` green in clerk-zig
- [x] rusty has no local OAuth/PKCE/store source
- [x] Shared session DB path is `$PMS_HOME/auth/session.db`
- [x] CONSUMING.md accurate for path + tag deps
