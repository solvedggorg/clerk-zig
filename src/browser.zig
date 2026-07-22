//! Open a URL in the user's default browser (Linux).
//!
//! Always launches via `xdg-open`, which exits quickly and consults `$BROWSER`
//! from the process environment. Waiting on a long-lived browser binary would
//! block the OAuth callback listener.

const std = @import("std");
const Io = std.Io;
const Env = std.process.Environ.Map;

pub const Error = error{OpenFailed};

/// Open `url` in a browser. Does not block until the browser window closes.
pub fn open(io: Io, env: *const Env, url: []const u8) Error!void {
    _ = env; // child inherits process env; xdg-open honors $BROWSER
    var child = std.process.spawn(io, .{
        .argv = &.{ "xdg-open", url },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return error.OpenFailed;
    // xdg-open is short-lived (launches then exits); reaping avoids zombies.
    _ = child.wait(io) catch return error.OpenFailed;
}
