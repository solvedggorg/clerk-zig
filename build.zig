const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("clerk_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Session store (Task 3). Path dep for monorepo development.
    const libsql = b.dependency("zig_libsql", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("zig_libsql", libsql.module("zig_libsql"));

    const lib = b.addLibrary(.{
        .name = "clerk_zig",
        .root_module = mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = mod,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library unit tests");
    test_step.dependOn(&run_tests.step);
}
