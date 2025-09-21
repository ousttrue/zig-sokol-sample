const std = @import("std");
const examples_build = @import("examples");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const examples_dep = b.dependency("examples", .{
        .target = target,
        .optimize = optimize,
    });
    const cimgui = examples_dep.module("cimgui");
    const sokol = examples_dep.module("sokol");
    const dbgui = examples_dep.module("dbgui");
    dbgui.addImport("sokol", sokol);

    const mod = b.createModule(.{
        .root_source_file = b.path("bufferoffsets-sapp.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = sokol },
            .{ .name = "dbgui", .module = dbgui },
            .{ .name = "cimgui", .module = cimgui },
        },
    });

    const opts = examples_build.Options{
        .name = "bufferoffsets",
        .mod = mod,
        .shaders = &.{
            "bufferoffsets-sapp.glsl",
        },
    };
    if (target.result.cpu.arch.isWasm()) {
        try examples_build.buildWeb(b, examples_dep, opts);
    } else {
        try examples_build.buildNative(b, examples_dep, opts);
    }
}
