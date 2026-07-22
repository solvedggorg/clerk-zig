//! clerk-zig — shared Clerk CLI auth for the PMS suite.
//!
//! Public OAuth client + PKCE, session store under `$PMS_HOME/auth/session.db`.
//! See docs/DESIGN.md. Linux only.

const std = @import("std");
const builtin = @import("builtin");

pub const version = "0.0.1-dev";

pub const paths = @import("paths.zig");
pub const config = @import("config.zig");
pub const pkce = @import("pkce.zig");
pub const oauth = @import("oauth.zig");
pub const callback = @import("callback.zig");
pub const browser = @import("browser.zig");
pub const store = @import("store.zig");
pub const login = @import("login.zig");

// Ported in plan Task 6:
// pub const registry = @import("registry.zig");

test {
    if (builtin.os.tag != .linux) {
        // Package is Linux-only; keep compile on other hosts for docs CI if needed.
    }
    _ = paths;
    _ = config;
    _ = pkce;
    _ = oauth;
    _ = callback;
    _ = browser;
    _ = store;
    _ = login;
}

test "version string non-empty" {
    try std.testing.expect(version.len > 0);
}
