//! Local SQLite session store for product auth (`$PMS_HOME/auth/session.db`).
//!
//! Single active session (id=1). Tokens are never logged.
//! File mode 0600 is required on open (fail closed if chmod fails).
//! Journal mode stays DELETE (no WAL sidecars that could skip permissioning).
//!
//! Engine: vendored SQLite via zig-libsql (not system libsqlite3).

const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const Env = std.process.Environ.Map;
const paths = @import("paths.zig");
const libsql = @import("zig_libsql");

const log = std.log.scoped(.session_store);

pub const Error = error{
    SqliteOpen,
    SqliteExec,
    SqlitePrepare,
    SqliteBind,
    SqliteStep,
    FilePermissions,
    OutOfMemory,
    NoHomeDirectory,
};

pub const Session = struct {
    clerk_user_id: []const u8,
    email: ?[]const u8,
    access_token: []const u8,
    refresh_token: ?[]const u8,
    expires_at: i64,
    scopes: ?[]const u8,
    updated_at: i64,

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.clerk_user_id);
        if (self.email) |e| allocator.free(e);
        // Owned by getSession; const in the public type so putSession can borrow.
        std.crypto.secureZero(u8, @constCast(self.access_token));
        allocator.free(self.access_token);
        if (self.refresh_token) |t| {
            std.crypto.secureZero(u8, @constCast(t));
            allocator.free(t);
        }
        if (self.scopes) |s| allocator.free(s);
        self.* = undefined;
    }
};

pub const Store = struct {
    db: libsql.Database,
    path: []const u8,
    allocator: std.mem.Allocator,

    pub fn open(io: Io, allocator: std.mem.Allocator, env: *const Env) Error!Store {
        // Ensure `$PMS_HOME/auth` exists (mode 0700) before creating session.db.
        const auth_dir = paths.authDir(allocator, env) catch |e| switch (e) {
            error.NoHomeDirectory => return error.NoHomeDirectory,
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer allocator.free(auth_dir);
        _ = Dir.cwd().createDirPathStatus(io, auth_dir, .fromMode(0o700)) catch |e| {
            log.err("failed to create auth directory {s}: {s}", .{ auth_dir, @errorName(e) });
            return error.FilePermissions;
        };
        // Fail closed: re-apply 0700 even if the directory already existed.
        Dir.cwd().setFilePermissions(io, auth_dir, .fromMode(0o700), .{}) catch |e| {
            log.err("failed to restrict auth directory permissions for {s}: {s}", .{ auth_dir, @errorName(e) });
            return error.FilePermissions;
        };

        // Ownership of db_path transfers to openPathOwned (frees on all errors).
        const db_path = paths.sessionDbPath(allocator, env) catch |e| switch (e) {
            error.NoHomeDirectory => return error.NoHomeDirectory,
            error.OutOfMemory => return error.OutOfMemory,
        };
        return try openPathOwned(io, allocator, db_path);
    }

    /// Open an explicit path (tests). Parent directory must exist.
    /// Caller path is copied; openPathOwned owns the copy.
    pub fn openPath(io: Io, allocator: std.mem.Allocator, db_path: []const u8) Error!Store {
        const path_owned = allocator.dupe(u8, db_path) catch return error.OutOfMemory;
        return try openPathOwned(io, allocator, path_owned);
    }

    /// Takes ownership of `db_path` (allocator-owned). Frees it on every error path.
    fn openPathOwned(io: Io, allocator: std.mem.Allocator, db_path: []const u8) Error!Store {
        var database = libsql.Database.open(allocator, .{ .path = db_path }) catch |e| {
            allocator.free(db_path);
            return switch (e) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.SqliteOpen,
            };
        };

        // Required: token store must not stay group/world readable.
        Dir.cwd().setFilePermissions(io, db_path, .fromMode(0o600), .{}) catch |e| {
            log.err("failed to restrict session DB permissions for {s}: {s}", .{ db_path, @errorName(e) });
            database.deinit();
            allocator.free(db_path);
            return error.FilePermissions;
        };

        var store: Store = .{
            .db = database,
            .path = db_path,
            .allocator = allocator,
        };
        errdefer store.close();

        try store.migrate();
        return store;
    }

    pub fn close(self: *Store) void {
        self.db.deinit();
        self.allocator.free(self.path);
        self.* = undefined;
    }

    fn migrate(self: *Store) Error!void {
        // DELETE journal (default): no session.db-wal / session.db-shm sidecars.
        const sql =
            \\PRAGMA journal_mode=DELETE;
            \\CREATE TABLE IF NOT EXISTS meta (
            \\  key   TEXT PRIMARY KEY,
            \\  value TEXT NOT NULL
            \\);
            \\CREATE TABLE IF NOT EXISTS session (
            \\  id              INTEGER PRIMARY KEY CHECK (id = 1),
            \\  clerk_user_id   TEXT NOT NULL,
            \\  email           TEXT,
            \\  access_token    TEXT NOT NULL,
            \\  refresh_token   TEXT,
            \\  expires_at      INTEGER NOT NULL,
            \\  scopes          TEXT,
            \\  updated_at      INTEGER NOT NULL
            \\);
            \\INSERT OR IGNORE INTO meta(key, value) VALUES('schema_version', '1');
        ;
        try self.exec(sql);
    }

    fn exec(self: *Store, sql: []const u8) Error!void {
        var conn = self.db.connect();
        conn.exec(sql, .{}) catch |e| {
            log.err("sqlite exec: {s}", .{conn.lastErrorMessage()});
            return switch (e) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.SqliteExec,
            };
        };
    }

    pub fn putSession(self: *Store, session: Session) Error!void {
        const sql =
            \\INSERT INTO session(id, clerk_user_id, email, access_token, refresh_token, expires_at, scopes, updated_at)
            \\VALUES(1, ?1, ?2, ?3, ?4, ?5, ?6, ?7)
            \\ON CONFLICT(id) DO UPDATE SET
            \\  clerk_user_id=excluded.clerk_user_id,
            \\  email=excluded.email,
            \\  access_token=excluded.access_token,
            \\  refresh_token=excluded.refresh_token,
            \\  expires_at=excluded.expires_at,
            \\  scopes=excluded.scopes,
            \\  updated_at=excluded.updated_at;
        ;
        var conn = self.db.connect();
        var stmt = conn.prepare(sql) catch |e| {
            log.err("sqlite prepare: {s}", .{conn.lastErrorMessage()});
            return switch (e) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.SqlitePrepare,
            };
        };
        defer stmt.deinit();

        try bindText(&stmt, 1, session.clerk_user_id);
        try bindTextOpt(&stmt, 2, session.email);
        try bindText(&stmt, 3, session.access_token);
        try bindTextOpt(&stmt, 4, session.refresh_token);
        stmt.bindInt(5, session.expires_at) catch |e| return switch (e) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.SqliteBind,
        };
        try bindTextOpt(&stmt, 6, session.scopes);
        stmt.bindInt(7, session.updated_at) catch |e| return switch (e) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.SqliteBind,
        };

        stmt.execute() catch |e| {
            log.err("sqlite step: {s}", .{conn.lastErrorMessage()});
            return switch (e) {
                error.OutOfMemory => error.OutOfMemory,
                error.Bind => error.SqliteBind,
                else => error.SqliteStep,
            };
        };
    }

    pub fn getSession(self: *Store, allocator: std.mem.Allocator) Error!?Session {
        const sql =
            \\SELECT clerk_user_id, email, access_token, refresh_token, expires_at, scopes, updated_at
            \\FROM session WHERE id = 1;
        ;
        var conn = self.db.connect();
        var stmt = conn.prepare(sql) catch |e| {
            log.err("sqlite prepare: {s}", .{conn.lastErrorMessage()});
            return switch (e) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.SqlitePrepare,
            };
        };
        defer stmt.deinit();

        const row = stmt.step() catch |e| {
            log.err("sqlite step: {s}", .{conn.lastErrorMessage()});
            return switch (e) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.SqliteStep,
            };
        } orelse return null;

        const user_id = try dupText(allocator, row, 0) orelse return error.SqliteStep;
        errdefer allocator.free(user_id);
        const email = try dupText(allocator, row, 1);
        errdefer if (email) |e| allocator.free(e);
        const access = try dupText(allocator, row, 2) orelse return error.SqliteStep;
        errdefer allocator.free(access);
        const refresh = try dupText(allocator, row, 3);
        errdefer if (refresh) |t| allocator.free(t);
        const expires_at = row.int(4) catch return error.SqliteStep;
        const scopes = try dupText(allocator, row, 5);
        errdefer if (scopes) |s| allocator.free(s);
        const updated_at = row.int(6) catch return error.SqliteStep;

        return .{
            .clerk_user_id = user_id,
            .email = email,
            .access_token = access,
            .refresh_token = refresh,
            .expires_at = expires_at,
            .scopes = scopes,
            .updated_at = updated_at,
        };
    }

    pub fn clearSession(self: *Store) Error!void {
        try self.exec("DELETE FROM session WHERE id = 1;");
    }
};

fn mkdirp(io: Io, path: []const u8) !void {
    try Dir.cwd().createDirPath(io, path);
}

fn bindText(stmt: *libsql.Statement, idx: usize, text: []const u8) Error!void {
    stmt.bindText(idx, text) catch |e| return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.SqliteBind,
    };
}

fn bindTextOpt(stmt: *libsql.Statement, idx: usize, text: ?[]const u8) Error!void {
    if (text) |t| return bindText(stmt, idx, t);
    stmt.bindNull(idx) catch |e| return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.SqliteBind,
    };
}

fn dupText(allocator: std.mem.Allocator, row: libsql.Row, col: usize) Error!?[]u8 {
    const slice = row.text(col) catch return error.SqliteStep;
    const s = slice orelse return null;
    return allocator.dupe(u8, s) catch return error.OutOfMemory;
}

fn removeAllAbsolute(io: Io, path: []const u8) void {
    Dir.cwd().deleteTree(io, path) catch {};
    Dir.cwd().deleteFile(io, path) catch {};
}

/// Absolute unique directory path under `/tmp` for tests. Does not create it.
fn uniqueTmpRoot(io: Io, allocator: std.mem.Allocator, tag: []const u8) ![]u8 {
    var rb: [4]u8 = undefined;
    io.random(&rb);
    const hex = std.fmt.bytesToHex(rb, .lower);
    return std.fmt.allocPrint(allocator, "/tmp/clerk-zig-{s}-{d}-{s}", .{ tag, std.os.linux.getpid(), hex[0..8] });
}

test "store put get clear roundtrip" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const root = try uniqueTmpRoot(io, gpa, "auth-store");
    defer gpa.free(root);
    defer removeAllAbsolute(io, root);
    try mkdirp(io, root);

    const db_path = try std.fs.path.join(gpa, &.{ root, "session.db" });
    defer gpa.free(db_path);

    var store = try Store.openPath(io, gpa, db_path);
    defer store.close();

    try std.testing.expect((try store.getSession(gpa)) == null);

    try store.putSession(.{
        .clerk_user_id = "user_abc",
        .email = "dev@example.com",
        .access_token = "access-secret",
        .refresh_token = "refresh-secret",
        .expires_at = 1_700_000_000,
        .scopes = "profile email",
        .updated_at = 1_700_000_000,
    });

    var got = (try store.getSession(gpa)).?;
    defer got.deinit(gpa);
    try std.testing.expectEqualStrings("user_abc", got.clerk_user_id);
    try std.testing.expectEqualStrings("dev@example.com", got.email.?);
    try std.testing.expectEqualStrings("access-secret", got.access_token);
    try std.testing.expectEqualStrings("refresh-secret", got.refresh_token.?);
    try std.testing.expectEqual(@as(i64, 1_700_000_000), got.expires_at);

    try store.clearSession();
    try std.testing.expect((try store.getSession(gpa)) == null);
}

test "store open via PMS_HOME" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var env = Env.init(gpa);
    defer env.deinit();
    const home_dir = try uniqueTmpRoot(io, gpa, "auth-home");
    defer gpa.free(home_dir);
    defer removeAllAbsolute(io, home_dir);
    try env.put("PMS_HOME", home_dir);

    var store = try Store.open(io, gpa, &env);
    defer store.close();
    try std.testing.expect(std.mem.endsWith(u8, store.path, "auth/session.db"));
}
