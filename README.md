# clerk-zig

> [!IMPORTANT]
> **Linux-only** shared library for the PMS suite (rusty, scripty, hasky, …).
> Product CLI auth via Clerk (public OAuth client + PKCE). Not a full Clerk SDK.

Zig package that centralizes **solved.gg / iResolved product identity**:

- Clerk OAuth authorize / token / refresh / revoke / userinfo
- PKCE + loopback callback + browser open
- Shared session store under **`$PMS_HOME/auth/session.db`** (zig-libsql)
- Shared suite root **`$PMS_HOME`** (default `~/.pms`) so one login serves every PM

## Status

**Phase 0 scaffold + design/plan.** Implementation extracts and generalizes
`rusty/src/auth/` (see `docs/DESIGN.md` and `docs/plans/2026-07-22-clerk-zig.md`).

## Build

```sh
zig build
zig build test
```

Requires Zig **0.16.x**, Linux, and `zig-libsql` (path dep while developing).

## Consume

See [`docs/CONSUMING.md`](docs/CONSUMING.md).

## Docs

| Doc | Role |
|-----|------|
| `docs/DESIGN.md` | Architecture and suite contract |
| `docs/PMS_HOME.md` | `~/.pms` layout |
| `docs/CONSUMING.md` | How PMs depend on this package |
| `docs/plans/2026-07-22-clerk-zig.md` | Implementation plan |
| `AGENTS.md` | Rules for humans and agents |

## License

MIT — see `LICENSE`.
