const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "stb_image",
        .root_module = b.addModule("stb_image", .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("stb_image.zig"),
            .link_libc = true,
        }),
    });
    if (target.result.cpu.arch.isWasm()) {
        // use emscripten builtin stb_image
    } else {
        lib.addCSourceFiles(.{
            .files = &.{
                "stb_image.c",
            },
        });
    }
    b.installArtifact(lib);
}
