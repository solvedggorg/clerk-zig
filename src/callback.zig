//! One-shot localhost OAuth callback server on `127.0.0.1` (dynamic port).

const std = @import("std");
const Io = std.Io;
const net = std.Io.net;

pub const CallbackResult = struct {
    code: []u8,
    state: []u8,

    pub fn deinit(self: *CallbackResult, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.state);
        self.* = undefined;
    }
};

pub const Error = error{
    BindFailed,
    AcceptFailed,
    InvalidCallback,
    MissingCode,
    MissingState,
    OutOfMemory,
    WriteFailed,
    ReadFailed,
};

pub const Listener = struct {
    server: net.Server,
    port: u16,
    io: Io,

    pub fn start(io: Io) Error!Listener {
        const addr: net.IpAddress = .{ .ip4 = .loopback(0) };
        var server = addr.listen(io, .{
            .kernel_backlog = 1,
            .reuse_address = true,
        }) catch return error.BindFailed;
        const port = server.socket.address.getPort();
        if (port == 0) {
            server.deinit(io);
            return error.BindFailed;
        }
        return .{
            .server = server,
            .port = port,
            .io = io,
        };
    }

    pub fn deinit(self: *Listener) void {
        self.server.deinit(self.io);
        self.* = undefined;
    }

    pub fn redirectUri(self: *const Listener, buf: []u8) error{NoSpaceLeft}![]const u8 {
        return std.fmt.bufPrint(buf, "http://127.0.0.1:{d}/callback", .{self.port});
    }

    /// Block until one HTTP request arrives; parse `code` and `state` query params.
    pub fn wait(self: *Listener, allocator: std.mem.Allocator) Error!CallbackResult {
        const stream = self.server.accept(self.io) catch return error.AcceptFailed;
        defer stream.close(self.io);

        var in_buf: [8192]u8 = undefined;
        var out_buf: [1024]u8 = undefined;
        var stream_reader = stream.reader(self.io, &in_buf);
        var stream_writer = stream.writer(self.io, &out_buf);

        // Read until end of headers (\r\n\r\n) or buffer full.
        var head: std.ArrayList(u8) = .empty;
        defer head.deinit(allocator);
        while (true) {
            var tmp: [512]u8 = undefined;
            const n = stream_reader.interface.readSliceShort(&tmp) catch return error.ReadFailed;
            if (n == 0) break;
            try head.appendSlice(allocator, tmp[0..n]);
            if (std.mem.indexOf(u8, head.items, "\r\n\r\n") != null) break;
            if (head.items.len > 16 * 1024) return error.InvalidCallback;
        }

        const target = parseRequestTarget(head.items) orelse return error.InvalidCallback;
        const code = queryParam(target, "code") orelse return error.MissingCode;
        const state = queryParam(target, "state") orelse return error.MissingState;

        const html =
            \\<!doctype html><html><head><meta charset="utf-8"><title>Signed in</title></head>
            \\<body style="font-family:system-ui;padding:2rem">
            \\<h1>Signed in</h1><p>You can close this tab and return to the terminal.</p>
            \\</body></html>
        ;
        const response = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ html.len, html });
        defer allocator.free(response);
        stream_writer.interface.writeAll(response) catch return error.WriteFailed;
        stream_writer.interface.flush() catch {};

        const code_owned = try allocator.dupe(u8, code);
        errdefer allocator.free(code_owned);
        const state_owned = try allocator.dupe(u8, state);
        return .{
            .code = code_owned,
            .state = state_owned,
        };
    }
};

fn parseRequestTarget(head: []const u8) ?[]const u8 {
    // First line: METHOD target HTTP/1.x
    const line_end = std.mem.indexOf(u8, head, "\r\n") orelse return null;
    const line = head[0..line_end];
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next() orelse return null; // method
    return it.next();
}

fn queryParam(target: []const u8, key: []const u8) ?[]const u8 {
    const qmark = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    var it = std.mem.splitScalar(u8, target[qmark + 1 ..], '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const k = pair[0..eq];
        const v = pair[eq + 1 ..];
        if (std.mem.eql(u8, k, key)) return v;
    }
    return null;
}

test "queryParam extracts code and state" {
    const t = "/callback?code=abc%2F1&state=xyz";
    try std.testing.expectEqualStrings("abc%2F1", queryParam(t, "code").?);
    try std.testing.expectEqualStrings("xyz", queryParam(t, "state").?);
    try std.testing.expect(queryParam(t, "missing") == null);
}

test "parseRequestTarget" {
    const head = "GET /callback?code=a&state=b HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
    try std.testing.expectEqualStrings("/callback?code=a&state=b", parseRequestTarget(head).?);
}
