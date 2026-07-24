//! Clerk OAuth token exchange / refresh / revoke / userinfo for the CLI.

const std = @import("std");
const Io = std.Io;
const config_mod = @import("config.zig");
const Config = config_mod.Config;

const log = std.log.scoped(.oauth);

pub const TokenSet = struct {
    access_token: []u8,
    refresh_token: ?[]u8,
    expires_in: i64,
    scope: ?[]u8,

    pub fn deinit(self: *TokenSet, allocator: std.mem.Allocator) void {
        std.crypto.secureZero(u8, self.access_token);
        allocator.free(self.access_token);
        if (self.refresh_token) |t| {
            std.crypto.secureZero(u8, t);
            allocator.free(t);
        }
        if (self.scope) |s| allocator.free(s);
        self.* = undefined;
    }
};

pub const UserInfo = struct {
    sub: []u8,
    email: ?[]u8,

    pub fn deinit(self: *UserInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.sub);
        if (self.email) |e| allocator.free(e);
        self.* = undefined;
    }
};

/// HTTP failure with status for diagnostics (never log response bodies that may embed tokens).
pub const HttpStatus = struct {
    status: u16,
};

pub const Error = error{
    HttpStatusError,
    InvalidTokenResponse,
    InvalidUserInfo,
    OutOfMemory,
    WriteFailed,
} || std.http.Client.FetchError || std.Uri.ParseError;

/// Build the authorize URL (caller owns returned slice).
pub fn authorizeUrl(
    allocator: std.mem.Allocator,
    cfg: Config,
    redirect_uri: []const u8,
    challenge: []const u8,
    state: []const u8,
) error{OutOfMemory}![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try list.print(allocator, "{s}/oauth/authorize?response_type=code", .{cfg.issuer});
    try list.appendSlice(allocator, "&client_id=");
    try appendQuery(allocator, &list, cfg.client_id);
    try list.appendSlice(allocator, "&redirect_uri=");
    try appendQuery(allocator, &list, redirect_uri);
    try list.appendSlice(allocator, "&code_challenge=");
    try appendQuery(allocator, &list, challenge);
    try list.appendSlice(allocator, "&code_challenge_method=S256");
    try list.appendSlice(allocator, "&state=");
    try appendQuery(allocator, &list, state);
    try list.appendSlice(allocator, "&scope=");
    try appendQuery(allocator, &list, cfg.scopes);
    return try list.toOwnedSlice(allocator);
}

pub fn exchangeCode(
    io: Io,
    allocator: std.mem.Allocator,
    cfg: Config,
    code: []const u8,
    redirect_uri: []const u8,
    code_verifier: []const u8,
) Error!TokenSet {
    var client = makeClient(io, allocator);
    defer client.deinit();
    return try exchangeCodeClient(&client, allocator, cfg, code, redirect_uri, code_verifier);
}

pub fn exchangeCodeClient(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    cfg: Config,
    code: []const u8,
    redirect_uri: []const u8,
    code_verifier: []const u8,
) Error!TokenSet {
    return try postFormToken(client, allocator, cfg, "/oauth/token", &.{
        .{ .k = "grant_type", .v = "authorization_code" },
        .{ .k = "code", .v = code },
        .{ .k = "redirect_uri", .v = redirect_uri },
        .{ .k = "client_id", .v = cfg.client_id },
        .{ .k = "code_verifier", .v = code_verifier },
    });
}

pub fn refresh(
    io: Io,
    allocator: std.mem.Allocator,
    cfg: Config,
    refresh_token: []const u8,
) Error!TokenSet {
    var client = makeClient(io, allocator);
    defer client.deinit();
    return try refreshClient(&client, allocator, cfg, refresh_token);
}

pub fn refreshClient(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    cfg: Config,
    refresh_token: []const u8,
) Error!TokenSet {
    return try postFormToken(client, allocator, cfg, "/oauth/token", &.{
        .{ .k = "grant_type", .v = "refresh_token" },
        .{ .k = "refresh_token", .v = refresh_token },
        .{ .k = "client_id", .v = cfg.client_id },
    });
}

/// Best-effort revoke; errors are ignored by callers that only care about local clear.
pub fn revoke(
    io: Io,
    allocator: std.mem.Allocator,
    cfg: Config,
    token: []const u8,
) void {
    var client = makeClient(io, allocator);
    defer client.deinit();
    revokeClient(&client, allocator, cfg, token);
}

pub fn revokeClient(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    cfg: Config,
    token: []const u8,
) void {
    postFormRaw(client, allocator, cfg, "/oauth/revoke", &.{
        .{ .k = "token", .v = token },
        .{ .k = "client_id", .v = cfg.client_id },
    }) catch |e| {
        log.debug("revoke request failed: {s}", .{@errorName(e)});
        return;
    };
}

pub fn userInfo(
    io: Io,
    allocator: std.mem.Allocator,
    cfg: Config,
    access_token: []const u8,
) Error!UserInfo {
    var client = makeClient(io, allocator);
    defer client.deinit();
    return try userInfoClient(&client, allocator, cfg, access_token);
}

pub fn userInfoClient(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    cfg: Config,
    access_token: []const u8,
) Error!UserInfo {
    const url = try std.fmt.allocPrint(allocator, "{s}/oauth/userinfo", .{cfg.issuer});
    defer allocator.free(url);

    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{access_token});
    defer allocator.free(auth_header);

    const body = try fetchBytes(client, allocator, .{
        .url = url,
        .method = .GET,
        .payload = null,
        .extra_headers = &.{
            .{ .name = "Authorization", .value = auth_header },
            .{ .name = "Accept", .value = "application/json" },
        },
    });
    defer allocator.free(body);

    return try parseUserInfo(allocator, body);
}

fn makeClient(io: Io, allocator: std.mem.Allocator) std.http.Client {
    return .{ .allocator = allocator, .io = io };
}

const FormField = struct { k: []const u8, v: []const u8 };

fn postFormToken(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    cfg: Config,
    path: []const u8,
    fields: []const FormField,
) Error!TokenSet {
    const resp = try postFormRaw(client, allocator, cfg, path, fields);
    defer allocator.free(resp);
    return try parseTokenSet(allocator, resp);
}

fn postFormRaw(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    cfg: Config,
    path: []const u8,
    fields: []const FormField,
) Error![]u8 {
    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ cfg.issuer, path });
    defer allocator.free(url);

    var body_list: std.ArrayList(u8) = .empty;
    defer body_list.deinit(allocator);
    for (fields, 0..) |f, i| {
        if (i > 0) try body_list.append(allocator, '&');
        try appendQuery(allocator, &body_list, f.k);
        try body_list.append(allocator, '=');
        try appendQuery(allocator, &body_list, f.v);
    }
    const payload = body_list.items;

    return try fetchBytes(client, allocator, .{
        .url = url,
        .method = .POST,
        .payload = payload,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
            .{ .name = "Accept", .value = "application/json" },
        },
    });
}

const FetchOpts = struct {
    url: []const u8,
    method: std.http.Method,
    payload: ?[]const u8,
    extra_headers: []const std.http.Header,
};

fn fetchBytes(client: *std.http.Client, allocator: std.mem.Allocator, opts: FetchOpts) Error![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = opts.url },
        .method = opts.method,
        .payload = opts.payload,
        .extra_headers = opts.extra_headers,
        .response_writer = &aw.writer,
    });
    const status: u16 = @intFromEnum(result.status);
    if (status >= 400) {
        // Log status only — body may contain sensitive OAuth error detail near tokens.
        log.err("HTTP {d} from OAuth endpoint", .{status});
        return error.HttpStatusError;
    }
    return try aw.toOwnedSlice();
}

const TokenResponse = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    expires_in: ?std.json.Value = null,
    scope: ?[]const u8 = null,
};

fn parseTokenSet(allocator: std.mem.Allocator, body: []const u8) Error!TokenSet {
    const parsed = std.json.parseFromSlice(TokenResponse, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidTokenResponse,
    };
    defer parsed.deinit();
    const tr = parsed.value;

    if (tr.access_token.len == 0) return error.InvalidTokenResponse;

    const expires: i64 = blk: {
        const e = tr.expires_in orelse break :blk 3600;
        break :blk switch (e) {
            .integer => |i| i,
            .float => |f| {
                if (!std.math.isFinite(f)) return error.InvalidTokenResponse;
                if (f < 0 or f > @as(f64, @floatFromInt(std.math.maxInt(i64)))) return error.InvalidTokenResponse;
                break :blk @intFromFloat(f);
            },
            .string => |s| std.fmt.parseInt(i64, s, 10) catch return error.InvalidTokenResponse,
            else => 3600,
        };
    };

    const access_token = try allocator.dupe(u8, tr.access_token);
    errdefer {
        std.crypto.secureZero(u8, access_token);
        allocator.free(access_token);
    }
    const refresh_token: ?[]u8 = if (tr.refresh_token) |r| try allocator.dupe(u8, r) else null;
    errdefer if (refresh_token) |t| {
        std.crypto.secureZero(u8, t);
        allocator.free(t);
    };
    const scope: ?[]u8 = if (tr.scope) |s| try allocator.dupe(u8, s) else null;

    return .{
        .access_token = access_token,
        .refresh_token = refresh_token,
        .expires_in = expires,
        .scope = scope,
    };
}

const UserInfoResponse = struct {
    sub: []const u8,
    email: ?[]const u8 = null,
};

fn parseUserInfo(allocator: std.mem.Allocator, body: []const u8) Error!UserInfo {
    const parsed = std.json.parseFromSlice(UserInfoResponse, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidUserInfo,
    };
    defer parsed.deinit();
    const ui = parsed.value;
    if (ui.sub.len == 0) return error.InvalidUserInfo;

    const sub_owned = try allocator.dupe(u8, ui.sub);
    errdefer allocator.free(sub_owned);
    const email: ?[]u8 = if (ui.email) |e| try allocator.dupe(u8, e) else null;

    return .{
        .sub = sub_owned,
        .email = email,
    };
}

fn isUnreserved(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_' or c == '~';
}

fn appendQuery(allocator: std.mem.Allocator, list: *std.ArrayList(u8), raw: []const u8) error{OutOfMemory}!void {
    for (raw) |b| {
        if (isUnreserved(b)) {
            try list.append(allocator, b);
        } else if (b == ' ') {
            try list.append(allocator, '+');
        } else {
            var buf: [3]u8 = undefined;
            const enc = std.fmt.bufPrint(&buf, "%{X:0>2}", .{b}) catch unreachable;
            try list.appendSlice(allocator, enc);
        }
    }
}

test "authorizeUrl includes pkce params" {
    const gpa = std.testing.allocator;
    const url = try authorizeUrl(gpa, .{
        .issuer = "https://clerk.example.com",
        .client_id = "client_1",
        .scopes = "profile email",
    }, "http://127.0.0.1:1234/callback", "chal", "st");
    defer gpa.free(url);
    try std.testing.expect(std.mem.indexOf(u8, url, "https://clerk.example.com/oauth/authorize?") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge=chal") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "state=st") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "client_id=client_1") != null);
}

test "parseTokenSet extracts fields" {
    const gpa = std.testing.allocator;
    var ts = try parseTokenSet(gpa,
        \\{"access_token":"a","refresh_token":"r","expires_in":120,"scope":"profile"}
    );
    defer ts.deinit(gpa);
    try std.testing.expectEqualStrings("a", ts.access_token);
    try std.testing.expectEqualStrings("r", ts.refresh_token.?);
    try std.testing.expectEqual(@as(i64, 120), ts.expires_in);
}

test "parseTokenSet rejects missing access_token" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.InvalidTokenResponse, parseTokenSet(gpa,
        \\{"refresh_token":"r"}
    ));
}

test "parseTokenSet rejects non-object" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.InvalidTokenResponse, parseTokenSet(gpa, "[]"));
}

test "parseUserInfo extracts sub and email" {
    const gpa = std.testing.allocator;
    var ui = try parseUserInfo(gpa,
        \\{"sub":"user_1","email":"a@b.co"}
    );
    defer ui.deinit(gpa);
    try std.testing.expectEqualStrings("user_1", ui.sub);
    try std.testing.expectEqualStrings("a@b.co", ui.email.?);
}

test "parseUserInfo rejects missing sub" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.InvalidUserInfo, parseUserInfo(gpa,
        \\{"email":"a@b.co"}
    ));
}

test "authorizeUrl OOM is clean under checkAllAllocationFailures" {
    const gpa = std.testing.allocator;
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn impl(allocator: std.mem.Allocator) !void {
            const url = authorizeUrl(allocator, .{
                .issuer = "https://clerk.example.com",
                .client_id = "c",
                .scopes = "s",
            }, "http://127.0.0.1:1/callback", "chal", "st") catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
            };
            defer allocator.free(url);
        }
    }.impl, .{});
}

test "parseTokenSet OOM is clean under checkAllAllocationFailures" {
    const gpa = std.testing.allocator;
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn impl(allocator: std.mem.Allocator) !void {
            var ts = parseTokenSet(allocator,
                \\{"access_token":"a","refresh_token":"r","expires_in":1,"scope":"s"}
            ) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return e,
            };
            defer ts.deinit(allocator);
        }
    }.impl, .{});
}

test "appendQuery encodes reserved characters" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    try appendQuery(gpa, &list, "a b/c");
    try std.testing.expectEqualStrings("a+b%2Fc", list.items);
}
