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
    const rowmath = examples_dep.module("rowmath");
    const stb_image = examples_dep.artifact("stb_image");
    dbgui.addImport("sokol", sokol);

    const mod = b.createModule(.{
        .root_source_file = b.path("droptest-sapp.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = sokol },
            .{ .name = "dbgui", .module = dbgui },
            .{ .name = "cimgui", .module = cimgui },
            .{ .name = "rowmath", .module = rowmath },
            .{ .name = "stb_image", .module = stb_image.root_module },
        },
    });

    const opts = examples_build.Options{
        .name = "droptest-sapp",
        .mod = mod,
        .shaders = &.{
        },
    };
    if (target.result.cpu.arch.isWasm()) {
        try examples_build.buildWeb(b, examples_dep, opts);
    } else {
        try examples_build.buildNative(b, examples_dep, opts);
    }
}
