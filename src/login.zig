//! Orchestrate product CLI auth login (Clerk OAuth PKCE + local session store).

const std = @import("std");
const Io = std.Io;
const Env = std.process.Environ.Map;
const config_mod = @import("config.zig");
const pkce = @import("pkce.zig");
const oauth = @import("oauth.zig");
const callback = @import("callback.zig");
const browser = @import("browser.zig");
const store_mod = @import("store.zig");

pub const Error = error{
    NotConfigured,
    StateMismatch,
    BrowserFailed,
    NoSpaceLeft,
} || oauth.Error || callback.Error || store_mod.Error;

pub const LoginResult = struct {
    email: ?[]u8,
    clerk_user_id: []u8,

    pub fn deinit(self: *LoginResult, allocator: std.mem.Allocator) void {
        if (self.email) |e| allocator.free(e);
        allocator.free(self.clerk_user_id);
        self.* = undefined;
    }
};

/// Run the interactive login flow. Writes session to `$PMS_HOME/auth/session.db`.
pub fn run(
    io: Io,
    allocator: std.mem.Allocator,
    env: *const Env,
    out: *Io.Writer,
    err: *Io.Writer,
) Error!LoginResult {
    const cfg = config_mod.Config.fromEnv(env) orelse {
        try err.writeAll(
            \\product auth: not configured
            \\  Set PMS_AUTH_CLIENT_ID and PMS_AUTH_ISSUER (Clerk OAuth public app).
            \\  Legacy RUSTY_AUTH_CLIENT_ID / RUSTY_AUTH_ISSUER are accepted when PMS_AUTH_* are unset.
            \\  See docs: product CLI auth (Clerk + local SQLite).
            \\
        );
        return error.NotConfigured;
    };

    var listener = try callback.Listener.start(io);
    defer listener.deinit();

    var uri_buf: [64]u8 = undefined;
    const redirect_uri = try listener.redirectUri(&uri_buf);

    const pair = pkce.generate(io);
    const auth_url = try oauth.authorizeUrl(allocator, cfg, redirect_uri, &pair.challenge, &pair.state);
    defer allocator.free(auth_url);

    try out.print("Opening browser for sign-in…\n", .{});
    try out.print("If nothing opens, visit:\n  {s}\n", .{auth_url});
    try out.flush();

    browser.open(io, env, auth_url) catch {
        try err.writeAll("product auth: could not open a browser; open the URL above manually\n");
    };

    try out.writeAll("Waiting for authorization in the browser…\n");
    try out.flush();

    var cb = try listener.wait(allocator);
    defer cb.deinit(allocator);

    if (!std.mem.eql(u8, cb.state, &pair.state)) {
        try err.writeAll("product auth: OAuth state mismatch (possible CSRF); try again\n");
        return error.StateMismatch;
    }

    // Percent-decode code if needed (query parser left encodings intact).
    const code = try percentDecodeAlloc(allocator, cb.code);
    defer allocator.free(code);

    var tokens = try oauth.exchangeCode(io, allocator, cfg, code, redirect_uri, &pair.verifier);
    defer tokens.deinit(allocator);

    var info = try oauth.userInfo(io, allocator, cfg, tokens.access_token);
    defer info.deinit(allocator);

    const now: i64 = Io.Clock.real.now(io).toSeconds();
    const expires_at = std.math.add(i64, now, @max(tokens.expires_in, 0)) catch return error.InvalidTokenResponse;

    var store = try store_mod.Store.open(io, allocator, env);
    defer store.close();
    try store.putSession(.{
        .clerk_user_id = info.sub,
        .email = info.email,
        .access_token = tokens.access_token,
        .refresh_token = tokens.refresh_token,
        .expires_at = expires_at,
        .scopes = tokens.scope,
        .updated_at = now,
    });

    return .{
        .email = if (info.email) |e| try allocator.dupe(u8, e) else null,
        .clerk_user_id = try allocator.dupe(u8, info.sub),
    };
}

pub fn logout(
    io: Io,
    allocator: std.mem.Allocator,
    env: *const Env,
) store_mod.Error!void {
    var store = try store_mod.Store.open(io, allocator, env);
    defer store.close();

    if (try store.getSession(allocator)) |sess_const| {
        var sess = sess_const;
        defer sess.deinit(allocator);
        if (config_mod.Config.fromEnv(env)) |cfg| {
            if (sess.refresh_token) |rt| {
                oauth.revoke(io, allocator, cfg, rt);
            } else {
                oauth.revoke(io, allocator, cfg, sess.access_token);
            }
        }
    }
    try store.clearSession();
}

/// Refresh access token if within `skew_seconds` of expiry. Returns owned access token.
pub fn ensureAccessToken(
    io: Io,
    allocator: std.mem.Allocator,
    env: *const Env,
    skew_seconds: i64,
) Error!?[]u8 {
    var store = try store_mod.Store.open(io, allocator, env);
    defer store.close();
    var sess = (try store.getSession(allocator)) orelse return null;
    defer sess.deinit(allocator);

    const now: i64 = Io.Clock.real.now(io).toSeconds();
    if (sess.expires_at > now + skew_seconds) {
        return try allocator.dupe(u8, sess.access_token);
    }

    const cfg = config_mod.Config.fromEnv(env) orelse return error.NotConfigured;
    // Expired/near-expiry without a refresh token: force re-login rather than
    // handing callers a known-stale access token.
    const refresh_token = sess.refresh_token orelse {
        try store.clearSession();
        return null;
    };

    var tokens = try oauth.refresh(io, allocator, cfg, refresh_token);
    defer tokens.deinit(allocator);

    const expires_at = std.math.add(i64, now, @max(tokens.expires_in, 0)) catch return error.InvalidTokenResponse;
    try store.putSession(.{
        .clerk_user_id = sess.clerk_user_id,
        .email = sess.email,
        .access_token = tokens.access_token,
        .refresh_token = tokens.refresh_token orelse refresh_token,
        .expires_at = expires_at,
        .scopes = tokens.scope orelse sess.scopes,
        .updated_at = now,
    });
    return try allocator.dupe(u8, tokens.access_token);
}

fn percentDecodeAlloc(allocator: std.mem.Allocator, input: []const u8) error{OutOfMemory}![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hi = std.fmt.parseInt(u8, input[i + 1 .. i + 3], 16) catch {
                try list.append(allocator, input[i]);
                i += 1;
                continue;
            };
            try list.append(allocator, hi);
            i += 3;
        } else if (input[i] == '+') {
            try list.append(allocator, ' ');
            i += 1;
        } else {
            try list.append(allocator, input[i]);
            i += 1;
        }
    }
    return try list.toOwnedSlice(allocator);
}

test "percentDecodeAlloc" {
    const gpa = std.testing.allocator;
    const d = try percentDecodeAlloc(gpa, "a%2Fb+c");
    defer gpa.free(d);
    try std.testing.expectEqualStrings("a/b c", d);
}
