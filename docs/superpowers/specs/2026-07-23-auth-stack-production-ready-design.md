# Production-ready auth stack (clerk-zig + zig-libsql)

**Status:** Approved  
**Date:** 2026-07-23  
**Suite:** PMS  

## Problem

Product work across the PMS suite is blocked until **clerk-zig** and **zig-libsql**
are functionally complete and production-ready as a paired dependency stack.
Today:

- **zig-libsql** has a tagged **v0.2.0** and a solid local + Hrana remote MVP, but
  clerk-zig still path-deps the monorepo tree.
- **clerk-zig** implements OAuth/PKCE/store/login and is already consumed by
  **rusty**, but is still `0.0.1-dev`, has no CI, no release tag, no registry
  module, and no production dep pin on zig-libsql.
- Other PMs (scripty, hasky, deploy, …) must be able to add thin `auth` CLIs
  later **without further library work**.

## Goals

1. **Session-store contract frozen** on zig-libsql **v0.2.0** (local file DB,
   0600-friendly auth usage, `lastError*`, named binds as used by store).
2. **clerk-zig v0.1.0** production release: library complete for suite auth,
   registry API, CI, docs, tagged GitHub release.
3. **Dependency graph** for production is tag-based, not path-based:
   ```text
   zig-libsql@v0.2.0 → clerk-zig@v0.1.0 → rusty / future PMs
   ```
4. **Consumer readiness:** CONSUMING docs + optional example so any PM can wire
   `auth login|logout|whoami|status` with branding only.
5. **Gate:** no other product feature work starts until success criteria below
   pass.

## Non-goals (this gate)

- Thin `auth` CLIs in scripty, hasky, deploy, or other PMs (docs + library only).
- Embedded-replica pure inject (R3b.1+). Optional R3b.0 merge only if it does not
  risk the default SQLite engine used by session.db.
- Clerk Backend API, JWKS middleware, webhooks, non-Linux ports.
- Migrating every PM’s data tree under `$PMS_HOME/<pm>/` (documented only).
- Unified `$PMS_HOME/bin` PATH shims.

## Architecture

```text
┌──────────────────────────────────────────────────────────┐
│  Future PM CLIs (scripty/hasky/deploy) — not this gate    │
│  rusty auth (already thin CLI)                            │
└───────────────────────────┬──────────────────────────────┘
                            │ @import("clerk_zig")
┌───────────────────────────▼──────────────────────────────┐
│  clerk-zig @ v0.1.0                                       │
│  config · pkce · oauth · callback · browser · login        │
│  store ──► zig-libsql                                     │
│  paths · registry (toolchains/manifest.toml)              │
└───────────────────────────┬──────────────────────────────┘
                            │ zig_libsql @ v0.2.0 (url+hash)
              $PMS_HOME/auth/session.db
              $PMS_HOME/toolchains/manifest.toml
```

### zig-libsql (production contract for this gate)

| Item | Decision |
|------|----------|
| Version pin | **v0.2.0** (existing release) |
| Engine for session.db | Default **sqlite** amalgamation |
| Required surface | `Database.open`, `Connection`, prepare/bind/step/exec, `lastErrorMessage` / `lastErrorCode` |
| Remote Hrana | Already shipped; not required for clerk-zig; leave as-is |
| R3b / replicas | **Out of gate.** Do not block v0.1.0 clerk-zig on inject |
| R3b.0 PR (#12) | Optional merge **only if** default `-Dengine=sqlite` CI stays green and public API stays compatible with v0.2.0 consumers. Prefer **not** re-tagging for auth gate. If merge needs a bump, cut **v0.2.1** patch with changelog; clerk-zig pins that tag instead |
| Path deps | Development only; CONSUMING already states this |

No zig-libsql feature work is required for the auth gate unless consumer prep
gaps appear (missing error surface, broken tests, docs wrong). Verify with
`zig build test` and clerk-zig store tests against the **tag tarball**, not only
the monorepo path.

### clerk-zig (production bar)

| Area | Requirement |
|------|-------------|
| Version | Bump to **0.1.0** in `build.zig.zon` and `src/root.zig` `version` |
| OAuth / PKCE / store / login | Keep; tests green; no token logging; session **0600** + `PRAGMA journal_mode=DELETE` |
| **registry** | New `src/registry.zig` — see below |
| CI | GitHub Actions: `zig fmt --check`, `zig build`, `zig build test` on Linux (mirror zig-libsql style; simpler setup-zig action OK) |
| Dependency | `zig_libsql` via **GitHub tag tarball + content hash** (not `../zig-libsql` in the release tree) |
| Example | `examples/whoami.zig` (or build step optional) showing open store + whoami-style read without PM branding |
| Docs | Update README status, CONSUMING (tag fetch for both packages), PMS_HOME, DESIGN task 6 complete, AGENTS |
| Release | Tag **`v0.1.0`** + GitHub Release notes |

Monorepo **may** keep a local override for day-to-day hacking (document dual
mode), but the **published** `build.zig.zon` on the release tag must use
url+hash for zig-libsql.

### Registry module

**Path:** `$PMS_HOME/toolchains/manifest.toml`  
**Owner:** clerk-zig only  
**paths helper:** already exists (`toolchainsDir`, `toolchainsManifestPath`)

**Format (v1 — simple, hand-writable, no full TOML dependency):**

Prefer a **minimal TOML-like** or **INI-style** format that clerk-zig owns end-to-end
without depending on rusty’s channel parser. Recommended v1:

```toml
# $PMS_HOME/toolchains/manifest.toml
# clerk-zig registry v1 — one [[tool]] table per install

[[tool]]
name = "rusty"
version = "0.0.1-dev"
path = "/home/user/.pms/rusty"
updated_at = 1730000000
```

**Public API (sketch — exact names fixed in implementation plan):**

| Function | Behavior |
|----------|----------|
| `Registry.load(allocator, io, env)` | Read manifest if present; empty registry if missing |
| `Registry.save` | Write atomically (temp + rename); mkdir `toolchains/` 0700 |
| `list` | Iterator or slice of `ToolEntry` |
| `get(name)` | Lookup by tool name |
| `put(entry)` | Upsert by `name` |
| `remove(name)` | Delete entry; no-op if missing |

**`ToolEntry` fields:** `name`, `version`, `path`, `updated_at` (unix seconds).

**Validation:** non-empty `name` (no `/` or NUL); `path` absolute; `version`
non-empty. Fail closed on malformed files (`error.MalformedManifest`).

**Security:** manifest is not secret (no tokens). Mode **0640** or **0600** is
fine; prefer **0600** for consistency with suite hygiene. Do not store tokens
here.

**Parser:** implement a **tiny** array-of-tables reader/writer in
`registry.zig` (or `registry_format.zig`) scoped to this schema only — not a
general TOML library. Round-trip tests required.

### Consumer readiness (no new CLIs)

1. **rusty** remains the reference thin CLI (`src/cli/auth_cmd.zig`). After
   clerk-zig **v0.1.0** exists, rusty **may** pin the tag tarball or keep monorepo
   path; document which is used in CI.
2. **CONSUMING.md** must include a copy-paste skeleton:
   - `build.zig.zon` dep on clerk-zig tag
   - `build.zig` `addImport`
   - switch on `login` / `logout` / `whoami` / `status` calling `clerk.login` /
     `store` (mirror rusty, brand-neutral comments)
3. **examples/whoami.zig** (optional binary via `zig build example` or documented
   compile) proves the library works without rusty.

### Dependency and release order

1. Verify zig-libsql **v0.2.0** builds and tests; confirm release tarball hash.
2. Harden clerk-zig (registry, CI, example, docs).
3. Point clerk-zig `build.zig.zon` at zig-libsql tag; `zig fetch` / record hash;
   `zig build test` against that pin.
4. Tag clerk-zig **v0.1.0** and create GitHub Release.
5. Optionally update rusty to tag pin (or leave path + note “production consumers
   use tag”).
6. Mark gate complete in README/ROADMAP of both packages.

## Error handling and security (unchanged contracts)

- No `CLERK_SECRET_KEY` in clerk-zig.
- Never log access/refresh tokens or secret-bearing URLs.
- Session DB: create/open with **0600**, fail closed; **DELETE** journal.
- Issuer must be `https://` after trim.
- Linux only.

## Testing

| Layer | Coverage |
|-------|----------|
| zig-libsql | Existing suite green on v0.2.0 |
| clerk-zig unit | paths, config, pkce, oauth parse, callback, store roundtrip, login helpers, **registry roundtrip** |
| clerk-zig CI | fmt + build + test on Linux |
| Integration | Build clerk-zig against **tag** zig-libsql (not only path); store put/get under temp `PMS_HOME` |
| Manual (doc only) | `PMS_AUTH_*` set → rusty `auth login` → session at `$PMS_HOME/auth/session.db` |

## Success criteria (gate)

- [x] `cd zig-libsql && zig build && zig build test` green (v0.2.0 / master as pinned)
- [x] `cd clerk-zig && zig build && zig build test` green
- [x] clerk-zig CI workflow on default branch green
- [x] `registry` exported from `root.zig` with tests
- [x] clerk-zig `build.zig.zon` pins zig-libsql by **url + hash** on release tag
- [x] GitHub release **clerk-zig v0.1.0**
- [x] CONSUMING docs describe tag fetch + CLI skeleton; example present
- [x] README/AGENTS state: production-ready for PM auth CLIs; replicas not required
- [x] No open “path-only production” claim without documenting monorepo exception

## Risks

| Risk | Mitigation |
|------|------------|
| R3b work distracts from gate | Explicit non-goal; park inject |
| TOML parser scope creep | Schema-only format; reject unknown structure |
| Hash churn when re-tagging zig-libsql | Prefer freeze on v0.2.0; patch only if auth needs fix |
| rusty monorepo path vs tag | Document dual mode; CI can use path inside pms/ |

## Related docs

- [DESIGN.md](../../DESIGN.md) — original clerk-zig architecture  
- [PMS_HOME.md](../../PMS_HOME.md) — suite layout  
- [plans/2026-07-22-clerk-zig.md](../../plans/2026-07-22-clerk-zig.md) — tasks 0–5 done; task 6 superseded by this gate  
- zig-libsql `docs/ROADMAP.md`, `docs/CONSUMING.md`  
- rusty `src/cli/auth_cmd.zig` — reference consumer  

## Implementation next step

After user review of this spec, write the implementation plan under
`docs/superpowers/plans/2026-07-23-auth-stack-production-ready.md` and execute
it before any other PMS product work.
