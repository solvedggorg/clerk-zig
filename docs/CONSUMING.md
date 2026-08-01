# Consuming clerk-zig

> **Prefer [pms-sdk](../../pms-sdk)** for product toolchains.
> Products should depend on **`pms_sdk` only** and use `pms.auth` (this package
> is the implementation detail behind that façade). Direct `clerk_zig` deps are
> deprecated for rusty / worgo / hasky / … and will be removed from product
> `build.zig.zon` files.

How to use this package **if** you are working on clerk-zig itself, or on the
pms-sdk auth façade.

## Requirements

- Zig **0.16.x**
- Linux
- **zig-libsql** is transitive via clerk-zig

## Product path (recommended)

```zig
// build.zig.zon — products
.pms_sdk = .{ .path = "../pms-sdk" }, // or published tag later

// application code
const pms = @import("pms_sdk");
var result = try pms.auth.login.run(io, allocator, env, out, err);
const token = try pms.auth.resolveBearerToken(io, allocator, env);
// Toolchain registry: pms.toolchain.Registry (not clerk.registry)
```

Full consumer guide for the suite: `pms-sdk/README.md` and
`docs/suite-architecture.md`.

## Direct clerk-zig (library maintainers only)

```sh
zig fetch --save https://github.com/solvedggorg/clerk-zig/archive/refs/tags/v0.1.1.tar.gz
```

```zig
// build.zig
const clerk = b.dependency("clerk_zig", .{
    .target = target,
    .optimize = optimize,
});
mod.addImport("clerk_zig", clerk.module("clerk_zig"));
```

Monorepo path dep while hacking clerk-zig:

```zig
// build.zig.zon
.dependencies = .{
    .clerk_zig = .{ .path = "../clerk-zig" },
},
```

## Import

```zig
const clerk = @import("clerk_zig");

// Config from env (PMS_AUTH_* / legacy RUSTY_AUTH_*)
const cfg = clerk.config.Config.fromEnv(env) orelse return error.NotConfigured;

// Shared session
var store = try clerk.store.Store.open(io, allocator, env);
defer store.close();

// Login orchestration (browser callback waits up to 5 minutes by default)
var result = try clerk.login.run(io, allocator, env, out, err);
defer result.deinit(allocator);
```

Ownership: returned slices from `paths.*`, `oauth.authorizeUrl`, `login.run`,
`store.getSession`, and token helpers are **caller-owned** — free with the
allocator you passed (or call the type's `deinit`).

**Never log** access/refresh tokens or authorize URLs that might embed secrets.

Module name: **`clerk_zig`**. Package name in `build.zig.zon`: **`clerk_zig`**.

## CLI skeleton (copy into your PM)

Keep product-facing commands in the PM (`scripty auth …`, `hasky auth …`).
Full reference: **rusty** `src/cli/auth_cmd.zig` (uses `pms.auth`).

```zig
// e.g. src/cli/auth_cmd.zig — branding only
const pms = @import("pms_sdk");
const auth = pms.auth;

var result = try auth.login.run(io, allocator, env, out, err);
defer result.deinit(allocator);
try auth.login.logout(io, allocator, env);
// whoami / status: auth.store.Store.open → getSession
// registry: pms.toolchain.Registry (clerk.registry is deprecated)
```

Suggested subcommands: `login` | `logout` | `whoami` | `status` (+ optional
toolchain registry list/register if the PM owns suite installs).

## Registry API (deprecated)

> **Deprecated.** Prefer `pms.toolchain.Registry` (supports optional `sha256`).
> `clerk.registry` remains for tag compatibility until clerk-zig 0.2.

```zig
// New code:
var reg = try @import("pms_sdk").toolchain.Registry.load(io, allocator, env);

// Legacy (clerk-zig only):
var reg = try clerk.registry.Registry.load(io, allocator, env);
defer reg.deinit();

// Upsert
try reg.put(.{
    .name = "rusty",
    .version = "0.1.0",
    .path = "/path/to/install",
    .updated_at = std.time.timestamp(),
});
try reg.save(io);

// List
for (reg.entries.items) |e| {
    _ = e.name;
    _ = e.version;
    _ = e.path;
}

// Lookup
if (reg.get("rusty")) |e| {
    _ = e;
}
```

Manifest path: `$PMS_HOME/toolchains/manifest.toml` (schema `# clerk-zig registry v1` + `[[tool]]` tables).

## Environment

See `AGENTS.md` — `PMS_HOME`, `PMS_AUTH_CLIENT_ID`, `PMS_AUTH_ISSUER`.

## Security (consumer-owned UX)

- Never print access/refresh tokens.
- Point users at suite docs for Clerk Dashboard public OAuth app setup.
