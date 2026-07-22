//! Clerk OAuth token exchange / refresh / revoke / userinfo for the CLI.

const std = @import("std");
const Io = std.Io;
const config_mod = @import("config.zig");
const Config = config_mod.Config;

pub const TokenSet = struct {
    access_token: []u8,
    refresh_token: ?[]u8,
    expires_in: i64,
    scope: ?[]u8,

    pub fn deinit(self: *TokenSet, allocator: std.mem.Allocator) void {
        allocator.free(self.access_token);
        if (self.refresh_token) |t| allocator.free(t);
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
    return try postForm(io, allocator, cfg, "/oauth/token", &.{
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
    return try postForm(io, allocator, cfg, "/oauth/token", &.{
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
    var dummy = postForm(io, allocator, cfg, "/oauth/revoke", &.{
        .{ .k = "token", .v = token },
        .{ .k = "client_id", .v = cfg.client_id },
    }) catch return;
    dummy.deinit(allocator);
}

pub fn userInfo(
    io: Io,
    allocator: std.mem.Allocator,
    cfg: Config,
    access_token: []const u8,
) Error!UserInfo {
    const url = try std.fmt.allocPrint(allocator, "{s}/oauth/userinfo", .{cfg.issuer});
    defer allocator.free(url);

    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{access_token});
    defer allocator.free(auth_header);

    const body = try fetchBytes(io, allocator, .{
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

const FormField = struct { k: []const u8, v: []const u8 };

fn postForm(
    io: Io,
    allocator: std.mem.Allocator,
    cfg: Config,
    path: []const u8,
    fields: []const FormField,
) Error!TokenSet {
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

    const resp = try fetchBytes(io, allocator, .{
        .url = url,
        .method = .POST,
        .payload = payload,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
            .{ .name = "Accept", .value = "application/json" },
        },
    });
    defer allocator.free(resp);

    // Revoke may return empty body / non-token JSON.
    if (std.mem.eql(u8, path, "/oauth/revoke")) {
        return .{
            .access_token = try allocator.dupe(u8, ""),
            .refresh_token = null,
            .expires_in = 0,
            .scope = null,
        };
    }

    return try parseTokenSet(allocator, resp);
}

const FetchOpts = struct {
    url: []const u8,
    method: std.http.Method,
    payload: ?[]const u8,
    extra_headers: []const std.http.Header,
};

fn fetchBytes(io: Io, allocator: std.mem.Allocator, opts: FetchOpts) Error![]u8 {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

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
    if (status >= 400) return error.HttpStatusError;
    return try aw.toOwnedSlice();
}

fn parseTokenSet(allocator: std.mem.Allocator, body: []const u8) Error!TokenSet {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.InvalidTokenResponse;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.InvalidTokenResponse,
    };
    const access = obj.get("access_token") orelse return error.InvalidTokenResponse;
    const access_s = switch (access) {
        .string => |s| s,
        else => return error.InvalidTokenResponse,
    };
    const refresh_s: ?[]const u8 = blk: {
        const r = obj.get("refresh_token") orelse break :blk null;
        break :blk switch (r) {
            .string => |s| s,
            else => null,
        };
    };
    const expires: i64 = blk: {
        const e = obj.get("expires_in") orelse break :blk 3600;
        break :blk switch (e) {
            .integer => |i| i,
            .float => |f| {
                if (!std.math.isFinite(f)) return error.InvalidTokenResponse;
                if (f < 0 or f > @as(f64, @floatFromInt(std.math.maxInt(i64)))) return error.InvalidTokenResponse;
                break :blk @intFromFloat(f);
            },
            else => 3600,
        };
    };
    const scope_s: ?[]const u8 = blk: {
        const s = obj.get("scope") orelse break :blk null;
        break :blk switch (s) {
            .string => |x| x,
            else => null,
        };
    };

    const access_token = try allocator.dupe(u8, access_s);
    errdefer allocator.free(access_token);
    const refresh_token: ?[]u8 = if (refresh_s) |r| try allocator.dupe(u8, r) else null;
    errdefer if (refresh_token) |t| allocator.free(t);
    const scope: ?[]u8 = if (scope_s) |s| try allocator.dupe(u8, s) else null;
    // last dupe: no further allocation after this; caller owns on success

    return .{
        .access_token = access_token,
        .refresh_token = refresh_token,
        .expires_in = expires,
        .scope = scope,
    };
}

fn parseUserInfo(allocator: std.mem.Allocator, body: []const u8) Error!UserInfo {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.InvalidUserInfo;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.InvalidUserInfo,
    };
    const sub_v = obj.get("sub") orelse return error.InvalidUserInfo;
    const sub = switch (sub_v) {
        .string => |s| s,
        else => return error.InvalidUserInfo,
    };
    const email_s: ?[]const u8 = blk: {
        const e = obj.get("email") orelse break :blk null;
        break :blk switch (e) {
            .string => |s| s,
            else => null,
        };
    };
    const sub_owned = try allocator.dupe(u8, sub);
    errdefer allocator.free(sub_owned);
    const email: ?[]u8 = if (email_s) |e| try allocator.dupe(u8, e) else null;
    // last dupe: no further allocation after this; caller owns on success

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

test "parseUserInfo extracts sub and email" {
    const gpa = std.testing.allocator;
    var ui = try parseUserInfo(gpa,
        \\{"sub":"user_1","email":"a@b.co"}
    );
    defer ui.deinit(gpa);
    try std.testing.expectEqualStrings("user_1", ui.sub);
    try std.testing.expectEqualStrings("a@b.co", ui.email.?);
}
