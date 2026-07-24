//! One-shot localhost OAuth callback server on `127.0.0.1` (dynamic port).

const std = @import("std");
const Io = std.Io;
const net = std.Io.net;

/// Default browser-callback wait (5 minutes).
pub const default_wait_timeout: Io.Timeout = .{ .duration = .{
    .raw = .fromSeconds(5 * 60),
    .clock = .real,
} };

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
    Timeout,
    OutOfMemory,
    WriteFailed,
    ReadFailed,
};

pub const Listener = struct {
    server: net.Server,
    port: u16,
    io: Io,
    /// True after server socket was closed (timeout cancel or normal deinit).
    closed: bool = false,

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
        if (!self.closed) {
            self.server.deinit(self.io);
            self.closed = true;
        }
        self.* = undefined;
    }

    pub fn redirectUri(self: *const Listener, buf: []u8) error{NoSpaceLeft}![]const u8 {
        return std.fmt.bufPrint(buf, "http://127.0.0.1:{d}/callback", .{self.port});
    }

    /// Block until one valid callback arrives (or `timeout` elapses).
    /// Pass `.none` for no deadline; `default_wait_timeout` for CLI login.
    pub fn wait(self: *Listener, allocator: std.mem.Allocator, timeout: Io.Timeout) Error!CallbackResult {
        const stream = try self.acceptStream(timeout);
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

        const line = firstRequestLine(head.items) orelse return error.InvalidCallback;
        const target = parseRequestTarget(line) orelse return error.InvalidCallback;
        if (!std.mem.eql(u8, parseMethod(line) orelse "", "GET")) return error.InvalidCallback;
        if (!pathIsCallback(target)) return error.InvalidCallback;

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

    fn acceptStream(self: *Listener, timeout: Io.Timeout) Error!net.Stream {
        if (timeout == .none) {
            return self.server.accept(self.io) catch return error.AcceptFailed;
        }

        // Concurrent accept + timed wait on a readiness flag. On timeout, close
        // the listen socket so accept unblocks (SocketNotListening).
        const Shared = struct {
            stream: ?net.Stream = null,
            err: ?net.Server.AcceptError = null,
            /// 0 = waiting, 1 = accept finished (success or error).
            ready: std.atomic.Value(u32) = .init(0),
        };
        var shared: Shared = .{};

        const AcceptTask = struct {
            fn run(listener: *Listener, st: *Shared) void {
                const s = listener.server.accept(listener.io) catch |e| {
                    st.err = e;
                    st.ready.store(1, .release);
                    Io.futexWake(listener.io, u32, &st.ready.raw, 1);
                    return;
                };
                st.stream = s;
                st.ready.store(1, .release);
                Io.futexWake(listener.io, u32, &st.ready.raw, 1);
            }
        };

        var fut = Io.concurrent(self.io, AcceptTask.run, .{ self, &shared }) catch {
            // A deadline was requested but we cannot honor it without
            // concurrency; fail instead of silently blocking forever.
            return error.AcceptFailed;
        };

        // Wait until ready or timeout. Spurious wakeups re-check the flag.
        while (shared.ready.load(.acquire) == 0) {
            Io.futexWaitTimeout(self.io, u32, &shared.ready.raw, 0, timeout) catch |e| switch (e) {
                error.Timeout => {
                    if (shared.ready.load(.acquire) != 0) break;
                    // Unblock accept by closing the listen socket.
                    if (!self.closed) {
                        self.server.deinit(self.io);
                        self.closed = true;
                    }
                    _ = fut.await(self.io);
                    // Prefer stream if accept raced past the close.
                    if (shared.stream) |s| return s;
                    return error.Timeout;
                },
                error.Canceled => {
                    if (!self.closed) {
                        self.server.deinit(self.io);
                        self.closed = true;
                    }
                    _ = fut.await(self.io);
                    return error.AcceptFailed;
                },
            };
        }

        _ = fut.await(self.io);
        if (shared.stream) |s| return s;
        if (shared.err) |e| switch (e) {
            error.SocketNotListening, error.Canceled => return error.Timeout,
            else => return error.AcceptFailed,
        };
        return error.AcceptFailed;
    }
};

fn firstRequestLine(head: []const u8) ?[]const u8 {
    const line_end = std.mem.indexOf(u8, head, "\r\n") orelse return null;
    return head[0..line_end];
}

fn parseMethod(line: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    return it.next();
}

fn parseRequestTarget(line: []const u8) ?[]const u8 {
    // METHOD target HTTP/1.x
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next() orelse return null; // method
    return it.next();
}

/// Path component (before `?`) must be `/callback`.
fn pathIsCallback(target: []const u8) bool {
    const path = if (std.mem.indexOfScalar(u8, target, '?')) |q|
        target[0..q]
    else
        target;
    return std.mem.eql(u8, path, "/callback");
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

test "parseRequestTarget and method" {
    const line = "GET /callback?code=a&state=b HTTP/1.1";
    try std.testing.expectEqualStrings("GET", parseMethod(line).?);
    try std.testing.expectEqualStrings("/callback?code=a&state=b", parseRequestTarget(line).?);
}

test "pathIsCallback rejects wrong paths" {
    try std.testing.expect(pathIsCallback("/callback?code=a&state=b"));
    try std.testing.expect(pathIsCallback("/callback"));
    try std.testing.expect(!pathIsCallback("/other?code=a&state=b"));
    try std.testing.expect(!pathIsCallback("/callback/extra"));
    try std.testing.expect(!pathIsCallback("/"));
}

test "firstRequestLine" {
    const head = "GET /callback?code=a&state=b HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
    try std.testing.expectEqualStrings("GET /callback?code=a&state=b HTTP/1.1", firstRequestLine(head).?);
}
