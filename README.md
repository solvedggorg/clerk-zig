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

**Production-ready library (v0.1.1)** for suite product auth:

- Clerk OAuth PKCE + session store (`zig-libsql` **v0.2.1**)
- Shared `$PMS_HOME/auth/session.db`
- Toolchains registry (`$PMS_HOME/toolchains/manifest.toml`)

First consumer: **[rusty](../rusty)** (`rusty auth …`). Other PMs add thin CLIs
when ready — see [`docs/CONSUMING.md`](docs/CONSUMING.md). Embedded-replica work
in zig-libsql is **not** required for this package.

## Build

```sh
zig build
zig build test
```

Requires Zig **0.16.x**, Linux. `zig-libsql` is a tag dependency (v0.2.1).

## Consume

**Product toolchains should depend on [pms-sdk](../pms-sdk)** and use
`pms.auth` — not a direct `clerk_zig` dependency. See
[`docs/CONSUMING.md`](docs/CONSUMING.md).

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
