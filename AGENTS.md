# clerk-zig — agent instructions

## Product identity

clerk-zig is the **shared Clerk CLI auth adapter** for the PMS suite:

- Public OAuth client + PKCE only (no `CLERK_SECRET_KEY` in this package).
- Session store: `$PMS_HOME/auth/session.db` via **zig-libsql**.
- Suite root: `$PMS_HOME` (default `~/.pms`), overridable with env `PMS_HOME`.
- Consumers: rusty, scripty, hasky, deploy, and future PMs.

It is **not**:

- crates.io / Hackage / npm login
- A full Clerk Backend API SDK
- A JWT middleware framework (out of v1)
- macOS/Windows supported

## Absolute rules

1. **No secret key** in CLI flows. Public client_id + PKCE only.
2. **Never log tokens** or URLs that embed secrets.
3. Session DB must open with mode **0600** (fail closed). Journal **DELETE**.
4. Issuer must be **https://** after trim.
5. Prefer extracting/porting proven code from `../rusty/src/auth/` over inventing new OAuth.
6. CLI subcommand branding stays in each PM (`rusty auth`, later `scripty auth`); this package is library-only (optional tiny example binary is fine).
7. Linux only — refuse non-Linux ports.
8. Pass allocators explicitly; tests use `std.testing.allocator` and wire into root `test { }`.
9. Version strings stay in sync: `build.zig.zon`, `src/root.zig`.
10. Do not claim completion without `zig build` + `zig build test` evidence.

## Env contract

| Variable | Role |
|----------|------|
| `PMS_HOME` | Suite data root (default `~/.pms`) |
| `PMS_AUTH_CLIENT_ID` | Clerk OAuth public client id |
| `PMS_AUTH_ISSUER` | Clerk Frontend API / issuer (`https://…`, no trailing slash) |
| `PMS_AUTH_SCOPES` | Optional; default `profile email offline_access` |

**Deprecation window (rusty migration):** accept `RUSTY_AUTH_CLIENT_ID`,
`RUSTY_AUTH_ISSUER`, `RUSTY_AUTH_SCOPES` when `PMS_AUTH_*` unset. Prefer PMS_*.

## Architecture (v1)

```
config → pkce → oauth (HTTP) → callback/browser → login
                      ↓
                   store (zig-libsql @ $PMS_HOME/auth/session.db)
```

Optional later: `$PMS_HOME/toolchains/manifest.toml` for suite install registry.

## Module layout

| Path | Role |
|------|------|
| `src/root.zig` | Public surface |
| `src/paths.zig` | `$PMS_HOME`, auth paths |
| `src/config.zig` | Env → Config |
| `src/pkce.zig` | PKCE + state |
| `src/oauth.zig` | Token endpoints |
| `src/callback.zig` | Loopback redirect |
| `src/browser.zig` | Open browser |
| `src/store.zig` | Session DB |
| `src/login.zig` | Orchestration |
| `src/registry.zig` | Toolchain install manifest (phase 6) |

## Working agreement

1. Read `docs/DESIGN.md` before large changes.
2. Every store/oauth change includes tests run by `zig build test`.
3. First consumer cutover is **rusty** (delete `rusty/src/auth` after wire-up).
4. Match zig-libsql consume patterns (`docs/CONSUMING.md`).
