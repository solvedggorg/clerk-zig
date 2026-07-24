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
        const manifest_path = paths.toolchainsManifestPath(allocator, env) catch |e| switch (e) {
            error.NoHomeDirectory => return error.NoHomeDirectory,
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer allocator.free(manifest_path);
        return try loadPath(io, allocator, manifest_path);
    }

    /// Load from an explicit path (tests). Missing file → empty; path still recorded.
    pub fn loadPath(io: Io, allocator: std.mem.Allocator, manifest_path: []const u8) Error!Registry {
        const path_owned = allocator.dupe(u8, manifest_path) catch return error.OutOfMemory;
        errdefer allocator.free(path_owned);

        const text = Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(1 << 20)) catch |e| switch (e) {
            error.FileNotFound => {
                return .{
                    .allocator = allocator,
                    .entries = .empty,
                    .path = path_owned,
                };
            },
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoFailure,
        };
        defer allocator.free(text);

        var entries = try parseManifest(allocator, text);
        errdefer {
            for (entries.items) |*ent| ent.deinit(allocator);
            entries.deinit(allocator);
        }

        return .{
            .allocator = allocator,
            .entries = entries,
            .path = path_owned,
        };
    }

    pub fn save(self: *const Registry, io: Io) Error!void {
        const parent = std.fs.path.dirname(self.path) orelse return error.IoFailure;
        _ = Dir.cwd().createDirPathStatus(io, parent, .fromMode(0o700)) catch return error.IoFailure;

        const rendered = try renderManifest(self.allocator, self.entries.items);
        defer self.allocator.free(rendered);

        const tmp_path = std.fmt.allocPrint(self.allocator, "{s}.tmp", .{self.path}) catch return error.OutOfMemory;
        defer self.allocator.free(tmp_path);

        Dir.cwd().writeFile(io, .{ .sub_path = tmp_path, .data = rendered }) catch return error.IoFailure;
        errdefer Dir.cwd().deleteFile(io, tmp_path) catch {};

        Dir.renameAbsolute(tmp_path, self.path, io) catch return error.IoFailure;

        Dir.cwd().setFilePermissions(io, self.path, .fromMode(0o600), .{}) catch return error.IoFailure;
    }

    pub fn get(self: *const Registry, name: []const u8) ?*const ToolEntry {
        for (self.entries.items) |*e| {
            if (std.mem.eql(u8, e.name, name)) return e;
        }
        return null;
    }

    /// Upsert by name. Copies all fields onto the registry allocator.
    pub fn put(self: *Registry, entry: ToolEntry) Error!void {
        try validateEntry(entry);

        const name = self.allocator.dupe(u8, entry.name) catch return error.OutOfMemory;
        errdefer self.allocator.free(name);
        const version = self.allocator.dupe(u8, entry.version) catch return error.OutOfMemory;
        errdefer self.allocator.free(version);
        const path = self.allocator.dupe(u8, entry.path) catch return error.OutOfMemory;
        errdefer self.allocator.free(path);

        const owned: ToolEntry = .{
            .name = name,
            .version = version,
            .path = path,
            .updated_at = entry.updated_at,
        };

        for (self.entries.items) |*e| {
            if (std.mem.eql(u8, e.name, owned.name)) {
                e.deinit(self.allocator);
                e.* = owned;
                return;
            }
        }

        self.entries.append(self.allocator, owned) catch return error.OutOfMemory;
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

const Partial = struct {
    name: ?[]u8 = null,
    version: ?[]u8 = null,
    path: ?[]u8 = null,
    updated_at: ?i64 = null,
    active: bool = false,

    fn hasAny(self: Partial) bool {
        return self.name != null or self.version != null or self.path != null or self.updated_at != null;
    }

    fn deinit(self: *Partial, allocator: std.mem.Allocator) void {
        if (self.name) |n| allocator.free(n);
        if (self.version) |v| allocator.free(v);
        if (self.path) |p| allocator.free(p);
        self.* = .{};
    }

    fn isComplete(self: Partial) bool {
        return self.name != null and self.version != null and self.path != null and self.updated_at != null;
    }
};

fn finalizePartial(allocator: std.mem.Allocator, partial: *Partial, list: *std.ArrayListUnmanaged(ToolEntry)) Error!void {
    if (!partial.active) return;
    if (!partial.isComplete()) {
        partial.deinit(allocator);
        return error.MalformedManifest;
    }
    const entry: ToolEntry = .{
        .name = partial.name.?,
        .version = partial.version.?,
        .path = partial.path.?,
        .updated_at = partial.updated_at.?,
    };
    // Clear partial ownership before validate may fail without free of entry fields.
    partial.* = .{};
    errdefer {
        var e = entry;
        e.deinit(allocator);
    }
    try validateEntry(entry);
    list.append(allocator, entry) catch return error.OutOfMemory;
}

fn parseQuoted(allocator: std.mem.Allocator, raw: []const u8) Error![]u8 {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return error.MalformedManifest;
    return allocator.dupe(u8, raw[1 .. raw.len - 1]) catch return error.OutOfMemory;
}

fn parseKeyValue(allocator: std.mem.Allocator, line: []const u8, partial: *Partial) Error!void {
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return error.MalformedManifest;
    const key = std.mem.trim(u8, line[0..eq], " \t");
    const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
    if (key.len == 0 or value.len == 0) return error.MalformedManifest;

    if (std.mem.eql(u8, key, "name")) {
        if (partial.name != null) return error.MalformedManifest;
        partial.name = try parseQuoted(allocator, value);
    } else if (std.mem.eql(u8, key, "version")) {
        if (partial.version != null) return error.MalformedManifest;
        partial.version = try parseQuoted(allocator, value);
    } else if (std.mem.eql(u8, key, "path")) {
        if (partial.path != null) return error.MalformedManifest;
        partial.path = try parseQuoted(allocator, value);
    } else if (std.mem.eql(u8, key, "updated_at")) {
        if (partial.updated_at != null) return error.MalformedManifest;
        partial.updated_at = std.fmt.parseInt(i64, value, 10) catch return error.MalformedManifest;
    } else {
        return error.MalformedManifest;
    }
}

fn parseManifest(allocator: std.mem.Allocator, text: []const u8) Error!std.ArrayListUnmanaged(ToolEntry) {
    var list: std.ArrayListUnmanaged(ToolEntry) = .empty;
    errdefer {
        for (list.items) |*e| e.deinit(allocator);
        list.deinit(allocator);
    }

    var partial: Partial = .{};
    errdefer partial.deinit(allocator);

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        // Strip optional CR from CRLF.
        const line_no_cr = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r')
            raw_line[0 .. raw_line.len - 1]
        else
            raw_line;
        const line = std.mem.trim(u8, line_no_cr, " \t");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.eql(u8, line, "[[tool]]")) {
            if (partial.active) {
                try finalizePartial(allocator, &partial, &list);
            } else if (partial.hasAny()) {
                return error.MalformedManifest;
            }
            partial = .{ .active = true };
            continue;
        }

        if (!partial.active) return error.MalformedManifest;
        try parseKeyValue(allocator, line, &partial);
    }

    if (partial.active) {
        try finalizePartial(allocator, &partial, &list);
    } else if (partial.hasAny()) {
        return error.MalformedManifest;
    }

    return list;
}

fn renderManifest(allocator: std.mem.Allocator, entries: []const ToolEntry) Error![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    list.appendSlice(allocator, "# clerk-zig registry v1\n\n") catch return error.OutOfMemory;

    for (entries) |e| {
        const block = std.fmt.allocPrint(allocator,
            \\[[tool]]
            \\name = "{s}"
            \\version = "{s}"
            \\path = "{s}"
            \\updated_at = {d}
            \\
            \\
        , .{ e.name, e.version, e.path, e.updated_at }) catch return error.OutOfMemory;
        defer allocator.free(block);
        list.appendSlice(allocator, block) catch return error.OutOfMemory;
    }

    return list.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn mkdirp(io: Io, path: []const u8) !void {
    try Dir.cwd().createDirPath(io, path);
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
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const root = try uniqueTmpRoot(io, gpa, "registry");
    defer gpa.free(root);
    defer removeAllAbsolute(io, root);
    try mkdirp(io, root);

    const manifest = try std.fs.path.join(gpa, &.{ root, "manifest.toml" });
    defer gpa.free(manifest);

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

test "parseManifest rejects incomplete tool and unknown keys" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.MalformedManifest, parseManifest(gpa,
        \\[[tool]]
        \\name = "x"
        \\
    ));
    try std.testing.expectError(error.MalformedManifest, parseManifest(gpa,
        \\[[tool]]
        \\name = "x"
        \\version = "1"
        \\path = "/abs"
        \\updated_at = 1
        \\extra = "nope"
        \\
    ));
}

test "parseManifest OOM is clean under checkAllAllocationFailures" {
    const gpa = std.testing.allocator;
    const sample =
        \\[[tool]]
        \\name = "rusty"
        \\version = "0.0.1"
        \\path = "/tmp/pms/rusty"
        \\updated_at = 1
        \\
    ;
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn impl(allocator: std.mem.Allocator, text: []const u8) !void {
            var list = parseManifest(allocator, text) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return e,
            };
            defer {
                for (list.items) |*ent| ent.deinit(allocator);
                list.deinit(allocator);
            }
        }
    }.impl, .{sample});
}
