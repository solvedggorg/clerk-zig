# Consuming clerk-zig

How product toolchains (rusty, scripty, hasky, …) depend on this package.

## Requirements

- Zig **0.16.x**
- Linux
- **zig-libsql** (session store)

## Local path (development)

While hacking the monorepo:

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

## Release tag (production)

Prefer a published GitHub tag once cut:

```sh
zig fetch --save https://github.com/solvedggorg/clerk-zig/archive/refs/tags/v0.1.0.tar.gz
```

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

## CLI wiring (consumer-owned)

Keep product-facing commands in the PM:

```text
rusty auth login|logout|whoami|status
```

Call into `clerk_zig.login` / `store`; print brand-specific help and errors.

## Environment

See `AGENTS.md` — `PMS_HOME`, `PMS_AUTH_CLIENT_ID`, `PMS_AUTH_ISSUER`.

## Security (consumer-owned UX)

- Never print access/refresh tokens.
- Point users at suite docs for Clerk Dashboard public OAuth app setup.
