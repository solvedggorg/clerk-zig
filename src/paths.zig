//! Suite root (`$PMS_HOME`) and auth paths.
//!
//! Default root: `~/.pms`. Auth session: `$PMS_HOME/auth/session.db`.

const std = @import("std");
const Env = std.process.Environ.Map;

/// `$PMS_HOME` or `~/.pms`. Caller owns the slice.
pub fn home(allocator: std.mem.Allocator, env: *const Env) ![]u8 {
    if (env.get("PMS_HOME")) |h| {
        if (h.len > 0) return try allocator.dupe(u8, h);
    }
    const home_dir = env.get("HOME") orelse return error.NoHomeDirectory;
    return try std.fs.path.join(allocator, &.{ home_dir, ".pms" });
}

/// `$PMS_HOME/auth`. Caller owns the slice.
pub fn authDir(allocator: std.mem.Allocator, env: *const Env) ![]u8 {
    const h = try home(allocator, env);
    defer allocator.free(h);
    return try std.fs.path.join(allocator, &.{ h, "auth" });
}

/// `$PMS_HOME/auth/session.db`. Caller owns the slice.
pub fn sessionDbPath(allocator: std.mem.Allocator, env: *const Env) ![]u8 {
    const a = try authDir(allocator, env);
    defer allocator.free(a);
    return try std.fs.path.join(allocator, &.{ a, "session.db" });
}

/// `$PMS_HOME/toolchains`. Caller owns the slice.
pub fn toolchainsDir(allocator: std.mem.Allocator, env: *const Env) ![]u8 {
    const h = try home(allocator, env);
    defer allocator.free(h);
    return try std.fs.path.join(allocator, &.{ h, "toolchains" });
}

/// `$PMS_HOME/toolchains/manifest.toml`. Caller owns the slice.
pub fn toolchainsManifestPath(allocator: std.mem.Allocator, env: *const Env) ![]u8 {
    const t = try toolchainsDir(allocator, env);
    defer allocator.free(t);
    return try std.fs.path.join(allocator, &.{ t, "manifest.toml" });
}

/// `$PMS_HOME/<pm>`. Caller owns the slice.
pub fn pmHome(allocator: std.mem.Allocator, env: *const Env, pm: []const u8) ![]u8 {
    const h = try home(allocator, env);
    defer allocator.free(h);
    return try std.fs.path.join(allocator, &.{ h, pm });
}

test "home honors PMS_HOME" {
    const gpa = std.testing.allocator;
    var map = Env.init(gpa);
    defer map.deinit();
    try map.put("PMS_HOME", "/tmp/pms-home-test");
    const h = try home(gpa, &map);
    defer gpa.free(h);
    try std.testing.expectEqualStrings("/tmp/pms-home-test", h);
}

test "sessionDbPath under PMS_HOME" {
    const gpa = std.testing.allocator;
    var map = Env.init(gpa);
    defer map.deinit();
    try map.put("PMS_HOME", "/tmp/pms-home-test");
    const p = try sessionDbPath(gpa, &map);
    defer gpa.free(p);
    try std.testing.expectEqualStrings("/tmp/pms-home-test/auth/session.db", p);
}

test "home falls back to HOME/.pms" {
    const gpa = std.testing.allocator;
    var map = Env.init(gpa);
    defer map.deinit();
    try map.put("HOME", "/tmp/u");
    // Ensure PMS_HOME is not set via empty map only having HOME
    const h = try home(gpa, &map);
    defer gpa.free(h);
    try std.testing.expectEqualStrings("/tmp/u/.pms", h);
}

test "pmHome nests under suite root" {
    const gpa = std.testing.allocator;
    var map = Env.init(gpa);
    defer map.deinit();
    try map.put("PMS_HOME", "/tmp/pms");
    const p = try pmHome(gpa, &map, "rusty");
    defer gpa.free(p);
    try std.testing.expectEqualStrings("/tmp/pms/rusty", p);
}
