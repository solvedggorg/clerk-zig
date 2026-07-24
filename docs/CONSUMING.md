# Consuming clerk-zig

How product toolchains (rusty, scripty, hasky, …) depend on this package.

## Requirements

- Zig **0.16.x**
- Linux
- **zig-libsql** is transitive via clerk-zig (no need for PMs to depend on it
  unless they use libsql directly)

## Production (tag fetch)

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
// Transitive zig-libsql (v0.2.1) is pulled automatically for the session store.
// Depend on zig_libsql yourself only if you @import it directly.
```

## Local path (development only)

While hacking the monorepo, override with a path dep:

```zig
// build.zig.zon
.dependencies = .{
    .clerk_zig = .{ .path = "../clerk-zig" },
    // clerk-zig already depends on zig_libsql; re-export only if you use it directly
},
```

```zig
// build.zig
const clerk = b.dependency("clerk_zig", .{
    .target = target,
    .optimize = optimize,
});
mod.addImport("clerk_zig", clerk.module("clerk_zig"));
```

Do **not** ship path deps in production builds.

## Import

```zig
const clerk = @import("clerk_zig");

// Config from env (PMS_AUTH_* / legacy RUSTY_AUTH_*)
const cfg = clerk.config.Config.fromEnv(env) orelse return error.NotConfigured;

// Shared session
var store = try clerk.store.Store.open(io, allocator, env);
defer store.close();

// Login orchestration
var result = try clerk.login.run(io, allocator, env, out, err);
defer result.deinit(allocator);
```

Module name: **`clerk_zig`**. Package name in `build.zig.zon`: **`clerk_zig`**.

## CLI skeleton (copy into your PM)

Keep product-facing commands in the PM (`scripty auth …`, `hasky auth …`).
Full reference: **rusty** `src/cli/auth_cmd.zig`.

```zig
// e.g. src/cli/auth_cmd.zig — branding only
const clerk = @import("clerk_zig");

// login:
var result = try clerk.login.run(io, allocator, env, out, err);
defer result.deinit(allocator);

// logout:
try clerk.login.logout(io, allocator, env);

// whoami / status: clerk.store.Store.open → get / refresh helpers
// registry (optional for your CLI):
//   var reg = try clerk.registry.Registry.load(io, allocator, env);
//   defer reg.deinit();
//   try reg.put(.{ .name = "scripty", .version = "…", .path = "…", .updated_at = … });
//   try reg.save(io);
//   for (reg.entries.items) |e| { … }  // list
```

Suggested subcommands: `login` | `logout` | `whoami` | `status` (+ optional
registry list/register if the PM owns suite installs).

## Registry API

```zig
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
