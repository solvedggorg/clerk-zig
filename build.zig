const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Primary contract: module `clerk_zig` for `b.dependency` + `addImport`.
    const mod = b.addModule("clerk_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Production pin: zig-libsql tag in build.zig.zon (not a monorepo path).
    const libsql = b.dependency("zig_libsql", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("zig_libsql", libsql.module("zig_libsql"));

    // Optional static library install for non-module consumers; most PMs only
    // need the module via addImport.
    const lib = b.addLibrary(.{
        .name = "clerk_zig",
        .root_module = mod,
        .linkage = .static,
    });
    const install_lib = b.addInstallArtifact(lib, .{});
    const lib_step = b.step("lib", "Install static library artifact");
    lib_step.dependOn(&install_lib.step);
    // Default `zig build` still installs the lib for local discoverability.
    b.getInstallStep().dependOn(&install_lib.step);

    // Brand-neutral store demo (optional consumer skeleton).
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/whoami.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "clerk_zig", .module = mod },
        },
    });
    const example = b.addExecutable(.{
        .name = "clerk-whoami",
        .root_module = example_mod,
    });
    const example_install = b.addInstallArtifact(example, .{});
    const example_step = b.step("example", "Build examples/whoami");
    example_step.dependOn(&example_install.step);

    const tests = b.addTest(.{
        .root_module = mod,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library unit tests");
    test_step.dependOn(&run_tests.step);
}
