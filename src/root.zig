//! clerk-zig — shared Clerk CLI auth for the PMS suite.
//!
//! Public OAuth client + PKCE only (no secret key). Session store:
//! `$PMS_HOME/auth/session.db` via zig-libsql. Linux only.
//!
//! ## Public modules
//!
//! | Module | Role |
//! |--------|------|
//! | `paths` | `$PMS_HOME` and auth/toolchain paths (caller owns slices) |
//! | `config` | Env → OAuth config (`PMS_AUTH_*`, legacy `RUSTY_AUTH_*`) |
//! | `pkce` | Verifier / S256 challenge / CSRF state |
//! | `oauth` | Authorize URL, token exchange, refresh, revoke, userinfo |
//! | `callback` | Loopback OAuth redirect listener |
//! | `browser` | Open system browser (`xdg-open`) |
//! | `store` | Single-row session CRUD (file mode 0600, journal DELETE) |
//! | `login` | Interactive login / logout / token refresh orchestration |
//! | `registry` | Toolchain install manifest (`manifest.toml`) |
//!
//! **Never log tokens** or URLs that embed secrets. See `docs/DESIGN.md`.

const std = @import("std");
const builtin = @import("builtin");

pub const version = "0.1.1";

pub const paths = @import("paths.zig");
pub const config = @import("config.zig");
pub const pkce = @import("pkce.zig");
pub const oauth = @import("oauth.zig");
pub const callback = @import("callback.zig");
pub const browser = @import("browser.zig");
pub const store = @import("store.zig");
pub const login = @import("login.zig");
pub const registry = @import("registry.zig");

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
    _ = registry;
}

test "version string non-empty" {
    try std.testing.expect(version.len > 0);
}
