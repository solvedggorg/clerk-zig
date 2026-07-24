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

`clerk-zig` uses iResolved’s **dual-class** model (source-available; **not** OSI open source):

| Class | When it applies | Terms |
| --- | --- | --- |
| **A — Source Available** | Source trees, forks, evaluation, unofficial builds | [LICENSE.md](LICENSE.md) (iResolved Source Available License v0.1) |
| **B — Authenticated / commercial** | Active [solved.gg](https://solved.gg) account + official signed builds from [get.solved.gg](https://get.solved.gg) | [EULA](https://docs.solved.gg/legal/2026-07-04/eula) · [Terms](https://docs.solved.gg/legal/2026-07-04/terms) · [Privacy](https://docs.solved.gg/legal/2026-07-04/privacy) |

For permitted non-competitive production use of an official build, Class B **supersedes payment / commercial-license-fee** portions of Class A while the account is in good standing and the use remains within the EULA and applicable Order limits; **competition, AI, distribution, and other non-payment restrictions still apply** unless the EULA expressly grants broader rights. See [LICENSE.md §2.3](LICENSE.md#23-authenticated-account-and-commercial-terms-class-b-interaction).

Contributions require the [CLA](https://docs.solved.gg/legal/2026-07-04/cla). Legal hub: [docs.solved.gg/legal](https://docs.solved.gg/legal/2026-07-04/faq). Commercial: [intake@solved.gg](mailto:intake@solved.gg).
