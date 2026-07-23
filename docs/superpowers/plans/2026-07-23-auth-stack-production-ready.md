# Auth stack production-ready Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make clerk-zig and zig-libsql a production-ready paired stack (session store + suite auth + registry + tags + CI) so other PMS work can proceed and future PMs can wire thin auth CLIs without further library changes.

**Architecture:** Freeze zig-libsql **v0.2.0** as the session-store contract. Ship clerk-zig **v0.1.0** with a schema-only toolchains registry, GitHub CI, tag-based `zig_libsql` pin, consumer docs + example. Defer other-PM auth CLIs and embedded-replica inject.

**Tech Stack:** Zig 0.16.x, zig-libsql v0.2.0, Linux, GitHub Actions.

**Spec:** [`../specs/2026-07-23-auth-stack-production-ready-design.md`](../specs/2026-07-23-auth-stack-production-ready-design.md)

**Repos (relative to monorepo unless noted):**
- Primary: `/home/awfixer/Projects/pms/clerk-zig`
- Dep: `/home/awfixer/Projects/pms/zig-libsql`
- Reference consumer: `/home/awfixer/Projects/pms/rusty`

---

## File map

| Path | Responsibility |
|------|----------------|
| `clerk-zig/src/registry.zig` | Load/save/list/get/put/remove tool entries |
| `clerk-zig/src/root.zig` | Export `registry`, bump `version` to `0.1.0` |
| `clerk-zig/src/paths.zig` | Already has `toolchainsDir` / `toolchainsManifestPath` — tests only if missing |
| `clerk-zig/build.zig` | Wire example binary optional step |
| `clerk-zig/build.zig.zon` | version `0.1.0`; pin zig-libsql url+hash |
| `clerk-zig/examples/whoami.zig` | Brand-neutral store read demo |
| `clerk-zig/.github/workflows/ci.yml` | fmt + build + test |
| `clerk-zig/.github/actions/setup-zig/action.yml` | Zig 0.16 setup (mirror zig-libsql) |
| `clerk-zig/README.md`, `docs/CONSUMING.md`, `AGENTS.md`, `docs/PMS_HOME.md` | Production status + skeleton |
| `zig-libsql` | Verify only unless a real auth-blocking bug is found |
| `rusty/build.zig.zon` | Optional note/path; monorepo may keep path dep |

---

### Task 1: Verify zig-libsql v0.2.0 contract

**Files:** none (verification only)

- [ ] **Step 1: Checkout / confirm tag**

```bash
cd /home/awfixer/Projects/pms/zig-libsql
git fetch --tags origin
git show v0.2.0:build.zig.zon | head -20
# Expect .version = "0.2.0"
```

- [ ] **Step 2: Build and test on current tree that matches release surface**

```bash
cd /home/awfixer/Projects/pms/zig-libsql
# Prefer master at release commit if R3b branch has unrelated WIP:
git stash push -u -m 'wip' 2>/dev/null || true
git checkout master
zig build
zig build test
```

Expected: both exit 0. Record any failures; fix only if they block local session store (unlikely). Do **not** implement R3b inject in this plan.

- [ ] **Step 3: Confirm tarball hash used by Zig 0.16**

```bash
cd /tmp
rm -rf clerk-fetch-test && mkdir clerk-fetch-test && cd clerk-fetch-test
cat > build.zig <<'EOF'
const std = @import("std");
pub fn build(b: *std.Build) void { _ = b; }
EOF
cat > build.zig.zon <<'EOF'
.{
    .name = .tmp_fetch,
    .version = "0.0.0",
    .fingerprint = 0x55d3cd4ab0b3e3b3,
    .minimum_zig_version = "0.16.0",
    .dependencies = .{},
    .paths = .{"build.zig", "build.zig.zon"},
}
EOF
zig fetch --save https://github.com/solvedggorg/zig-libsql/archive/refs/tags/v0.2.0.tar.gz
cat build.zig.zon
```

Expected dependency block (hash may match exactly):

```zig
.zig_libsql = .{
    .url = "https://github.com/solvedggorg/zig-libsql/archive/refs/tags/v0.2.0.tar.gz",
    .hash = "zig_libsql-0.2.0-sj_Iy0O3mgCdfdzNPtpRS4DXhuY-ZXYSSHRrGV2mYDxj",
},
```

Save this hash for Task 5. If fetch fails (network), use path dep temporarily and re-run Task 5 before release.

- [ ] **Step 4: Commit nothing** — verification only. If you left zig-libsql on a feature branch, leave a note; clerk-zig pin is the **tag**, not the branch.

---

### Task 2: Registry module (TDD)

**Files:**

- Create: `clerk-zig/src/registry.zig`
- Modify: `clerk-zig/src/root.zig`
- Use: `clerk-zig/src/paths.zig` (`toolchainsManifestPath`, `toolchainsDir`)

- [ ] **Step 1: Write failing tests in `src/registry.zig` first (file may only have tests + stubs)**

Create `src/registry.zig` with tests that will fail until implemented. Start with this full file (implementation fills in after red):

```zig
//! Suite toolchains install registry (`$PMS_HOME/toolchains/manifest.toml`).
//!
//! Schema-only format (not a general TOML library). No tokens here.

const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const Env = std.process.Environ.Map;
const paths = @import("paths.zig");

pub const Error = error{
    OutOfMemory,
    NoHomeDirectory,
    MalformedManifest,
    InvalidEntry,
    IoFailure,
};

pub const ToolEntry = struct {
    name: []const u8,
    version: []const u8,
    path: []const u8,
    updated_at: i64,

    pub fn deinit(self: *ToolEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(ToolEntry) = .empty,
    /// Absolute path to manifest.toml (owned).
    path: []const u8,

    pub fn deinit(self: *Registry) void {
        for (self.entries.items) |*e| e.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.allocator.free(self.path);
        self.* = undefined;
    }

    /// Load from `$PMS_HOME/toolchains/manifest.toml`. Missing file → empty registry.
    pub fn load(io: Io, allocator: std.mem.Allocator, env: *const Env) Error!Registry {
        _ = io;
        _ = allocator;
        _ = env;
        return error.IoFailure; // replace in implement step
    }

    /// Load from an explicit path (tests). Missing file → empty; path still recorded.
    pub fn loadPath(io: Io, allocator: std.mem.Allocator, manifest_path: []const u8) Error!Registry {
        _ = io;
        _ = allocator;
        _ = manifest_path;
        return error.IoFailure;
    }

    pub fn save(self: *const Registry, io: Io) Error!void {
        _ = self;
        _ = io;
        return error.IoFailure;
    }

    pub fn get(self: *const Registry, name: []const u8) ?*const ToolEntry {
        for (self.entries.items) |*e| {
            if (std.mem.eql(u8, e.name, name)) return e;
        }
        return null;
    }

    /// Upsert by name. Copies all fields onto the registry allocator.
    pub fn put(self: *Registry, entry: ToolEntry) Error!void {
        _ = self;
        _ = entry;
        return error.IoFailure;
    }

    pub fn remove(self: *Registry, name: []const u8) void {
        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (std.mem.eql(u8, self.entries.items[i].name, name)) {
                self.entries.items[i].deinit(self.allocator);
                _ = self.entries.orderedRemove(i);
                return;
            }
            i += 1;
        }
    }
};

fn validateName(name: []const u8) Error!void {
    if (name.len == 0) return error.InvalidEntry;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return error.InvalidEntry;
    if (std.mem.indexOfScalar(u8, name, 0) != null) return error.InvalidEntry;
}

fn validateEntry(entry: ToolEntry) Error!void {
    try validateName(entry.name);
    if (entry.version.len == 0) return error.InvalidEntry;
    if (entry.path.len == 0) return error.InvalidEntry;
    if (!std.fs.path.isAbsolute(entry.path)) return error.InvalidEntry;
}

// --- format helpers (implement with module) ---

fn parseManifest(allocator: std.mem.Allocator, text: []const u8) Error!std.ArrayListUnmanaged(ToolEntry) {
    _ = allocator;
    _ = text;
    return error.MalformedManifest;
}

fn renderManifest(allocator: std.mem.Allocator, entries: []const ToolEntry) Error![]u8 {
    _ = allocator;
    _ = entries;
    return error.OutOfMemory;
}

test "validate rejects empty name and relative path" {
    try std.testing.expectError(error.InvalidEntry, validateEntry(.{
        .name = "",
        .version = "1",
        .path = "/abs",
        .updated_at = 0,
    }));
    try std.testing.expectError(error.InvalidEntry, validateEntry(.{
        .name = "rusty",
        .version = "1",
        .path = "relative",
        .updated_at = 0,
    }));
}

test "parse empty and roundtrip one tool" {
    const gpa = std.testing.allocator;
    var empty = try parseManifest(gpa, "");
    defer {
        for (empty.items) |*e| e.deinit(gpa);
        empty.deinit(gpa);
    }
    try std.testing.expectEqual(@as(usize, 0), empty.items.len);

    const sample =
        \\# clerk-zig registry v1
        \\
        \\[[tool]]
        \\name = "rusty"
        \\version = "0.0.1-dev"
        \\path = "/tmp/pms/rusty"
        \\updated_at = 1730000000
        \\
    ;
    var list = try parseManifest(gpa, sample);
    defer {
        for (list.items) |*e| e.deinit(gpa);
        list.deinit(gpa);
    }
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("rusty", list.items[0].name);
    try std.testing.expectEqualStrings("0.0.1-dev", list.items[0].version);
    try std.testing.expectEqualStrings("/tmp/pms/rusty", list.items[0].path);
    try std.testing.expectEqual(@as(i64, 1730000000), list.items[0].updated_at);

    const rendered = try renderManifest(gpa, list.items);
    defer gpa.free(rendered);
    var again = try parseManifest(gpa, rendered);
    defer {
        for (again.items) |*e| e.deinit(gpa);
        again.deinit(gpa);
    }
    try std.testing.expectEqual(@as(usize, 1), again.items.len);
    try std.testing.expectEqualStrings("rusty", again.items[0].name);
}

test "put get remove roundtrip via loadPath save" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Build an absolute path for the manifest under the tmp dir.
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs = try tmp.dir.realpath(".", &path_buf);
    const manifest = try std.fs.path.join(gpa, &.{ abs, "manifest.toml" });
    defer gpa.free(manifest);

    const io = std.testing.io;
    var reg = try Registry.loadPath(io, gpa, manifest);
    defer reg.deinit();

    try reg.put(.{
        .name = "hasky",
        .version = "0.1.0",
        .path = "/opt/hasky",
        .updated_at = 42,
    });
    try reg.save(io);

    var reg2 = try Registry.loadPath(io, gpa, manifest);
    defer reg2.deinit();
    const got = reg2.get("hasky") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("0.1.0", got.version);
    try std.testing.expectEqual(@as(i64, 42), got.updated_at);

    reg2.remove("hasky");
    try reg2.save(io);
    var reg3 = try Registry.loadPath(io, gpa, manifest);
    defer reg3.deinit();
    try std.testing.expect(reg3.get("hasky") == null);
}
```

Note: if `std.testing.io` / `tmpDir` APIs differ on this Zig 0.16 snapshot, mirror the patterns already used in `src/store.zig` tests (read `store.zig` bottom tests and match `Io` usage exactly).

- [ ] **Step 2: Wire into root so tests run**

In `src/root.zig`, add:

```zig
pub const registry = @import("registry.zig");
```

And inside the existing `test { }` block:

```zig
_ = registry;
```

Also set:

```zig
pub const version = "0.1.0";
```

(version bump may wait for Task 6 if you prefer one version commit; either is fine as long as release is consistent.)

- [ ] **Step 3: Run tests — expect FAIL**

```bash
cd /home/awfixer/Projects/pms/clerk-zig
zig build test 2>&1 | tail -40
```

Expected: failures from `parseManifest` / `loadPath` stubs (`MalformedManifest` or `IoFailure`).

- [ ] **Step 4: Implement parse/render/load/save/put**

Replace stubs with working code. Implementation requirements:

**Parse rules:**
- Ignore blank lines and `#` comments.
- On `[[tool]]`, start a new entry; previous incomplete entry → `MalformedManifest`.
- Inside a tool: keys `name`, `version`, `path` (quoted strings `"..."` only), `updated_at` (decimal integer).
- At EOF, finalize last tool; all four fields required → else `MalformedManifest`.
- Call `validateEntry` before appending.

**Render rules:**
- Emit header `# clerk-zig registry v1\n\n`
- For each entry:

```text
[[tool]]
name = "..."
version = "..."
path = "..."
updated_at = <i64>

```

**loadPath:**
- Dupe `manifest_path` into `Registry.path`.
- If file missing → empty entries.
- Else read all into allocator buffer, `parseManifest`, take ownership of entries.

**load:**
- `toolchainsManifestPath(allocator, env)` then `loadPath`.

**save:**
- `mkdirp` parent of `self.path` (mode 0o700 for toolchains dir).
- `renderManifest`.
- Write to `path ++ ".tmp"` then rename to `path` (atomic).
- `setFilePermissions` 0o600 on final file (fail → `IoFailure`).
- Reuse mkdir style from `store.zig` (`mkdirp` helper — either export a small shared helper or copy the private function).

**put:**
- `validateEntry`.
- If name exists: free old fields, replace with duped fields.
- Else append new owned `ToolEntry` (dupe name/version/path).

Use `std.fmt.allocPrint` / `ArrayList(u8)` for render. Prefer `std.fs.cwd()` + `Io` APIs matching store.

- [ ] **Step 5: Run tests — expect PASS**

```bash
cd /home/awfixer/Projects/pms/clerk-zig
zig build test
```

Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
cd /home/awfixer/Projects/pms/clerk-zig
git add src/registry.zig src/root.zig
git commit -m "$(cat <<'EOF'
feat: add toolchains registry for PMS_HOME manifest

Schema-only [[tool]] manifest at toolchains/manifest.toml with
load/save/put/get/remove and round-trip tests.
EOF
)"
```

---

### Task 3: Example whoami binary

**Files:**

- Create: `clerk-zig/examples/whoami.zig`
- Modify: `clerk-zig/build.zig`

- [ ] **Step 1: Add example source**

```zig
//! Brand-neutral demo: print session identity from clerk-zig store.
//! Not a full OAuth CLI — consumers own `auth login` branding.
const std = @import("std");
const clerk = @import("clerk_zig");

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var env = try std.process.getEnvMap(gpa);
    defer env.deinit();

    const io = std.Io.Threaded.Global.init;
    // If Threaded.Global is wrong for this Zig, match login.zig / store tests.

    var store = clerk.store.Store.open(io, gpa, &env) catch |e| {
        std.debug.print("whoami: open store failed: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    };
    defer store.close();

    var sess = store.get() catch |e| {
        std.debug.print("whoami: read failed: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    } orelse {
        std.debug.print("not logged in\n", .{});
        std.process.exit(1);
    };
    defer sess.deinit(gpa);

    if (sess.email) |email| {
        std.debug.print("{s} ({s})\n", .{ email, sess.clerk_user_id });
    } else {
        std.debug.print("{s}\n", .{sess.clerk_user_id});
    }
}
```

Adjust `Io` construction to match `login.zig` / rusty — **copy the exact pattern from an existing working binary in the monorepo** if the snippet does not compile.

- [ ] **Step 2: Wire `zig build example` in `build.zig`**

After the library install, add:

```zig
const example_mod = b.createModule(.{
    .root_source_file = b.path("examples/whoami.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "clerk_zig", .module = mod },
    },
});
const example = b.addExecutable(.{
    .name = "clerk-whoami",
    .root_module = example_mod,
});
const example_step = b.step("example", "Build examples/whoami");
example_step.dependOn(&b.addInstallArtifact(example, .{}).step);
```

If `createModule` + `imports` differs on this Zig, use the same `addImport` pattern as other packages in the monorepo (`scripty`/`hasky` build.zig).

- [ ] **Step 3: Build example**

```bash
cd /home/awfixer/Projects/pms/clerk-zig
zig build example
```

Expected: artifact under `zig-out/bin/clerk-whoami` (or install prefix).

- [ ] **Step 4: Commit**

```bash
git add examples/whoami.zig build.zig
git commit -m "feat: add examples/whoami consumer skeleton"
```

---

### Task 4: CI workflow

**Files:**

- Create: `clerk-zig/.github/actions/setup-zig/action.yml`
- Create: `clerk-zig/.github/workflows/ci.yml`

- [ ] **Step 1: Setup action (mirror zig-libsql)**

`.github/actions/setup-zig/action.yml`:

```yaml
name: Setup Zig
description: Install the pinned Zig toolchain

inputs:
  zig-version:
    description: Zig version (must stay in sync with build.zig.zon minimum_zig_version)
    required: false
    default: "0.16.0"

runs:
  using: composite
  steps:
    - name: Install Zig
      uses: mlugg/setup-zig@v2
      with:
        version: ${{ inputs.zig-version }}

    - name: Verify Zig
      shell: bash
      run: |
        set -euo pipefail
        zig version
        zig env
```

- [ ] **Step 2: CI workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/master' && github.ref != 'refs/heads/main' }}

env:
  ZIG_VERSION: "0.16.0"

jobs:
  fmt:
    name: zig fmt --check
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - name: Setup Zig
        uses: ./.github/actions/setup-zig
        with:
          zig-version: ${{ env.ZIG_VERSION }}
      - name: Format check
        run: |
          set -euo pipefail
          zig fmt --check src build.zig build.zig.zon examples

  build-test:
    name: zig build && zig build test
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - name: Setup Zig
        uses: ./.github/actions/setup-zig
        with:
          zig-version: ${{ env.ZIG_VERSION }}
      - name: Build and test
        run: |
          set -euo pipefail
          zig build
          zig build test
          zig build example
```

**Note:** Until Task 5 lands url+hash, CI on GitHub **cannot** use `../zig-libsql`. Either:
1. Land Task 5 **before** pushing CI, or
2. Temporarily keep path dep and use a monorepo-only CI (not applicable for standalone clerk-zig repo).

**Required order:** implement Task 5 in the same PR/push as CI so GitHub clone of clerk-zig alone succeeds.

If runners must use Blacksmith labels like zig-libsql, swap `ubuntu-latest` for `blacksmith-2vcpu-ubuntu-2404` / `blacksmith-4vcpu-ubuntu-2404` to match org practice.

- [ ] **Step 3: Local fmt check**

```bash
cd /home/awfixer/Projects/pms/clerk-zig
zig fmt --check src build.zig build.zig.zon examples
```

- [ ] **Step 4: Commit CI files only after Task 5 zon is ready** — or commit CI + zon together in Task 5. Prefer **one commit** with “ci + pin zig-libsql” if easier.

---

### Task 5: Pin zig-libsql by release tag

**Files:**

- Modify: `clerk-zig/build.zig.zon`

- [ ] **Step 1: Replace path dependency**

Set `build.zig.zon` to:

```zig
.{
    .name = .clerk_zig,
    .version = "0.1.0",
    .fingerprint = 0xd8c443889ae04b73, // Changing this has security and trust implications.
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .zig_libsql = .{
            .url = "https://github.com/solvedggorg/zig-libsql/archive/refs/tags/v0.2.0.tar.gz",
            .hash = "zig_libsql-0.2.0-sj_Iy0O3mgCdfdzNPtpRS4DXhuY-ZXYSSHRrGV2mYDxj",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "examples",
        "LICENSE",
        "README.md",
        "AGENTS.md",
        "docs",
    },
}
```

If `zig build` complains about hash, re-run:

```bash
zig fetch --save https://github.com/solvedggorg/zig-libsql/archive/refs/tags/v0.2.0.tar.gz
```

and keep the hash Zig writes.

- [ ] **Step 2: Build against pin**

```bash
cd /home/awfixer/Projects/pms/clerk-zig
zig build
zig build test
zig build example
```

Expected: exit 0 using cache of v0.2.0 tarball (no `../zig-libsql` required).

- [ ] **Step 3: Document monorepo override in CONSUMING (next task)** — path override is for local dual-repo hacking only:

```zig
// development only — do not ship:
.zig_libsql = .{ .path = "../zig-libsql" },
```

- [ ] **Step 4: Commit**

```bash
git add build.zig.zon .github
git commit -m "$(cat <<'EOF'
build: pin zig-libsql v0.2.0 by tag and add CI

Production consumers and GitHub CI use the release tarball hash;
version bump toward 0.1.0.
EOF
)"
```

---

### Task 6: Docs + version consistency

**Files:**

- Modify: `clerk-zig/README.md`
- Modify: `clerk-zig/docs/CONSUMING.md`
- Modify: `clerk-zig/AGENTS.md`
- Modify: `clerk-zig/docs/PMS_HOME.md`
- Modify: `clerk-zig/src/root.zig` (ensure `version = "0.1.0"`)
- Modify: `clerk-zig/docs/plans/2026-07-22-clerk-zig.md` (mark task 6 / point to this plan)

- [ ] **Step 1: README status section**

Replace Status with:

```markdown
## Status

**Production-ready library (v0.1.0)** for suite product auth:

- Clerk OAuth PKCE + session store (`zig-libsql` **v0.2.0**)
- Shared `$PMS_HOME/auth/session.db`
- Toolchains registry (`$PMS_HOME/toolchains/manifest.toml`)

First consumer: **rusty** (`rusty auth …`). Other PMs add thin CLIs when ready —
see [`docs/CONSUMING.md`](docs/CONSUMING.md). Embedded-replica work in zig-libsql
is **not** required for this package.
```

- [ ] **Step 2: CONSUMING.md — tag fetch + CLI skeleton**

Ensure production section uses:

```sh
zig fetch --save https://github.com/solvedggorg/clerk-zig/archive/refs/tags/v0.1.0.tar.gz
```

And that zig-libsql is **transitive** via clerk-zig (no need for PMs to depend on zig-libsql unless they use it directly).

Add section **CLI skeleton (copy into your PM)**:

```zig
// e.g. src/cli/auth_cmd.zig — branding only
const clerk = @import("clerk_zig");

// login:
var result = try clerk.login.run(io, allocator, env, out, err);
defer result.deinit(allocator);

// logout:
try clerk.login.logout(io, allocator, env);

// whoami / status: clerk.store.Store.open → get / refresh helpers
// registry (optional): clerk.registry.Registry.load → put/list
```

Point at rusty `src/cli/auth_cmd.zig` as the full reference.

- [ ] **Step 3: AGENTS.md**

- Mark registry as implemented (not “optional later”).
- Note production pin zig-libsql v0.2.0.
- Rule: do not claim production-ready without `zig build test` + CI green.

- [ ] **Step 4: PMS_HOME.md**

Mark `toolchains/manifest.toml` as owned by clerk-zig registry (v1 schema with `[[tool]]`).

- [ ] **Step 5: Commit**

```bash
git add README.md docs AGENTS.md src/root.zig
git commit -m "docs: mark v0.1.0 production auth stack and consumer skeleton"
```

---

### Task 7: Tag release v0.1.0

**Files:** none (git/GitHub)

- [ ] **Step 1: Final verification**

```bash
cd /home/awfixer/Projects/pms/clerk-zig
zig fmt --check src build.zig build.zig.zon examples
zig build
zig build test
zig build example
grep -n 'version' build.zig.zon src/root.zig
# Expect 0.1.0 in both
```

- [ ] **Step 2: Push master**

```bash
cd /home/awfixer/Projects/pms/clerk-zig
git push origin master
```

Wait for CI green on GitHub (`gh run list --limit 3`).

- [ ] **Step 3: Tag and release**

```bash
cd /home/awfixer/Projects/pms/clerk-zig
git tag -a v0.1.0 -m "clerk-zig v0.1.0 — production suite auth + registry"
git push origin v0.1.0
gh release create v0.1.0 \
  --title "v0.1.0" \
  --notes "$(cat <<'EOF'
## clerk-zig v0.1.0

Production-ready shared Clerk CLI auth for the PMS suite.

- OAuth PKCE, loopback callback, session store via **zig-libsql v0.2.0**
- Session path: \`$PMS_HOME/auth/session.db\`
- Toolchains registry: \`$PMS_HOME/toolchains/manifest.toml\`
- Linux only; public OAuth client (no secret key)

### Depend

\`\`\`sh
zig fetch --save https://github.com/solvedggorg/clerk-zig/archive/refs/tags/v0.1.0.tar.gz
\`\`\`

See docs/CONSUMING.md. Reference CLI: rusty \`auth\` subcommands.
EOF
)"
```

Confirm: `gh release view v0.1.0`.

- [ ] **Step 4: Optional rusty note**

In rusty monorepo, either keep `.path = "../clerk-zig"` for development or pin the tag. Prefer **keep path** inside `pms/` monorepo with a comment:

```zig
// monorepo path; production out-of-tree consumers use clerk-zig v0.1.0 tag
.clerk_zig = .{ .path = "../clerk-zig" },
```

Only change rusty if you want CI outside monorepo; not required for gate if monorepo is the only consumer today.

```bash
# if you edit rusty:
cd /home/awfixer/Projects/pms/rusty
# edit build.zig.zon comment only
git add build.zig.zon
git commit -m "docs: note clerk-zig v0.1.0 production tag for out-of-tree consumers"
```

---

### Task 8: Gate checklist (no code)

- [ ] **Step 1: Run the success criteria from the design spec**

```bash
cd /home/awfixer/Projects/pms/zig-libsql && zig build && zig build test
cd /home/awfixer/Projects/pms/clerk-zig && zig build && zig build test && zig build example
cd /home/awfixer/Projects/pms/clerk-zig && gh release view v0.1.0
cd /home/awfixer/Projects/pms/clerk-zig && gh run list --limit 1
# Confirm build.zig.zon has url+hash for zig_libsql
grep -A3 zig_libsql build.zig.zon
# Confirm registry export
rg 'pub const registry' src/root.zig
```

- [ ] **Step 2: Mark design success criteria** by editing the design spec checkboxes to `[x]` and commit:

```bash
cd /home/awfixer/Projects/pms/clerk-zig
# edit docs/superpowers/specs/2026-07-23-auth-stack-production-ready-design.md checkboxes
git add docs/superpowers/specs/2026-07-23-auth-stack-production-ready-design.md
git commit -m "docs: mark auth stack production gate complete"
git push origin master
```

- [ ] **Step 3: Stop** — do not start unrelated PMS feature work until all boxes pass.

---

## Spec coverage (self-review)

| Spec requirement | Task |
|------------------|------|
| zig-libsql v0.2.0 freeze / verify | 1 |
| registry API + tests | 2 |
| example / consumer skeleton binary | 3 |
| CI | 4 |
| tag pin zig-libsql url+hash | 5 |
| docs CONSUMING + status | 6 |
| clerk-zig v0.1.0 release | 7 |
| gate checklist | 8 |
| No other-PM auth CLIs | explicit non-goal |
| No R3b inject | Task 1 verification only |

## Placeholder / consistency notes

- `Io` construction must match existing clerk-zig/store/login (copy from repo; Zig 0.16 Io API is evolving).
- Hash string is the Zig 0.16 package hash form (`zig_libsql-0.2.0-…`), not the old `1220…` multihash.
- Version `0.1.0` must match in `build.zig.zon` and `src/root.zig` before tag.
- CI and tag pin must land together so GitHub builds without monorepo siblings.
