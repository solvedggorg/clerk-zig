//! PKCE (RFC 7636) + CSRF state for the CLI OAuth login flow.

const std = @import("std");
const Io = std.Io;

pub const verifier_bytes = 32;
pub const state_bytes = 16;

/// Base64url (no pad) length for `n` raw bytes.
pub fn b64UrlLen(n: usize) usize {
    return std.base64.url_safe_no_pad.Encoder.calcSize(n);
}

pub const Pair = struct {
    /// High-entropy secret sent only at token exchange.
    verifier: [b64UrlLen(verifier_bytes)]u8,
    /// S256 challenge placed on the authorize URL.
    challenge: [b64UrlLen(32)]u8,
    /// CSRF token for the authorize/callback round-trip.
    state: [b64UrlLen(state_bytes)]u8,
};

/// Generate a fresh PKCE verifier/challenge and CSRF state using `io.random`.
pub fn generate(io: Io) Pair {
    var raw_v: [verifier_bytes]u8 = undefined;
    io.random(&raw_v);
    var raw_s: [state_bytes]u8 = undefined;
    io.random(&raw_s);

    var pair: Pair = undefined;
    _ = std.base64.url_safe_no_pad.Encoder.encode(&pair.verifier, &raw_v);
    _ = std.base64.url_safe_no_pad.Encoder.encode(&pair.state, &raw_s);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&pair.verifier, &digest, .{});
    _ = std.base64.url_safe_no_pad.Encoder.encode(&pair.challenge, &digest);
    return pair;
}

test "pkce generate shapes and challenge is S256 of verifier" {
    const io = std.testing.io;
    const p = generate(io);
    try std.testing.expect(p.verifier.len == b64UrlLen(verifier_bytes));
    try std.testing.expect(p.challenge.len == b64UrlLen(32));
    try std.testing.expect(p.state.len == b64UrlLen(state_bytes));

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&p.verifier, &digest, .{});
    var expect_chal: [b64UrlLen(32)]u8 = undefined;
    _ = std.base64.url_safe_no_pad.Encoder.encode(&expect_chal, &digest);
    try std.testing.expectEqualStrings(&expect_chal, &p.challenge);

    // Second draw should differ (random).
    const p2 = generate(io);
    try std.testing.expect(!std.mem.eql(u8, &p.verifier, &p2.verifier));
    try std.testing.expect(!std.mem.eql(u8, &p.state, &p2.state));
}
