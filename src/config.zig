//! Runtime OAuth configuration for product CLI auth (Clerk public client).

const std = @import("std");
const Env = std.process.Environ.Map;

pub const default_scopes = "profile email offline_access";

pub const Config = struct {
    /// Clerk Frontend API / OAuth issuer, e.g. `https://clerk.example.com` (no trailing slash).
    issuer: []const u8,
    /// Public OAuth application client id (no secret — PKCE public client).
    client_id: []const u8,
    scopes: []const u8,

    /// Parse config from env. Returns null when unset/invalid.
    /// Prefers `PMS_AUTH_*`; falls back to legacy `RUSTY_AUTH_*`.
    pub fn fromEnv(env: *const Env) ?Config {
        const client_raw = firstNonEmpty(env, &.{ "PMS_AUTH_CLIENT_ID", "RUSTY_AUTH_CLIENT_ID" }) orelse return null;
        const client_id = std.mem.trim(u8, client_raw, " \t\r\n");
        if (client_id.len == 0) return null;

        const issuer_raw = firstNonEmpty(env, &.{ "PMS_AUTH_ISSUER", "RUSTY_AUTH_ISSUER" }) orelse return null;
        const issuer_trimmed = std.mem.trim(u8, issuer_raw, " \t\r\n");
        const issuer = std.mem.trimEnd(u8, issuer_trimmed, "/");
        if (issuer.len == 0) return null;
        if (!std.mem.startsWith(u8, issuer, "https://")) return null;

        const scopes_raw = firstNonEmpty(env, &.{ "PMS_AUTH_SCOPES", "RUSTY_AUTH_SCOPES" }) orelse default_scopes;
        const scopes = std.mem.trim(u8, scopes_raw, " \t\r\n");
        return .{
            .issuer = issuer,
            .client_id = client_id,
            .scopes = if (scopes.len > 0) scopes else default_scopes,
        };
    }
};

fn firstNonEmpty(env: *const Env, keys: []const []const u8) ?[]const u8 {
    for (keys) |k| {
        if (env.get(k)) |v| {
            if (std.mem.trim(u8, v, " \t\r\n").len > 0) return v;
        }
    }
    return null;
}

test "fromEnv requires client id and https issuer" {
    const gpa = std.testing.allocator;
    var env = Env.init(gpa);
    defer env.deinit();
    try std.testing.expect(Config.fromEnv(&env) == null);
    try env.put("PMS_AUTH_CLIENT_ID", "client_x");
    try std.testing.expect(Config.fromEnv(&env) == null);
    try env.put("PMS_AUTH_ISSUER", "https://clerk.example.com/");
    const cfg = Config.fromEnv(&env).?;
    try std.testing.expectEqualStrings("client_x", cfg.client_id);
    try std.testing.expectEqualStrings("https://clerk.example.com", cfg.issuer);
    try std.testing.expectEqualStrings(default_scopes, cfg.scopes);
}

test "fromEnv falls back to RUSTY_AUTH_*" {
    const gpa = std.testing.allocator;
    var env = Env.init(gpa);
    defer env.deinit();
    try env.put("RUSTY_AUTH_CLIENT_ID", "legacy_client");
    try env.put("RUSTY_AUTH_ISSUER", "https://legacy.example.com");
    const cfg = Config.fromEnv(&env).?;
    try std.testing.expectEqualStrings("legacy_client", cfg.client_id);
    try std.testing.expectEqualStrings("https://legacy.example.com", cfg.issuer);
}

test "fromEnv prefers PMS_AUTH over RUSTY_AUTH" {
    const gpa = std.testing.allocator;
    var env = Env.init(gpa);
    defer env.deinit();
    try env.put("RUSTY_AUTH_CLIENT_ID", "legacy");
    try env.put("RUSTY_AUTH_ISSUER", "https://legacy.example.com");
    try env.put("PMS_AUTH_CLIENT_ID", "suite");
    try env.put("PMS_AUTH_ISSUER", "https://suite.example.com");
    const cfg = Config.fromEnv(&env).?;
    try std.testing.expectEqualStrings("suite", cfg.client_id);
    try std.testing.expectEqualStrings("https://suite.example.com", cfg.issuer);
}

test "fromEnv rejects non-https issuers" {
    const gpa = std.testing.allocator;
    var env = Env.init(gpa);
    defer env.deinit();
    try env.put("PMS_AUTH_CLIENT_ID", "client_x");
    try env.put("PMS_AUTH_ISSUER", "http://insecure.example.com");
    try std.testing.expect(Config.fromEnv(&env) == null);
}

test "fromEnv rejects empty issuer and whitespace-only client" {
    const gpa = std.testing.allocator;
    var env = Env.init(gpa);
    defer env.deinit();
    try env.put("PMS_AUTH_CLIENT_ID", "   ");
    try env.put("PMS_AUTH_ISSUER", "https://clerk.example.com");
    try std.testing.expect(Config.fromEnv(&env) == null);

    try env.put("PMS_AUTH_CLIENT_ID", "ok");
    try env.put("PMS_AUTH_ISSUER", "   ");
    try std.testing.expect(Config.fromEnv(&env) == null);
}

test "fromEnv empty scopes falls back to default" {
    const gpa = std.testing.allocator;
    var env = Env.init(gpa);
    defer env.deinit();
    try env.put("PMS_AUTH_CLIENT_ID", "c");
    try env.put("PMS_AUTH_ISSUER", "https://clerk.example.com");
    try env.put("PMS_AUTH_SCOPES", "   ");
    const cfg = Config.fromEnv(&env).?;
    try std.testing.expectEqualStrings(default_scopes, cfg.scopes);
}
