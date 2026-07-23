//! Brand-neutral demo: print session identity from clerk-zig store.
//! Not a full OAuth CLI — consumers own `auth login` branding.
//! Tokens are never printed.

const std = @import("std");
const clerk = @import("clerk_zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;
    const env = init.environ_map;

    var store = clerk.store.Store.open(io, arena, env) catch |e| {
        std.debug.print("whoami: open store failed: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    };
    defer store.close();

    var sess = store.getSession(arena) catch |e| {
        std.debug.print("whoami: read failed: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    } orelse {
        std.debug.print("not logged in\n", .{});
        std.process.exit(1);
    };
    defer sess.deinit(arena);

    if (sess.email) |email| {
        std.debug.print("{s} ({s})\n", .{ email, sess.clerk_user_id });
    } else {
        std.debug.print("{s}\n", .{sess.clerk_user_id});
    }
}
