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
        .root_source_file = b.path("cubemap-jpeg-sapp.zig"),
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

    // assets
    const assets = [_][]const u8{
        "nb2_negx.jpg",
        "nb2_negy.jpg",
        "nb2_negz.jpg",
        "nb2_posx.jpg",
        "nb2_posy.jpg",
        "nb2_posz.jpg",
    };
    for (assets) |asset| {
        b.getInstallStep().dependOn(&b.addInstallFile(
            examples_dep.path("data/nissibeach2").path(b, asset),
            b.fmt("bin/{s}", .{asset}),
        ).step);
    }

    const opts = examples_build.Options{
        .name = "cubemap-jpeg",
        .mod = mod,
        .shaders = &.{
            "cubemap-jpeg-sapp.glsl",
        },
    };
    if (target.result.cpu.arch.isWasm()) {
        try examples_build.buildWeb(b, examples_dep, opts);
    } else {
        try examples_build.buildNative(b, examples_dep, opts);
    }
}
